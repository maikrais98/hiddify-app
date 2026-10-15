#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "digest"
require "fileutils"
require "json"
require "open3"
require "openssl"
require "optparse"
require "rexml/document"
require "securerandom"
require "tempfile"
require "tmpdir"
require "time"

module IOSBaselineManualSigning
  TEAM_ID = "M9D72QQJ79"
  APP_BUNDLE_ID = "com.womaninred.baseline"
  EXTENSION_BUNDLE_ID = "#{APP_BUNDLE_ID}.HiddifyPacketTunnel"
  APP_GROUP = "group.#{APP_BUNDLE_ID}"
  NETWORK_EXTENSION = "packet-tunnel-provider"
  DISTRIBUTION_OIDS = %w[1.2.840.113635.100.6.1.4 1.2.840.113635.100.6.1.7].freeze
  CLOUD_MANAGED_OID = "1.2.840.113635.100.6.1.32"
  SHA256 = /\A[0-9a-f]{64}\z/
  UUID = /\A[A-Za-z0-9-]{1,128}\z/

  class SafeError < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  ProfileMaterial = Struct.new(
    :role, :bundle_identifier, :uuid, :cms_der, :cms_sha256, :aps_environment,
    :app_groups, :network_extensions, :vpn_api,
    keyword_init: true
  ) do
    def inspect
      "#<#{self.class.name} role=#{role.inspect} bundle_identifier=#{bundle_identifier.inspect}>"
    end
  end

  Material = Struct.new(
    :private_key_pem, :certificate_pem, :certificate_der, :certificate_sha1,
    :certificate_sha256, :app_profile, :extension_profile,
    keyword_init: true
  ) do
    def inspect
      "#<#{self.class.name} certificate_sha256=#{certificate_sha256.inspect}>"
    end
  end

  class IdentityValidator
    def initialize(now: Time.now.utc)
      @now = now
    end

    def validate!(private_key:, certificate:, pinned_sha256:)
      unless private_key.respond_to?(:public_key) && certificate.is_a?(OpenSSL::X509::Certificate) &&
          certificate.check_private_key(private_key)
        raise SafeError, "SIGNING_IDENTITY_KEY_MISMATCH"
      end

      pinned = pinned_sha256.to_s.downcase
      raise SafeError, "SIGNING_CERTIFICATE_FINGERPRINT_INVALID" unless SHA256.match?(pinned)

      actual = Digest::SHA256.hexdigest(certificate.to_der)
      raise SafeError, "SIGNING_CERTIFICATE_FINGERPRINT_MISMATCH" unless secure_equal?(actual, pinned)

      common_names = subject_values(certificate, "CN")
      expected_name = /\AApple Distribution: .+ \([A-Z0-9]{10}\)\z/
      oids = certificate.extensions.map(&:oid)
      dedicated = common_names.length == 1 && expected_name.match?(common_names.first) &&
        (oids & DISTRIBUTION_OIDS).any? && !oids.include?(CLOUD_MANAGED_OID)
      raise SafeError, "SIGNING_CERTIFICATE_NOT_DEDICATED_DISTRIBUTION" unless dedicated

      expected_suffix = "(#{TEAM_ID})"
      raise SafeError, "SIGNING_CERTIFICATE_TEAM_MISMATCH" unless
        subject_values(certificate, "OU") == [TEAM_ID] && common_names.first.end_with?(expected_suffix)
      raise SafeError, "SIGNING_CERTIFICATE_NOT_YET_VALID" if certificate.not_before > @now
      raise SafeError, "SIGNING_CERTIFICATE_EXPIRED" if certificate.not_after <= @now

      [actual, Digest::SHA1.hexdigest(certificate.to_der).upcase]
    rescue OpenSSL::X509::CertificateError, OpenSSL::PKey::PKeyError
      raise SafeError, "SIGNING_IDENTITY_INVALID"
    end

    private

    def subject_values(certificate, key)
      certificate.subject.to_a.select { |name, _value, _type| name == key }.map { |_name, value, _type| value }
    end

    def secure_equal?(left, right)
      return false unless left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).reduce(0) { |difference, (a, b)| difference | (a ^ b) }.zero?
    end
  end

  class PlistXML
    MAX_BYTES = 2 * 1024 * 1024

    def self.parse(xml)
      raise SafeError, "PROVISIONING_PROFILE_PLIST_INVALID" unless
        xml.is_a?(String) && xml.bytesize.positive? && xml.bytesize <= MAX_BYTES

      document = REXML::Document.new(xml)
      root = document.elements["plist"]&.elements&.to_a&.first
      raise SafeError, "PROVISIONING_PROFILE_PLIST_INVALID" unless root

      parse_value(root, 0)
    rescue REXML::ParseException, ArgumentError
      raise SafeError, "PROVISIONING_PROFILE_PLIST_INVALID"
    end

    def self.parse_value(element, depth)
      raise SafeError, "PROVISIONING_PROFILE_PLIST_INVALID" if depth > 32

      case element.name
      when "dict"
        children = element.elements.to_a
        raise SafeError, "PROVISIONING_PROFILE_PLIST_INVALID" unless children.length.even?

        result = {}
        children.each_slice(2) do |key, value|
          raise SafeError, "PROVISIONING_PROFILE_PLIST_INVALID" unless key.name == "key"
          raise SafeError, "PROVISIONING_PROFILE_PLIST_INVALID" if result.key?(key.text.to_s)

          result[key.text.to_s] = parse_value(value, depth + 1)
        end
        result
      when "array" then element.elements.map { |child| parse_value(child, depth + 1) }
      when "string" then element.text.to_s
      when "true" then true
      when "false" then false
      when "date" then Time.iso8601(element.text.to_s)
      when "data" then Base64.strict_decode64(element.text.to_s.gsub(/\s+/, ""))
      when "integer" then Integer(element.text.to_s, 10)
      when "real" then Float(element.text.to_s)
      else raise SafeError, "PROVISIONING_PROFILE_PLIST_INVALID"
      end
    end
    private_class_method :parse_value
  end

  class CMSDecoder
    def decode(cms)
      raise SafeError, "PROVISIONING_PROFILE_CMS_INVALID" unless cms.is_a?(String) && cms.bytesize <= PlistXML::MAX_BYTES

      signed = OpenSSL::PKCS7.new(cms)
      signers = signed.certificates
      raise SafeError, "PROVISIONING_PROFILE_CMS_INVALID" unless signers.is_a?(Array) && !signers.empty?

      store = OpenSSL::X509::Store.new
      flags = OpenSSL::PKCS7::NOVERIFY | OpenSSL::PKCS7::BINARY
      verified = signed.verify(signers, store, nil, flags)
      raise SafeError, "PROVISIONING_PROFILE_CMS_INVALID" unless verified && signed.data

      PlistXML.parse(signed.data)
    rescue OpenSSL::PKCS7::PKCS7Error, OpenSSL::X509::StoreError, SystemCallError
      raise SafeError, "PROVISIONING_PROFILE_CMS_INVALID"
    end
  end

  class ProfileValidator
    def initialize(certificate_sha256:, now: Time.now.utc)
      @certificate_sha256 = certificate_sha256
      @now = now
    end

    def validate!(role:, profile:, cms_der:)
      prefix = role == :app ? "APP_PROFILE" : "EXTENSION_PROFILE"
      expected_bundle = role == :app ? APP_BUNDLE_ID : EXTENSION_BUNDLE_ID
      raise SafeError, "#{prefix}_INVALID" unless profile.is_a?(Hash)

      uuid = profile["UUID"]
      raise SafeError, "#{prefix}_UUID_INVALID" unless uuid.is_a?(String) && UUID.match?(uuid)
      raise SafeError, "#{prefix}_TEAM_MISMATCH" unless profile["TeamIdentifier"] == [TEAM_ID]

      expiration = profile["ExpirationDate"]
      raise SafeError, "#{prefix}_EXPIRATION_INVALID" unless expiration.is_a?(Time)
      raise SafeError, "#{prefix}_EXPIRED" if expiration <= @now
      raise SafeError, "#{prefix}_DEVICE_DISTRIBUTION_FORBIDDEN" if profile.key?("ProvisionedDevices")
      raise SafeError, "#{prefix}_ENTERPRISE_FORBIDDEN" if profile.key?("ProvisionsAllDevices")

      entitlements = profile["Entitlements"]
      raise SafeError, "#{prefix}_ENTITLEMENTS_INVALID" unless entitlements.is_a?(Hash)
      raise SafeError, "#{prefix}_BUNDLE_MISMATCH" unless
        entitlements["application-identifier"] == "#{TEAM_ID}.#{expected_bundle}"
      raise SafeError, "#{prefix}_TEAM_MISMATCH" unless
        entitlements["com.apple.developer.team-identifier"] == TEAM_ID
      raise SafeError, "#{prefix}_GET_TASK_ALLOW_FORBIDDEN" unless entitlements["get-task-allow"] == false
      raise SafeError, "#{prefix}_NOT_APP_STORE" unless entitlements["beta-reports-active"] == true
      app_groups = entitlements["com.apple.security.application-groups"]
      unless string_array?(app_groups) && app_groups.include?(APP_GROUP)
        raise SafeError, "#{prefix}_APP_GROUP_MISSING"
      end
      network_extensions = entitlements["com.apple.developer.networking.networkextension"]
      unless string_array?(network_extensions) && network_extensions.include?(NETWORK_EXTENSION)
        raise SafeError, "#{prefix}_NETWORK_EXTENSION_MISSING"
      end
      vpn_api = entitlements["com.apple.developer.networking.vpn.api"]
      unless string_array?(vpn_api) && vpn_api.include?("allow-vpn")
        raise SafeError, "#{prefix}_VPN_API_MISSING"
      end

      aps = entitlements["aps-environment"]
      raise SafeError, "#{prefix}_APS_ENVIRONMENT_INVALID" unless aps.nil? || aps == "production"

      certificates = profile["DeveloperCertificates"]
      unless certificates.is_a?(Array) && certificates.all? { |certificate| certificate.is_a?(String) }
        raise SafeError, "#{prefix}_SIGNERS_INVALID"
      end
      signer_present = certificates.any? do |certificate|
        Digest::SHA256.hexdigest(certificate) == @certificate_sha256
      end
      raise SafeError, "#{prefix}_SIGNER_MISMATCH" unless signer_present

      ProfileMaterial.new(
        role: role.to_s,
        bundle_identifier: expected_bundle,
        uuid: uuid,
        cms_der: cms_der,
        cms_sha256: Digest::SHA256.hexdigest(cms_der),
        aps_environment: aps,
        app_groups: app_groups.sort,
        network_extensions: network_extensions.sort,
        vpn_api: vpn_api.sort
      )
    end

    private

    def string_array?(value)
      value.is_a?(Array) && !value.empty? && value.all? { |item| item.is_a?(String) && !item.empty? }
    end
  end

  def self.validate_material!(p12_der:, p12_password:, pinned_certificate_sha256:,
    app_profile_cms:, extension_profile_cms:, now: Time.now.utc, cms_decoder: CMSDecoder.new)
    p12 = OpenSSL::PKCS12.new(p12_der, p12_password)
    raise SafeError, "SIGNING_IDENTITY_INVALID" unless p12.key && p12.certificate

    certificate_sha256, certificate_sha1 = IdentityValidator.new(now: now).validate!(
      private_key: p12.key,
      certificate: p12.certificate,
      pinned_sha256: pinned_certificate_sha256
    )
    validator = ProfileValidator.new(certificate_sha256: certificate_sha256, now: now)
    app_profile = validator.validate!(role: :app, profile: cms_decoder.decode(app_profile_cms),
      cms_der: app_profile_cms)
    extension_profile = validator.validate!(role: :extension,
      profile: cms_decoder.decode(extension_profile_cms), cms_der: extension_profile_cms)

    Material.new(
      private_key_pem: p12.key.to_pem,
      certificate_pem: p12.certificate.to_pem,
      certificate_der: p12.certificate.to_der,
      certificate_sha1: certificate_sha1,
      certificate_sha256: certificate_sha256,
      app_profile: app_profile,
      extension_profile: extension_profile
    )
  rescue OpenSSL::PKCS12::PKCS12Error, OpenSSL::PKey::PKeyError, OpenSSL::X509::CertificateError
    raise SafeError, "SIGNING_IDENTITY_INVALID"
  end

  class ProjectOverrides
    attr_reader :project_path, :workspace_path, :entitlements_root, :export_options_path

    def initialize(project_root:, material:, nonce: SecureRandom.hex(8))
      @project_root = File.expand_path(project_root)
      @material = material
      @nonce = nonce
      raise SafeError, "OVERRIDE_NONCE_INVALID" unless /\A[a-zA-Z0-9]{4,64}\z/.match?(@nonce)

      @ios_root = File.join(@project_root, "ios")
      @project_path = File.join(@ios_root, "Runner.manual-#{@nonce}.xcodeproj")
      @workspace_path = File.join(@ios_root, "Runner.manual-#{@nonce}.xcworkspace")
      @entitlements_root = File.join(@ios_root, ".manual-signing-#{@nonce}")
      @export_options_path = File.join(@entitlements_root, "ExportOptions.plist")
      @source_project_file = File.join(@ios_root, "Runner.xcodeproj", "project.pbxproj")
      @owned_paths = []
      @source_entitlements_sha256 = {}
    end

    def prepare!
      ensure_source!
      refuse_collisions!
      @original_project_sha256 = Digest::SHA256.file(@source_project_file).hexdigest

      @owned_paths << @project_path
      FileUtils.cp_r(File.join(@ios_root, "Runner.xcodeproj"), @project_path)
      @owned_paths << @workspace_path
      FileUtils.cp_r(File.join(@ios_root, "Runner.xcworkspace"), @workspace_path)
      @owned_paths << @entitlements_root
      FileUtils.mkdir_p(@entitlements_root, mode: 0o700)
      patch_project!
      patch_workspace!
      write_entitlements!
      write_export_options!
      self
    rescue StandardError
      cleanup!
      raise
    end

    def cleanup!
      @owned_paths.reverse_each do |path|
        next unless path.start_with?("#{@ios_root}/")

        FileUtils.rm_rf(path)
      end
      @owned_paths.clear
    end

    def provenance(controller_sha:)
      raise SafeError, "SIGNING_CONTROLLER_SHA_INVALID" unless /\A[0-9a-f]{40}\z/.match?(controller_sha.to_s)

      {
        "schema" => "ios-baseline-manual-signing-overrides/v1",
        "controllerSHA" => controller_sha,
        "teamID" => TEAM_ID,
        "certificateSHA256" => @material.certificate_sha256,
        "originalProjectSHA256" => @original_project_sha256,
        "overrideProjectSHA256" => Digest::SHA256.file(File.join(@project_path, "project.pbxproj")).hexdigest,
        "exportOptionsSHA256" => Digest::SHA256.file(@export_options_path).hexdigest,
        "targets" => [@material.app_profile, @material.extension_profile].map do |profile|
          entitlement = File.join(@entitlements_root, "#{profile.role}.entitlements")
          {
            "bundleIdentifier" => profile.bundle_identifier,
            "profileSHA256" => profile.cms_sha256,
            "sourceEntitlementsSHA256" => @source_entitlements_sha256.fetch(profile.role),
            "entitlementsSHA256" => Digest::SHA256.file(entitlement).hexdigest
          }
        end
      }
    end

    private

    def ensure_source!
      required = [@source_project_file, File.join(@ios_root, "Runner.xcworkspace", "contents.xcworkspacedata")]
      raise SafeError, "SIGNING_PROJECT_SOURCE_MISSING" unless required.all? { |path| File.file?(path) }
    end

    def refuse_collisions!
      raise SafeError, "SIGNING_OVERRIDE_COLLISION" if
        [@project_path, @workspace_path, @entitlements_root].any? { |path| File.exist?(path) }
    end

    def patch_project!
      path = File.join(@project_path, "project.pbxproj")
      text = File.binread(path)
      project_name = File.basename(@project_path)
      Dir.glob(File.join(@project_path, "**", "*.xcscheme")).each do |scheme|
        value = File.binread(scheme).gsub("container:Runner.xcodeproj", "container:#{project_name}")
        File.binwrite(scheme, value)
      end

      text = patch_release_configuration(text, "Runner", @material.app_profile)
      text = patch_release_configuration(text, "HiddifyPacketTunnel", @material.extension_profile)
      File.binwrite(path, text)
    end

    def patch_release_configuration(text, target_name, profile)
      list_pattern = /([0-9A-F]{24}) \/\* Build configuration list for PBXNativeTarget "#{Regexp.escape(target_name)}" \*\/ = \{.*?buildConfigurations = \((.*?)\);/m
      list_match = text.match(list_pattern)
      raise SafeError, "SIGNING_PROJECT_TARGET_MISSING" unless list_match

      release_id = list_match[2][/([0-9A-F]{24}) \/\* Release \*\//, 1]
      raise SafeError, "SIGNING_PROJECT_RELEASE_CONFIGURATION_MISSING" unless release_id

      marker = "#{release_id} /* Release */ = {"
      block_start = text.index(marker)
      raise SafeError, "SIGNING_PROJECT_RELEASE_CONFIGURATION_MISSING" unless block_start

      block_end = matching_brace(text, text.index("{", block_start))
      block = text[block_start..block_end]
      settings_marker = "buildSettings = {"
      settings_start = block.index(settings_marker)
      raise SafeError, "SIGNING_PROJECT_BUILD_SETTINGS_MISSING" unless settings_start

      settings_brace = block.index("{", settings_start)
      settings_end = matching_brace(block, settings_brace)
      settings = block[(settings_brace + 1)...settings_end]
      keys = /\A\s*(?:"?CODE_SIGN_IDENTITY\[sdk=iphoneos\*\]"?|CODE_SIGN_STYLE|DEVELOPMENT_TEAM|PROVISIONING_PROFILE(?:_SPECIFIER)?|CODE_SIGN_ENTITLEMENTS|OTHER_CODE_SIGN_FLAGS)\s*=.*;\s*\n?/
      settings = settings.lines.reject { |line| keys.match?(line) }.join
      entitlement_path = ".manual-signing-#{@nonce}/#{profile.role}.entitlements"
      injected = <<~SETTINGS.lines.map { |line| "\t\t\t\t#{line}" }.join
        CODE_SIGN_ENTITLEMENTS = "#{entitlement_path}";
        "CODE_SIGN_IDENTITY[sdk=iphoneos*]" = #{@material.certificate_sha1};
        CODE_SIGN_STYLE = Manual;
        DEVELOPMENT_TEAM = #{TEAM_ID};
        OTHER_CODE_SIGN_FLAGS = "--keychain $(IOS_BASELINE_SIGNING_KEYCHAIN)";
        PROVISIONING_PROFILE_SPECIFIER = #{profile.uuid};
      SETTINGS
      patched_settings = "\n#{injected}#{settings}"
      patched_block = block.dup
      patched_block[(settings_brace + 1)...settings_end] = patched_settings
      text[block_start..block_end] = patched_block
      text
    end

    def matching_brace(text, opening)
      depth = 0
      text.bytes.each_with_index do |byte, index|
        next if index < opening

        depth += 1 if byte == 123
        depth -= 1 if byte == 125
        return index if depth.zero?
      end
      raise SafeError, "SIGNING_PROJECT_PARSE_FAILED"
    end

    def patch_workspace!
      path = File.join(@workspace_path, "contents.xcworkspacedata")
      text = File.binread(path)
      replaced = text.sub("group:Runner.xcodeproj", "group:#{File.basename(@project_path)}")
      raise SafeError, "SIGNING_WORKSPACE_PROJECT_MISSING" if replaced == text

      File.binwrite(path, replaced)
    end

    def write_entitlements!
      [@material.app_profile, @material.extension_profile].each do |profile|
        source = profile.role == "app" ? "Runner/Runner.entitlements" :
          "HiddifyPacketTunnel/HiddifyPacketTunnel.entitlements"
        source_path = File.join(@ios_root, source)
        @source_entitlements_sha256[profile.role] = Digest::SHA256.file(source_path).hexdigest
        entitlements = read_xml_plist(source_path)
        groups = entitlements["com.apple.security.application-groups"]
        unless groups.is_a?(Array) && groups.all? { |group| group.is_a?(String) }
          raise SafeError, "SIGNING_SOURCE_APP_GROUPS_INVALID"
        end
        groups = groups.map { |group| group.gsub("$(BASE_BUNDLE_IDENTIFIER)", APP_BUNDLE_ID) }
        unless (groups - profile.app_groups).empty? && groups.include?(APP_GROUP)
          raise SafeError, "#{profile.role.upcase}_PROFILE_APP_GROUP_GRANT_MISSING"
        end
        entitlements["com.apple.security.application-groups"] = groups

        network_extensions = entitlements["com.apple.developer.networking.networkextension"]
        unless network_extensions.is_a?(Array) &&
            network_extensions.all? { |value| value.is_a?(String) } &&
            (network_extensions - profile.network_extensions).empty?
          raise SafeError, "#{profile.role.upcase}_PROFILE_NETWORK_EXTENSION_GRANT_MISSING"
        end

        vpn_api = entitlements["com.apple.developer.networking.vpn.api"]
        unless vpn_api.is_a?(Array) && vpn_api.all? { |value| value.is_a?(String) } &&
            (vpn_api - profile.vpn_api).empty?
          raise SafeError, "#{profile.role.upcase}_PROFILE_VPN_API_GRANT_MISSING"
        end

        if entitlements.key?("aps-environment") && profile.aps_environment != "production"
          raise SafeError, "#{profile.role.upcase}_PROFILE_APS_ENVIRONMENT_REQUIRED"
        end
        if entitlements.key?("aps-environment")
          entitlements["aps-environment"] = "production"
        end
        write_private(File.join(@entitlements_root, "#{profile.role}.entitlements"), plist_xml(entitlements))
      end
    end

    def write_export_options!
      options = {
        "destination" => "export",
        "manageAppVersionAndBuildNumber" => false,
        "method" => "app-store-connect",
        "provisioningProfiles" => {
          APP_BUNDLE_ID => @material.app_profile.uuid,
          EXTENSION_BUNDLE_ID => @material.extension_profile.uuid
        },
        "signingCertificate" => @material.certificate_sha1,
        "signingStyle" => "manual",
        "stripSwiftSymbols" => true,
        "teamID" => TEAM_ID,
        "uploadSymbols" => true
      }
      write_private(@export_options_path, plist_xml(options))
    end

    def read_xml_plist(path)
      value = PlistXML.parse(File.binread(path))
      raise SafeError, "SIGNING_ENTITLEMENTS_INVALID" unless value.is_a?(Hash)

      value
    rescue SafeError, SystemCallError
      raise SafeError, "SIGNING_ENTITLEMENTS_INVALID"
    end

    def plist_xml(value)
      body = plist_value(value, 0)
      %(<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n#{body}</plist>\n)
    end

    def plist_value(value, depth)
      indent = "\t" * depth
      case value
      when Hash
        lines = value.sort_by { |key, _item| key }.flat_map do |key, item|
          ["#{indent}\t<key>#{xml_escape(key)}</key>\n", plist_value(item, depth + 1)]
        end
        "#{indent}<dict>\n#{lines.join}#{indent}</dict>\n"
      when Array
        "#{indent}<array>\n#{value.map { |item| plist_value(item, depth + 1) }.join}#{indent}</array>\n"
      when String then "#{indent}<string>#{xml_escape(value)}</string>\n"
      when true then "#{indent}<true/>\n"
      when false then "#{indent}<false/>\n"
      else raise SafeError, "SIGNING_PLIST_VALUE_INVALID"
      end
    end

    def xml_escape(value)
      value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    def write_private(path, content)
      File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |file| file.write(content) }
    end
  end

  class CommandRunner
    def run!(*command, code:)
      _output, status = Open3.capture2e(*command)
      raise SafeError, code unless status.success?
    rescue SystemCallError
      raise SafeError, code
    end

    def capture!(*command, code:)
      output, status = Open3.capture2e(*command)
      raise SafeError, code unless status.success?

      output
    rescue SystemCallError
      raise SafeError, code
    end
  end

  class SigningSession
    attr_reader :keychain_path

    def initialize(material:, project_root:, runner: CommandRunner.new, home: Dir.home)
      @material = material
      @project_root = project_root
      @runner = runner
      @home = File.expand_path(home)
      @temporary_root = nil
      @installed_profiles = []
      @original_keychains = nil
      @keychain_created = false
    end

    def prepare!
      @temporary_root = Dir.mktmpdir("ios-baseline-signing-", ENV["RUNNER_TEMP"] || Dir.tmpdir)
      File.chmod(0o700, @temporary_root)
      @keychain_path = File.join(@temporary_root, "manual-signing.keychain-db")
      password = SecureRandom.hex(32)
      certificate_path = write_private("distribution.cer.pem", @material.certificate_pem)
      private_key_path = write_private("distribution.key.pem", @material.private_key_pem)

      @original_keychains = parse_keychains(@runner.capture!("/usr/bin/security", "list-keychains", "-d", "user",
        code: "KEYCHAIN_LIST_FAILED"))
      raise SafeError, "KEYCHAIN_LIST_INVALID" if @original_keychains.empty?
      @runner.run!("/usr/bin/security", "create-keychain", "-p", password, @keychain_path,
        code: "KEYCHAIN_CREATE_FAILED")
      @keychain_created = true
      @runner.run!("/usr/bin/security", "set-keychain-settings", "-lut", "21600", @keychain_path,
        code: "KEYCHAIN_CONFIGURE_FAILED")
      @runner.run!("/usr/bin/security", "unlock-keychain", "-p", password, @keychain_path,
        code: "KEYCHAIN_UNLOCK_FAILED")
      @runner.run!("/usr/bin/security", "import", certificate_path, "-k", @keychain_path,
        "-T", "/usr/bin/codesign", "-T", "/usr/bin/security", code: "KEYCHAIN_IMPORT_FAILED")
      @runner.run!("/usr/bin/security", "import", private_key_path, "-k", @keychain_path,
        "-T", "/usr/bin/codesign", "-T", "/usr/bin/security", code: "KEYCHAIN_IMPORT_FAILED")
      @runner.run!("/usr/bin/security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-s",
        "-k", password, @keychain_path, code: "KEYCHAIN_ACCESS_CONTROL_FAILED")
      @runner.run!("/usr/bin/security", "list-keychains", "-d", "user", "-s",
        *(@original_keychains + [@keychain_path]).uniq, code: "KEYCHAIN_LIST_UPDATE_FAILED")
      identities = @runner.capture!("/usr/bin/security", "find-identity", "-v", "-p", "codesigning",
        @keychain_path, code: "SIGNING_IDENTITY_NOT_USABLE")
      raise SafeError, "SIGNING_IDENTITY_NOT_USABLE" unless identities.upcase.include?(@material.certificate_sha1)

      install_profile(@material.app_profile)
      install_profile(@material.extension_profile)
      self
    rescue StandardError
      cleanup!
      raise
    end

    def cleanup!
      errors = []
      @installed_profiles.each do |entry|
        path, expected_digest = entry
        begin
          unless File.file?(path) && Digest::SHA256.file(path).hexdigest == expected_digest
            raise SafeError, "PROFILE_CLEANUP_OWNERSHIP_LOST"
          end
          File.delete(path)
        rescue SafeError, SystemCallError => error
          errors << (error.is_a?(SafeError) ? error : SafeError.new("PROFILE_CLEANUP_FAILED"))
        end
      end
      @installed_profiles.clear
      if @original_keychains
        begin
          @runner.run!("/usr/bin/security", "list-keychains", "-d", "user", "-s", *@original_keychains,
            code: "KEYCHAIN_LIST_RESTORE_FAILED")
          @original_keychains = nil
        rescue SafeError => error
          errors << error
        end
      end
      if @keychain_created && @keychain_path && File.exist?(@keychain_path)
        begin
          @runner.run!("/usr/bin/security", "delete-keychain", @keychain_path,
            code: "KEYCHAIN_DELETE_FAILED")
        rescue SafeError => error
          errors << error
        end
      end
      if @temporary_root && File.directory?(@temporary_root)
        begin
          FileUtils.remove_entry_secure(@temporary_root)
          @temporary_root = nil
          @keychain_created = false
        rescue SystemCallError
          errors << SafeError.new("SIGNING_TEMPORARY_FILES_CLEANUP_FAILED")
        end
      end
      raise errors.first unless errors.empty?
    end

    private

    def write_private(name, content)
      path = File.join(@temporary_root, name)
      File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |file| file.write(content) }
      path
    end

    def parse_keychains(output)
      output.scan(/"([^"]+)"/).flatten.select { |path| path.start_with?("/") }
    end

    def install_profile(profile)
      root = File.join(@home, "Library", "Developer", "Xcode", "UserData", "Provisioning Profiles")
      FileUtils.mkdir_p(root)
      path = File.join(root, "#{profile.uuid}.mobileprovision")
      if File.exist?(path)
        existing = Digest::SHA256.file(path).hexdigest
        return if existing == profile.cms_sha256

        raise SafeError, "PROFILE_DESTINATION_COLLISION"
      end

      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(profile.cms_der) }
      @installed_profiles << [path, profile.cms_sha256]
    end
  end

  class SignedArtifactVerifier
    def initialize(project_root:, pinned_certificate_sha256:, runner: CommandRunner.new)
      @project_root = File.expand_path(project_root)
      @pinned_certificate_sha256 = pinned_certificate_sha256.to_s.downcase
      @runner = runner
      raise SafeError, "SIGNING_CERTIFICATE_FINGERPRINT_INVALID" unless SHA256.match?(@pinned_certificate_sha256)
    end

    def verify!
      archive_app = File.join(@project_root,
        "build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app")
      verify_app_and_extension!(archive_app, "SIGNED_ARCHIVE")

      ipa_files = Dir.glob(File.join(@project_root, "build/ios/ipa/*.ipa"))
      raise SafeError, "SIGNED_IPA_COUNT_INVALID" unless ipa_files.length == 1

      extraction_root = Dir.mktmpdir("ios-baseline-signed-ipa-", ENV["RUNNER_TEMP"] || Dir.tmpdir)
      begin
        @runner.run!("/usr/bin/ditto", "-x", "-k", ipa_files.first, extraction_root,
          code: "SIGNED_IPA_EXTRACTION_FAILED")
        apps = Dir.glob(File.join(extraction_root, "Payload/*.app"))
        raise SafeError, "SIGNED_IPA_APP_COUNT_INVALID" unless apps.length == 1

        verify_app_and_extension!(apps.first, "SIGNED_IPA")
      ensure
        FileUtils.remove_entry_secure(extraction_root) if File.directory?(extraction_root)
      end
      true
    end

    private

    def verify_app_and_extension!(app, prefix)
      raise SafeError, "#{prefix}_APP_MISSING" unless File.directory?(app)

      extensions = Dir.glob(File.join(app, "PlugIns/HiddifyPacketTunnel.appex"))
      raise SafeError, "#{prefix}_EXTENSION_COUNT_INVALID" unless extensions.length == 1

      [app, extensions.first].each { |bundle| verify_bundle!(bundle, prefix) }
    end

    def verify_bundle!(bundle, prefix)
      @runner.run!("/usr/bin/codesign", "--verify", "--strict", bundle,
        code: "#{prefix}_SIGNATURE_INVALID")
      certificate_prefix = File.join(Dir.tmpdir, "ios-baseline-cert-#{SecureRandom.hex(12)}-")
      @runner.run!("/usr/bin/codesign", "--display", "--extract-certificates", certificate_prefix, bundle,
        code: "#{prefix}_CERTIFICATE_EXTRACTION_FAILED")
      leaf = "#{certificate_prefix}0"
      raise SafeError, "#{prefix}_CERTIFICATE_MISSING" unless File.file?(leaf)
      actual = Digest::SHA256.file(leaf).hexdigest
      raise SafeError, "SIGNED_ARTIFACT_CERTIFICATE_MISMATCH" unless actual == @pinned_certificate_sha256
    ensure
      Dir.glob("#{certificate_prefix}*").each { |path| File.delete(path) if File.file?(path) } if certificate_prefix
    end
  end

  class WithSigning
    SECRET_NAMES = %w[
      IOS_BASELINE_SIGNING_P12_BASE64 IOS_BASELINE_SIGNING_P12_PASSWORD
      IOS_BASELINE_APP_PROFILE_BASE64 IOS_BASELINE_EXTENSION_PROFILE_BASE64
      IOS_BASELINE_SIGNING_CERT_SHA256
    ].freeze

    def initialize(project_root:, provenance_path:, material:, controller_sha:, command:,
      session: nil, artifact_verifier: nil, nonce: SecureRandom.hex(8))
      @project_root = project_root
      @provenance_path = File.expand_path(provenance_path, project_root)
      @material = material
      @controller_sha = controller_sha
      @command = command
      @session = session || SigningSession.new(material: material, project_root: project_root)
      @artifact_verifier = artifact_verifier || SignedArtifactVerifier.new(
        project_root: project_root, pinned_certificate_sha256: material.certificate_sha256
      )
      @overrides = ProjectOverrides.new(project_root: project_root, material: material, nonce: nonce)
    end

    def run
      received_signal = nil
      child_pid = nil
      old_handlers = nil
      result = nil
      cleanup_error = nil
      begin
        old_handlers = %w[INT TERM].to_h do |signal|
          [signal, Signal.trap(signal) do
            received_signal ||= signal
            if child_pid
              begin
                Process.kill(signal, -child_pid)
              rescue Errno::ESRCH, Errno::EINVAL
                nil
              end
            else
              raise SignalException, signal
            end
          end]
        end
        @overrides.prepare!
        @session.prepare!
        write_provenance!
        env = child_environment
        child_pid = Process.spawn(env, *@command, in: $stdin, out: $stdout, err: $stderr, pgroup: true)
        _waited, status = Process.wait2(child_pid)
        result = status.exitstatus || 1
        @artifact_verifier.verify! if status.success? && !received_signal
      rescue SignalException => signal
        received_signal ||= Signal.signame(signal.signo)
        result = 128 + signal.signo
      rescue SystemCallError
        raise SafeError, "SIGNING_COMMAND_START_FAILED"
      ensure
        begin
          @session.cleanup!
        rescue StandardError => error
          cleanup_error = error.is_a?(SafeError) ? error : SafeError.new("SIGNING_SESSION_CLEANUP_FAILED")
        end
        begin
          @overrides.cleanup!
        rescue StandardError
          cleanup_error ||= SafeError.new("SIGNING_OVERRIDE_CLEANUP_FAILED")
        end
        old_handlers&.each { |signal, handler| Signal.trap(signal, handler) }
      end
      raise cleanup_error if cleanup_error

      received_signal ? 128 + Signal.list.fetch(received_signal) : result
    end

    private

    def write_provenance!
      receipt = @overrides.provenance(controller_sha: @controller_sha)
      FileUtils.mkdir_p(File.dirname(@provenance_path))
      temporary = "#{@provenance_path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.pretty_generate(receipt) + "\n")
      end
      File.rename(temporary, @provenance_path)
    ensure
      File.delete(temporary) if temporary && File.exist?(temporary)
    end

    def child_environment
      scrubbed = {}
      (SECRET_NAMES + ENV.keys.grep(/\A(?:APPSTORE_|ASC_|APPLE_API_)/)).uniq.each do |name|
        scrubbed[name] = nil
      end
      scrubbed.merge(
        "IOS_BASELINE_SIGNING_WORKSPACE" => @overrides.workspace_path,
        "IOS_BASELINE_SIGNING_EXPORT_OPTIONS" => @overrides.export_options_path,
        "IOS_BASELINE_SIGNING_KEYCHAIN" => @session.keychain_path,
        "SIGNING_CONTROLLER_SHA" => @controller_sha
      )
    end
  end

  class CLI
    def self.run(argv)
      action = argv.shift
      raise SafeError, "SIGNING_COMMAND_INVALID" unless action == "with-signing"

      separator = argv.index("--")
      raise SafeError, "SIGNING_CHILD_COMMAND_MISSING" unless separator

      option_args = argv.shift(separator)
      argv.shift
      raise SafeError, "SIGNING_CHILD_COMMAND_MISSING" if argv.empty?
      options = {}
      OptionParser.new do |parser|
        parser.on("--project-root PATH") { |value| options[:project_root] = value }
        parser.on("--provenance-path PATH") { |value| options[:provenance_path] = value }
      end.parse!(option_args)
      raise SafeError, "SIGNING_PROJECT_ROOT_MISSING" if options[:project_root].to_s.empty?
      raise SafeError, "SIGNING_PROVENANCE_PATH_MISSING" if options[:provenance_path].to_s.empty?

      material = IOSBaselineManualSigning.validate_material!(
        p12_der: decode_env!("IOS_BASELINE_SIGNING_P12_BASE64"),
        p12_password: fetch_env!("IOS_BASELINE_SIGNING_P12_PASSWORD"),
        pinned_certificate_sha256: fetch_env!("IOS_BASELINE_SIGNING_CERT_SHA256"),
        app_profile_cms: decode_env!("IOS_BASELINE_APP_PROFILE_BASE64"),
        extension_profile_cms: decode_env!("IOS_BASELINE_EXTENSION_PROFILE_BASE64")
      )
      controller_sha = fetch_env!("SIGNING_CONTROLLER_SHA")
      WithSigning.new(project_root: options.fetch(:project_root),
        provenance_path: options.fetch(:provenance_path), material: material,
        controller_sha: controller_sha, command: argv).run
    rescue OptionParser::ParseError
      raise SafeError, "SIGNING_OPTIONS_INVALID"
    end

    def self.fetch_env!(name)
      value = ENV[name]
      raise SafeError, "PERSISTENT_SIGNING_MATERIAL_MISSING" if value.to_s.empty?

      value
    end

    def self.decode_env!(name)
      Base64.strict_decode64(fetch_env!(name))
    rescue ArgumentError
      raise SafeError, "PERSISTENT_SIGNING_MATERIAL_INVALID"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    exit IOSBaselineManualSigning::CLI.run(ARGV)
  rescue IOSBaselineManualSigning::SafeError => error
    warn "ERROR_CODE=#{error.code}"
    exit 1
  rescue StandardError
    warn "ERROR_CODE=MANUAL_SIGNING_INTERNAL_ERROR"
    exit 1
  end
end
