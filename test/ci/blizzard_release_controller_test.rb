# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "tmpdir"
require "fileutils"
require "open3"
require "json"
require "digest"

class BlizzardReleaseControllerTest < Minitest::Test
  BASELINE = "0830294eff5b8cd86324545ed00689648c70bd23"
  WORKFLOW = File.expand_path("../../.github/workflows/ios-baseline.yml", __dir__)

  def setup
    @jobs = YAML.safe_load(File.read(WORKFLOW)).fetch("jobs")
  end

  def test_exact_reviewed_release_pin_and_unchanged_metadata_pin
    env = @jobs.fetch("validate-source").fetch("steps").first.fetch("env")
    assert_equal "6e50da15abc2265d6b507d20d67c98cbcab871e7", env.fetch("TRUSTED_RELEASE_SOURCE_SHA")
    assert_equal "3fb04c73f94c1174a668842ec3e50190abef6e6a", env.fetch("TRUSTED_SOURCE_SHA")
  end

  def test_intel_capacity_fallback_preserves_exact_apple_toolchain_before_protected_jobs
    @jobs.each_value { |job| assert_equal "macos-26-intel", job.fetch("runs-on") }
    validation = @jobs.fetch("validate-source")
    refute validation.key?("environment")
    refute_includes validation.to_s, "secrets."
    probe = validation.fetch("steps").find { |step| step["name"] == "Verify available Intel Apple toolchain" }
    refute_nil probe
    assert_equal "/Applications/Xcode_26.6.app/Contents/Developer", probe.fetch("env").fetch("DEVELOPER_DIR")
    signing_probe = @jobs.fetch("sign-baseline").fetch("steps").find { |step| step["name"] == "Verify checkout and pinned Apple toolchain" }
    [probe, signing_probe].each do |step|
      script = step.fetch("run")
      assert_includes script, 'test "$(uname -m)" = "x86_64"'
      assert_includes script, 'test "$(xcodebuild -version)" = "$(printf \'Xcode 26.6\\nBuild version 17F113\')"'
      assert_includes script, 'test "$(xcrun --sdk iphoneos --show-sdk-version)" = "26.5"'
    end
    assert_equal probe.fetch("env").fetch("DEVELOPER_DIR"), @jobs.fetch("sign-baseline").fetch("env").fetch("DEVELOPER_DIR")
    assert_includes @jobs.fetch("test-source").fetch("needs"), "validate-source"
    assert_includes @jobs.fetch("preflight-upload").fetch("needs"), "test-source"
    assert_includes @jobs.fetch("sign-baseline").fetch("needs"), "preflight-upload"
  end

  def test_exact_baseline_is_fetched_and_checked_before_flutter_tests
    steps = @jobs.fetch("test-source").fetch("steps")
    fetch_index = steps.index { |step| step["name"] == "Fetch exact presentation contract baseline" }
    refute_nil fetch_index, "Shallow source checkout must receive the immutable contract baseline"
    assert_equal "git fetch --no-tags --depth=1 origin #{BASELINE}\ngit cat-file -e '#{BASELINE}^{commit}'\n",
                 steps.fetch(fetch_index).fetch("run")
    assert_operator fetch_index, :>, steps.index { |step| step["name"] == "Verify exact checked-out source" }
    assert_operator fetch_index, :<, steps.index { |step| step["name"] == "Run full Flutter tests" }
    checkout = steps.find { |step| step.key?("uses") && step.fetch("uses").start_with?("actions/checkout@") }
    assert_equal 1, checkout.fetch("with").fetch("fetch-depth")
    assert_equal false, checkout.fetch("with").fetch("persist-credentials")
  end

  def test_native_diagnostics_privacy_is_verified_before_release
    steps = @jobs.fetch("test-source").fetch("steps")
    index = steps.index { |step| step["name"] == "Verify safe native diagnostics" }
    refute_nil index, "The new logging boundary must be tested before signing"
    assert_equal "bash test/security/native_diagnostics_privacy_test.sh", steps.fetch(index).fetch("run")
    assert_operator index, :>, steps.index { |step| step["name"] == "Generate prerequisites without source drift" }
    assert_operator index, :<, steps.index { |step| step["name"] == "Run full Flutter tests" }
    assert_includes @jobs.fetch("preflight-upload").fetch("needs"), "test-source"
  end

  def test_manual_vpn_policy_is_verified_in_unprotected_source_gate_before_release
    test_source = @jobs.fetch("test-source")
    matches = test_source.fetch("steps").select do |step|
      step.fetch("run", "").to_s.match?(%r{\bbash\s+test/ios/vpn_manager_manual_policy_test\.sh\b})
    end

    assert_equal 1, matches.length, "The manual VPN regression harness must run exactly once"
    refute test_source.key?("environment"), "The native source gate must remain unprotected"
    refute_includes test_source.to_s, "secrets."
    assert_includes @jobs.fetch("preflight-upload").fetch("needs"), "test-source"
    assert_includes @jobs.fetch("sign-baseline").fetch("needs"), "preflight-upload"
    assert_includes @jobs.fetch("upload-testflight").fetch("needs"), "sign-baseline"
  end

  def test_foreground_mode_harness_blocks_signing_in_unprotected_source_gate
    source = @jobs.fetch("test-source")
    steps = source.fetch("steps")
    harnesses = steps.each_index.select do |index|
      steps[index].fetch("run", "").to_s.match?(%r{\bbash\s+test/ios/foreground_setup_mode_test\.sh\b})
    end
    assert_equal 1, harnesses.length, "Foreground setup mode regression must run exactly once before signing"
    assert_equal 1, steps.count { |step| step.fetch("run", "").to_s.lines.any? { |line| line.strip == "ruby test/ci/ios_source_ci_scope_test.rb" } }
    index = harnesses.fetch(0)
    assert_operator index, :>, steps.index { |step| step["name"] == "Generate prerequisites without source drift" }
    assert_operator index, :<, steps.index { |step| step["name"] == "Run full Flutter tests" }
    refute source.key?("environment")
    refute_includes source.to_s, "secrets."
    assert_includes @jobs.fetch("preflight-upload").fetch("needs"), "test-source"
    assert_includes @jobs.fetch("sign-baseline").fetch("needs"), "preflight-upload"
  end

  def test_native_receipt_precedes_signing_and_is_bound_to_artifact
    steps = @jobs.fetch("sign-baseline").fetch("steps")
    index = steps.index { |step| step["name"] == "Capture actual unsigned native inputs" }
    refute_nil index
    assert_operator index, :>, steps.index { |step| step["name"] == "Compile exact version without signing" }
    assert_operator index, :<, steps.index { |step| step["name"] == "Archive and export without provisioning updates" }
    assert_equal "f6ff1529fd6d8af5f706051d9251ac9231c83407", steps.fetch(index).fetch("env").fetch("FLUTTER_FRAMEWORK_REVISION")
    capture = steps.fetch(index).fetch("run")
    assert_includes capture, "cmp ios/Podfile.lock ios/Pods/Manifest.lock"
    %w[ios/Podfile.lock ios/Pods/Manifest.lock ios/Runner/GeneratedPluginRegistrant.m].each { |path| assert_includes capture, path }
    assert_includes capture, "ios/Pods/Local Podspecs/*.json"
    assert_includes capture, "Pods-Runner.release.xcconfig"
    assert_includes capture, 'ENV.fetch("SOURCE_SHA")'
    assert_includes capture, 'ENV.fetch("FLUTTER_FRAMEWORK_REVISION")'
    assert_includes capture, "pod --version"
    producer = steps.find { |step| step["name"] == "Verify signed IPA and write provenance" }.fetch("run")
    assert_includes producer, "native_inputs_sha256"
    consumer = @jobs.fetch("upload-testflight").fetch("steps").find { |step| step["name"] == "Verify source, version, build, digest, and signed identity" }.fetch("run")
    assert_includes consumer, "native_inputs_sha256"
    assert_includes consumer, "NATIVE_INPUTS_MISMATCH"
    artifact = steps.find { |step| step["name"] == "Retain exact baseline candidate" }.fetch("with")
    assert_equal "out", artifact.fetch("path")
    assert_equal 7, artifact.fetch("retention-days")
  end

  def test_native_receipt_executes_and_rejects_incoherence_or_tampering
    capture = @jobs.fetch("sign-baseline").fetch("steps").find { |step| step["name"] == "Capture actual unsigned native inputs" }.fetch("run")
    consumer = @jobs.fetch("upload-testflight").fetch("steps").find { |step| step["name"] == "Verify source, version, build, digest, and signed identity" }.fetch("run")
    verify = consumer.match(/ruby -rjson -rdigest <<'RUBY'\n.*?^RUBY$/m).to_s
    refute_empty verify
    Dir.mktmpdir("native-receipt-test") do |directory|
      files = {
        "ios/Podfile.lock" => "PODS: []\n",
        "ios/Pods/Manifest.lock" => "PODS: []\n",
        "ios/Runner/GeneratedPluginRegistrant.m" => "// fixture\n",
        "ios/Pods/Local Podspecs/example.podspec.json" => "{}\n",
        "ios/Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig" => "PODS_ROOT = fixture\n",
        "bin/pod" => "#!/bin/sh\nprintf '1.16.2\\n'\n"
      }
      files.each do |path, content|
        target = File.join(directory, path)
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, content)
      end
      File.chmod(0755, File.join(directory, "bin/pod"))
      env = {"SOURCE_SHA" => "6aa9477e98f84757b22451a12890bed898d89b84", "FLUTTER_FRAMEWORK_REVISION" => "f6ff1529fd6d8af5f706051d9251ac9231c83407", "PATH" => "#{directory}/bin:/usr/bin:/bin"}
      output, status = Open3.capture2e(env, "bash", "-e", "-c", capture, chdir: directory)
      assert status.success?, output
      root = File.join(directory, "out/native-inputs")
      manifest = File.join(root, "manifest.json")
      receipt = JSON.parse(File.read(manifest))
      assert_equal "1.16.2", receipt.fetch("cocoapods_version")
      assert_equal env.fetch("FLUTTER_FRAMEWORK_REVISION"), receipt.fetch("flutter_revision")
      assert_equal files.keys.reject { |path| path == "bin/pod" }.sort, receipt.fetch("files").map { |entry| entry.fetch("path") }.sort
      refute_includes File.read(manifest), directory
      signing_receipt = File.join(directory, "out/ios-baseline-signing-overrides.json")
      File.write(signing_receipt, JSON.generate(schema: "ios-baseline-signing-overrides/v1"))
      File.write(File.join(directory, "out/provenance.json"), JSON.generate(
        native_inputs_sha256: Digest::SHA256.file(manifest).hexdigest,
        signing_overrides_sha256: Digest::SHA256.file(signing_receipt).hexdigest))
      output, status = Open3.capture2e(env, "bash", "-e", "-c", verify, chdir: directory)
      assert status.success?, output
      File.write(signing_receipt, "tampered")
      output, status = Open3.capture2e(env, "bash", "-e", "-c", verify, chdir: directory)
      refute status.success?
      assert_includes output, "SIGNING_OVERRIDES_MISMATCH"
      File.write(signing_receipt, JSON.generate(schema: "ios-baseline-signing-overrides/v1"))
      File.write(File.join(root, "ios/Podfile.lock"), "tampered")
      output, status = Open3.capture2e(env, "bash", "-e", "-c", verify, chdir: directory)
      refute status.success?
      assert_includes output, "NATIVE_INPUTS_MISMATCH"
      File.write(File.join(directory, "ios/Pods/Manifest.lock"), "incoherent")
      _, status = Open3.capture2e(env, "bash", "-e", "-c", capture, chdir: directory)
      refute status.success?
    end
  end

end
