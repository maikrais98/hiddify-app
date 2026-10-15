# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "open3"
require "tmpdir"
require "fileutils"

class IosBaselinePersistentSigningGateTest < Minitest::Test
  WORKFLOW = File.expand_path("../../.github/workflows/ios-baseline.yml", __dir__)
  MATERIALS = %w[
    IOS_BASELINE_SIGNING_P12_BASE64 IOS_BASELINE_SIGNING_P12_PASSWORD
    IOS_BASELINE_APP_PROFILE_BASE64 IOS_BASELINE_EXTENSION_PROFILE_BASE64
    IOS_BASELINE_SIGNING_CERT_SHA256
  ].freeze

  def setup
    @job = YAML.safe_load(File.read(WORKFLOW)).fetch("jobs").fetch("sign-baseline")
    @steps = @job.fetch("steps")
  end

  def test_signing_job_has_no_apple_account_credentials_or_provisioning_write_flags
    text = @job.to_s
    %w[APPSTORE_API_PRIVATE_KEY APPSTORE_API_KEY_ID APPSTORE_ISSUER_ID
       -allowProvisioningUpdates -authenticationKeyPath -authenticationKeyID
       -authenticationKeyIssuerID AuthKey_].each do |forbidden|
      refute_includes text, forbidden
    end
    assert_equal "release-signing", @job.fetch("environment")
    assert_equal "preflight-upload", @job.fetch("needs")
  end

  def test_material_gate_precedes_checkout_and_every_build_tool
    gate_index = @steps.index { |step| step["name"] == "Require persistent signing setup" }
    refute_nil gate_index, "signing must stop before build tools when persistent material is unavailable"
    assert_equal 1, gate_index
    assert_equal "Require protected signing environment readiness", @steps.first.fetch("name")
    assert_equal MATERIALS.sort, @steps.fetch(gate_index).fetch("env").keys.sort
    @steps.each_with_index do |step, index|
      next unless step.key?("uses") || step.fetch("run", "").match?(/xcodebuild|flutter|curl|pod install/)

      assert_operator gate_index, :<, index
    end
  end

  def test_each_missing_material_stops_without_signing_or_secret_output
    MATERIALS.each do |missing|
      env = MATERIALS.to_h { |name| [name, "SECRET_CANARY_#{name}"] }
      env[missing] = ""
      output, status, touched = execute_gate(env)
      refute status.success?, missing
      assert_equal "ERROR_CODE=PERSISTENT_SIGNING_MATERIAL_MISSING\n", output
      refute touched
      refute_includes output, "CANARY"
    end
  end

  def test_presence_alone_does_not_enable_an_unimplemented_signing_setup
    env = MATERIALS.to_h { |name| [name, "SECRET_CANARY_#{name}"] }
    output, status, touched = execute_gate(env)
    refute status.success?
    assert_equal "ERROR_CODE=PERSISTENT_SIGNING_SETUP_REQUIRED\n", output
    refute touched
    refute_includes output, "CANARY"
  end

  def test_read_only_probe_runs_controller_checks_without_secrets
    path = File.join(File.dirname(WORKFLOW), "ios-baseline-signing-inventory.yml")
    document = YAML.safe_load(File.read(path))
    triggers = document["on"] || document[true]
    assert triggers.key?("pull_request"), "controller checks must run on pull requests"
    job = document.fetch("jobs").fetch("test-probe")
    refute_includes job.to_s, "secrets."
    commands = job.fetch("steps").map { |step| step.fetch("run", "") }.join("\n")
    %w[ios_baseline_persistent_signing_gate_test.rb ios_baseline_signing_diagnostics_test.rb
       blizzard_release_controller_test.rb].each do |test|
      assert_includes commands, "ruby test/ci/#{test}"
    end
  end

  private

  def execute_gate(env)
    step = @steps.find { |candidate| candidate["name"] == "Require persistent signing setup" }
    refute_nil step, "persistent signing guard is missing"
    Dir.mktmpdir("persistent-signing-gate") do |directory|
      bin = File.join(directory, "bin")
      FileUtils.mkdir_p(bin)
      marker = File.join(directory, "signing-tool-used")
      %w[xcodebuild security curl openssl].each do |name|
        path = File.join(bin, name)
        File.write(path, "#!/bin/sh\ntouch \"$SIGNING_TOOL_MARKER\"\nexit 99\n")
        File.chmod(0755, path)
      end
      output, status = Open3.capture2e(env.merge("PATH" => "#{bin}:/usr/bin:/bin", "SIGNING_TOOL_MARKER" => marker),
        "bash", "-e", "-o", "pipefail", "-c", step.fetch("run"), chdir: directory)
      [output, status, File.exist?(marker)]
    end
  end
end
