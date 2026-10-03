#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "base64"
require "openssl"
require "time"
require_relative "../../scripts/verify_ios_baseline_ipa"

# Provisioning fixtures exercise the permission comparison boundary only.
# Real codesign verification and embedded-profile extraction still require an IPA.
class IosBaselineSignedEntitlementsTest < Minitest::Test
  TEAM = "M9D72QQJ79"
  APP = "com.womaninred.baseline"
  EXTENSION = "#{APP}.HiddifyPacketTunnel"
  GROUP = "group.#{APP}"

  def setup
    @app = entitlements(APP)
    @extension = entitlements(EXTENSION)
    @app_profile = profile(@app)
    @extension_profile = profile(@extension)
  end

  def entitlements(bundle)
    {
      "application-identifier" => "#{TEAM}.#{bundle}",
      "com.apple.developer.team-identifier" => TEAM,
      "com.apple.security.application-groups" => [GROUP],
      "com.apple.developer.networking.networkextension" => ["packet-tunnel-provider"],
      "com.apple.developer.networking.vpn.api" => ["allow-vpn"],
      "get-task-allow" => false
    }
  end

  def profile(grants)
    { "TeamIdentifier" => [TEAM], "ApplicationIdentifierPrefix" => [TEAM], "Entitlements" => Marshal.load(Marshal.dump(grants)) }
  end

  def iphoneos_info(identifier = APP)
    { "CFBundleIdentifier" => identifier, "CFBundleSupportedPlatforms" => ["iPhoneOS"], "DTPlatformName" => "iphoneos" }
  end

  def verify
    IosBaselineSignedEntitlements.verify!(
      app: @app, extension: @extension,
      app_profile: @app_profile, extension_profile: @extension_profile,
      team: TEAM, app_identifier: APP, extension_identifier: EXTENSION,
      app_group: GROUP
    )
  end

  def assert_rejected(code)
    error = assert_raises(IosBaselineSignedEntitlements::SafeError) { verify }
    assert_equal code, error.code
    refute_match(/profileContent|BEGIN .*PRIVATE KEY|subscription/i, error.message)
  end

  def test_accepts_distinct_targets_with_matching_provisioned_permissions
    assert_equal true, verify
  end

  def test_rejects_old_woman_in_red_application_identifier
    @app["application-identifier"] = "#{TEAM}.com.womaninred.app"
    assert_rejected("APP_ID_MISMATCH")
  end

  def test_rejects_wrong_extension_even_if_its_profile_matches_it
    @extension["application-identifier"] = "#{TEAM}.#{APP}.SingBoxPacketTunnel"
    @extension_profile = profile(@extension)
    assert_rejected("EXTENSION_ID_MISMATCH")
  end

  def test_rejects_wrong_team_in_either_signature_or_profile
    [@app, @extension].each do |signed|
      original = signed["com.apple.developer.team-identifier"]
      signed["com.apple.developer.team-identifier"] = "WRONGTEAM1"
      assert_rejected("TEAM_MISMATCH")
      signed["com.apple.developer.team-identifier"] = original
    end
    [@app_profile, @extension_profile].each do |embedded|
      original = embedded["TeamIdentifier"]
      embedded["TeamIdentifier"] = ["WRONGTEAM1"]
      assert_rejected("TEAM_MISMATCH")
      embedded["TeamIdentifier"] = original
    end
  end

  def test_rejects_shared_or_missing_app_group_in_both_targets
    [@app, @extension].each do |signed|
      original = signed["com.apple.security.application-groups"]
      [["group.com.womaninred.app"], [GROUP, "group.com.womaninred.app"], []].each do |groups|
        signed["com.apple.security.application-groups"] = groups
        assert_rejected("APP_GROUP_MISMATCH")
      end
      signed["com.apple.security.application-groups"] = original
    end
  end

  def test_rejects_missing_grant_in_each_embedded_profile
    [@app_profile, @extension_profile].each do |embedded|
      key = "com.apple.developer.networking.networkextension"
      original = embedded["Entitlements"].delete(key)
      assert_rejected("ENTITLEMENT_NOT_PROVISIONED")
      embedded["Entitlements"][key] = original
    end
  end

  def test_rejects_a_value_not_granted_by_its_own_target_profile
    @extension["com.apple.developer.networking.networkextension"] << "dns-proxy"
    # Granting it to the other target must not satisfy the extension's profile.
    @app_profile["Entitlements"]["com.apple.developer.networking.networkextension"] << "dns-proxy"
    assert_rejected("ENTITLEMENT_NOT_PROVISIONED")
  end

  def test_accepts_signed_subset_of_profile_array_permissions
    @extension_profile["Entitlements"]["com.apple.developer.networking.networkextension"] << "dns-proxy"
    assert_equal true, verify
  end

  def test_rejects_get_task_allow_for_distribution
    @app["get-task-allow"] = true
    @app_profile["Entitlements"]["get-task-allow"] = true
    assert_rejected("DEBUG_ENTITLEMENT")
  end

  def test_checks_additional_entitlements_instead_of_a_small_allowlist
    @app["aps-environment"] = "production"
    assert_rejected("ENTITLEMENT_NOT_PROVISIONED")
    @app_profile["Entitlements"]["aps-environment"] = "development"
    assert_rejected("ENTITLEMENT_NOT_PROVISIONED")
    @app_profile["Entitlements"]["aps-environment"] = "production"
    assert_equal true, verify
  end
  def test_accepts_legacy_app_prefix_independent_of_team
    [@app, @extension, @app_profile["Entitlements"], @extension_profile["Entitlements"]].each do |rights|
      rights["application-identifier"] = rights["application-identifier"].sub(TEAM, "OLDPREFIX1")
    end
    [@app_profile, @extension_profile].each { |p| p["ApplicationIdentifierPrefix"] = ["OLDPREFIX1"] }
    assert_equal true, verify
  end

  def test_rejects_missing_or_unrelated_authorized_prefix
    @app_profile["ApplicationIdentifierPrefix"] = ["OTHERPRE01"]
    assert_rejected("APP_ID_MISMATCH")
    @app_profile.delete("ApplicationIdentifierPrefix")
    assert_rejected("PROFILE_MALFORMED")
  end

  def test_preserves_source_macos_boolean_rights_without_profile_grants
    %w[com.apple.security.app-sandbox com.apple.security.network.client com.apple.security.network.server].each do |key|
      @app[key] = @extension[key] = true
    end
    assert_equal true, verify
    @app["com.apple.security.network.client"] = "true"
    assert_rejected("ENTITLEMENTS_MALFORMED")
  end

  def test_accepts_profile_identifier_and_keychain_wildcards_only
    @app_profile["Entitlements"]["application-identifier"] = "#{TEAM}.*"
    @app["keychain-access-groups"] = ["#{TEAM}.#{APP}"]
    @app_profile["Entitlements"]["keychain-access-groups"] = ["#{TEAM}.*"]
    assert_equal true, verify
    @app_profile["Entitlements"]["com.apple.developer.networking.networkextension"] = ["*"]
    assert_rejected("ENTITLEMENT_NOT_PROVISIONED")
  end

  def test_rejects_malformed_profile_and_signed_objects_safely
    @app_profile["Entitlements"] = []
    assert_rejected("PROFILE_MALFORMED")
    @app_profile = profile(@app)
    @extension = nil
    assert_rejected("ENTITLEMENTS_MALFORMED")
  end

  def test_rejects_missing_packet_tunnel_even_if_profile_allows_absence
    @extension.delete("com.apple.developer.networking.networkextension")
    assert_rejected("REQUIRED_ENTITLEMENT_MISSING")
  end

  def test_archive_symlinks_are_rejected_before_extraction
    Dir.mktmpdir do |dir|
      ipa = File.join(dir, "fixture.ipa")
      File.write(ipa, "fixture")
      calls = []
      capture = lambda do |*args, **_kwargs|
        calls << args
        args.include?("-Z1") ? "Payload/App.app/link\n" : "lrwxr-xr-x  2.0 unx 12 b- stor 01-Jan-26 00:00 Payload/App.app/link\n"
      end
      IosBaselineSignedEntitlements.stub(:capture!, capture) do
        error = assert_raises(IosBaselineSignedEntitlements::SafeError) do
          IosBaselineSignedEntitlements.verify_ipa!(ipa: ipa, team: TEAM, app_identifier: APP,
            extension_identifier: EXTENSION, app_group: GROUP)
        end
        assert_equal "IPA_INVALID", error.code
      end
      refute calls.any? { |args| args.first == "/usr/bin/ditto" }
    end
  end

  def test_capture_does_not_expose_subprocess_diagnostics
    status = Object.new
    def status.success?; false; end
    Open3.stub(:capture3, ["profileContent", "PRIVATE KEY confidential", status]) do
      error = assert_raises(IosBaselineSignedEntitlements::SafeError) do
        IosBaselineSignedEntitlements.capture!("unused", code: "SIGNATURE_INVALID")
      end
      assert_equal "SIGNATURE_INVALID", error.message
    end
  end

  def test_real_profile_plist_types_are_supported
    xml = '<?xml version="1.0"?><plist version="1.0"><dict><key>ExpirationDate</key><date>2027-01-01T00:00:00Z</date><key>DeveloperCertificates</key><array><data>YWJj</data></array><key>Entitlements</key><dict><key>get-task-allow</key><false/></dict></dict></plist>'
    parsed = IosBaselineSignedEntitlements.plist!(xml)
    assert_equal "2027-01-01T00:00:00Z", parsed["ExpirationDate"]
    assert_equal ["YWJj"], parsed["DeveloperCertificates"]
    assert_equal false, parsed["Entitlements"]["get-task-allow"]
  end

  def test_source_capabilities_preserved_and_push_transformed_for_distribution
    source = { "aps-environment" => "development", "com.apple.security.application-groups" => ["group.$(BASE_BUNDLE_IDENTIFIER)"],
      "com.apple.developer.networking.networkextension" => ["packet-tunnel-provider", "dns-proxy"], "com.apple.security.network.client" => true }
    signed = Marshal.load(Marshal.dump(source))
    signed["aps-environment"] = "production"
    signed["com.apple.security.application-groups"] = [GROUP]
    assert IosBaselineSignedEntitlements.preserve_source!(signed, source, APP)
    signed["com.apple.developer.networking.networkextension"].pop
    error = assert_raises(IosBaselineSignedEntitlements::SafeError) { IosBaselineSignedEntitlements.preserve_source!(signed, source, APP) }
    assert_equal "SOURCE_ENTITLEMENTS_MISMATCH", error.code
  end

  def test_iphoneos_bundle_may_omit_only_boolean_macos_source_rights
    IosBaselineSignedEntitlements::MACOS_BOOLEAN_KEYS.each do |key|
      assert IosBaselineSignedEntitlements.preserve_source!({}, { key => true }, APP, bundle_info: iphoneos_info)
    end
    source = IosBaselineSignedEntitlements::MACOS_BOOLEAN_KEYS.to_h { |key| [key, true] }
    source["com.apple.security.network.client"] = false

    assert IosBaselineSignedEntitlements.preserve_source!({}, source, APP, bundle_info: iphoneos_info)

    error = assert_raises(IosBaselineSignedEntitlements::SourceMismatchError) do
      IosBaselineSignedEntitlements.preserve_source!({}, source, APP)
    end
    assert_equal %w[MACOS_SANDBOX MACOS_NETWORK_CLIENT MACOS_NETWORK_SERVER],
      error.public_payload[:mismatched_entitlements]
  end

  def test_iphoneos_bundle_does_not_relax_present_or_non_boolean_macos_source_rights
    key = "com.apple.security.app-sandbox"
    [[false, true], [nil, true], ["true", true]].each do |signed_value, source_value|
      error = assert_raises(IosBaselineSignedEntitlements::SourceMismatchError) do
        IosBaselineSignedEntitlements.preserve_source!({ key => signed_value }, { key => source_value }, APP,
          bundle_info: iphoneos_info)
      end
      assert_equal ["MACOS_SANDBOX"], error.public_payload[:mismatched_entitlements]
    end

    [nil, "true"].each do |source_value|
      error = assert_raises(IosBaselineSignedEntitlements::SourceMismatchError) do
        IosBaselineSignedEntitlements.preserve_source!({}, { key => source_value }, APP, bundle_info: iphoneos_info)
      end
      assert_equal ["MACOS_SANDBOX"], error.public_payload[:mismatched_entitlements]
    end
  end

  def test_macos_omission_requires_exact_iphoneos_platform_proof
    source = { "com.apple.security.app-sandbox" => true }
    [nil, {},
     { "CFBundleSupportedPlatforms" => ["iPhoneOS"] },
     { "DTPlatformName" => "iphoneos" },
     { "CFBundleSupportedPlatforms" => ["iPhoneSimulator"], "DTPlatformName" => "iphonesimulator" },
     { "CFBundleSupportedPlatforms" => ["MacOSX"], "DTPlatformName" => "macosx" },
     { "CFBundleSupportedPlatforms" => ["iPhoneOS", "MacOSX"], "DTPlatformName" => "iphoneos" }].each do |bundle_info|
      error = assert_raises(IosBaselineSignedEntitlements::SourceMismatchError) do
        IosBaselineSignedEntitlements.preserve_source!({}, source, APP, bundle_info: bundle_info)
      end
      assert_equal ["MACOS_SANDBOX"], error.public_payload[:mismatched_entitlements]
    end
  end

  def test_critical_source_mismatch_is_rejected_alongside_allowed_macos_omissions
    critical_rights = {
      "aps-environment" => ["development", "APS_ENVIRONMENT"],
      "com.apple.security.application-groups" => [["group.$(BASE_BUNDLE_IDENTIFIER)"], "APP_GROUP"],
      "com.apple.developer.networking.networkextension" => [["packet-tunnel-provider"], "NETWORK_EXTENSIONS"],
      "com.apple.developer.networking.vpn.api" => [["allow-vpn"], "VPN_API"]
    }
    critical_rights.each do |key, (value, label)|
      source = IosBaselineSignedEntitlements::MACOS_BOOLEAN_KEYS.to_h { |macos_key| [macos_key, true] }
      source[key] = value
      error = assert_raises(IosBaselineSignedEntitlements::SourceMismatchError) do
        IosBaselineSignedEntitlements.preserve_source!({}, source, APP, target: "APP", bundle_info: iphoneos_info)
      end
      assert_equal({ code: "SOURCE_ENTITLEMENTS_MISMATCH", target: "APP",
        mismatched_entitlements: [label] }, error.public_payload)
    end
  end

  def test_source_mismatch_reports_all_safe_labels_for_target_without_private_details
    private_key = "private.entitlement.internal-customer-id"
    source = {
      "aps-environment" => "development",
      "com.apple.developer.networking.networkextension" => ["packet-tunnel-provider"],
      "com.apple.developer.networking.vpn.api" => ["allow-vpn"],
      "com.apple.security.application-groups" => ["group.$(BASE_BUNDLE_IDENTIFIER)"],
      "com.apple.security.app-sandbox" => true,
      "com.apple.security.network.client" => true,
      "com.apple.security.network.server" => true,
      private_key => "source-private-value"
    }
    signed = {
      "aps-environment" => "private-environment",
      "com.apple.developer.networking.networkextension" => ["private-extension-mode"],
      "com.apple.developer.networking.vpn.api" => ["private-vpn-mode"],
      "com.apple.security.application-groups" => ["private-app-group"],
      "com.apple.security.app-sandbox" => false,
      "com.apple.security.network.client" => false,
      "com.apple.security.network.server" => false,
      private_key => "signed-private-value"
    }

    error = assert_raises(IosBaselineSignedEntitlements::SafeError) do
      IosBaselineSignedEntitlements.preserve_source!(signed, source, APP, target: "APP", bundle_info: iphoneos_info)
    end

    assert_equal "IosBaselineSignedEntitlements::SourceMismatchError", error.class.name
    assert_respond_to error, :public_payload
    assert_equal "SOURCE_ENTITLEMENTS_MISMATCH", error.code
    assert_equal({ code: "SOURCE_ENTITLEMENTS_MISMATCH", target: "APP",
      mismatched_entitlements: %w[APS_ENVIRONMENT NETWORK_EXTENSIONS VPN_API APP_GROUP MACOS_SANDBOX
        MACOS_NETWORK_CLIENT MACOS_NETWORK_SERVER OTHER] }, error.public_payload)
    serialized = JSON.generate(error.public_payload)
    [private_key, "source-private-value", "signed-private-value", "private-environment", "private-extension-mode",
     "private-vpn-mode", "private-app-group", APP, GROUP, TEAM].each do |private_detail|
      refute_includes serialized, private_detail
    end
  end

  def test_generic_safe_error_and_invalid_source_keep_code_only_payload
    error = IosBaselineSignedEntitlements::SafeError.new("SOURCE_ENTITLEMENTS_MISMATCH")
    assert_respond_to error, :public_payload
    assert_equal({ code: "SOURCE_ENTITLEMENTS_MISMATCH" }, error.public_payload)

    invalid_source = assert_raises(IosBaselineSignedEntitlements::SafeError) do
      IosBaselineSignedEntitlements.preserve_source!({}, [], APP, target: "EXTENSION")
    end
    assert_instance_of IosBaselineSignedEntitlements::SafeError, invalid_source
    assert_equal({ code: "SOURCE_ENTITLEMENTS_MISMATCH" }, invalid_source.public_payload)
  end

  def test_source_mismatch_error_sanitizes_direct_constructor_inputs
    error = IosBaselineSignedEntitlements::SourceMismatchError.new(
      target: "PRIVATE_TARGET", mismatched_entitlements: ["PRIVATE_RAW_LABEL", "APS_ENVIRONMENT"]
    )

    assert_equal({ code: "SOURCE_ENTITLEMENTS_MISMATCH", target: "UNKNOWN",
      mismatched_entitlements: %w[OTHER APS_ENVIRONMENT] }, error.public_payload)
    serialized = JSON.generate(error.public_payload)
    refute_includes serialized, "PRIVATE_TARGET"
    refute_includes serialized, "PRIVATE_RAW_LABEL"
  end

  def test_source_mismatch_error_keeps_canonical_labels_after_input_mutation
    target = +"APP"
    label = +"APS_ENVIRONMENT"
    error = IosBaselineSignedEntitlements::SourceMismatchError.new(
      target: target, mismatched_entitlements: [label]
    )

    target.replace("PRIVATE_TARGET_ID")
    label.replace("PRIVATE_ENTITLEMENT_VALUE")

    assert_equal({ code: "SOURCE_ENTITLEMENTS_MISMATCH", target: "APP",
      mismatched_entitlements: ["APS_ENVIRONMENT"] }, error.public_payload)
    serialized = JSON.generate(error.public_payload)
    refute_includes serialized, "PRIVATE_TARGET_ID"
    refute_includes serialized, "PRIVATE_ENTITLEMENT_VALUE"
  end

  def test_ipa_verification_labels_source_checks_for_each_target
    Dir.mktmpdir do |dir|
      ipa = File.join(dir, "fixture.ipa")
      app_entitlements = File.join(dir, "app.entitlements")
      extension_entitlements = File.join(dir, "extension.entitlements")
      File.write(ipa, "fixture")
      File.write(app_entitlements, "app source")
      File.write(extension_entitlements, "extension source")
      platform_proofs = []
      inspected_infos = [iphoneos_info(APP), iphoneos_info(EXTENSION)]
      capture = lambda do |*args, **_kwargs|
        if args.include?("-Z1")
          "Payload/App.app/Info.plist\nPayload/App.app/PlugIns/Tunnel.appex/Info.plist\n"
        elsif args.first == "/usr/bin/zipinfo"
          "-rw-r--r--  2.0 unx 1 b- stor 01-Jan-26 00:00 Payload/App.app/Info.plist\n"
        elsif args.first == "/usr/bin/ditto"
          FileUtils.mkdir_p(File.join(args.last, "Payload", "App.app", "PlugIns", "Tunnel.appex"))
          ""
        else
          flunk "unexpected command: #{args.first}"
        end
      end
      preserve = lambda do |_signed, _source, _identifier, target:, bundle_info:|
        platform_proofs << [target, bundle_info]
        true
      end

      IosBaselineSignedEntitlements.stub(:capture!, capture) do
        IosBaselineSignedEntitlements.stub(:inspect_bundle!, ->(*_args) { [{}, {}, inspected_infos.shift] }) do
          IosBaselineSignedEntitlements.stub(:plist!, {}) do
            IosBaselineSignedEntitlements.stub(:preserve_source!, preserve) do
              IosBaselineSignedEntitlements.stub(:verify!, true) do
                IosBaselineSignedEntitlements.verify_ipa!(ipa: ipa, team: TEAM, app_identifier: APP,
                  extension_identifier: EXTENSION, app_group: GROUP, app_entitlements: app_entitlements,
                  extension_entitlements: extension_entitlements)
              end
            end
          end
        end
      end

      assert_equal [["APP", iphoneos_info(APP)], ["EXTENSION", iphoneos_info(EXTENSION)]], platform_proofs
    end
  end

  def test_extension_wrong_platform_cannot_use_app_platform_proof
    Dir.mktmpdir do |dir|
      ipa = File.join(dir, "fixture.ipa")
      app_entitlements = File.join(dir, "app.entitlements")
      extension_entitlements = File.join(dir, "extension.entitlements")
      File.write(ipa, "fixture")
      File.write(app_entitlements, "app source")
      File.write(extension_entitlements, "extension source")
      source = { "com.apple.security.app-sandbox" => true }
      inspections = [
        [{}, {}, iphoneos_info(APP)],
        [{}, {}, iphoneos_info(EXTENSION).merge("DTPlatformName" => "iphonesimulator")]
      ]
      capture = lambda do |*args, **_kwargs|
        if args.include?("-Z1")
          "Payload/App.app/Info.plist\nPayload/App.app/PlugIns/Tunnel.appex/Info.plist\n"
        elsif args.first == "/usr/bin/zipinfo"
          "-rw-r--r--  2.0 unx 1 b- stor 01-Jan-26 00:00 Payload/App.app/Info.plist\n"
        elsif args.first == "/usr/bin/ditto"
          FileUtils.mkdir_p(File.join(args.last, "Payload", "App.app", "PlugIns", "Tunnel.appex"))
          ""
        else
          flunk "unexpected command: #{args.first}"
        end
      end

      IosBaselineSignedEntitlements.stub(:capture!, capture) do
        IosBaselineSignedEntitlements.stub(:inspect_bundle!, ->(*_args) { inspections.shift }) do
          IosBaselineSignedEntitlements.stub(:plist!, source) do
            error = assert_raises(IosBaselineSignedEntitlements::SourceMismatchError) do
              IosBaselineSignedEntitlements.verify_ipa!(ipa: ipa, team: TEAM, app_identifier: APP,
                extension_identifier: EXTENSION, app_group: GROUP, app_entitlements: app_entitlements,
                extension_entitlements: extension_entitlements)
            end
            assert_equal({ code: "SOURCE_ENTITLEMENTS_MISMATCH", target: "EXTENSION",
              mismatched_entitlements: ["MACOS_SANDBOX"] }, error.public_payload)
          end
        end
      end
    end
  end

  def test_version_and_build_checked_for_each_bundle
    info = { "CFBundleShortVersionString" => "1.2.3", "CFBundleVersion" => "101" }
    assert IosBaselineSignedEntitlements.verify_version!(info, "1.2.3", "101")
    [["2.0", "101", "VERSION_MISMATCH"], ["1.2.3", "102", "BUILD_NUMBER_MISMATCH"]].each do |version, build, code|
      error = assert_raises(IosBaselineSignedEntitlements::SafeError) { IosBaselineSignedEntitlements.verify_version!(info, version, build) }
      assert_equal code, error.code
    end
  end

  def distribution_profile
    { "ExpirationDate" => "2030-01-01T00:00:00Z", "DeveloperCertificates" => [Base64.strict_encode64("fixture DER")],
      "Entitlements" => { "get-task-allow" => false } }
  end

  def check_distribution(profile, leaf = "fixture DER")
    IosBaselineSignedEntitlements.verify_distribution_profile!(profile, signer_der: leaf, now: Time.utc(2029, 1, 1))
  end

  def test_distribution_profile_accepts_authorized_leaf_and_future_expiry
    assert check_distribution(distribution_profile)
  end

  def test_distribution_profile_expiration_and_malformed_dates
    ["2028-01-01T00:00:00Z", "2029-01-01T00:00:00Z", nil, "tomorrow"].each do |date|
      profile = distribution_profile.merge("ExpirationDate" => date)
      error = assert_raises(IosBaselineSignedEntitlements::SafeError) { check_distribution(profile) }
      assert_equal(date && date.start_with?("202") ? "PROFILE_EXPIRED" : "PROFILE_MALFORMED", error.code)
    end
  end

  def test_distribution_profile_rejects_device_distribution_flags
    [{ "ProvisionedDevices" => [] }, { "ProvisionedDevices" => ["private-device"] },
     { "ProvisionsAllDevices" => true }, { "ProvisionsAllDevices" => false }].each do |flags|
      error = assert_raises(IosBaselineSignedEntitlements::SafeError) { check_distribution(distribution_profile.merge(flags)) }
      assert_equal "PROFILE_NOT_APP_STORE", error.code
      refute_includes error.message, "private-device"
    end
  end

  def test_distribution_profile_requires_own_signer_certificate
    error = assert_raises(IosBaselineSignedEntitlements::SafeError) { check_distribution(distribution_profile, "other DER") }
    assert_equal "SIGNER_NOT_PROVISIONED", error.code
    [nil, [], ["invalid base64!"], [""]].each do |certs|
      error = assert_raises(IosBaselineSignedEntitlements::SafeError) do
        check_distribution(distribution_profile.merge("DeveloperCertificates" => certs))
      end
      assert_equal "PROFILE_MALFORMED", error.code
    end
  end

  def test_native_signer_certificate_extraction_from_existing_signed_binary
    fixture = ENV["IOS_BASELINE_SIGNER_FIXTURE_BINARY"]
    skip "native signed fixture supplied only for local read-only reproduction" unless fixture
    _out, diagnostic, status = Open3.capture3("/usr/bin/codesign", "--display", "--verbose=4", fixture)
    skip "local fixture has unavailable native certificate chain; actual CI IPA remains mandatory" if status.success? && diagnostic.include?("Authority=(unavailable)")
    leaf = IosBaselineSignedEntitlements.signer_der!(fixture)
    assert_operator leaf.bytesize, :>, 0
    assert_equal leaf, OpenSSL::X509::Certificate.new(leaf).to_der
  end

  def test_signer_leaf_is_extracted_from_bundle_and_temp_files_removed
    prefix = nil
    capture = lambda do |*args, **_kwargs|
      assert_equal 4, args.length, "optional extraction prefix must not become another inspected path"
      assert_equal ["/usr/bin/codesign", "--display"], args.take(2)
      assert_equal "/fixture/App.app", args.last
      assert_match(/\A--extract-certificates=.+\z/, args[2])
      prefix = args[2].delete_prefix("--extract-certificates=")
      File.binwrite("#{prefix}0", "fixture DER")
      ""
    end
    IosBaselineSignedEntitlements.stub(:capture!, capture) do
      assert_equal "fixture DER", IosBaselineSignedEntitlements.signer_der!("/fixture/App.app")
    end
    refute File.exist?("#{prefix}0")
  end

  def test_bundle_inspection_requires_distribution_gate_for_each_target
    [APP, EXTENSION].each do |identifier|
      Dir.mktmpdir do |bundle|
        File.write(File.join(bundle, "Info.plist"), "fixture")
        values = [{ "CFBundleIdentifier" => identifier }, {}, distribution_profile.merge("ExpirationDate" => "2000-01-01T00:00:00Z")]
        IosBaselineSignedEntitlements.stub(:capture!, "captured") do
          IosBaselineSignedEntitlements.stub(:plist!, ->(_data) { values.shift }) do
            IosBaselineSignedEntitlements.stub(:signer_der!, "fixture DER") do
              error = assert_raises(IosBaselineSignedEntitlements::SafeError) do
                IosBaselineSignedEntitlements.inspect_bundle!(bundle, identifier, nil, nil)
              end
              assert_equal "PROFILE_EXPIRED", error.code
            end
          end
        end
      end
    end
  end

  def test_bundle_inspection_returns_verified_info_for_source_preservation
    Dir.mktmpdir do |bundle|
      File.write(File.join(bundle, "Info.plist"), "fixture")
      info = iphoneos_info(APP)
      embedded_profile = distribution_profile
      parsed = [info, {}, embedded_profile]

      IosBaselineSignedEntitlements.stub(:capture!, "captured") do
        IosBaselineSignedEntitlements.stub(:plist!, ->(_data) { parsed.shift }) do
          IosBaselineSignedEntitlements.stub(:signer_der!, "fixture DER") do
            assert_equal [{}, embedded_profile, info],
              IosBaselineSignedEntitlements.inspect_bundle!(bundle, APP, nil, nil)
          end
        end
      end
    end
  end

end
