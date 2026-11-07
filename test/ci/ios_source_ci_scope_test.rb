# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "open3"
require "tmpdir"
require "fileutils"

class IosSourceCiScopeTest < Minitest::Test
  def test_generic_matrix_is_disabled_while_full_source_tests_remain_enabled
    workflow = YAML.safe_load(File.read(File.expand_path("../../.github/workflows/build.yml", __dir__)))
    jobs = workflow.fetch("jobs")
    assert_equal "${{ false }}", jobs.fetch("build")["if"],
                 "The iOS-only source PR must not trigger Android, desktop or Linux builds"
    source_tests = jobs.fetch("test")
    refute source_tests.key?("if"), "Full source tests must remain unconditional"
    assert source_tests.fetch("steps").any? { |step| step["run"] == "flutter test" }
    assert_equal "test", jobs.fetch("build").fetch("needs")
  end

  ROOT = File.expand_path("../..", __dir__)
  VALIDATOR = ".github/scripts/validate_ios_release_config.py"
  PROJECT = "ios/Runner.xcodeproj/project.pbxproj"
  FIXTURE_FILES = [
    VALIDATOR, PROJECT, "pubspec.yaml", "ios/Base.xcconfig", "ios/exportOptions.plist",
    "ios/Runner/Runner.entitlements", "ios/HiddifyPacketTunnel/HiddifyPacketTunnel.entitlements",
    "ios/Runner/Info.plist", "ios/HiddifyPacketTunnel/Info.plist",
    "ios/Runner/PrivacyInfo.xcprivacy", "ios/HiddifyPacketTunnel/PrivacyInfo.xcprivacy"
  ].freeze

  def test_validator_accepts_actual_luma_configuration
    assert_validator(ROOT, success: true)
  end

  def test_flutter_versions_work_before_generated_config_exists
    with_fixture do |root|
      refute File.exist?(File.join(root, "ios/Flutter/Generated.xcconfig"))
      assert_validator(root, success: true)
    end
  end

  def test_matching_literal_versions_are_supported
    with_fixture do |root|
      version, build = File.read(File.join(root, "pubspec.yaml")).match(/^version:\s*(\d+\.\d+\.\d+)\+(\d+)$/).captures
      rewrite(root, PROJECT) { |text| text.gsub("$(FLUTTER_BUILD_NAME)", version).gsub("$(FLUTTER_BUILD_NUMBER)", build) }
      assert_validator(root, success: true)
    end
  end

  def test_inconsistent_or_unknown_version_settings_fail
    [
      ["$(FLUTTER_BUILD_NAME)", "99.98.97"],
      ["$(FLUTTER_BUILD_NUMBER)", "999999"],
      ["$(FLUTTER_BUILD_NAME)", "$(FLUTTER_BUILD_NUMBER)"],
      ["$(FLUTTER_BUILD_NUMBER)", "$(UNKNOWN_BUILD_NUMBER)"]
    ].each do |from, to|
      with_fixture do |root|
        rewrite(root, PROJECT) { |text| text.sub(from, to) }
        assert_validator(root, success: false, message: "versions are inconsistent")
      end
    end
  end

  def test_flutter_versions_require_generated_config_source_linkage
    with_fixture do |root|
      rewrite(root, "ios/Base.xcconfig") { |text| text.sub('Flutter/Generated.xcconfig', 'Flutter/Other.xcconfig') }
      assert_validator(root, success: false, message: "to include Flutter/Generated.xcconfig")
    end
  end

  def test_team_mismatches_fail
    with_fixture do |root|
      rewrite(root, PROJECT) { |text| text.sub(/DEVELOPMENT_TEAM = [A-Z0-9]+;/, "DEVELOPMENT_TEAM = WRONGTEAM;") }
      assert_validator(root, success: false, message: "Xcode Team IDs")
    end
    with_fixture do |root|
      update_export(root, "options['teamID'] = 'WRONGTEAM'")
      assert_validator(root, success: false, message: "Team ID does not match")
    end
  end

  def test_manual_signing_requires_correct_profiles_and_automatic_validates_supplied_profiles
    %w[automatic manual].each do |style|
      with_fixture do |root|
        update_export(root, "options['signingStyle'] = '#{style}'; options.pop('provisioningProfiles', None)")
        assert_validator(root, success: style == "automatic", message: style == "manual" ? "profile bundle IDs" : nil)
      end
      with_fixture do |root|
        update_export(root, "options['signingStyle'] = '#{style}'; options['provisioningProfiles'] = {'wrong.bundle': 'Profile'}")
        assert_validator(root, success: false, message: "profile bundle IDs")
      end
      with_fixture do |root|
        bundle = File.read(File.join(root, "ios/Base.xcconfig")).match(/^BASE_BUNDLE_IDENTIFIER\s*=\s*(\S+)/)[1]
        update_export(root, "options['signingStyle'] = '#{style}'; options['provisioningProfiles'] = {'#{bundle}': 'App Profile', '#{bundle}.HiddifyPacketTunnel': 'Tunnel Profile'}")
        assert_validator(root, success: true)
      end
    end
  end

  private

  def with_fixture
    Dir.mktmpdir("ios-release-config-") do |root|
      FIXTURE_FILES.each do |relative|
        destination = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(File.join(ROOT, relative), destination)
      end
      yield root
    end
  end

  def rewrite(root, relative)
    path = File.join(root, relative)
    File.write(path, yield(File.read(path)))
  end

  def update_export(root, mutation)
    script = <<~PYTHON
      import plistlib, sys
      from pathlib import Path
      path = Path(sys.argv[1])
      options = plistlib.loads(path.read_bytes())
      #{mutation}
      path.write_bytes(plistlib.dumps(options))
    PYTHON
    output, status = Open3.capture2e("python3", "-c", script, File.join(root, "ios/exportOptions.plist"))
    assert status.success?, output
  end

  def assert_validator(root, success:, message: nil)
    output, status = Open3.capture2e("python3", File.join(root, VALIDATOR), chdir: root)
    assert_equal success, status.success?, output
    assert_includes output, message if message
  end
end
