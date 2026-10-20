# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "open3"

class IosBaselineManualSigningWorkflowTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def setup
    @workflow = YAML.safe_load(File.read(File.join(ROOT, ".github/workflows/ios-baseline.yml")))
    @job = @workflow.fetch("jobs").fetch("sign-baseline")
    @steps = @job.fetch("steps")
  end

  def test_signer_comes_from_verified_controller_not_application_pin
    checkout = @steps.find { |step| step["name"] == "Check out signing controller without credentials" }
    refute_nil checkout, "the pinned application does not contain the new signing helper"
    assert_equal "${{ github.sha }}", checkout.fetch("with").fetch("ref")
    assert_equal ".signing-controller", checkout.fetch("with").fetch("path")
    assert_equal false, checkout.fetch("with").fetch("persist-credentials")
    verification = @steps.find { |step| step["name"] == "Verify signing controller" }
    assert_includes verification.fetch("run"), 'git -C .signing-controller rev-parse HEAD'
    assert_equal "${{ github.sha }}", verification.fetch("env").fetch("SIGNING_CONTROLLER_SHA")
  end

  def test_signing_wraps_both_xcode_commands_with_cleanup_and_target_specific_material
    step = @steps.find { |item| item["name"] == "Archive and export without provisioning updates" }
    command = step.fetch("run")
    assert_includes command, "ruby .signing-controller/scripts/ios_baseline_manual_signing.rb with-signing"
    assert_includes command, '--provenance-path out/ios-baseline-signing-overrides.json'
    assert_includes command, '-workspace "$IOS_BASELINE_SIGNING_WORKSPACE"'
    assert_includes command, '-exportOptionsPlist "$IOS_BASELINE_SIGNING_EXPORT_OPTIONS"'
    refute_includes command, "PROVISIONING_PROFILE_SPECIFIER="
    refute_includes command, "-allowProvisioningUpdates"
    assert_equal "${{ github.sha }}", step.fetch("env").fetch("SIGNING_CONTROLLER_SHA")
    %w[IOS_BASELINE_SIGNING_P12_BASE64 IOS_BASELINE_SIGNING_P12_PASSWORD
       IOS_BASELINE_APP_PROFILE_BASE64 IOS_BASELINE_EXTENSION_PROFILE_BASE64].each do |name|
      assert_equal "${{ secrets.#{name} }}", step.fetch("env").fetch(name)
      refute @job.fetch("env").key?(name)
    end
  end

  def test_public_signing_override_receipt_is_digest_bound_before_upload
    producer = @steps.find { |item| item["name"] == "Verify signed IPA and write provenance" }.fetch("run")
    consumer = @workflow.fetch("jobs").fetch("upload-testflight").fetch("steps")
                        .find { |item| item["name"] == "Verify source, version, build, digest, and signed identity" }.fetch("run")
    [producer, consumer].each do |command|
      assert_includes command, "signing_overrides_sha256"
      assert_includes command, "out/ios-baseline-signing-overrides.json"
    end
    assert_includes consumer, "SIGNING_OVERRIDES_MISMATCH"
  end

  def test_pull_request_checks_validate_new_helpers_without_secrets_or_signing
    path = File.join(ROOT, ".github/workflows/ios-baseline-manual-signing.yml")
    workflow = YAML.safe_load(File.read(path))
    job = workflow.fetch("jobs")["test-manual-signing"]
    refute_nil job, "manual signing checks must run on a secretless macOS runner"
    assert_equal "macos-26-intel", job.fetch("runs-on"), "Use the available Intel pool for fixture signing checks"
    refute job.key?("environment")
    refute_includes job.to_s, "secrets."
    commands = job.fetch("steps").map { |step| step.fetch("run", "") }.join("\n")
    %w[ios_baseline_manual_signing_test.rb ios_baseline_signing_request_test.rb
       ios_baseline_manual_signing_workflow_test.rb].each do |test|
      assert_includes commands, "ruby test/ci/#{test}"
    end
  end
end
