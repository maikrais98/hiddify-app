#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "timeout"
require "uri"

module AppleIdentityInventory
  API_ORIGIN = "https://api.appstoreconnect.apple.com"
  API_HOST = "api.appstoreconnect.apple.com"
  SCHEMA = "ios-baseline-identity-inventory/v1"

  APP_IDENTIFIER = "com.womaninred.baseline"
  EXTENSION_IDENTIFIER = "com.womaninred.baseline.HiddifyPacketTunnel"
  APP_GROUP_IDENTIFIER = "group.com.womaninred.baseline"
  OLD_APP_IDENTIFIER = "com.womaninred.app"
  SIGNED_BASELINE_TEAM_ID = "M9D72QQJ79"

  class SafeError < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  class TokenProvider
    def initialize(issuer_id:, key_id:, private_key:, clock: -> { Time.now.to_i })
      @issuer_id = issuer_id
      @key_id = key_id
      @private_key = private_key
      @clock = clock
    end

    def call
      issued_at = @clock.call.to_i
      header = { "alg" => "ES256", "kid" => @key_id, "typ" => "JWT" }
      payload = {
        "iss" => @issuer_id,
        "iat" => issued_at,
        "exp" => issued_at + 1_100,
        "aud" => "appstoreconnect-v1"
      }
      signing_input = [header, payload].map { |part| base64url(JSON.generate(part)) }.join(".")
      key = OpenSSL::PKey.read(@private_key)
      der_signature = key.sign(OpenSSL::Digest::SHA256.new, signing_input)
      signature = der_to_raw_signature(der_signature)
      "#{signing_input}.#{base64url(signature)}"
    rescue OpenSSL::OpenSSLError, ArgumentError, TypeError
      raise SafeError, "TOKEN_ERROR"
    end

    private

    def base64url(value)
      Base64.urlsafe_encode64(value, padding: false)
    end

    def der_to_raw_signature(signature)
      sequence = OpenSSL::ASN1.decode(signature)
      unless sequence.is_a?(OpenSSL::ASN1::Sequence) && sequence.value.length == 2
        raise SafeError, "TOKEN_ERROR"
      end

      sequence.value.map do |integer|
        bytes = integer.value.to_i.to_s(16)
        bytes = "0#{bytes}" if bytes.length.odd?
        raw = [bytes].pack("H*")
        raise SafeError, "TOKEN_ERROR" if raw.bytesize > 32

        raw.rjust(32, "\0")
      end.join
    end
  end

  class HttpTransport
    Response = Struct.new(:code, :body, keyword_init: true)

    def get(uri, headers:)
      request = Net::HTTP::Get.new(uri)
      headers.each { |name, value| request[name] = value }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 20
      http.write_timeout = 20 if http.respond_to?(:write_timeout=)
      response = http.request(request)
      Response.new(code: response.code, body: response.body.to_s)
    rescue IOError, SystemCallError, SocketError, Timeout::Error
      raise SafeError, "NETWORK_ERROR"
    end
  end

  class Inventory
    MAX_PAGES = 50
    SAFE_ENUM = /\A[A-Z][A-Z0-9_]{0,79}\z/.freeze

    def initialize(transport:, token_provider:)
      @transport = transport
      @token_provider = token_provider
    end

    def collect
      app_bundles = bundle_ids(APP_IDENTIFIER)
      extension_bundles = bundle_ids(EXTENSION_IDENTIFIER)
      old_app_bundles = bundle_ids(OLD_APP_IDENTIFIER)
      app_store_records = apps(APP_IDENTIFIER)

      app_identity = identity_summary(APP_IDENTIFIER, app_bundles)
      extension_identity = identity_summary(EXTENSION_IDENTIFIER, extension_bundles)

      {
        "schema" => SCHEMA,
        "status" => "OK",
        "read_only" => true,
        "identities" => {
          "app" => app_identity,
          "extension" => extension_identity
        },
        "app_group" => {
          "identifier" => APP_GROUP_IDENTIFIER,
          "status" => "UNSUPPORTED_BY_API",
          "reason_code" => "NO_DOCUMENTED_BUNDLE_ID_APP_GROUP_RELATIONSHIP"
        },
        "app_store_record" => registration_summary(APP_IDENTIFIER, app_store_records, attribute: "bundleId"),
        "team" => team_summary(old_app_bundles)
      }
    end

    private

    def identity_summary(identifier, resources)
      summary = registration_summary(identifier, resources)
      resource = exact_matches(resources, identifier).first
      return { "bundle_id" => summary, "capabilities" => [], "profiles" => empty_profile_summary } unless resource && summary["status"] == "REGISTERED"

      resource_id = safe_resource_id(resource["id"])
      {
        "bundle_id" => summary,
        "capabilities" => capability_types(resource_id),
        "profiles" => profile_summary(resource_id)
      }
    end

    def team_summary(old_app_resources)
      matches = exact_matches(old_app_resources, OLD_APP_IDENTIFIER)
      count = matches.length
      observed_id = safe_team_id(matches.first&.dig("attributes", "seedId"))
      team_matches = count == 1 && observed_id == SIGNED_BASELINE_TEAM_ID
      {
        "status" => team_matches ? "VERIFIED" : "UNVERIFIED",
        "observed_id" => observed_id,
        "previous_signed_team_id" => SIGNED_BASELINE_TEAM_ID,
        "match_to_previous_team" => team_matches,
        "candidate_assignment" => "UNVERIFIED",
        "evidence_code" => team_matches ? "OLD_BUNDLE_SEED_MATCHES_SIGNED_BASELINE" : "OLD_BUNDLE_SEED_NOT_MATCHED",
        "old_bundle_id_registered_count" => count
      }
    end

    def registration_summary(identifier, resources, attribute: "identifier")
      count = exact_matches(resources, identifier, attribute: attribute).length
      status = if count.zero?
                 "UNREGISTERED"
               elsif count == 1
                 "REGISTERED"
               else
                 "AMBIGUOUS"
               end
      {
        "identifier" => identifier,
        "status" => status,
        "registered_count" => count,
        "global_availability" => count.zero? ? "UNVERIFIED" : "NOT_APPLICABLE",
        "availability_evidence" => count.zero? ? "PENDING_CREATE_ATTEMPT" : "NOT_APPLICABLE"
      }
    end

    def exact_matches(resources, identifier, attribute: "identifier")
      resources.select do |resource|
        resource.is_a?(Hash) && resource.dig("attributes", attribute) == identifier
      end
    end

    def bundle_ids(identifier)
      list("/v1/bundleIds", {
        "fields[bundleIds]" => "identifier,seedId",
        "filter[identifier]" => identifier,
        "limit" => "200"
      })
    end

    def apps(identifier)
      list("/v1/apps", {
        "fields[apps]" => "bundleId",
        "filter[bundleId]" => identifier,
        "limit" => "200"
      })
    end

    def capability_types(resource_id)
      resources = list("/v1/bundleIds/#{resource_id}/bundleIdCapabilities", {
        "fields[bundleIdCapabilities]" => "capabilityType",
        "limit" => "200"
      })
      resources.map do |resource|
        value = resource.dig("attributes", "capabilityType") if resource.is_a?(Hash)
        value if value.is_a?(String) && SAFE_ENUM.match?(value)
      end.compact.uniq.sort
    end

    def profile_summary(resource_id)
      resources = list("/v1/bundleIds/#{resource_id}/profiles", {
        "fields[profiles]" => "expirationDate,profileState,profileType",
        "limit" => "200"
      })
      states = Hash.new(0)
      types = Hash.new(0)
      resources.each do |resource|
        next unless resource.is_a?(Hash)

        state = safe_enum(resource.dig("attributes", "profileState"))
        type = safe_enum(resource.dig("attributes", "profileType"))
        states[state] += 1
        types[type] += 1
      end
      { "count" => resources.length, "states" => sorted_hash(states), "types" => sorted_hash(types) }
    end

    def empty_profile_summary
      { "count" => 0, "states" => {}, "types" => {} }
    end

    def safe_enum(value)
      value.is_a?(String) && SAFE_ENUM.match?(value) ? value : "UNKNOWN"
    end

    def sorted_hash(hash)
      hash.keys.sort.each_with_object({}) { |key, result| result[key] = hash[key] }
    end

    def list(path, query)
      uri = URI("#{API_ORIGIN}#{path}")
      uri.query = URI.encode_www_form(query)
      resources = []
      visited = {}
      pages = 0

      loop do
        validate_uri!(uri)
        raise SafeError, "PAGINATION_LOOP" if visited[uri.to_s]
        raise SafeError, "PAGINATION_LIMIT" if pages >= MAX_PAGES

        visited[uri.to_s] = true
        pages += 1
        response = @transport.get(uri, headers: {
          "Authorization" => "Bearer #{@token_provider.call}",
          "Accept" => "application/json"
        })
        unless response.code.to_s.match?(/\A2\d\d\z/)
          raise SafeError, "HTTP_STATUS_#{safe_status(response.code)}"
        end

        document = parse_document(response.body)
        resources.concat(document.fetch("data"))
        next_link = document.dig("links", "next")
        break if next_link.nil?
        raise SafeError, "INVALID_RESPONSE" unless next_link.is_a?(String) && !next_link.empty?

        uri = URI(next_link)
      end

      resources
    rescue URI::InvalidURIError
      raise SafeError, "UNSAFE_PAGINATION_LINK"
    end

    def parse_document(body)
      document = JSON.parse(body)
      raise SafeError, "INVALID_RESPONSE" unless document.is_a?(Hash) && document["data"].is_a?(Array)
      raise SafeError, "INVALID_RESPONSE" if document.key?("links") && !document["links"].is_a?(Hash)

      document
    rescue JSON::ParserError, TypeError
      raise SafeError, "MALFORMED_RESPONSE"
    end

    def validate_uri!(uri)
      unless uri.is_a?(URI::HTTPS) && uri.host == API_HOST && uri.port == 443 && uri.path.start_with?("/v1/") && uri.userinfo.nil?
        raise SafeError, "UNSAFE_PAGINATION_LINK"
      end
    end

    def safe_resource_id(value)
      unless value.is_a?(String) && value.match?(/\A[A-Za-z0-9-]{1,128}\z/)
        raise SafeError, "UNSAFE_RESOURCE_ID"
      end

      value
    end

    def safe_status(value)
      value.to_s.match?(/\A\d{3}\z/) ? value.to_s : "UNKNOWN"
    end

    def safe_team_id(value)
      value.is_a?(String) && value.match?(/\A[A-Z0-9]{10}\z/) ? value : nil
    end
  end

  class CLI
    def self.run(env: ENV, out: $stdout)
      required = %w[APPSTORE_ISSUER_ID APPSTORE_API_KEY_ID APPSTORE_API_PRIVATE_KEY]
      raise SafeError, "MISSING_CREDENTIALS" unless required.all? { |name| env[name].is_a?(String) && !env[name].empty? }

      token_provider = TokenProvider.new(
        issuer_id: env.fetch("APPSTORE_ISSUER_ID"),
        key_id: env.fetch("APPSTORE_API_KEY_ID"),
        private_key: env.fetch("APPSTORE_API_PRIVATE_KEY")
      )
      result = Inventory.new(transport: HttpTransport.new, token_provider: token_provider).collect
      out.puts(JSON.pretty_generate(result))
      0
    rescue SafeError => error
      out.puts(JSON.generate({ "schema" => SCHEMA, "status" => "FAILED", "error_code" => error.code }))
      1
    rescue StandardError
      out.puts(JSON.generate({ "schema" => SCHEMA, "status" => "FAILED", "error_code" => "UNEXPECTED_ERROR" }))
      1
    end
  end
end

exit AppleIdentityInventory::CLI.run if $PROGRAM_NAME == __FILE__
