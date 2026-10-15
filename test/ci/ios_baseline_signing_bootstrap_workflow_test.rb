# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"
require "yaml"

class IOSBaselineSigningBootstrapWorkflowTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  PATH = File.join(ROOT, ".github/workflows/ios-baseline-signing-bootstrap.yml")

  def workflow
    assert File.file?(PATH), "bootstrap workflow is not implemented"
    YAML.safe_load(File.read(PATH))
  end

  def account
    workflow.fetch("jobs").fetch("bootstrap")
  end

  def step(name)
    value = account.fetch("steps").find { |item| item["name"] == name }
    refute_nil value, name
    value
  end

  def test_account_job_requires_manual_dispatch_main_and_exact_repository
    job = account
    %w[workflow_dispatch refs/heads/main maikrais98/hiddify-app].each do |guard|
      assert_includes job.fetch("if"), guard
    end
    assert_equal "release-publish", job.fetch("environment")
    assert_equal({ "contents" => "read", "actions" => "read" }, job.fetch("permissions"))
    assert_equal false, workflow.fetch("concurrency").fetch("cancel-in-progress")
  end

  def test_only_account_step_receives_apple_secrets_after_persisted_checkpoint
    steps = account.fetch("steps")
    holders = steps.select { |item| item.fetch("env", {}).values.any? { |value| value.to_s.include?("secrets.") } }
    assert_equal ["Execute scoped Apple operation"], holders.map { |item| item.fetch("name") }
    assert_equal %w[APPSTORE_API_KEY_ID APPSTORE_API_PRIVATE_KEY APPSTORE_ISSUER_ID],
      holders.first.fetch("env").keys.grep(/APPSTORE/).sort
    intent_index = steps.index { |item| item["name"] == "Persist create intent before Apple writes" }
    api_index = steps.index { |item| item["name"] == "Execute scoped Apple operation" }
    refute_nil intent_index
    assert_operator intent_index, :<, api_index
    checkpoint = steps.fetch(intent_index)
    assert_includes checkpoint.fetch("if"), "create"
    assert_equal "bootstrap/request/intent.json", checkpoint.fetch("with").fetch("path")
    assert_operator checkpoint.fetch("with").fetch("retention-days"), :>=, 7
    text = account.to_s
    %w[IOS_BASELINE_SIGNING_P12 -allowProvisioningUpdates -exportArchive -authenticationKeyPath].each do |forbidden|
      refute_includes text, forbidden
    end
  end

  def test_every_guard_blocks_before_apple_credentials_without_echoing_canaries
    command = step("Require separate bootstrap authorization").fetch("run")
    base = { "RELEASE_ENVIRONMENT_READY" => "true", "SIGNING_BOOTSTRAP_READY" => "true",
      "MODE" => "create", "CONFIRMATION" => "CREATE_ONE_BLIZZARD_DISTRIBUTION_IDENTITY",
      "GITHUB_RUN_ATTEMPT" => "1" }
    [{ "RELEASE_ENVIRONMENT_READY" => "false" }, { "SIGNING_BOOTSTRAP_READY" => "false" },
     { "GITHUB_RUN_ATTEMPT" => "2" }, { "CONFIRMATION" => "SECRET_CANARY" },
     { "MODE" => "SECRET_CANARY" }].each do |change|
      output, status = Open3.capture2e(base.merge(change), "bash", "-e", "-o", "pipefail", "-c", command)
      refute status.success?
      assert_match(/\AERROR_CODE=[A-Z_]+\n\z/, output)
      refute_includes output, "CANARY"
    end
    _, status = Open3.capture2e(base, "bash", "-e", "-o", "pipefail", "-c", command)
    assert status.success?
    _, status = Open3.capture2e(base.merge("MODE" => "resume", "GITHUB_RUN_ATTEMPT" => "4", "CONFIRMATION" => ""),
      "bash", "-e", "-o", "pipefail", "-c", command)
    assert status.success?, "read-only reconciliation must remain available after an uncertain create"
  end

  def test_prior_create_intent_and_unknown_github_result_both_prevent_new_write
    command = step("Reject a previous create intent").fetch("run")
    Dir.mktmpdir("bootstrap-checkpoint") do |directory|
      File.write(File.join(directory, "gh"), "#!/bin/sh\nprintf '%s\\n' \"$FAKE_COUNT\"\nexit \"$FAKE_EXIT\"\n")
      File.chmod(0755, File.join(directory, "gh"))
      base = { "PATH" => "#{directory}:/usr/bin:/bin", "SPKI_SHA256" => "a" * 64,
        "FAKE_COUNT" => "0", "FAKE_EXIT" => "0" }
      output, status = Open3.capture2e(base, "bash", "-e", "-o", "pipefail", "-c", command)
      assert status.success?, output
      [{ "FAKE_COUNT" => "1" }, { "FAKE_COUNT" => "SECRET_CANARY" }, { "FAKE_EXIT" => "1" },
       { "SPKI_SHA256" => "SECRET_CANARY" }].each do |change|
        output, status = Open3.capture2e(base.merge(change), "bash", "-e", "-o", "pipefail", "-c", command)
        refute status.success?
        assert_match(/\AERROR_CODE=[A-Z_]+\n\z/, output)
        refute_includes output, "CANARY"
      end
    end
  end

  def test_controller_and_api_helper_are_pinned_without_checkout_credentials
    checkouts = account.fetch("steps").select { |item| item.fetch("uses", "").start_with?("actions/checkout@") }
    assert_equal 2, checkouts.length
    checkouts.each { |item| assert_equal false, item.fetch("with").fetch("persist-credentials") }
    assert_equal "${{ github.sha }}", checkouts.first.fetch("with").fetch("ref")
    assert_equal "3fb04c73f94c1174a668842ec3e50190abef6e6a", checkouts.last.fetch("with").fetch("ref")
    verifier = step("Verify controller and trusted API helper").fetch("run")
    assert_includes verifier, "13cd9ed9688c4fec9e346bd12c845eac72616b823b57760535f5f667b6d8a38c"
    assert_includes verifier, "git rev-parse HEAD"
  end

  def test_pull_request_test_job_has_no_environment_or_account_access
    job = workflow.fetch("jobs").fetch("test-bootstrap")
    refute job.key?("environment")
    refute_includes job.to_s, "secrets."
    text = job.fetch("steps").map { |item| item.fetch("run", "") }.join("\n")
    assert_includes text, "ruby test/ci/ios_baseline_signing_bootstrap_test.rb"
    assert_includes text, "ruby test/ci/ios_baseline_signing_bootstrap_workflow_test.rb"
    refute_match(/flutter build|xcodebuild|pod install/, text)
  end

  def test_user_inputs_are_environment_values_and_results_have_a_bounded_retention
    commands = account.fetch("steps").map { |item| item.fetch("run", "") }.join("\n")
    refute_match(/\$\{\{\s*inputs\./, commands)
    receipt = step("Retain public bootstrap receipt")
    assert_includes receipt.fetch("if"), "always()"
    assert_equal "bootstrap/result", receipt.fetch("with").fetch("path")
    assert_equal 7, receipt.fetch("with").fetch("retention-days")
  end
end
