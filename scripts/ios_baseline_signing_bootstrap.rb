#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "digest"
require "fileutils"
require "json"
require "openssl"
require "time"
require "uri"

require_relative "ios_baseline_signing_request"
require_relative "ios_baseline_manual_signing"

module IOSBaselineSigningBootstrap
  TEAM_ID = "M9D72QQJ79"
  APP_BUNDLE_ID = "com.womaninred.baseline"
  EXTENSION_BUNDLE_ID = "#{APP_BUNDLE_ID}.HiddifyPacketTunnel"
  APP_GROUP = "group.#{APP_BUNDLE_ID}"
  BUNDLE_IDENTIFIERS = [APP_BUNDLE_ID, EXTENSION_BUNDLE_ID].freeze
  ROLES = { app: APP_BUNDLE_ID, extension: EXTENSION_BUNDLE_ID }.freeze
  REQUIRED_NETWORK_EXTENSIONS = {
    app: %w[app-proxy-provider dns-proxy packet-tunnel-provider],
    extension: %w[app-proxy-provider content-filter-provider dns-proxy packet-tunnel-provider]
  }.freeze
  TRUSTED_HELPER_SOURCE_SHA = "3fb04c73f94c1174a668842ec3e50190abef6e6a"
  TRUSTED_HELPER_SHA256 = "13cd9ed9688c4fec9e346bd12c845eac72616b823b57760535f5f667b6d8a38c"
  RESOURCE_ID = /\A[A-Za-z0-9_-]{1,128}\z/
  SHA256 = /\A[0-9a-f]{64}\z/
  CERTIFICATE_FIELDS = "certificateContent,certificateType,expirationDate"
  CERTIFICATE_TYPES = %w[DISTRIBUTION IOS_DISTRIBUTION].freeze
  CERTIFICATE_TYPES_FILTER = CERTIFICATE_TYPES.join(",")
  PROFILE_FIELDS = "expirationDate,name,profileContent,profileState,profileType"
  PROFILE_TYPE = "IOS_APP_STORE"
  EXPECTED_SUBJECT = {
    "commonName" => "Blizzard iOS Baseline Distribution",
    "organization" => "Blizzard",
    "organizationalUnit" => "Release Engineering"
  }.freeze
  EXPECTED_SUBJECT_NAME = OpenSSL::X509::Name.new([
    ["O", "Blizzard", OpenSSL::ASN1::UTF8STRING],
    ["OU", "Release Engineering", OpenSSL::ASN1::UTF8STRING],
    ["CN", "Blizzard iOS Baseline Distribution", OpenSSL::ASN1::UTF8STRING]
  ])
  DISTRIBUTION_OIDS = %w[1.2.840.113635.100.6.1.4 1.2.840.113635.100.6.1.7].freeze
  CLOUD_MANAGED_OID = "1.2.840.113635.100.6.1.32"

  class SafeError < StandardError
    attr_reader :code, :stage, :details

    def initialize(code, stage: nil, details: nil)
      @code = code
      @stage = stage
      @details = details
      super(code)
    end
  end

  def self.public_key_spki_der(key)
    key.public_key.to_der
  end

  class Request
    attr_reader :csr_pem, :csr, :manifest, :spki_sha256, :csr_sha256, :created_at

    def self.load(csr_pem, manifest)
      new(csr_pem, manifest).validate!
    end

    def initialize(csr_pem, manifest)
      @csr_pem = csr_pem
      @manifest = manifest
    end

    def validate!
      raise SafeError, "REQUEST_CSR_INVALID" unless @csr_pem.is_a?(String) && @csr_pem.bytesize <= 64 * 1024
      raise SafeError, "REQUEST_MANIFEST_INVALID" unless @manifest.is_a?(Hash)

      expected_keys = %w[createdAt csrFile csrSHA256 keyAlgorithm schema spkiSHA256 subject]
      raise SafeError, "REQUEST_MANIFEST_INVALID" unless @manifest.keys.sort == expected_keys
      raise SafeError, "REQUEST_MANIFEST_INVALID" unless
        @manifest["schema"] == IOSBaselineSigningRequest::REQUEST_SCHEMA &&
        @manifest["csrFile"] == "request.csr.pem" &&
        @manifest["keyAlgorithm"] == { "name" => "RSA", "bits" => 3072 } &&
        @manifest["subject"] == EXPECTED_SUBJECT

      @csr_sha256 = Digest::SHA256.hexdigest(@csr_pem)
      raise SafeError, "REQUEST_CSR_HASH_MISMATCH" unless @manifest["csrSHA256"] == @csr_sha256
      @csr = OpenSSL::X509::Request.new(@csr_pem)
      raise SafeError, "REQUEST_CSR_SIGNATURE_INVALID" unless @csr.verify(@csr.public_key)
      raise SafeError, "REQUEST_CSR_SUBJECT_INVALID" unless @csr.subject.to_der == EXPECTED_SUBJECT_NAME.to_der
      key = @csr.public_key
      raise SafeError, "REQUEST_KEY_INVALID" unless key.is_a?(OpenSSL::PKey::RSA) && key.n.num_bits == 3072

      @spki_sha256 = Digest::SHA256.hexdigest(IOSBaselineSigningBootstrap.public_key_spki_der(key))
      raise SafeError, "REQUEST_SPKI_MISMATCH" unless @manifest["spkiSHA256"] == @spki_sha256
      raise SafeError, "REQUEST_CREATED_AT_INVALID" unless @manifest["createdAt"].is_a?(String)
      @created_at = Time.iso8601(@manifest["createdAt"]).utc
      self
    rescue OpenSSL::OpenSSLError
      raise SafeError, "REQUEST_CSR_INVALID"
    rescue ArgumentError
      raise SafeError, "REQUEST_CREATED_AT_INVALID"
    end

    def intent_id
      IOSBaselineSigningBootstrap.intent_id(@manifest)
    end
  end

  def self.intent_id(manifest)
    payload = {
      "schema" => "ios-baseline-signing-intent/v1",
      "teamId" => TEAM_ID,
      "bundleIdentifiers" => BUNDLE_IDENTIFIERS,
      "appGroup" => APP_GROUP,
      "csrSHA256" => manifest.fetch("csrSHA256"),
      "spkiSHA256" => manifest.fetch("spkiSHA256")
    }
    Digest::SHA256.hexdigest(JSON.generate(payload))
  rescue KeyError
    raise SafeError, "REQUEST_MANIFEST_INVALID"
  end

  def self.checkpoint(request, clock: -> { Time.now })
    {
      "schema" => "ios-baseline-signing-intent/v1",
      "authorized" => true,
      "createdAt" => clock.call.utc.iso8601,
      "intentId" => request.intent_id,
      "teamId" => TEAM_ID,
      "bundleIdentifiers" => BUNDLE_IDENTIFIERS,
      "appGroup" => APP_GROUP,
      "csrSHA256" => request.csr_sha256,
      "spkiSHA256" => request.spki_sha256
    }
  end

  def self.prepare_checkpoint(csr_pem:, manifest:, clock: -> { Time.now })
    checkpoint(Request.load(csr_pem, manifest), clock: clock)
  end

  def self.profile_name(role, spki_sha256)
    label = role.to_sym == :app ? "App" : "Extension"
    "Blizzard iOS Baseline #{label} #{spki_sha256[0, 16]}"
  end

  class RestrictedTransport
    CURSOR = /\A[\x21-\x7E]{1,1024}\z/

    def initialize(delegate)
      @delegate = delegate
    end

    def request(method:, url:, headers:, body:, timeouts:)
      uri = normalize_origin(url)
      if method == "GET"
        validate_get!(uri, body)
      elsif method == "POST"
        validate_post!(uri, body)
      else
        raise SafeError, "UNSAFE_ASC_REQUEST"
      end
      @delegate.request(method: method, url: uri.to_s, headers: headers, body: body, timeouts: timeouts)
    end

    def normalize(url)
      uri = normalize_origin(url)
      raise SafeError, "UNSAFE_ASC_REQUEST" unless %w[GET POST].any?
      uri.to_s
    end

    private

    def normalize_origin(url)
      uri = URI.join("#{IOSBaselineRelease::API_ORIGIN}/", url)
      safe = uri.is_a?(URI::HTTPS) && uri.host == URI(IOSBaselineRelease::API_ORIGIN).host &&
        uri.port == 443 && uri.userinfo.nil? && uri.fragment.nil?
      raise SafeError, "UNSAFE_ASC_REQUEST" unless safe
      uri
    rescue URI::InvalidURIError, ArgumentError
      raise SafeError, "UNSAFE_ASC_REQUEST"
    end

    def params(uri)
      pairs = URI.decode_www_form(uri.query.to_s)
      raise SafeError, "UNSAFE_ASC_REQUEST" unless pairs.map(&:first).uniq.length == pairs.length
      result = pairs.to_h
      cursor = result.delete("cursor")
      raise SafeError, "UNSAFE_ASC_REQUEST" if cursor && !CURSOR.match?(cursor)
      [result, cursor]
    rescue ArgumentError
      raise SafeError, "UNSAFE_ASC_REQUEST"
    end

    def validate_get!(uri, body)
      raise SafeError, "UNSAFE_ASC_REQUEST" unless body.nil?
      values, = params(uri)
      expected = case uri.path
                 when "/v1/certificates"
                   {
                     "filter[certificateType]" => CERTIFICATE_TYPES_FILTER,
                     "fields[certificates]" => CERTIFICATE_FIELDS,
                     "limit" => "200"
                   }
                 when "/v1/bundleIds"
                   identifier = values["filter[identifier]"]
                   raise SafeError, "UNSAFE_ASC_REQUEST" unless BUNDLE_IDENTIFIERS.include?(identifier)
                   { "filter[identifier]" => identifier, "fields[bundleIds]" => "identifier", "limit" => "200" }
                 when %r{\A/v1/bundleIds/([A-Za-z0-9_-]{1,128})/profiles\z}
                   { "fields[profiles]" => PROFILE_FIELDS, "limit" => "200" }
                 else
                   raise SafeError, "UNSAFE_ASC_REQUEST"
                 end
      raise SafeError, "UNSAFE_ASC_REQUEST" unless values == expected
    end

    def validate_post!(uri, body)
      raise SafeError, "UNSAFE_ASC_REQUEST" unless uri.query.to_s.empty? && body.is_a?(String)
      payload = JSON.parse(body)
      case uri.path
      when "/v1/certificates"
        validate_certificate_body!(payload)
      when "/v1/profiles"
        validate_profile_body!(payload)
      else
        raise SafeError, "UNSAFE_ASC_REQUEST"
      end
    rescue JSON::ParserError
      raise SafeError, "UNSAFE_ASC_REQUEST"
    end

    def validate_certificate_body!(payload)
      data = payload.is_a?(Hash) && payload["data"]
      attributes = data.is_a?(Hash) && data["attributes"]
      valid = payload.keys == ["data"] && data.keys.sort == %w[attributes type] &&
        data["type"] == "certificates" && attributes.is_a?(Hash) &&
        attributes.keys.sort == %w[certificateType csrContent] &&
        attributes["certificateType"] == "DISTRIBUTION" &&
        attributes["csrContent"].is_a?(String) && attributes["csrContent"].include?("BEGIN CERTIFICATE REQUEST")
      raise SafeError, "UNSAFE_ASC_REQUEST" unless valid
    end

    def validate_profile_body!(payload)
      data = payload.is_a?(Hash) && payload["data"]
      attributes = data.is_a?(Hash) && data["attributes"]
      relationships = data.is_a?(Hash) && data["relationships"]
      bundle = relationships.is_a?(Hash) && relationships.dig("bundleId", "data")
      certificates = relationships.is_a?(Hash) && relationships.dig("certificates", "data")
      certificate = certificates.is_a?(Array) && certificates.length == 1 && certificates.first
      valid = payload.keys == ["data"] && data.keys.sort == %w[attributes relationships type] &&
        data["type"] == "profiles" && attributes.is_a?(Hash) &&
        attributes.keys.sort == %w[name profileType] && attributes["profileType"] == PROFILE_TYPE &&
        attributes["name"].is_a?(String) &&
        /\ABlizzard iOS Baseline (?:App|Extension) [0-9a-f]{16}\z/.match?(attributes["name"]) &&
        relationships.keys.sort == %w[bundleId certificates] && resource_link?(bundle, "bundleIds") &&
        resource_link?(certificate, "certificates")
      raise SafeError, "UNSAFE_ASC_REQUEST" unless valid
    end

    def resource_link?(value, type)
      value.is_a?(Hash) && value.keys.sort == %w[id type] && value["type"] == type &&
        value["id"].is_a?(String) && RESOURCE_ID.match?(value["id"])
    end
  end

  class PageCollector
    MAX_PAGES = 50

    def initialize(client)
      @client = client
    end

    def all(path)
      initial = URI.join("#{IOSBaselineRelease::API_ORIGIN}/", path)
      expected_path = initial.path
      expected_query = query_without_cursor(initial)
      next_path = path
      seen_urls = {}
      seen_ids = {}
      result = []
      total = nil
      total_mode = nil
      pages = 0
      until next_path.to_s.empty?
        uri = URI.join("#{IOSBaselineRelease::API_ORIGIN}/", next_path)
        safe_origin = uri.is_a?(URI::HTTPS) && uri.host == URI(IOSBaselineRelease::API_ORIGIN).host &&
          uri.port == 443 && uri.userinfo.nil? && uri.fragment.nil?
        raise SafeError, "UNSAFE_ASC_REQUEST" unless safe_origin
        raise SafeError, "PAGINATION_ROUTE_CHANGED" unless uri.path == expected_path
        raise SafeError, "PAGINATION_QUERY_CHANGED" unless query_without_cursor(uri) == expected_query
        normalized = uri.to_s
        raise SafeError, "PAGINATION_DUPLICATE" if seen_urls.key?(normalized)
        raise SafeError, "PAGINATION_LIMIT" if pages >= MAX_PAGES
        seen_urls[normalized] = true
        pages += 1
        payload = @client.get(next_path)
        raise SafeError, "PAGINATION_RESPONSE_INVALID" unless payload.is_a?(Hash) && payload["data"].is_a?(Array)
        payload["data"].each do |resource|
          id = resource.is_a?(Hash) && resource["id"]
          raise SafeError, "PAGINATION_RESPONSE_INVALID" unless id.is_a?(String) && RESOURCE_ID.match?(id)
          raise SafeError, "PAGINATION_DUPLICATE" if seen_ids.key?(id)
          seen_ids[id] = true
        end
        present, current_total = page_total(payload)
        mode = present ? :present : :absent
        total_mode ||= mode
        raise SafeError, "PAGINATION_TOTAL_CHANGED" unless mode == total_mode
        total ||= current_total if present
        raise SafeError, "PAGINATION_TOTAL_CHANGED" if present && total != current_total
        result.concat(payload["data"])
        raise SafeError, "PAGINATION_TOTAL_MISMATCH" if total && result.length > total
        links = payload["links"]
        raise SafeError, "PAGINATION_RESPONSE_INVALID" if links && !links.is_a?(Hash)
        next_path = links && links["next"]
        unless next_path.nil? || (next_path.is_a?(String) && !next_path.empty?)
          raise SafeError, "PAGINATION_RESPONSE_INVALID"
        end
      end
      raise SafeError, "PAGINATION_TOTAL_MISMATCH" if total && result.length != total
      result
    end

    private

    def query_without_cursor(uri)
      URI.decode_www_form(uri.query.to_s).reject { |key, _value| key == "cursor" }.sort
    end

    def page_total(payload)
      return [false, nil] unless payload.key?("meta")
      meta = payload["meta"]
      raise SafeError, "PAGINATION_TOTAL_INVALID" unless meta.is_a?(Hash)
      return [false, nil] unless meta.key?("paging")
      paging = meta["paging"]
      raise SafeError, "PAGINATION_TOTAL_INVALID" unless paging.is_a?(Hash)
      return [false, nil] unless paging.key?("total")
      value = paging["total"]
      raise SafeError, "PAGINATION_TOTAL_INVALID" unless value.is_a?(Integer) && value >= 0
      [true, value]
    end
  end

  class Bootstrap
    def initialize(client:, clock: -> { Time.now }, profile_decoder: IOSBaselineManualSigning::CMSDecoder.new)
      @client = client
      @pages = PageCollector.new(client)
      @clock = clock
      @profile_decoder = profile_decoder
      @progress = nil
    end

    def run(mode:, csr_pem:, manifest:, env: {})
      raise SafeError, "MODE_INVALID" unless %w[plan create resume].include?(mode)
      request = Request.load(csr_pem, manifest)
      @progress = { "profiles" => {} }
      validate_create_gate!(request, env) if mode == "create"
      certificate_record = find_certificate(request)
      bundles = ROLES.each_with_object({}) do |(role, identifier), result|
        result[role] = exact_bundle(identifier)
      end

      if certificate_record.nil?
        return plan_result(request, %w[certificate appProfile extensionProfile]) if mode == "plan"
        raise SafeError, "RESUME_CERTIFICATE_NOT_FOUND" if mode == "resume"
        certificate_record = create_certificate(request)
      end
      track_certificate(certificate_record)

      profiles = {}
      missing = []
      ROLES.each_key do |role|
        profile = find_profile(role, bundles.fetch(role), certificate_record, request)
        if profile
          profiles[role] = profile
          track_profile(role, profile)
        else
          missing << "#{role}Profile"
        end
      end
      ensure_unique_profile_ids!(profiles)
      return plan_result(request, missing) if mode == "plan" && !missing.empty?
      raise SafeError, "RESUME_PROFILE_NOT_FOUND" if mode == "resume" && !missing.empty?

      missing.each do |label|
        role = label == "appProfile" ? :app : :extension
        profiles[role] = create_profile(role, bundles.fetch(role), certificate_record, request)
        track_profile(role, profiles.fetch(role))
      end
      ensure_unique_profile_ids!(profiles)
      ready_result(request, certificate_record, profiles)
    rescue SafeError => error
      raise with_progress(error)
    rescue IOSBaselineRelease::SafeError => error
      raise with_progress(SafeError.new(error.code))
    end

    private

    def now
      value = @clock.call
      (value.is_a?(Time) ? value : Time.at(value.to_i)).utc
    rescue ArgumentError, RangeError
      raise SafeError, "CLOCK_INVALID"
    end

    def validate_create_gate!(request, env)
      checks = {
        "IOS_SIGNING_CREATE_AUTHORIZED" => "true",
        "IOS_SIGNING_INTENT_ID" => request.intent_id,
        "GITHUB_EVENT_NAME" => "workflow_dispatch",
        "GITHUB_REF" => "refs/heads/main",
        "GITHUB_REPOSITORY" => "maikrais98/hiddify-app",
        "GITHUB_RUN_ATTEMPT" => "1"
      }
      checks.each { |name, expected| raise SafeError, "CREATE_GATE_INVALID" unless env[name] == expected }
      age = now - request.created_at
      raise SafeError, "CREATE_REQUEST_STALE" unless age >= -300 && age <= 86_400
      validate_checkpoint!(request, env)
    end

    def validate_checkpoint!(request, env)
      path = env["IOS_SIGNING_CHECKPOINT_PATH"]
      expected_digest = env["IOS_SIGNING_CHECKPOINT_SHA256"]
      raise SafeError, "CREATE_CHECKPOINT_INVALID" unless path.is_a?(String) && File.file?(path) &&
        expected_digest.is_a?(String) && SHA256.match?(expected_digest)
      bytes = File.binread(path)
      raise SafeError, "CREATE_CHECKPOINT_INVALID" unless Digest::SHA256.hexdigest(bytes) == expected_digest
      parsed = JSON.parse(bytes)
      expected = IOSBaselineSigningBootstrap.checkpoint(request, clock: -> { Time.iso8601(parsed.fetch("createdAt")) })
      raise SafeError, "CREATE_CHECKPOINT_INVALID" unless parsed == expected
    rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError, KeyError, ArgumentError
      raise SafeError, "CREATE_CHECKPOINT_INVALID"
    end

    def find_certificate(request)
      resources = @pages.all(certificate_path)
      matches = resources.map { |resource| parse_certificate_resource(resource) }
        .select { |record| record.fetch(:spki_sha256) == request.spki_sha256 }
      raise SafeError, "CERTIFICATE_SPKI_AMBIGUOUS" if matches.length > 1
      return nil if matches.empty?
      validate_certificate!(matches.first)
    end

    def certificate_path
      "/v1/certificates?" + URI.encode_www_form(
        "filter[certificateType]" => CERTIFICATE_TYPES_FILTER,
        "fields[certificates]" => CERTIFICATE_FIELDS,
        "limit" => 200
      )
    end

    def parse_certificate_resource(resource)
      attributes = resource.is_a?(Hash) && resource["attributes"]
      id = resource.is_a?(Hash) && resource["id"]
      valid = resource.is_a?(Hash) && resource["type"] == "certificates" &&
        id.is_a?(String) && RESOURCE_ID.match?(id) && attributes.is_a?(Hash) &&
        attributes["certificateContent"].is_a?(String) && attributes["certificateType"].is_a?(String) &&
        attributes["expirationDate"].is_a?(String)
      raise SafeError, "CERTIFICATE_RESOURCE_INVALID" unless valid
      der = Base64.strict_decode64(attributes["certificateContent"])
      certificate = OpenSSL::X509::Certificate.new(der)
      {
        id: id,
        type: attributes["certificateType"],
        expiration: Time.iso8601(attributes["expirationDate"]).utc,
        certificate: certificate,
        der: certificate.to_der,
        sha256: Digest::SHA256.hexdigest(certificate.to_der),
        spki_sha256: Digest::SHA256.hexdigest(IOSBaselineSigningBootstrap.public_key_spki_der(certificate.public_key))
      }
    rescue ArgumentError, OpenSSL::OpenSSLError
      raise SafeError, "CERTIFICATE_RESOURCE_INVALID"
    end

    def validate_certificate!(record)
      certificate = record.fetch(:certificate)
      raise SafeError, "CERTIFICATE_TYPE_INVALID" unless CERTIFICATE_TYPES.include?(record.fetch(:type))
      team_values = certificate.subject.to_a.select { |name, _value, _type| name == "OU" }
        .map { |_name, value, _type| value }
      raise SafeError, "CERTIFICATE_TEAM_MISMATCH" unless team_values == [TEAM_ID]
      oids = certificate.extensions.map(&:oid)
      common_names = certificate.subject.to_a.select { |name, _value, _type| name == "CN" }
        .map { |_name, value, _type| value }
      dedicated_name = /\AApple Distribution: .+ \(#{Regexp.escape(TEAM_ID)}\)\z/
      unless common_names.length == 1 && dedicated_name.match?(common_names.first) &&
          (oids & DISTRIBUTION_OIDS).any?
        raise SafeError, "CERTIFICATE_DISTRIBUTION_INVALID"
      end
      raise SafeError, "CERTIFICATE_CLOUD_MANAGED_FORBIDDEN" if oids.include?(CLOUD_MANAGED_OID)
      raise SafeError, "CERTIFICATE_NOT_YET_VALID" if certificate.not_before > now
      raise SafeError, "CERTIFICATE_EXPIRED" if certificate.not_after <= now || record.fetch(:expiration) <= now
      raise SafeError, "CERTIFICATE_EXPIRATION_MISMATCH" unless certificate.not_after.to_i == record.fetch(:expiration).to_i
      record
    end

    def exact_bundle(identifier)
      resources = @pages.all("/v1/bundleIds?" + URI.encode_www_form(
        "filter[identifier]" => identifier,
        "fields[bundleIds]" => "identifier",
        "limit" => 200
      ))
      matches = resources.select { |resource| resource.is_a?(Hash) && resource.dig("attributes", "identifier") == identifier }
      raise SafeError, "BUNDLE_ID_NOT_FOUND" if matches.empty?
      raise SafeError, "BUNDLE_ID_AMBIGUOUS" unless matches.length == 1
      resource = matches.first
      valid = resource["type"] == "bundleIds" && resource["id"].is_a?(String) &&
        RESOURCE_ID.match?(resource["id"])
      raise SafeError, "BUNDLE_ID_INVALID" unless valid
      resource.fetch("id")
    end

    def profile_path(bundle_id)
      "/v1/bundleIds/#{bundle_id}/profiles?" + URI.encode_www_form(
        "fields[profiles]" => PROFILE_FIELDS,
        "limit" => 200
      )
    end

    def find_profile(role, bundle_id, certificate_record, request)
      resources = @pages.all(profile_path(bundle_id))
      expected_name = IOSBaselineSigningBootstrap.profile_name(role, request.spki_sha256)
      matches = resources.select { |resource| resource.is_a?(Hash) && resource.dig("attributes", "name") == expected_name }
      raise SafeError, "#{role.to_s.upcase}_PROFILE_AMBIGUOUS" if matches.length > 1
      return nil if matches.empty?
      validate_profile!(role, matches.first, certificate_record, expected_name)
    end

    def validate_profile!(role, resource, certificate_record, expected_name)
      prefix = role.to_s.upcase
      attributes = resource.is_a?(Hash) && resource["attributes"]
      id = resource.is_a?(Hash) && resource["id"]
      valid = resource.is_a?(Hash) && resource["type"] == "profiles" &&
        id.is_a?(String) && RESOURCE_ID.match?(id) && attributes.is_a?(Hash) &&
        attributes["name"] == expected_name && attributes["profileContent"].is_a?(String) &&
        attributes["expirationDate"].is_a?(String)
      raise SafeError, "#{prefix}_PROFILE_RESOURCE_INVALID" unless valid
      raise SafeError, "#{prefix}_PROFILE_TYPE_INVALID" unless attributes["profileType"] == PROFILE_TYPE
      raise SafeError, "#{prefix}_PROFILE_STATE_INVALID" unless attributes["profileState"] == "ACTIVE"
      expiration = Time.iso8601(attributes["expirationDate"]).utc
      raise SafeError, "#{prefix}_PROFILE_EXPIRED" if expiration <= now
      cms = Base64.strict_decode64(attributes["profileContent"])
      decoded = @profile_decoder.decode(cms)
      validator = IOSBaselineManualSigning::ProfileValidator.new(
        certificate_sha256: certificate_record.fetch(:sha256), now: now
      )
      material = validator.validate!(role: role, profile: decoded, cms_der: cms)
      raise SafeError, "#{prefix}_PROFILE_EXPIRATION_MISMATCH" unless decoded["ExpirationDate"].to_i == expiration.to_i
      unless (REQUIRED_NETWORK_EXTENSIONS.fetch(role) - material.network_extensions).empty?
        raise SafeError, "#{prefix}_PROFILE_NETWORK_EXTENSION_GRANTS_MISMATCH"
      end
      if role == :app && material.aps_environment != "production"
        raise SafeError, "APP_PROFILE_APS_ENVIRONMENT_REQUIRED"
      end
      raise SafeError, "#{prefix}_PROFILE_APP_GROUP_GRANTS_MISMATCH" unless material.app_groups.include?(APP_GROUP)
      raise SafeError, "#{prefix}_PROFILE_VPN_API_GRANTS_MISMATCH" unless material.vpn_api.include?("allow-vpn")
      { id: id, cms: cms, sha256: material.cms_sha256, expiration: expiration.iso8601 }
    rescue ArgumentError, OpenSSL::OpenSSLError
      raise SafeError, "#{prefix}_PROFILE_RESOURCE_INVALID"
    rescue IOSBaselineManualSigning::SafeError => error
      raise SafeError, error.code
    end

    def create_certificate(request)
      body = {
        "data" => {
          "type" => "certificates",
          "attributes" => { "certificateType" => "DISTRIBUTION", "csrContent" => request.csr_pem }
        }
      }
      payload = uncertain_post("CREATE_CERTIFICATE", "/v1/certificates", body) do
        found = find_certificate(request)
        track_certificate(found) if found
        found
      end
      resource = payload.is_a?(Hash) && payload["data"]
      unless resource.is_a?(Hash)
        uncertain_outcome!("CREATE_CERTIFICATE") do
          found = find_certificate(request)
          track_certificate(found) if found
          found
        end
      end
      begin
        record = parse_certificate_resource(resource)
      rescue SafeError => error
        raise unless error.code == "CERTIFICATE_RESOURCE_INVALID"
        uncertain_outcome!("CREATE_CERTIFICATE") do
          found = find_certificate(request)
          track_certificate(found) if found
          found
        end
      end
      record = validate_certificate!(record)
      raise SafeError, "CERTIFICATE_SPKI_MISMATCH" unless record.fetch(:spki_sha256) == request.spki_sha256
      record
    end

    def create_profile(role, bundle_id, certificate_record, request)
      name = IOSBaselineSigningBootstrap.profile_name(role, request.spki_sha256)
      body = {
        "data" => {
          "type" => "profiles",
          "attributes" => { "name" => name, "profileType" => PROFILE_TYPE },
          "relationships" => {
            "bundleId" => { "data" => { "type" => "bundleIds", "id" => bundle_id } },
            "certificates" => { "data" => [
              { "type" => "certificates", "id" => certificate_record.fetch(:id) }
            ] }
          }
        }
      }
      payload = uncertain_post("CREATE_#{role.to_s.upcase}_PROFILE", "/v1/profiles", body) do
        found = find_profile(role, bundle_id, certificate_record, request)
        track_profile(role, found) if found
        found
      end
      resource = payload.is_a?(Hash) && payload["data"]
      unless resource.is_a?(Hash)
        uncertain_outcome!("CREATE_#{role.to_s.upcase}_PROFILE") do
          found = find_profile(role, bundle_id, certificate_record, request)
          track_profile(role, found) if found
          found
        end
      end
      begin
        validate_profile!(role, resource, certificate_record, name)
      rescue SafeError => error
        raise unless error.code == "#{role.to_s.upcase}_PROFILE_RESOURCE_INVALID"
        uncertain_outcome!("CREATE_#{role.to_s.upcase}_PROFILE") do
          found = find_profile(role, bundle_id, certificate_record, request)
          track_profile(role, found) if found
          found
        end
      end
    end

    def uncertain_post(stage, path, body)
      @client.post(path, body, retry_request: false)
    rescue IOSBaselineRelease::SafeError => error
      uncertain = error.code == "ASC_TRANSPORT_FAILED" || error.code == "ASC_HTTP_429" ||
        error.code == "ASC_RESPONSE_INVALID" || /\AASC_HTTP_5[0-9]{2}\z/.match?(error.code)
      raise SafeError.new(error.code, stage: stage) unless uncertain
      uncertain_outcome!(stage) { yield }
    end

    def uncertain_outcome!(stage)
      reconciled = false
      begin
        reconciled = !yield.nil?
      rescue StandardError
        reconciled = false
      end
      raise SafeError.new("POST_OUTCOME_UNCERTAIN", stage: stage,
        details: { "reconciled" => reconciled })
    end

    def plan_result(request, missing)
      code = if missing.empty?
               "SIGNING_BOOTSTRAP_READY"
             elsif missing.include?("certificate")
               "PLAN_CREATE_CERTIFICATE_AND_PROFILES"
             else
               "PLAN_CREATE_PROFILES"
             end
      {
        "schema" => "ios-baseline-signing-bootstrap-result/v1",
        "code" => code,
        "intentId" => request.intent_id,
        "spkiSHA256" => request.spki_sha256,
        "missing" => missing
      }
    end

    def ready_result(request, certificate_record, profiles)
      {
        "schema" => "ios-baseline-signing-bootstrap-result/v1",
        "code" => "SIGNING_BOOTSTRAP_READY",
        "intentId" => request.intent_id,
        "spkiSHA256" => request.spki_sha256,
        "certificateId" => certificate_record.fetch(:id),
        "certificateSHA256" => certificate_record.fetch(:sha256),
        "certificateDER" => certificate_record.fetch(:der),
        "profiles" => profiles
      }
    end

    def ensure_unique_profile_ids!(profiles)
      profile_ids = profiles.values.map { |profile| profile.fetch(:id) }
      raise SafeError, "PROFILE_ID_REUSED" unless profile_ids.uniq.length == profile_ids.length
    end

    def track_certificate(record)
      @progress["certificate"] = {
        "id" => record.fetch(:id),
        "sha256" => record.fetch(:sha256)
      }
    end

    def track_profile(role, profile)
      @progress.fetch("profiles")[role.to_s] = {
        "id" => profile.fetch(:id),
        "sha256" => profile.fetch(:sha256),
        "expiration" => profile.fetch(:expiration)
      }
    end

    def with_progress(error)
      confirmed = @progress && (@progress["certificate"] || !@progress.fetch("profiles", {}).empty?) ? @progress : nil
      details = (error.details || {}).dup
      details["confirmed"] = confirmed if confirmed
      SafeError.new(error.code, stage: error.stage, details: details.empty? ? nil : details)
    end
  end

  def self.require_verified_helper!(path)
    raise SafeError, "HELPER_NOT_FOUND" unless path.is_a?(String) && File.file?(path)
    raise SafeError, "HELPER_HASH_MISMATCH" unless Digest::SHA256.file(path).hexdigest == TRUSTED_HELPER_SHA256
    require File.realpath(path)
    required = %i[Client Config JwtProvider NetHTTPTransport SafeError]
    unless defined?(IOSBaselineRelease) && required.all? { |name| IOSBaselineRelease.const_defined?(name, false) }
      raise SafeError, "HELPER_API_INVALID"
    end
  rescue Errno::ENOENT, Errno::EACCES
    raise SafeError, "HELPER_NOT_FOUND"
  rescue LoadError
    raise SafeError, "HELPER_API_INVALID"
  end

  def self.safe_receipt(mode:, status:, clock:, request: nil, error: nil, result: nil)
    receipt = {
      "schema" => "ios-baseline-signing-bootstrap-receipt/v1",
      "status" => status,
      "mode" => mode,
      "observedAt" => clock.call.utc.iso8601,
      "helperSHA" => TRUSTED_HELPER_SOURCE_SHA
    }
    if request
      receipt["intentId"] = request.intent_id
      receipt["csrSHA256"] = request.csr_sha256
      receipt["spkiSHA256"] = request.spki_sha256
    end
    if result
      receipt["code"] = result.fetch("code")
      receipt["certificateId"] = result["certificateId"] if result["certificateId"]
      receipt["certificateSHA256"] = result["certificateSHA256"] if result["certificateSHA256"]
      receipt["profiles"] = result.fetch("profiles", {}).transform_values do |profile|
        { "id" => profile.fetch(:id), "sha256" => profile.fetch(:sha256), "expiration" => profile.fetch(:expiration) }
      end
      receipt["missing"] = result["missing"] if result["missing"]
    end
    if error
      receipt["code"] = error.respond_to?(:code) ? error.code : "SIGNING_BOOTSTRAP_FAILED"
      receipt["stage"] = error.stage if error.respond_to?(:stage) && error.stage
      receipt["outcomeReconciled"] = error.details["reconciled"] if error.respond_to?(:details) && error.details
      if error.respond_to?(:details) && error.details && error.details["confirmed"]
        receipt["confirmed"] = error.details["confirmed"]
      end
    end
    receipt
  rescue StandardError
    { "schema" => "ios-baseline-signing-bootstrap-receipt/v1", "status" => "FAILED",
      "mode" => mode.to_s, "code" => "SIGNING_BOOTSTRAP_FAILED" }
  end

  def self.write_exclusive(path, bytes, mode = 0o644)
    File.open(path, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
      file.binmode
      file.write(bytes)
      file.flush
      file.fsync
    end
    File.chmod(mode, path)
  rescue Errno::EEXIST
    raise SafeError, "OUTPUT_FILE_EXISTS"
  end

  def self.run_cli(arguments, env: ENV, out: $stdout, err: $stderr, transport: nil,
    clock: -> { Time.now }, client_options: {}, profile_decoder: IOSBaselineManualSigning::CMSDecoder.new)
    mode, helper_path, csr_path, manifest_path, output_directory = arguments
    raise SafeError, "USAGE_ERROR" unless arguments.length == 5 && %w[prepare plan create resume].include?(mode)
    require_verified_helper!(helper_path)
    csr_pem = File.binread(csr_path)
    manifest = JSON.parse(File.binread(manifest_path))
    request = Request.load(csr_pem, manifest)
    Dir.mkdir(output_directory, 0o700)
    File.chmod(0o700, output_directory)

    if mode == "prepare"
      age = clock.call.utc - request.created_at
      raise SafeError, "CREATE_REQUEST_STALE" unless age >= -300 && age <= 86_400
      intent = checkpoint(request, clock: clock)
      write_exclusive(File.join(output_directory, "intent.json"), JSON.generate(intent) + "\n")
      result = { "code" => "SIGNING_INTENT_PREPARED", "intentId" => request.intent_id }
    else
      issuer_id = IOSBaselineRelease::Config.required(env, "APPSTORE_ISSUER_ID")
      key_id = IOSBaselineRelease::Config.required(env, "APPSTORE_API_KEY_ID")
      private_key = IOSBaselineRelease::Config.required(env, "APPSTORE_API_PRIVATE_KEY")
      IOSBaselineRelease::Config.validate(issuer_id, /\A[A-Za-z0-9-]{3,128}\z/, "APPSTORE_ISSUER_ID")
      IOSBaselineRelease::Config.validate(key_id, /\A[A-Za-z0-9]{3,64}\z/, "APPSTORE_API_KEY_ID")
      provider = IOSBaselineRelease::JwtProvider.new(issuer_id: issuer_id, key_id: key_id,
        private_key: private_key, clock: -> { clock.call.to_i })
      options = { transport: RestrictedTransport.new(transport || IOSBaselineRelease::NetHTTPTransport.new),
        token_provider: provider }.merge(client_options)
      result = Bootstrap.new(client: IOSBaselineRelease::Client.new(**options), clock: clock,
        profile_decoder: profile_decoder)
        .run(mode: mode, csr_pem: csr_pem, manifest: manifest, env: env)
      if result["certificateDER"]
        write_exclusive(File.join(output_directory, "distribution.cer"), result.fetch("certificateDER"))
        write_exclusive(File.join(output_directory, "app.mobileprovision"), result.dig("profiles", :app, :cms))
        write_exclusive(File.join(output_directory, "extension.mobileprovision"),
          result.dig("profiles", :extension, :cms))
      end
    end
    receipt = safe_receipt(mode: mode, status: "SUCCEEDED", clock: clock, request: request, result: result)
    write_exclusive(File.join(output_directory, "receipt.json"), JSON.generate(receipt) + "\n")
    out.puts(JSON.generate("code" => result.fetch("code"), "intentId" => request.intent_id,
      "outputDirectory" => File.expand_path(output_directory)))
    0
  rescue Errno::EEXIST
    err.puts(JSON.generate("code" => "OUTPUT_DIRECTORY_EXISTS"))
    1
  rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError
    error = SafeError.new("SIGNING_INPUT_INVALID")
    write_failure_receipt(output_directory, mode, clock, request, error)
    err.puts(JSON.generate("code" => error.code))
    1
  rescue SafeError, IOSBaselineRelease::SafeError => error
    write_failure_receipt(output_directory, mode, clock, request, error)
    payload = { "code" => error.code }
    payload["stage"] = error.stage if error.respond_to?(:stage) && error.stage
    err.puts(JSON.generate(payload))
    1
  rescue StandardError
    error = SafeError.new("SIGNING_BOOTSTRAP_FAILED")
    write_failure_receipt(output_directory, mode, clock, request, error)
    err.puts(JSON.generate("code" => error.code))
    1
  end

  def self.write_failure_receipt(directory, mode, clock, request, error)
    return unless directory.is_a?(String) && File.directory?(directory)
    path = File.join(directory, "receipt.json")
    return if File.exist?(path)
    receipt = safe_receipt(mode: mode, status: "FAILED", clock: clock, request: request, error: error)
    write_exclusive(path, JSON.generate(receipt) + "\n")
  rescue StandardError
    nil
  end
end

exit(IOSBaselineSigningBootstrap.run_cli(ARGV)) if $PROGRAM_NAME == __FILE__
