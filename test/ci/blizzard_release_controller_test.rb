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
  AURORA_BASELINE = "521274b84c55b15027de43bf2d6c28fe85731cb5"
  PATCH_BASELINE = "b37b073eef2be19f2534443469c4fd22e7238463"
  LUMA_BASELINE = "20dd0b98fddee2480ca51c78c29eedffe5e61ae3"
  PREVIOUS_VISUAL_SOURCE = "bb5f0414ec3a42c5e9ea42414410d2566f445e75"
  PREVIOUS_RELEASE_SOURCE = "2c45e4e73fae9de250787c544dae634d92b9985f"
  QA45_BASELINE = "638b68226fc745acec43dc5d0b9576e30ddb69bf"
  RELEASE_SOURCE = "3ed0a966f13a4ee7a84819d80b34e956d6b4ca19"
  RELEASE_VERSION = "0.1.0"
  MINIMUM_BUILD = "45"
  APPROVER = "maikrais98"
  APPROVAL_SHA256 = "c11c139d064a95c24d61a8e2786b3cc91d61357a3d5e96a08498b10d17350bc7"
  DESIGN_SHA256 = "6ac2120d7a0b429950d2477657a5057a2f6f703d49c30fba95cf976a664108b6"
  ROOT = File.expand_path("../..", __dir__)
  WORKFLOW = File.expand_path("../../.github/workflows/ios-baseline.yml", __dir__)

  def setup
    @jobs = YAML.safe_load(File.read(WORKFLOW)).fetch("jobs")
  end

  def test_exact_reviewed_release_pin_and_unchanged_metadata_pin
    env = @jobs.fetch("validate-source").fetch("steps").first.fetch("env")
    assert_equal RELEASE_SOURCE, env.fetch("TRUSTED_RELEASE_SOURCE_SHA")
    assert_equal "3fb04c73f94c1174a668842ec3e50190abef6e6a", env.fetch("TRUSTED_SOURCE_SHA")
  end

  def test_owner_reference_approval_is_verified_in_the_unprivileged_controller_before_signing
    gate = @jobs.fetch("verify-release-approval")
    assert_equal "validate-source", gate.fetch("needs")
    refute gate.key?("environment")
    refute_includes gate.to_s, "secrets."

    checkout = gate.fetch("steps").find { |step| step["name"] == "Check out exact release approval controller" }
    assert_equal "${{ github.sha }}", checkout.fetch("with").fetch("ref")
    assert_equal false, checkout.fetch("with").fetch("persist-credentials")
    assert_equal 1, checkout.fetch("with").fetch("fetch-depth")

    verify = gate.fetch("steps").find { |step| step["name"] == "Verify explicit owner reference-release approval" }
    assert_equal RELEASE_SOURCE, verify.fetch("env").fetch("EXPECTED_SOURCE_SHA")
    assert_equal RELEASE_VERSION, verify.fetch("env").fetch("EXPECTED_VERSION")
    assert_equal MINIMUM_BUILD, verify.fetch("env").fetch("EXPECTED_MINIMUM_BUILD_NUMBER")
    assert_equal APPROVER, verify.fetch("env").fetch("EXPECTED_APPROVER")
    assert_equal APPROVAL_SHA256, verify.fetch("env").fetch("EXPECTED_APPROVAL_SHA256")
    script = verify.fetch("run")
    assert_includes script, 'release/reference-approvals/${EXPECTED_SOURCE_SHA}.json'
    assert_includes script, "scripts/verify_reference_release_approval.py"
    assert_includes script, "--expected-decision publish-testflight"
    assert_includes script, "--expected-visual-status verified-qa"
    assert_includes script, "--expected-qa-profile qa45"
    assert_includes script, 'release/qa-evidence'
    assert_equal "912bd6a22023e0fa1babdd4a509ed3e0c2bb96e60ed06b88272fbab3658ffb0f", verify.fetch("env").fetch("EXPECTED_EVIDENCE_SHA256")
    refute_includes script, "verify_visual_receipt.py"

    assert_equal ["preflight-upload", "verify-release-approval"].sort,
                 Array(@jobs.fetch("sign-baseline").fetch("needs")).sort
  end

  def test_upload_secret_jobs_are_transitively_gated_by_owner_approval
    assert_equal ["test-source", "verify-release-approval"].sort,
                 Array(@jobs.fetch("preflight-upload").fetch("needs")).sort
    %w[preflight-upload sign-baseline upload-testflight].each do |job|
      assert transitively_depends_on?(job, "verify-release-approval"),
             "#{job} must remain downstream of the release approval gate"
    end
    refute transitively_depends_on?("metadata-testflight", "verify-release-approval")
    refute transitively_depends_on?("status-testflight", "verify-release-approval")
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
    expected_fetch = [BASELINE, AURORA_BASELINE, PATCH_BASELINE, PREVIOUS_VISUAL_SOURCE, LUMA_BASELINE, PREVIOUS_RELEASE_SOURCE, QA45_BASELINE].map do |sha|
      "git fetch --no-tags --depth=1 origin #{sha}\ngit cat-file -e '#{sha}^{commit}'\n"
    end.join
    assert_equal expected_fetch, steps.fetch(fetch_index).fetch("run")
    guard_index = steps.index do |step|
      step.fetch("run", "").lines.any? { |line| line.strip == "ruby test/ci/blizzard_runtime_boundary_test.rb" }
    end
    refute_nil guard_index, "The exact Aurora runtime boundary must gate signing"
    assert_operator fetch_index, :<, guard_index
    assert_operator guard_index, :<, steps.index { |step| step["name"] == "Run full Flutter tests" }
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

  def test_source_boundary_hydrates_the_same_digest_bound_core_as_signing
    source = @jobs.fetch("test-source")
    steps = source.fetch("steps")
    hydration_index = steps.index { |step| step["name"] == "Prepare digest-bound official iOS core" }
    refute_nil hydration_index, "The full boundary test needs actual core files in a clean checkout"
    hydration = steps.fetch(hydration_index)
    signing = @jobs.fetch("sign-baseline")
    signing_hydration = signing.fetch("steps").find { |step| step["name"] == hydration.fetch("name") }
    signing_manifest_copy = 'cp "$RUNNER_TEMP/ios-baseline-core/HiddifyCore.xcframework.sha256" ios/Frameworks/HiddifyCore.xcframework.sha256'
    expected_run = signing_hydration.fetch("run").lines.reject { |line| line.strip == signing_manifest_copy }.join
    assert_equal expected_run, hydration.fetch("run"), "Keep the generated manifest in RUNNER_TEMP so the source checkout stays clean"
    %w[CORE_ARCHIVE_SHA256 CORE_ARCHIVE_SIZE].each do |key|
      assert_equal signing.fetch("env").fetch(key), hydration.fetch("env").fetch(key)
    end
    guard_index = steps.index { |step| step.fetch("run", "").include?("ruby test/ci/blizzard_runtime_boundary_test.rb") }
    assert_operator hydration_index, :<, guard_index
    refute source.key?("environment")
    refute_includes source.to_s, "secrets."
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

  def test_actual_reviewed_aurora_receipt_is_bound_to_the_pinned_design_and_source
    manifest = File.join(ROOT, "release/design-manifests/blizzard-aurora-03.json")
    receipt = File.join(ROOT, "release/visual-receipts/#{PREVIOUS_VISUAL_SOURCE}.json")
    assert File.file?(manifest), "Missing reviewed Aurora design manifest"
    assert_equal DESIGN_SHA256, Digest::SHA256.file(manifest).hexdigest
    assert File.file?(receipt), "Missing independent Aurora visual review"
    command = ["python3", File.join(ROOT, "scripts/verify_visual_receipt.py"), "--receipt", receipt,
               "--expected-design-manifest-sha256", DESIGN_SHA256, "--expected-source-sha"]
    output, status = Open3.capture2e(*command, PREVIOUS_VISUAL_SOURCE)
    assert status.success?, output
    output, status = Open3.capture2e(*command, AURORA_BASELINE)
    refute status.success?, "The current receipt must reject the old source"
    assert_includes output, "ERROR_CODE=VISUAL_RECEIPT_INVALID"
  end

  def test_qa45_evidence_gate_executes_and_rejects_pending_or_tampered_evidence
    step = @jobs.fetch("verify-release-approval").fetch("steps").find { |entry| entry["name"] == "Verify explicit owner reference-release approval" }
    script = step.fetch("run").lines.find { |line| line.include?("python3 -c") }
    refute_nil script
    evidence = JSON.parse(File.read(File.join(ROOT, "release/qa-evidence/#{RELEASE_SOURCE}.json")))
    Dir.mktmpdir("qa45-evidence") do |directory|
      path = File.join(directory, "release/qa-evidence/#{RELEASE_SOURCE}.json")
      FileUtils.mkdir_p(File.dirname(path))
      execute = lambda do |value, digest_override = nil|
        File.write(path, JSON.generate(value))
        env = {"EXPECTED_SOURCE_SHA" => RELEASE_SOURCE, "EXPECTED_EVIDENCE_SHA256" => digest_override || Digest::SHA256.file(path).hexdigest}
        Open3.capture2e(env, "bash", "-e", "-c", script, chdir: directory).last.success?
      end
      good = Marshal.load(Marshal.dump(evidence))
      good["full_flutter_tests_status"] = "passed"
      good["full_flutter_tests_passed"] ||= 1
      assert execute.call(good)
      refute execute.call(good, "0" * 64), "Byte digest must remain pinned"
      mutations = [
        ->(d) { d["source_sha"] = "0" * 40 },
        ->(d) { d["full_flutter_tests_status"] = "pending" },
        ->(d) { d["full_flutter_tests_passed"] = nil },
        ->(d) { d["targeted_tests_passed"] = 57 },
        ->(d) { d["native_captures"] = [{"file" => "old-qa37.png"}] },
        ->(d) { d["physical_qa"]["video"]["thermal_state_seconds"] = {"nominal" => 299} },
        ->(d) { d["physical_qa"]["foreground"]["build"] = 37 }
      ]
      mutations.each do |mutation|
        changed = Marshal.load(Marshal.dump(good))
        mutation.call(changed)
        refute execute.call(changed), "Changed evidence semantics must fail even with recomputed digest"
      end
    end
  end

  private

  def transitively_depends_on?(job, dependency, visited = [])
    return true if job == dependency
    return false if visited.include?(job)

    Array(@jobs.fetch(job).fetch("needs", [])).any? do |need|
      transitively_depends_on?(need, dependency, visited + [job])
    end
  end

end
