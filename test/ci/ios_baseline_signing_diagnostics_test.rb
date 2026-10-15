# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "tmpdir"
require "fileutils"
require "open3"

class IosBaselineSigningDiagnosticsTest < Minitest::Test
  WORKFLOW = File.expand_path("../../.github/workflows/ios-baseline.yml", __dir__)
  START_MARKER = "# SIGNING_DIAGNOSTIC_CLASSIFIER_START"
  END_MARKER = "# SIGNING_DIAGNOSTIC_CLASSIFIER_END"
  CANARIES = [
    "SECRET_KEY_CANARY_7f3d",
    "https://signed.example.invalid/private?token=URL_CANARY_8a4e",
    "ACCOUNT_CANARY_123456789",
    "/Users/private/Library/MobileDevice/Provisioning Profiles/PATH_CANARY.mobileprovision"
  ].freeze

  def setup
    @workflow = YAML.safe_load(File.read(WORKFLOW))
    @run = @workflow.fetch("jobs").fetch("sign-baseline").fetch("steps")
                    .find { |step| step["name"] == "Archive and export without provisioning updates" }
                    .fetch("run")
  end

  def test_classifier_emits_only_closed_tokens_for_known_causes
    cases = {
      "DEVELOPER_AGREEMENT_UPDATE_REQUIRED" => "The Apple Developer Program License Agreement has been updated and must be accepted.",
      "SIGNING_CERTIFICATE_QUOTA_EXCEEDED" => "You already have a current Apple Distribution certificate or a pending certificate request. The maximum number of certificates has been reached.",
      "SIGNING_CERTIFICATE_MISSING_OR_INVALID" => "0 valid identities found",
      "PROVISIONING_PROFILE_MISSING_OR_INVALID" => "No profiles for 'com.example.private' were found",
      "CAPABILITY_OR_ENTITLEMENT_MISMATCH" => "Provisioning profile doesn't support the Network Extensions capability.",
      "AUTHENTICATION_FAILED" => "DVTPortalServiceErrorDomain Code=1100 account=#{CANARIES.fetch(2)}",
      "KEYCHAIN_ACCESS_FAILED" => "errSecInteractionNotAllowed while opening keychain",
      "NETWORK_SERVICE_UNAVAILABLE" => "NSURLErrorDomain Code=-1009 #{CANARIES.fetch(1)}",
      "DISK_SPACE_EXHAUSTED" => "No space left on device at #{CANARIES.fetch(3)}"
    }

    cases.each do |token, message|
      output, status = classify("#{message}\n#{CANARIES.join(" ")}\n")
      assert status.success?, output
      assert_equal "SIGNING_DIAGNOSTIC=#{token}\n", output
      assert_no_canaries(output)
    end
  end

  def test_certificate_limit_wording_maps_to_fixed_quota_token
    output, status = classify("Certificate creation quota exceeded for #{CANARIES.fetch(2)}\n")

    assert status.success?, output
    assert_equal "SIGNING_DIAGNOSTIC=SIGNING_CERTIFICATE_QUOTA_EXCEEDED\n", output
    assert_no_canaries(output)
  end

  def test_multiple_known_causes_are_reported_as_a_fixed_ordered_token_list
    output, status = classify(<<~LOG)
      The Apple Developer Program License Agreement must be accepted.
      Certificate creation quota exceeded for #{CANARIES.fetch(2)}.
    LOG

    assert status.success?, output
    assert_equal <<~OUTPUT, output
      SIGNING_DIAGNOSTIC=DEVELOPER_AGREEMENT_UPDATE_REQUIRED
      SIGNING_DIAGNOSTIC=SIGNING_CERTIFICATE_QUOTA_EXCEEDED
    OUTPUT
    refute_includes output, "UNCLASSIFIED"
    assert_no_canaries(output)
  end

  def test_unknown_log_is_fail_closed_without_raw_leakage
    output, status = classify("PrivateLeakDomain Code=12345 Unrecognized failure #{CANARIES.join(" ")}\n")

    assert status.success?, output
    assert_equal "SIGNING_DIAGNOSTIC=UNCLASSIFIED\n", output
    assert_no_canaries(output)
  end

  def test_classifier_reads_only_a_bounded_tail
    old_cause = "The Apple Developer Program License Agreement must be accepted."
    output, status = classify("#{old_cause}\n#{"x" * (256 * 1024)}\n")
    assert status.success?, output
    assert_equal "SIGNING_DIAGNOSTIC=UNCLASSIFIED\n", output

    output, status = classify("#{"x" * (256 * 1024)}\nNo signing certificate found\n")
    assert status.success?, output
    assert_equal "SIGNING_DIAGNOSTIC=SIGNING_CERTIFICATE_MISSING_OR_INVALID\n", output
  end

  def test_missing_or_invalidly_encoded_log_is_fail_closed
    output, status = execute_classifier(File.join(Dir.tmpdir, "missing-signing-log-#{Process.pid}"))
    assert status.success?, output
    assert_equal "SIGNING_DIAGNOSTIC=UNCLASSIFIED\n", output

    Dir.mktmpdir("signing-diagnostic-invalid") do |directory|
      path = File.join(directory, "invalid.log")
      File.binwrite(path, "No signing certificate found\xff".b)
      output, status = execute_classifier(path)
      assert status.success?, output
      assert_equal "SIGNING_DIAGNOSTIC=UNCLASSIFIED\n", output
    end
  end

  def test_archive_and_export_failures_invoke_classifier_but_success_does_not
    archive_output, archive_status = execute_signing_step("archive_failure")
    refute archive_status.success?
    assert_includes archive_output, "SIGNING_DIAGNOSTIC=DEVELOPER_AGREEMENT_UPDATE_REQUIRED"
    assert_includes archive_output, "ERROR_CODE=SIGNING_ARCHIVE_FAILED"
    assert_no_canaries(archive_output)

    export_output, export_status = execute_signing_step("export_failure")
    refute export_status.success?
    assert_includes export_output, "SIGNING_DIAGNOSTIC=PROVISIONING_PROFILE_MISSING_OR_INVALID"
    assert_includes export_output, "ERROR_CODE=SIGNING_EXPORT_FAILED"
    assert_no_canaries(export_output)

    success_output, success_status = execute_signing_step("success")
    assert success_status.success?, success_output
    refute_includes success_output, "SIGNING_DIAGNOSTIC="
    assert_no_canaries(success_output)

    classifier_output, classifier_status = execute_signing_step("classifier_failure")
    refute classifier_status.success?
    assert_includes classifier_output, "SIGNING_DIAGNOSTIC=UNCLASSIFIED"
    assert_includes classifier_output, "ERROR_CODE=SIGNING_ARCHIVE_FAILED"
    assert_no_canaries(classifier_output)
  end

  private

  def classifier_source
    match = @run.match(/#{Regexp.escape(START_MARKER)}\n(?<source>.*?)^#{Regexp.escape(END_MARKER)}$/m)
    refute_nil match, "expected one marker-delimited inline Ruby signing classifier"
    assert_equal 1, @run.scan(START_MARKER).length
    assert_equal 1, @run.scan(END_MARKER).length
    match[:source]
  end

  def classify(content)
    Dir.mktmpdir("signing-diagnostic") do |directory|
      path = File.join(directory, "private.log")
      File.binwrite(path, content)
      return execute_classifier(path)
    end
  end

  def execute_classifier(path)
    Open3.capture2e({"SIGNING_DIAGNOSTIC_LOG_PATH" => path}, "ruby", stdin_data: classifier_source)
  end

  def execute_signing_step(mode)
    Dir.mktmpdir("signing-step") do |directory|
      bin = File.join(directory, "bin")
      FileUtils.mkdir_p(bin)
      fake = File.join(bin, "xcodebuild")
      File.write(fake, <<~'SH')
        #!/bin/sh
        export_archive=false
        for argument in "$@"; do
          [ "$argument" = "-exportArchive" ] && export_archive=true
        done
        case "$XCODEBUILD_MODE:$export_archive" in
          archive_failure:false)
            printf '%s\n' "The Apple Developer Program License Agreement must be accepted. SECRET_KEY_CANARY_7f3d"
            exit 1
            ;;
          classifier_failure:false)
            printf '%s\n' "Unrecognized failure SECRET_KEY_CANARY_7f3d"
            exit 1
            ;;
          export_failure:true)
            printf '%s\n' "No profiles for ACCOUNT_CANARY_123456789 were found at /Users/private/PATH_CANARY.mobileprovision"
            exit 1
            ;;
          *) exit 0 ;;
        esac
      SH
      File.chmod(0755, fake)
      if mode == "classifier_failure"
        ruby = File.join(bin, "ruby")
        File.write(ruby, "#!/bin/sh\nprintf '%s\\n' 'RuntimeError SECRET_KEY_CANARY_7f3d at /Users/private/classifier.rb' >&2\nexit 23\n")
        File.chmod(0755, ruby)
      end
      env = {
        "PATH" => "#{bin}:/usr/bin:/bin",
        "RUNNER_TEMP" => directory,
        "TEAM_ID" => "TEAM_CANARY",
        "BASE_BUNDLE_IDENTIFIER" => "com.example.private",
        "SERVICE_IDENTIFIER" => "com.example.service",
        "VERSION" => "0.0.1",
        "BUILD_NUMBER" => "5",
        "XCODEBUILD_MODE" => mode
      }
      return Open3.capture2e(env, "bash", "-e", "-o", "pipefail", "-c", @run, chdir: directory)
    end
  end

  def assert_no_canaries(output)
    CANARIES.each { |canary| refute_includes output, canary }
    refute_match(%r{https?://}, output)
    refute_match(%r{/Users/}, output)
  end
end
