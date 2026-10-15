# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "openssl"
require "rbconfig"
require "stringio"
require "tmpdir"

SCRIPT = File.expand_path("../../scripts/ios_baseline_manual_signing.rb", __dir__)
require SCRIPT if File.file?(SCRIPT)

class IOSBaselineManualSigningTest < Minitest::Test
  TEAM_ID = "M9D72QQJ79"
  APP_ID = "com.womaninred.baseline"
  EXTENSION_ID = "#{APP_ID}.HiddifyPacketTunnel"
  APP_GROUP = "group.#{APP_ID}"
  NETWORK_EXTENSION = "packet-tunnel-provider"
  NOW = Time.utc(2026, 10, 15, 12, 0, 0)

  class FixtureCMSDecoder
    def initialize(profiles)
      @profiles = profiles
    end

    def decode(cms)
      Marshal.load(Marshal.dump(@profiles.fetch(cms)))
    end
  end

  def implementation
    assert Object.const_defined?(:IOSBaselineManualSigning), "manual signing helper is missing"
    IOSBaselineManualSigning
  end

  def key
    @key ||= OpenSSL::PKey::RSA.new(2048)
  end

  def distribution_certificate(private_key: key, team: TEAM_ID, common_name: nil,
    not_before: NOW - 3600, not_after: NOW + 86_400)
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = 7
    certificate.subject = OpenSSL::X509::Name.parse(
      "/CN=#{common_name || "Apple Distribution: Fixture (#{team})"}/OU=#{team}/O=Fixture/C=US"
    )
    certificate.issuer = certificate.subject
    certificate.public_key = private_key.public_key
    certificate.not_before = not_before
    certificate.not_after = not_after
    factory = OpenSSL::X509::ExtensionFactory.new
    factory.subject_certificate = certificate
    factory.issuer_certificate = certificate
    certificate.add_extension(factory.create_extension("basicConstraints", "CA:FALSE", true))
    certificate.add_extension(factory.create_extension("keyUsage", "digitalSignature", true))
    certificate.add_extension(OpenSSL::X509::Extension.new("1.2.840.113635.100.6.1.4", "DER:05:00"))
    certificate.sign(private_key, OpenSSL::Digest::SHA256.new)
    certificate
  end

  def identity(certificate: distribution_certificate, private_key: key, password: "fixture-password")
    p12 = OpenSSL::PKCS12.create(password, "fixture", private_key, certificate)
    [p12.to_der, password, Digest::SHA256.hexdigest(certificate.to_der)]
  end

  def profile(identifier:, certificate: distribution_certificate, uuid: nil, aps: "production",
    get_task_allow: false, devices: false, all_devices: false, expires: NOW + 86_400,
    app_group: APP_GROUP, network_extension: "packet-tunnel-provider", vpn_api: "allow-vpn", beta: true)
    result = {
      "UUID" => uuid || (identifier == APP_ID ? "APP-PROFILE-UUID" : "EXT-PROFILE-UUID"),
      "Name" => identifier == APP_ID ? "Baseline App Store" : "Baseline Extension App Store",
      "TeamIdentifier" => [TEAM_ID],
      "ExpirationDate" => expires,
      "DeveloperCertificates" => [certificate.to_der],
      "Entitlements" => {
        "application-identifier" => "#{TEAM_ID}.#{identifier}",
        "com.apple.developer.team-identifier" => TEAM_ID,
        "com.apple.security.application-groups" => [app_group],
        "com.apple.developer.networking.networkextension" => Array(network_extension),
        "com.apple.developer.networking.vpn.api" => Array(vpn_api),
        "get-task-allow" => get_task_allow,
        "beta-reports-active" => beta
      }
    }
    result["Entitlements"]["aps-environment"] = aps unless aps.nil?
    result["ProvisionedDevices"] = ["DEVICE"] if devices
    result["ProvisionsAllDevices"] = true if all_devices
    result
  end

  def valid_material(overrides = {})
    certificate = overrides.fetch(:certificate) { distribution_certificate }
    p12_der, password, sha256 = identity(certificate: certificate,
      private_key: overrides.fetch(:private_key, key))
    profiles = {
      "app-cms" => overrides.fetch(:app_profile) { profile(identifier: APP_ID, certificate: certificate) },
      "extension-cms" => overrides.fetch(:extension_profile) do
        profile(identifier: EXTENSION_ID, certificate: certificate)
      end
    }
    implementation.validate_material!(
      p12_der: p12_der,
      p12_password: password,
      pinned_certificate_sha256: overrides.fetch(:pinned_certificate_sha256, sha256),
      app_profile_cms: "app-cms",
      extension_profile_cms: "extension-cms",
      now: NOW,
      cms_decoder: FixtureCMSDecoder.new(profiles)
    )
  end

  def error_code
    error = assert_raises(implementation::SafeError) { yield }
    error.code
  end

  def copy_project_fixture(root)
    FileUtils.mkdir_p(File.join(root, "ios"))
    FileUtils.cp_r(File.expand_path("../../ios/Runner.xcodeproj", __dir__), File.join(root, "ios"))
    FileUtils.cp_r(File.expand_path("../../ios/Runner.xcworkspace", __dir__), File.join(root, "ios"))
    FileUtils.mkdir_p(File.join(root, "ios/Runner"))
    FileUtils.mkdir_p(File.join(root, "ios/HiddifyPacketTunnel"))
    FileUtils.cp(File.expand_path("../../ios/Runner/Runner.entitlements", __dir__),
      File.join(root, "ios/Runner/Runner.entitlements"))
    FileUtils.cp(File.expand_path("../../ios/HiddifyPacketTunnel/HiddifyPacketTunnel.entitlements", __dir__),
      File.join(root, "ios/HiddifyPacketTunnel/HiddifyPacketTunnel.entitlements"))
  end

  def profile_xml(profile_hash)
    certificates = profile_hash.fetch("DeveloperCertificates").map do |certificate|
      "<data>#{Base64.strict_encode64(certificate)}</data>"
    end.join
    entitlements = profile_hash.fetch("Entitlements")
    aps = entitlements.key?("aps-environment") ?
      "<key>aps-environment</key><string>#{entitlements.fetch("aps-environment")}</string>" : ""
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0"><dict>
        <key>UUID</key><string>#{profile_hash.fetch("UUID")}</string>
        <key>Name</key><string>Fixture Profile</string>
        <key>TeamIdentifier</key><array><string>#{TEAM_ID}</string></array>
        <key>ExpirationDate</key><date>#{profile_hash.fetch("ExpirationDate").utc.iso8601}</date>
        <key>DeveloperCertificates</key><array>#{certificates}</array>
        <key>Entitlements</key><dict>
          <key>application-identifier</key><string>#{entitlements.fetch("application-identifier")}</string>
          <key>com.apple.developer.team-identifier</key><string>#{TEAM_ID}</string>
          <key>com.apple.security.application-groups</key><array><string>#{APP_GROUP}</string></array>
          <key>com.apple.developer.networking.networkextension</key><array><string>#{NETWORK_EXTENSION}</string></array>
          <key>com.apple.developer.networking.vpn.api</key><array><string>allow-vpn</string></array>
          <key>get-task-allow</key><false/>
          <key>beta-reports-active</key><true/>
          #{aps}
        </dict>
      </dict></plist>
    XML
  end

  def test_validates_exact_distribution_identity_and_two_app_store_profiles
    material = valid_material

    assert_match(/\A[0-9A-F]{40}\z/, material.certificate_sha1)
    assert_match(/\A[0-9a-f]{64}\z/, material.certificate_sha256)
    assert_equal APP_ID, material.app_profile.bundle_identifier
    assert_equal EXTENSION_ID, material.extension_profile.bundle_identifier
    assert_equal "APP-PROFILE-UUID", material.app_profile.uuid
    assert_equal "EXT-PROFILE-UUID", material.extension_profile.uuid
    refute_includes material.inspect, "Apple Distribution: Fixture"
  end

  def test_cms_decoder_preserves_plist_dates_and_certificate_data
    certificate = distribution_certificate
    xml = profile_xml(profile(identifier: APP_ID, certificate: certificate))
    cms = OpenSSL::PKCS7.sign(certificate, key, xml, [], OpenSSL::PKCS7::BINARY).to_der

    decoded = implementation::CMSDecoder.new.decode(cms)

    assert_equal Time.utc(2026, 10, 16, 12, 0, 0), decoded.fetch("ExpirationDate")
    assert_equal [certificate.to_der], decoded.fetch("DeveloperCertificates")
    assert_equal false, decoded.fetch("Entitlements").fetch("get-task-allow")
    assert_equal "production", decoded.fetch("Entitlements").fetch("aps-environment")
  end

  def test_rejects_private_key_that_does_not_match_certificate
    certificate = distribution_certificate
    code = error_code do
      implementation::IdentityValidator.new(now: NOW).validate!(
        private_key: OpenSSL::PKey::RSA.new(2048), certificate: certificate,
        pinned_sha256: Digest::SHA256.hexdigest(certificate.to_der)
      )
    end

    assert_equal "SIGNING_IDENTITY_KEY_MISMATCH", code
  end

  def test_rejects_development_and_cloud_managed_certificates
    development = distribution_certificate(common_name: "Apple Development: Fixture (#{TEAM_ID})")
    cloud = distribution_certificate(common_name: "Apple Distribution Managed: Fixture (#{TEAM_ID})")

    assert_equal "SIGNING_CERTIFICATE_NOT_DEDICATED_DISTRIBUTION",
      error_code { valid_material(certificate: development) }
    assert_equal "SIGNING_CERTIFICATE_NOT_DEDICATED_DISTRIBUTION",
      error_code { valid_material(certificate: cloud) }
  end

  def test_rejects_wrong_team_expiry_and_unpinned_certificate
    wrong_team = distribution_certificate(team: "AAAAAAAAAA")
    expired = distribution_certificate(not_after: NOW)

    assert_equal "SIGNING_CERTIFICATE_TEAM_MISMATCH",
      error_code { valid_material(certificate: wrong_team) }
    assert_equal "SIGNING_CERTIFICATE_EXPIRED",
      error_code { valid_material(certificate: expired) }
    assert_equal "SIGNING_CERTIFICATE_FINGERPRINT_MISMATCH",
      error_code { valid_material(pinned_certificate_sha256: "0" * 64) }
  end

  def test_rejects_profile_for_wrong_bundle_or_without_exact_signer
    certificate = distribution_certificate
    wrong_bundle = profile(identifier: "com.example.other", certificate: certificate)
    other_certificate = distribution_certificate(private_key: OpenSSL::PKey::RSA.new(2048))
    wrong_signer = profile(identifier: APP_ID, certificate: other_certificate)

    assert_equal "APP_PROFILE_BUNDLE_MISMATCH",
      error_code { valid_material(certificate: certificate, app_profile: wrong_bundle) }
    assert_equal "APP_PROFILE_SIGNER_MISMATCH",
      error_code { valid_material(certificate: certificate, app_profile: wrong_signer) }
  end

  def test_rejects_non_app_store_profile_shapes
    certificate = distribution_certificate

    assert_equal "APP_PROFILE_DEVICE_DISTRIBUTION_FORBIDDEN",
      error_code {
        valid_material(certificate: certificate,
          app_profile: profile(identifier: APP_ID, certificate: certificate, devices: true))
      }
    assert_equal "APP_PROFILE_ENTERPRISE_FORBIDDEN",
      error_code {
        valid_material(certificate: certificate,
          app_profile: profile(identifier: APP_ID, certificate: certificate, all_devices: true))
      }
    assert_equal "APP_PROFILE_NOT_APP_STORE",
      error_code {
        valid_material(certificate: certificate,
          app_profile: profile(identifier: APP_ID, certificate: certificate, beta: false))
      }
  end

  def test_rejects_unsafe_profile_entitlements_and_expiry
    certificate = distribution_certificate

    cases = {
      "APP_PROFILE_GET_TASK_ALLOW_FORBIDDEN" => profile(identifier: APP_ID,
        certificate: certificate, get_task_allow: true),
      "APP_PROFILE_APS_ENVIRONMENT_INVALID" => profile(identifier: APP_ID,
        certificate: certificate, aps: "development"),
      "APP_PROFILE_APP_GROUP_MISSING" => profile(identifier: APP_ID,
        certificate: certificate, app_group: "group.wrong"),
      "APP_PROFILE_NETWORK_EXTENSION_MISSING" => profile(identifier: APP_ID,
        certificate: certificate, network_extension: "wrong"),
      "APP_PROFILE_EXPIRED" => profile(identifier: APP_ID,
        certificate: certificate, expires: NOW)
    }
    cases.each do |expected, app_profile|
      assert_equal expected,
        error_code { valid_material(certificate: certificate, app_profile: app_profile) }
    end

    without_aps = profile(identifier: APP_ID, certificate: certificate, aps: nil)
    assert valid_material(certificate: certificate, app_profile: without_aps)
  end

  def test_rejects_invalid_profile_metadata_without_leaking_values
    certificate = distribution_certificate
    invalid = profile(identifier: APP_ID, certificate: certificate)
    invalid["UUID"] = "SECRET INVALID UUID"

    error = assert_raises(implementation::SafeError) do
      valid_material(certificate: certificate, app_profile: invalid)
    end

    assert_equal "APP_PROFILE_UUID_INVALID", error.code
    assert_equal error.code, error.message
    refute_includes error.message, invalid.fetch("UUID")
  end

  def test_creates_target_specific_release_overrides_without_changing_source_project
    material = valid_material
    Dir.mktmpdir("manual-signing-test") do |root|
      copy_project_fixture(root)
      original = File.binread(File.join(root, "ios/Runner.xcodeproj/project.pbxproj"))

      overrides = implementation::ProjectOverrides.new(
        project_root: root, material: material, nonce: "fixture123"
      ).prepare!

      assert_equal original, File.binread(File.join(root, "ios/Runner.xcodeproj/project.pbxproj"))
      generated = File.binread(File.join(overrides.project_path, "project.pbxproj"))
      assert_equal 2, generated.scan(/CODE_SIGN_STYLE = Manual;/).length
      assert_equal 2, generated.scan(/DEVELOPMENT_TEAM = #{TEAM_ID};/).length
      assert_equal 1, generated.scan(/PROVISIONING_PROFILE_SPECIFIER = APP-PROFILE-UUID;/).length
      assert_equal 1, generated.scan(/PROVISIONING_PROFILE_SPECIFIER = EXT-PROFILE-UUID;/).length
      assert_equal 2, generated.scan(/CODE_SIGN_IDENTITY\[sdk=iphoneos\*\]" = #{material.certificate_sha1};/).length
      refute_match(/Pods-Runner[^\n]+PROVISIONING_PROFILE/, generated)

      workspace = File.read(File.join(overrides.workspace_path, "contents.xcworkspacedata"))
      assert_includes workspace, "Runner.manual-fixture123.xcodeproj"
      assert_includes workspace, "Pods/Pods.xcodeproj"
      schemes = Dir.glob(File.join(overrides.project_path, "**", "*.xcscheme"))
      refute_empty schemes
      schemes.each do |scheme|
        contents = File.read(scheme)
        assert_includes contents, "container:Runner.manual-fixture123.xcodeproj"
        refute_includes contents, "container:Runner.xcodeproj"
      end
      assert_equal 2, Dir.glob(File.join(overrides.entitlements_root, "*.entitlements")).length
      contains_development = Dir.glob(File.join(overrides.entitlements_root, "*.entitlements")).any? do |path|
        File.read(path).include?("<string>development</string>")
      end
      refute contains_development

      export = File.read(overrides.export_options_path)
      assert_includes export, "<string>manual</string>"
      assert_includes export, APP_ID
      assert_includes export, EXTENSION_ID
      assert_includes export, material.certificate_sha1
      overrides.cleanup!
      refute File.exist?(overrides.project_path)
      refute File.exist?(overrides.workspace_path)
      assert_equal original, File.binread(File.join(root, "ios/Runner.xcodeproj/project.pbxproj"))
    end
  end

  def test_provenance_contains_public_hashes_and_no_identity_subject_or_profile_names
    material = valid_material
    Dir.mktmpdir("manual-signing-test") do |root|
      copy_project_fixture(root)
      overrides = implementation::ProjectOverrides.new(
        project_root: root, material: material, nonce: "fixture123"
      ).prepare!

      receipt = overrides.provenance(controller_sha: "2e2dc8d1180b0afb79fc99483bc0bcec7f3c71de")
      encoded = JSON.generate(receipt)
      assert_equal "ios-baseline-manual-signing-overrides/v1", receipt.fetch("schema")
      assert_equal material.certificate_sha256, receipt.fetch("certificateSHA256")
      assert_equal [APP_ID, EXTENSION_ID], receipt.fetch("targets").map { |target| target.fetch("bundleIdentifier") }
      assert receipt.fetch("originalProjectSHA256").match?(/\A[0-9a-f]{64}\z/)
      assert receipt.fetch("overrideProjectSHA256").match?(/\A[0-9a-f]{64}\z/)
      refute_includes encoded, "Apple Distribution: Fixture"
      refute_includes encoded, "Baseline App Store"
      refute_includes encoded, "APP-PROFILE-UUID"
    ensure
      overrides&.cleanup!
    end
  end

  def test_override_collision_is_never_deleted
    material = valid_material
    Dir.mktmpdir("manual-signing-test") do |root|
      copy_project_fixture(root)
      collision = File.join(root, "ios/Runner.manual-fixture123.xcodeproj")
      FileUtils.mkdir_p(collision)
      sentinel = File.join(collision, "sentinel")
      File.write(sentinel, "owner-data")

      code = error_code do
        implementation::ProjectOverrides.new(
          project_root: root, material: material, nonce: "fixture123"
        ).prepare!
      end

      assert_equal "SIGNING_OVERRIDE_COLLISION", code
      assert_equal "owner-data", File.read(sentinel)
    end
  end

  def test_required_source_aps_entitlement_cannot_be_silently_removed
    certificate = distribution_certificate
    material = valid_material(certificate: certificate,
      app_profile: profile(identifier: APP_ID, certificate: certificate, aps: nil))
    Dir.mktmpdir("manual-signing-test") do |root|
      copy_project_fixture(root)
      path = File.join(root, "ios/Runner/Runner.entitlements")
      source = File.read(path).sub("<dict>", "<dict>\n\t<key>aps-environment</key>\n\t<string>development</string>")
      File.write(path, source)

      code = error_code do
        implementation::ProjectOverrides.new(
          project_root: root, material: material, nonce: "fixture123"
        ).prepare!
      end

      assert_equal "APP_PROFILE_APS_ENVIRONMENT_REQUIRED", code
      assert_equal source, File.read(path)
    end
  end

  def test_source_entitlements_are_preserved_with_only_group_and_aps_release_substitutions
    certificate = distribution_certificate
    app_profile = profile(identifier: APP_ID, certificate: certificate,
      network_extension: %w[app-proxy-provider packet-tunnel-provider])
    material = valid_material(certificate: certificate, app_profile: app_profile)
    Dir.mktmpdir("manual-signing-test") do |root|
      copy_project_fixture(root)
      path = File.join(root, "ios/Runner/Runner.entitlements")
      source = File.read(path)
        .sub("<dict>", "<dict>\n\t<key>aps-environment</key>\n\t<string>development</string>")
        .sub("<string>packet-tunnel-provider</string>",
          "<string>app-proxy-provider</string>\n\t\t<string>packet-tunnel-provider</string>")
      File.write(path, source)

      overrides = implementation::ProjectOverrides.new(
        project_root: root, material: material, nonce: "fixture123"
      ).prepare!
      generated = File.read(File.join(overrides.entitlements_root, "app.entitlements"))

      assert_includes generated, "app-proxy-provider"
      assert_includes generated, "packet-tunnel-provider"
      assert_includes generated, "allow-vpn"
      assert_includes generated, "group.#{APP_ID}"
      assert_includes generated, "<string>production</string>"
      refute_includes generated, "<string>development</string>"
      assert_equal source, File.read(path)
    ensure
      overrides&.cleanup!
    end
  end

  def test_profile_must_grant_every_source_network_extension_value
    material = valid_material
    Dir.mktmpdir("manual-signing-test") do |root|
      copy_project_fixture(root)
      path = File.join(root, "ios/Runner/Runner.entitlements")
      source = File.read(path).sub("<string>packet-tunnel-provider</string>",
        "<string>app-proxy-provider</string>\n\t\t<string>packet-tunnel-provider</string>")
      File.write(path, source)

      code = error_code do
        implementation::ProjectOverrides.new(
          project_root: root, material: material, nonce: "fixture123"
        ).prepare!
      end

      assert_equal "APP_PROFILE_NETWORK_EXTENSION_GRANT_MISSING", code
      assert_equal source, File.read(path)
    end
  end

  class CleanupFixtureRunner
    attr_reader :commands

    def initialize(fail_on: nil)
      @fail_on = fail_on
      @commands = []
    end

    def run!(*command, code:)
      @commands << command
      raise IOSBaselineManualSigning::SafeError, code if command.include?(@fail_on)
    end

    def capture!(*command, code:)
      @commands << command
      return "\"/tmp/original.keychain-db\"\n" if command.include?("list-keychains")

      @identity_output || ""
    end

    attr_writer :identity_output
  end

  def test_session_cleanup_attempts_every_owned_resource_after_restore_failure
    Dir.mktmpdir("manual-signing-cleanup") do |parent|
      root = File.join(parent, "owned")
      FileUtils.mkdir_p(root)
      keychain = File.join(root, "manual-signing.keychain-db")
      private_key = File.join(root, "distribution.key.pem")
      File.write(keychain, "fixture")
      File.write(private_key, "private-key-canary")
      runner = CleanupFixtureRunner.new(fail_on: "list-keychains")
      session = implementation::SigningSession.new(material: valid_material,
        project_root: Dir.pwd, runner: runner)
      session.instance_variable_set(:@temporary_root, root)
      session.instance_variable_set(:@keychain_path, keychain)
      session.instance_variable_set(:@keychain_created, true)
      session.instance_variable_set(:@original_keychains, ["/tmp/original.keychain-db"])

      error = assert_raises(implementation::SafeError) { session.cleanup! }

      assert_equal "KEYCHAIN_LIST_RESTORE_FAILED", error.code
      assert runner.commands.any? { |command| command.include?("delete-keychain") }
      refute File.exist?(private_key)
      refute File.exist?(root)
    end
  end

  def test_profiles_use_xcode_userdata_location_and_cleanup_only_owned_files
    material = valid_material
    runner = CleanupFixtureRunner.new
    runner.identity_output = "1) #{material.certificate_sha1}\n  1 valid identities found"
    Dir.mktmpdir("manual-signing-home") do |home|
      session = implementation::SigningSession.new(material: material,
        project_root: Dir.pwd, runner: runner, home: home)
      session.prepare!
      profile_root = File.join(home, "Library/Developer/Xcode/UserData/Provisioning Profiles")
      app_path = File.join(profile_root, "APP-PROFILE-UUID.mobileprovision")
      extension_path = File.join(profile_root, "EXT-PROFILE-UUID.mobileprovision")
      assert_equal material.app_profile.cms_der, File.binread(app_path)
      assert_equal material.extension_profile.cms_der, File.binread(extension_path)

      session.cleanup!

      refute File.exist?(app_path)
      refute File.exist?(extension_path)
    end
  end

  def test_empty_original_keychain_search_list_fails_closed
    material = valid_material
    runner = CleanupFixtureRunner.new
    runner.identity_output = "1) #{material.certificate_sha1}\n  1 valid identities found"
    runner.define_singleton_method(:capture!) do |*command, code:|
      @commands << command
      command.include?("list-keychains") ? "" : @identity_output.to_s
    end
    Dir.mktmpdir("manual-signing-home") do |home|
      session = implementation::SigningSession.new(material: material,
        project_root: Dir.pwd, runner: runner, home: home)

      error = assert_raises(implementation::SafeError) { session.prepare! }

      assert_equal "KEYCHAIN_LIST_INVALID", error.code
    end
  end

  def test_digest_equal_existing_profile_is_reused_and_preserved
    material = valid_material
    runner = CleanupFixtureRunner.new
    runner.identity_output = "1) #{material.certificate_sha1}\n  1 valid identities found"
    Dir.mktmpdir("manual-signing-home") do |home|
      profile_root = File.join(home, "Library/Developer/Xcode/UserData/Provisioning Profiles")
      FileUtils.mkdir_p(profile_root)
      app_path = File.join(profile_root, "APP-PROFILE-UUID.mobileprovision")
      File.binwrite(app_path, material.app_profile.cms_der)

      session = implementation::SigningSession.new(material: material,
        project_root: Dir.pwd, runner: runner, home: home)
      session.prepare!
      session.cleanup!

      assert_equal material.app_profile.cms_der, File.binread(app_path)
    end
  end

  def test_different_existing_profile_is_never_overwritten_or_deleted
    material = valid_material
    runner = CleanupFixtureRunner.new
    runner.identity_output = "1) #{material.certificate_sha1}\n  1 valid identities found"
    Dir.mktmpdir("manual-signing-home") do |home|
      profile_root = File.join(home, "Library/Developer/Xcode/UserData/Provisioning Profiles")
      FileUtils.mkdir_p(profile_root)
      app_path = File.join(profile_root, "APP-PROFILE-UUID.mobileprovision")
      File.binwrite(app_path, "preexisting-owner-data")
      session = implementation::SigningSession.new(material: material,
        project_root: Dir.pwd, runner: runner, home: home)

      error = assert_raises(implementation::SafeError) { session.prepare! }

      assert_equal "PROFILE_DESTINATION_COLLISION", error.code
      assert_equal "preexisting-owner-data", File.binread(app_path)
    end
  end

  class WrapperFixtureSession
    attr_reader :keychain_path, :prepared, :cleaned

    def initialize(signal_during_prepare: nil)
      @keychain_path = "/tmp/fixture-signing.keychain-db"
      @signal_during_prepare = signal_during_prepare
    end

    def prepare!
      @prepared = true
      Process.kill(@signal_during_prepare, Process.pid) if @signal_during_prepare
      self
    end

    def cleanup!
      @cleaned = true
    end
  end

  class WrapperFixtureVerifier
    attr_reader :verified

    def verify!
      @verified = true
    end
  end

  class SignedArtifactFixtureRunner
    def initialize(certificates)
      @certificates = certificates
    end

    def run!(*command, code:)
      if command.include?("--extract-certificates")
        prefix = command[command.index("--extract-certificates") + 1]
        bundle = command.last
        role = bundle.end_with?("HiddifyPacketTunnel.appex") ? :extension : :app
        File.binwrite("#{prefix}0", @certificates.fetch(role))
      elsif command.first == "/usr/bin/ditto"
        destination = command.last
        app = File.join(destination, "Payload/Runner.app")
        FileUtils.mkdir_p(File.join(app, "PlugIns/HiddifyPacketTunnel.appex"))
      end
    end
  end

  def test_signed_artifact_verifier_pins_archive_and_exported_ipa_certificates
    certificate = distribution_certificate
    digest = Digest::SHA256.hexdigest(certificate.to_der)
    runner = SignedArtifactFixtureRunner.new(app: certificate.to_der, extension: certificate.to_der)
    Dir.mktmpdir("signed-artifact") do |root|
      archive_app = File.join(root, "build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app")
      FileUtils.mkdir_p(File.join(archive_app, "PlugIns/HiddifyPacketTunnel.appex"))
      FileUtils.mkdir_p(File.join(root, "build/ios/ipa"))
      File.binwrite(File.join(root, "build/ios/ipa/Runner.ipa"), "fixture")

      verifier = implementation::SignedArtifactVerifier.new(
        project_root: root, pinned_certificate_sha256: digest, runner: runner
      )

      assert verifier.verify!
    end
  end

  def test_signed_artifact_verifier_rejects_any_unpinned_nested_signer
    certificate = distribution_certificate
    other = distribution_certificate(private_key: OpenSSL::PKey::RSA.new(2048))
    runner = SignedArtifactFixtureRunner.new(app: certificate.to_der, extension: other.to_der)
    Dir.mktmpdir("signed-artifact") do |root|
      archive_app = File.join(root, "build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app")
      FileUtils.mkdir_p(File.join(archive_app, "PlugIns/HiddifyPacketTunnel.appex"))
      FileUtils.mkdir_p(File.join(root, "build/ios/ipa"))
      File.binwrite(File.join(root, "build/ios/ipa/Runner.ipa"), "fixture")
      verifier = implementation::SignedArtifactVerifier.new(
        project_root: root, pinned_certificate_sha256: Digest::SHA256.hexdigest(certificate.to_der), runner: runner
      )

      error = assert_raises(implementation::SafeError) { verifier.verify! }

      assert_equal "SIGNED_ARTIFACT_CERTIFICATE_MISMATCH", error.code
    end
  end

  def test_wrapper_inherits_stdin_but_scrubs_signing_and_apple_api_credentials
    material = valid_material
    Dir.mktmpdir("manual-signing-wrapper") do |root|
      copy_project_fixture(root)
      output = File.join(root, "child.json")
      provenance = File.join(root, "out/provenance.json")
      session = WrapperFixtureSession.new
      verifier = WrapperFixtureVerifier.new
      command = [RbConfig.ruby, "-rjson", "-e", <<~'RUBY', output]
        names = %w[
          IOS_BASELINE_SIGNING_P12_BASE64 IOS_BASELINE_SIGNING_P12_PASSWORD
          IOS_BASELINE_APP_PROFILE_BASE64 IOS_BASELINE_EXTENSION_PROFILE_BASE64
          IOS_BASELINE_SIGNING_CERT_SHA256 APPSTORE_API_PRIVATE_KEY ASC_PRIVATE_KEY
        ]
        payload = {
          "stdin" => STDIN.read,
          "secretsPresent" => names.select { |name| ENV.key?(name) },
          "workspace" => ENV.fetch("IOS_BASELINE_SIGNING_WORKSPACE"),
          "exportOptions" => ENV.fetch("IOS_BASELINE_SIGNING_EXPORT_OPTIONS"),
          "keychain" => ENV.fetch("IOS_BASELINE_SIGNING_KEYCHAIN"),
          "controllerSHA" => ENV.fetch("SIGNING_CONTROLLER_SHA")
        }
        File.write(ARGV.fetch(0), JSON.generate(payload))
      RUBY
      input = Tempfile.new("manual-signing-stdin")
      input.write("archive-and-export-heredoc")
      input.rewind
      previous_stdin = $stdin
      previous = {}
      %w[IOS_BASELINE_SIGNING_P12_BASE64 APPSTORE_API_PRIVATE_KEY ASC_PRIVATE_KEY].each do |name|
        previous[name] = ENV[name]
        ENV[name] = "SECRET_CANARY"
      end
      $stdin = input

      status = implementation::WithSigning.new(
        project_root: root, provenance_path: provenance, material: material,
        controller_sha: "2e2dc8d1180b0afb79fc99483bc0bcec7f3c71de",
        command: command, session: session, artifact_verifier: verifier, nonce: "fixture123"
      ).run

      payload = JSON.parse(File.read(output))
      assert_equal 0, status
      assert_equal "archive-and-export-heredoc", payload.fetch("stdin")
      assert_empty payload.fetch("secretsPresent")
      assert_equal session.keychain_path, payload.fetch("keychain")
      assert_includes payload.fetch("workspace"), "Runner.manual-fixture123.xcworkspace"
      assert_includes payload.fetch("exportOptions"), ".manual-signing-fixture123"
      assert_equal "2e2dc8d1180b0afb79fc99483bc0bcec7f3c71de", payload.fetch("controllerSHA")
      assert session.cleaned
      assert verifier.verified
      refute File.exist?(File.join(root, "ios/Runner.manual-fixture123.xcworkspace"))
    ensure
      $stdin = previous_stdin if previous_stdin
      input&.close!
      previous&.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    end
  end

  def test_term_during_prepare_cleans_up_and_never_spawns_child
    material = valid_material
    Dir.mktmpdir("manual-signing-wrapper") do |root|
      copy_project_fixture(root)
      marker = File.join(root, "child-ran")
      session = WrapperFixtureSession.new(signal_during_prepare: "TERM")

      status = implementation::WithSigning.new(
        project_root: root, provenance_path: File.join(root, "out/provenance.json"),
        material: material, controller_sha: "2e2dc8d1180b0afb79fc99483bc0bcec7f3c71de",
        command: [RbConfig.ruby, "-e", "File.write(ARGV.fetch(0), 'ran')", marker],
        session: session, nonce: "fixture123"
      ).run

      assert_equal 128 + Signal.list.fetch("TERM"), status
      assert session.prepared
      assert session.cleaned
      refute File.exist?(marker)
      refute File.exist?(File.join(root, "ios/Runner.manual-fixture123.xcworkspace"))
    end
  end
end
