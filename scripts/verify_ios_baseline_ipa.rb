#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require "digest"
require "optparse"
require "rexml/document"
require "base64"
require "time"

module IosBaselineSignedEntitlements
  class SafeError < StandardError
    attr_reader :code
    def initialize(code)
      @code = code
      super(code)
    end

    def public_payload
      { code: code }
    end
  end

  # Apple Entitlement Key Reference, Enabling App Sandbox: these three are
  # macOS-only Boolean settings, not iOS provisioning capabilities. Preserve them.
  # https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html
  MACOS_BOOLEAN_KEYS = %w[com.apple.security.app-sandbox com.apple.security.network.client com.apple.security.network.server].freeze
  WILDCARD_KEYS = %w[application-identifier keychain-access-groups com.apple.developer.ubiquity-kvstore-identifier].freeze
  SOURCE_ENTITLEMENT_LABELS = {
    "aps-environment" => "APS_ENVIRONMENT",
    "com.apple.developer.networking.networkextension" => "NETWORK_EXTENSIONS",
    "com.apple.developer.networking.vpn.api" => "VPN_API",
    "com.apple.security.application-groups" => "APP_GROUP",
    "com.apple.security.app-sandbox" => "MACOS_SANDBOX",
    "com.apple.security.network.client" => "MACOS_NETWORK_CLIENT",
    "com.apple.security.network.server" => "MACOS_NETWORK_SERVER"
  }.freeze
  SOURCE_TARGETS = %w[APP EXTENSION UNKNOWN].freeze
  SOURCE_ENTITLEMENT_SAFE_LABELS = (SOURCE_ENTITLEMENT_LABELS.values + ["OTHER"]).freeze

  class SourceMismatchError < SafeError
    def initialize(target:, mismatched_entitlements:)
      @target = SOURCE_TARGETS.find { |safe_target| safe_target == target } || "UNKNOWN"
      @mismatched_entitlements = mismatched_entitlements.map do |label|
        SOURCE_ENTITLEMENT_SAFE_LABELS.find { |safe_label| safe_label == label } || "OTHER"
      end.freeze
      super("SOURCE_ENTITLEMENTS_MISMATCH")
    end

    def public_payload
      super.merge(target: @target, mismatched_entitlements: @mismatched_entitlements)
    end
  end
  module_function

  def fail!(code)
    raise SafeError, code
  end

  def verify!(app:, extension:, app_profile:, extension_profile:, team:, app_identifier:, extension_identifier:, app_group:)
    [[app, app_profile, app_identifier, "APP_ID_MISMATCH"],
     [extension, extension_profile, extension_identifier, "EXTENSION_ID_MISMATCH"]].each do |signed, profile, bundle, id_code|
      fail!("ENTITLEMENTS_MALFORMED") unless signed.is_a?(Hash) && signed.keys.all? { |k| k.is_a?(String) }
      fail!("PROFILE_MALFORMED") unless profile.is_a?(Hash) && profile["Entitlements"].is_a?(Hash)
      prefixes = profile["ApplicationIdentifierPrefix"]
      fail!("PROFILE_MALFORMED") unless prefixes.is_a?(Array) && !prefixes.empty? && prefixes.all? { |p| p.is_a?(String) && p.match?(/\A[A-Z0-9]{10}\z/) }
      grants = profile["Entitlements"]
      fail!("TEAM_MISMATCH") unless profile["TeamIdentifier"] == [team] && signed["com.apple.developer.team-identifier"] == team && grants["com.apple.developer.team-identifier"] == team
      # TN2415/TN2311: App ID prefix is not necessarily the team identifier.
      fail!(id_code) unless prefixes.any? { |prefix| signed["application-identifier"] == "#{prefix}.#{bundle}" }
      fail!("APP_GROUP_MISMATCH") unless signed["com.apple.security.application-groups"] == [app_group]
      fail!("DEBUG_ENTITLEMENT") unless [nil, false].include?(signed["get-task-allow"]) && [nil, false].include?(grants["get-task-allow"])
      ne = signed["com.apple.developer.networking.networkextension"]
      fail!("REQUIRED_ENTITLEMENT_MISSING") unless ne.is_a?(Array) && ne.include?("packet-tunnel-provider")
      signed.each do |key, value|
        if MACOS_BOOLEAN_KEYS.include?(key)
          fail!("ENTITLEMENTS_MALFORMED") unless value == true || value == false
          next
        end
        next if key == "get-task-allow" && value == false && !grants.key?(key)
        fail!("ENTITLEMENT_NOT_PROVISIONED") unless grants.key?(key) && granted?(value, grants[key], WILDCARD_KEYS.include?(key))
      end
    end
    true
  end

  def granted?(value, grant, wildcard)
    if value.is_a?(Array)
      return grant.is_a?(Array) && !value.empty? && value.all? { |v| grant.any? { |g| granted?(v, g, wildcard) } }
    end
    if value.is_a?(Hash)
      return grant.is_a?(Hash) && value.all? { |k, v| grant.key?(k) && granted?(v, grant[k], wildcard) }
    end
    return false unless [String, TrueClass, FalseClass, Integer].include?(value.class) && value.class == grant.class
    return true if value == grant
    wildcard && value.is_a?(String) && !value.include?("*") && grant.end_with?("*") && grant.count("*") == 1 && value.start_with?(grant.delete_suffix("*"))
  end

  def capture!(*args, input: nil, code: "INSPECTION_FAILED")
    stdout, _stderr, status = Open3.capture3(*args, stdin_data: input)
    fail!(code) unless status.success?
    stdout
  rescue SystemCallError
    fail!(code)
  end

  def plist!(data)
    xml = capture!("/usr/bin/plutil", "-convert", "xml1", "-o", "-", "--", "-", input: data, code: "PLIST_INVALID")
    root = REXML::Document.new(xml).root
    fail!("PLIST_INVALID") unless root && root.name == "plist" && root.elements.size == 1
    plist_value!(root.elements[1])
  rescue REXML::ParseException
    fail!("PLIST_INVALID")
  end

  def plist_value!(node)
    case node.name
    when "dict"
      children = node.elements.to_a
      fail!("PLIST_INVALID") unless children.length.even?
      children.each_slice(2).each_with_object({}) do |(key, value), result|
        fail!("PLIST_INVALID") unless key.name == "key" && !result.key?(key.text.to_s)
        result[key.text.to_s] = plist_value!(value)
      end
    when "array" then node.elements.map { |child| plist_value!(child) }
    when "true" then true
    when "false" then false
    when "string", "date" then node.text.to_s
    when "data" then node.text.to_s.gsub(/\s/, "")
    when "integer" then Integer(node.text, 10)
    when "real" then Float(node.text)
    else fail!("PLIST_INVALID")
    end
  rescue ArgumentError, TypeError
    fail!("PLIST_INVALID")
  end

  def iphoneos_bundle?(info)
    info.is_a?(Hash) && info["CFBundleSupportedPlatforms"] == ["iPhoneOS"] && info["DTPlatformName"] == "iphoneos"
  end

  def preserve_source!(signed, source, app_identifier, target: "UNKNOWN", bundle_info: nil)
    fail!("SOURCE_ENTITLEMENTS_MISMATCH") unless source.is_a?(Hash)
    mismatches = []
    source.each do |key, value|
      expected = if key == "aps-environment"
                   "production"
                 elsif key == "com.apple.security.application-groups"
                   value.map { |group| group.gsub("$(BASE_BUNDLE_IDENTIFIER)", app_identifier) }
                 else
                   value
                 end
      actual = signed[key]
      matches = expected.is_a?(Array) ? actual.is_a?(Array) && actual.sort == expected.sort : actual == expected
      if MACOS_BOOLEAN_KEYS.include?(key) && !signed.key?(key)
        matches = [true, false].include?(value) && iphoneos_bundle?(bundle_info)
      end
      mismatches << SOURCE_ENTITLEMENT_LABELS.fetch(key, "OTHER") unless matches
    end
    raise SourceMismatchError.new(target: target, mismatched_entitlements: mismatches) unless mismatches.empty?
    true
  end

  def verify_version!(info, version, build_number)
    fail!("VERSION_MISMATCH") if version && info["CFBundleShortVersionString"] != version
    fail!("BUILD_NUMBER_MISMATCH") if build_number && info["CFBundleVersion"] != build_number
    true
  end

  def verify_distribution_profile!(profile, signer_der:, now: Time.now)
    fail!("PROFILE_MALFORMED") unless profile.is_a?(Hash)
    fail!("PROFILE_NOT_APP_STORE") if profile.key?("ProvisionedDevices") || profile.key?("ProvisionsAllDevices")
    expiry = profile["ExpirationDate"]
    fail!("PROFILE_MALFORMED") unless expiry.is_a?(String) && expiry.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
    begin
      expiration = Time.iso8601(expiry)
      fail!("PROFILE_MALFORMED") unless expiration.utc.iso8601 == expiry
    rescue ArgumentError
      fail!("PROFILE_MALFORMED")
    end
    fail!("PROFILE_EXPIRED") unless expiration > now
    certificates = profile["DeveloperCertificates"]
    fail!("PROFILE_MALFORMED") unless certificates.is_a?(Array) && !certificates.empty?
    digests = certificates.map do |encoded|
      fail!("PROFILE_MALFORMED") unless encoded.is_a?(String) && !encoded.empty?
      begin
        Digest::SHA256.digest(Base64.strict_decode64(encoded))
      rescue ArgumentError
        fail!("PROFILE_MALFORMED")
      end
    end
    fail!("SIGNER_NOT_PROVISIONED") unless signer_der.is_a?(String) && !signer_der.empty? && digests.include?(Digest::SHA256.digest(signer_der))
    true
  end

  def signer_der!(bundle)
    Dir.mktmpdir("baseline-signer-") do |dir|
      prefix = File.join(dir, "certificate")
      capture!("/usr/bin/codesign", "--display", "--extract-certificates=#{prefix}", bundle, code: "SIGNER_UNREADABLE")
      leaf = "#{prefix}0"
      fail!("SIGNER_UNREADABLE") unless File.file?(leaf) && !File.symlink?(leaf)
      File.binread(leaf)
    end
  rescue SystemCallError
    fail!("SIGNER_UNREADABLE")
  end

  def inspect_bundle!(bundle, identifier, version, build_number)
    capture!("/usr/bin/codesign", "--verify", "--deep", "--strict", bundle, code: "SIGNATURE_INVALID")
    info = plist!(File.binread(File.join(bundle, "Info.plist")))
    fail!("BUNDLE_ID_MISMATCH") unless info["CFBundleIdentifier"] == identifier
    verify_version!(info, version, build_number)
    signed = plist!(capture!("/usr/bin/codesign", "--display", "--entitlements", ":-", bundle, code: "ENTITLEMENTS_UNREADABLE"))
    profile = plist!(capture!("/usr/bin/security", "cms", "-D", "-i", File.join(bundle, "embedded.mobileprovision"), code: "PROFILE_UNREADABLE"))
    # security cms decodes the embedded CMS; this is not an independent CMS
    # chain-of-trust validation. codesign verifies the bundle's real signature.
    verify_distribution_profile!(profile, signer_der: signer_der!(bundle))
    [signed, profile, info]
  end

  def verify_ipa!(ipa:, team:, app_identifier:, extension_identifier:, app_group:, version: nil, build_number: nil,
                  app_entitlements: File.expand_path("../ios/Runner/Runner.entitlements", __dir__),
                  extension_entitlements: File.expand_path("../ios/HiddifyPacketTunnel/HiddifyPacketTunnel.entitlements", __dir__))
    fail!("IPA_MISSING") unless File.file?(ipa)
    ipa = File.realpath(ipa)
    digest = Digest::SHA256.file(ipa).hexdigest
    Dir.mktmpdir("baseline-ipa-") do |dir|
      # List before extraction; reject traversal and ambiguous archive entries.
      entries = capture!("/usr/bin/unzip", "-Z1", ipa, code: "IPA_INVALID").lines.map(&:chomp)
      fail!("IPA_INVALID") if entries.empty? || entries.uniq.length != entries.length || entries.any? { |p| p.start_with?("/") || p.split("/").include?("..") || p.include?("\\") }
      modes = capture!("/usr/bin/zipinfo", "-l", ipa, code: "IPA_INVALID")
      fail!("IPA_INVALID") if modes.lines.any? { |line| line.match?(/\Al[rwx-]{9}\s/) }
      capture!("/usr/bin/ditto", "-x", "-k", ipa, dir, code: "IPA_INVALID")
      fail!("IPA_INVALID") if Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH).any? { |p| File.symlink?(p) }
      apps = Dir.glob(File.join(dir, "Payload", "*.app"))
      fail!("APP_COUNT_MISMATCH") unless apps.length == 1
      extensions = Dir.glob(File.join(apps.first, "PlugIns", "*.appex"))
      fail!("EXTENSION_COUNT_MISMATCH") unless extensions.length == 1
      app, app_profile, app_info = inspect_bundle!(apps.first, app_identifier, version, build_number)
      extension, extension_profile, extension_info = inspect_bundle!(extensions.first, extension_identifier, version, build_number)
      preserve_source!(app, plist!(File.binread(app_entitlements)), app_identifier, target: "APP", bundle_info: app_info)
      preserve_source!(extension, plist!(File.binread(extension_entitlements)), app_identifier,
        target: "EXTENSION", bundle_info: extension_info)
      verify!(app: app, extension: extension, app_profile: app_profile, extension_profile: extension_profile,
              team: team, app_identifier: app_identifier, extension_identifier: extension_identifier, app_group: app_group)
      fail!("IPA_CHANGED") unless Digest::SHA256.file(ipa).hexdigest == digest
      { code: "SIGNED_ENTITLEMENTS_VERIFIED", ipa_sha256: digest, app_count: 1, extension_count: 1,
        app_entitlement_count: app.length, extension_entitlement_count: extension.length }
    end
  rescue SystemCallError
    fail!("INSPECTION_FAILED")
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    options = { team: "M9D72QQJ79", app_identifier: "com.womaninred.baseline",
                extension_identifier: "com.womaninred.baseline.HiddifyPacketTunnel", app_group: "group.com.womaninred.baseline" }
    OptionParser.new do |parser|
      parser.on("--version VALUE") { |v| options[:version] = v }
      parser.on("--build-number VALUE") { |v| options[:build_number] = v }
      parser.on("--app-entitlements PATH") { |v| options[:app_entitlements] = v }
      parser.on("--extension-entitlements PATH") { |v| options[:extension_entitlements] = v }
      parser.on("--ipa PATH") { |v| options[:ipa] = v }
      parser.on("--team VALUE") { |v| options[:team] = v }
      parser.on("--app-identifier VALUE") { |v| options[:app_identifier] = v }
      parser.on("--extension-identifier VALUE") { |v| options[:extension_identifier] = v }
      parser.on("--app-group VALUE") { |v| options[:app_group] = v }
    end.parse!
    IosBaselineSignedEntitlements.fail!("ARGUMENTS_INVALID") unless options[:ipa] && ARGV.empty?
    puts JSON.generate(IosBaselineSignedEntitlements.verify_ipa!(**options))
  rescue IosBaselineSignedEntitlements::SafeError => e
    warn JSON.generate(e.public_payload)
    exit 1
  rescue StandardError
    warn JSON.generate(code: "INSPECTION_FAILED")
    exit 1
  end
end
