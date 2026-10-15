#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "time"
require "uri"

module IOSBaselineSigningInventory
  BUNDLE_IDENTIFIERS = [
    "com.womaninred.baseline",
    "com.womaninred.baseline.HiddifyPacketTunnel"
  ].freeze
  TARGET_ROLES = {
    "com.womaninred.baseline" => "APP",
    "com.womaninred.baseline.HiddifyPacketTunnel" => "EXTENSION"
  }.freeze
  CERTIFICATES_STAGE = "CERTIFICATES_LIST"
  ERROR_STAGE = /\A(?:CERTIFICATES_LIST|BUNDLE_(?:LOOKUP|PROFILES)_(?:APP|EXTENSION)|PROFILE_CERTIFICATES_(?:APP|EXTENSION)_[0-9]{3})\z/
  TRUSTED_HELPER_SOURCE_SHA = "3fb04c73f94c1174a668842ec3e50190abef6e6a"
  TRUSTED_HELPER_SHA256 = "13cd9ed9688c4fec9e346bd12c845eac72616b823b57760535f5f667b6d8a38c"
  RESOURCE_ID = /\A[A-Za-z0-9_-]{1,128}\z/
  CERTIFICATE_FIELDS = "certificateType,expirationDate,activated"
  CERTIFICATE_TYPES_FILTER = "DEVELOPMENT,IOS_DEVELOPMENT,DISTRIBUTION,IOS_DISTRIBUTION"
  PROFILE_FIELDS = "profileType,profileState,expirationDate"
  CERTIFICATE_TYPES = %w[DEVELOPMENT IOS_DEVELOPMENT DISTRIBUTION IOS_DISTRIBUTION].freeze
  PROFILE_TYPES = %w[
    IOS_APP_DEVELOPMENT IOS_APP_STORE IOS_APP_ADHOC IOS_APP_INHOUSE
    MAC_APP_DEVELOPMENT MAC_APP_STORE MAC_APP_DIRECT TVOS_APP_DEVELOPMENT
    TVOS_APP_STORE TVOS_APP_ADHOC TVOS_APP_INHOUSE
    MAC_CATALYST_APP_DEVELOPMENT MAC_CATALYST_APP_STORE MAC_CATALYST_APP_DIRECT
  ].freeze
  PROFILE_STATES = %w[ACTIVE INVALID].freeze

  class SafeError < StandardError
    attr_reader :code, :stage

    def initialize(code, stage: nil)
      @code = code
      @stage = stage
      super(code)
    end
  end

  class RequestPolicy
    CURSOR = /\A[\x21-\x7E]{1,1024}\z/

    def normalize(url)
      uri = URI.join("#{IOSBaselineRelease::API_ORIGIN}/", url)
      safe_origin = uri.is_a?(URI::HTTPS) &&
        uri.host == URI(IOSBaselineRelease::API_ORIGIN).host && uri.port == 443 &&
        uri.userinfo.nil? && uri.fragment.nil?
      raise SafeError, "UNSAFE_ASC_REQUEST" unless safe_origin

      pairs = URI.decode_www_form(uri.query.to_s)
      raise SafeError, "UNSAFE_ASC_REQUEST" unless pairs.map(&:first).uniq.length == pairs.length

      params = pairs.to_h
      cursor = params.delete("cursor")
      raise SafeError, "UNSAFE_ASC_REQUEST" if cursor && !CURSOR.match?(cursor)

      expected = case uri.path
                 when "/v1/certificates"
                   {
                     "filter[certificateType]" => CERTIFICATE_TYPES_FILTER,
                     "fields[certificates]" => CERTIFICATE_FIELDS,
                     "limit" => "200"
                   }
                 when "/v1/bundleIds"
                   identifier = params["filter[identifier]"]
                   raise SafeError, "UNSAFE_ASC_REQUEST" unless BUNDLE_IDENTIFIERS.include?(identifier)

                   {
                     "filter[identifier]" => identifier,
                     "fields[bundleIds]" => "identifier",
                     "limit" => "200"
                   }
                 when %r{\A/v1/bundleIds/([A-Za-z0-9_-]{1,128})/profiles\z}
                   { "fields[profiles]" => PROFILE_FIELDS, "limit" => "200" }
                 when %r{\A/v1/profiles/([A-Za-z0-9_-]{1,128})/certificates\z}
                   { "fields[certificates]" => CERTIFICATE_FIELDS, "limit" => "200" }
                 else
                   raise SafeError, "UNSAFE_ASC_REQUEST"
                 end
      raise SafeError, "UNSAFE_ASC_REQUEST" unless params == expected

      uri.to_s
    rescue URI::InvalidURIError, ArgumentError
      raise SafeError, "UNSAFE_ASC_REQUEST"
    end
  end

  class GetOnlyTransport
    def initialize(delegate, policy: RequestPolicy.new)
      @delegate = delegate
      @policy = policy
    end

    def request(method:, url:, headers:, body:, timeouts:)
      raise SafeError, "READ_ONLY_VIOLATION" unless method == "GET" && body.nil?

      safe_url = @policy.normalize(url)
      @delegate.request(method: "GET", url: safe_url, headers: headers, body: nil, timeouts: timeouts)
    end
  end

  class PageCollector
    MAX_PAGES = 50

    def initialize(client, policy: RequestPolicy.new)
      @client = client
      @policy = policy
    end

    def all(path)
      initial = URI(@policy.normalize(path))
      expected_path = initial.path
      expected_query = query_without_cursor(initial)
      next_path = path
      resources = []
      visited_urls = {}
      resource_ids = {}
      declared_total = nil
      total_mode = nil
      page_count = 0

      until next_path.to_s.empty?
        normalized = @policy.normalize(next_path)
        uri = URI(normalized)
        raise SafeError, "PAGINATION_ROUTE_CHANGED" unless uri.path == expected_path
        raise SafeError, "PAGINATION_QUERY_CHANGED" unless query_without_cursor(uri) == expected_query
        raise SafeError, "PAGINATION_LOOP" if visited_urls.key?(normalized)
        raise SafeError, "PAGINATION_LIMIT" if page_count >= MAX_PAGES

        visited_urls[normalized] = true
        page_count += 1
        payload = @client.get(next_path)
        raise SafeError, "PAGINATION_RESPONSE_INVALID" unless payload.is_a?(Hash)

        data = payload["data"]
        raise SafeError, "PAGINATION_RESPONSE_INVALID" unless data.is_a?(Array)
        data.each do |resource|
          id = resource.is_a?(Hash) && resource["id"]
          raise SafeError, "PAGINATION_RESPONSE_INVALID" unless id.is_a?(String) && RESOURCE_ID.match?(id)
          raise SafeError, "PAGINATION_DUPLICATE" if resource_ids.key?(id)

          resource_ids[id] = true
        end

        present, total = page_total(payload)
        mode = present ? :present : :absent
        total_mode ||= mode
        raise SafeError, "PAGINATION_TOTAL_CHANGED" unless total_mode == mode
        if present
          declared_total ||= total
          raise SafeError, "PAGINATION_TOTAL_CHANGED" unless declared_total == total
        end

        resources.concat(data)
        raise SafeError, "PAGINATION_TOTAL_MISMATCH" if declared_total && resources.length > declared_total

        links = payload["links"]
        raise SafeError, "PAGINATION_RESPONSE_INVALID" if links && !links.is_a?(Hash)
        next_path = links && links["next"]
        unless next_path.nil? || (next_path.is_a?(String) && !next_path.empty?)
          raise SafeError, "PAGINATION_RESPONSE_INVALID"
        end
      end

      if declared_total && resources.length != declared_total
        raise SafeError, "PAGINATION_TOTAL_MISMATCH"
      end

      resources
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

      total = paging["total"]
      raise SafeError, "PAGINATION_TOTAL_INVALID" unless total.is_a?(Integer) && total >= 0

      [true, total]
    end
  end

  class Inventory
    def initialize(client:, clock: -> { Time.now })
      @pages = PageCollector.new(client)
      @clock = clock
    end

    def run
      certificate_resources = api_read(CERTIFICATES_STAGE, certificate_path)
      certificates_by_id = parse_certificates(certificate_resources)
      certificate_refs = certificates_by_id.keys.sort.each_with_index.each_with_object({}) do |(id, index), refs|
        refs[id] = format("certificate-%03d", index + 1)
      end
      used_profile_ids = {}
      targets = BUNDLE_IDENTIFIERS.map do |identifier|
        role = TARGET_ROLES.fetch(identifier)
        bundle = exact_bundle(identifier, role)
        target(identifier, role, bundle.fetch("id"), certificates_by_id, certificate_refs, used_profile_ids)
      end

      {
        "schema" => "ios-baseline-signing-inventory/v1",
        "observedAt" => observation_time,
        "helperSHA" => TRUSTED_HELPER_SOURCE_SHA,
        "certificates" => certificate_report(certificates_by_id, certificate_refs),
        "targets" => targets
      }
    end

    private

    def certificate_path
      "/v1/certificates?" + URI.encode_www_form(
        "filter[certificateType]" => CERTIFICATE_TYPES_FILTER,
        "fields[certificates]" => CERTIFICATE_FIELDS,
        "limit" => 200
      )
    end

    def api_read(stage, path)
      raise SafeError, "ERROR_STAGE_INVALID" unless ERROR_STAGE.match?(stage)

      @pages.all(path)
    rescue IOSBaselineRelease::SafeError => error
      raise SafeError.new(error.code, stage: stage)
    end

    def exact_bundle(identifier, role)
      resources = api_read("BUNDLE_LOOKUP_#{role}", "/v1/bundleIds?" + URI.encode_www_form(
        "filter[identifier]" => identifier,
        "fields[bundleIds]" => "identifier",
        "limit" => 200
      ))
      matches = resources.select do |resource|
        resource.is_a?(Hash) && resource.dig("attributes", "identifier") == identifier
      end
      raise SafeError, "BUNDLE_ID_NOT_FOUND" if matches.empty?
      raise SafeError, "BUNDLE_ID_AMBIGUOUS" unless matches.length == 1

      resource = matches.first
      attributes = resource.is_a?(Hash) && resource["attributes"]
      valid = resource.is_a?(Hash) && resource["type"] == "bundleIds" &&
        resource["id"].is_a?(String) && RESOURCE_ID.match?(resource["id"]) &&
        attributes.is_a?(Hash) && attributes["identifier"] == identifier
      raise SafeError, "BUNDLE_ID_INVALID" unless valid

      resource
    end

    def target(identifier, role, bundle_id, certificates_by_id, certificate_refs, used_profile_ids)
      resources = api_read("BUNDLE_PROFILES_#{role}", "/v1/bundleIds/#{bundle_id}/profiles?" + URI.encode_www_form(
        "fields[profiles]" => PROFILE_FIELDS,
        "limit" => 200
      ))
      parsed = resources.sort_by { |resource| resource.fetch("id") }.each_with_index.map do |resource, index|
        id, metadata = parse_profile(resource)
        raise SafeError, "PROFILE_ID_DUPLICATE" if used_profile_ids.key?(id)

        used_profile_ids[id] = true
        associations = profile_certificates(id, role, index + 1, certificates_by_id, certificate_refs)
        metadata.merge(
          "profileRef" => format("profile-%03d", index + 1),
          "certificateRefs" => associations
        )
      end

      {
        "bundleIdentifier" => identifier,
        "profileCount" => parsed.length,
        "byType" => counts(parsed, "type"),
        "byState" => counts(parsed, "state"),
        "expirationDates" => dates(parsed),
        "profiles" => parsed
      }
    end

    def parse_certificates(resources)
      resources.each_with_object({}) do |resource, parsed|
        id, metadata = parse_certificate(resource)
        parsed[id] = metadata
      end
    end

    def parse_certificate(resource)
      attributes = resource.is_a?(Hash) && resource["attributes"]
      id = resource.is_a?(Hash) && resource["id"]
      valid = resource.is_a?(Hash) && resource["type"] == "certificates" &&
        id.is_a?(String) && RESOURCE_ID.match?(id) && attributes.is_a?(Hash)
      raise SafeError, "CERTIFICATE_RESOURCE_INVALID" unless valid

      type = attributes["certificateType"]
      raise SafeError, "CERTIFICATE_TYPE_INVALID" unless type.is_a?(String) && CERTIFICATE_TYPES.include?(type)
      activated = attributes["activated"]
      if activated.nil?
        activated = "NOT_REPORTED"
      elsif activated != true && activated != false
        raise SafeError, "CERTIFICATE_ACTIVATED_INVALID"
      end

      [id, {
        "type" => type,
        "activated" => activated,
        "expirationDate" => iso8601(attributes["expirationDate"], "CERTIFICATE_EXPIRATION_INVALID")
      }]
    end

    def parse_profile(resource)
      attributes = resource.is_a?(Hash) && resource["attributes"]
      id = resource.is_a?(Hash) && resource["id"]
      valid = resource.is_a?(Hash) && resource["type"] == "profiles" &&
        id.is_a?(String) && RESOURCE_ID.match?(id) && attributes.is_a?(Hash)
      raise SafeError, "PROFILE_RESOURCE_INVALID" unless valid

      type = attributes["profileType"]
      state = attributes["profileState"]
      raise SafeError, "PROFILE_TYPE_INVALID" unless type.is_a?(String) && PROFILE_TYPES.include?(type)
      raise SafeError, "PROFILE_STATE_INVALID" unless state.is_a?(String) && PROFILE_STATES.include?(state)

      [id, {
        "type" => type,
        "state" => state,
        "expirationDate" => iso8601(attributes["expirationDate"], "PROFILE_EXPIRATION_INVALID")
      }]
    end

    def profile_certificates(profile_id, role, index, certificates_by_id, certificate_refs)
      stage = format("PROFILE_CERTIFICATES_%s_%03d", role, index)
      resources = api_read(stage, "/v1/profiles/#{profile_id}/certificates?" + URI.encode_www_form(
        "fields[certificates]" => CERTIFICATE_FIELDS,
        "limit" => 200
      ))
      resources.map do |resource|
        id, metadata = parse_certificate(resource)
        unless certificates_by_id[id] == metadata && certificate_refs.key?(id)
          raise SafeError, "CERTIFICATE_ASSOCIATION_INVALID"
        end

        certificate_refs.fetch(id)
      end.sort
    end

    def certificate_report(certificates_by_id, certificate_refs)
      items = certificates_by_id.keys.sort.map do |id|
        certificates_by_id.fetch(id).merge("certificateRef" => certificate_refs.fetch(id))
      end
      {
        "count" => items.length,
        "byType" => counts(items, "type"),
        "byActivated" => counts(items, "activated") { |value| value.to_s },
        "expirationDates" => dates(items),
        "items" => items
      }
    end

    def counts(items, key)
      values = items.map { |item| item.fetch(key) }
      values = values.map { |value| yield(value) } if block_given?
      values.sort.each_with_object({}) { |value, result| result[value] = result.fetch(value, 0) + 1 }
    end

    def dates(items)
      items.map { |item| item.fetch("expirationDate") }.uniq.sort
    end

    def iso8601(value, code)
      raise SafeError, code unless value.is_a?(String)

      Time.iso8601(value).utc.iso8601
    rescue ArgumentError
      raise SafeError, code
    end

    def observation_time
      value = @clock.call
      time = value.is_a?(Time) ? value : Time.at(value.to_i)
      time.utc.iso8601
    rescue ArgumentError, RangeError
      raise SafeError, "CLOCK_INVALID"
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

  def self.run_cli(arguments, env: ENV, out: $stdout, err: $stderr, transport: nil,
    clock: -> { Time.now }, client_options: {})
    args = arguments.dup
    raise SafeError, "USAGE_ERROR" unless args.length == 1

    require_verified_helper!(args.fetch(0))
    issuer_id = IOSBaselineRelease::Config.required(env, "APPSTORE_ISSUER_ID")
    key_id = IOSBaselineRelease::Config.required(env, "APPSTORE_API_KEY_ID")
    private_key = IOSBaselineRelease::Config.required(env, "APPSTORE_API_PRIVATE_KEY")
    IOSBaselineRelease::Config.validate(issuer_id, /\A[A-Za-z0-9-]{3,128}\z/, "APPSTORE_ISSUER_ID")
    IOSBaselineRelease::Config.validate(key_id, /\A[A-Za-z0-9]{3,64}\z/, "APPSTORE_API_KEY_ID")
    provider = IOSBaselineRelease::JwtProvider.new(
      issuer_id: issuer_id,
      key_id: key_id,
      private_key: private_key,
      clock: -> { clock.call.to_i }
    )
    guarded = GetOnlyTransport.new(transport || IOSBaselineRelease::NetHTTPTransport.new)
    options = { transport: guarded, token_provider: provider }.merge(client_options)
    client = IOSBaselineRelease::Client.new(**options)
    out.puts(JSON.generate(Inventory.new(client: client, clock: clock).run))
    0
  rescue SafeError => error
    payload = { "code" => error.code }
    payload["stage"] = error.stage if error.stage
    err.puts(JSON.generate(payload))
    1
  rescue IOSBaselineRelease::SafeError => error
    err.puts(JSON.generate("code" => error.code))
    1
  rescue StandardError
    err.puts(JSON.generate("code" => "SIGNING_INVENTORY_FAILED"))
    1
  end
end

if $PROGRAM_NAME == __FILE__
  exit IOSBaselineSigningInventory.run_cli(ARGV)
end
