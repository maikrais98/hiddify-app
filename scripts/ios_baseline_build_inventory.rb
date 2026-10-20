#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "time"
require "uri"

module IOSBaselineBuildInventory
  BUNDLE_ID = "com.womaninred.baseline"
  VERSION = "0.0.1"
  PLATFORM = "IOS"
  KNOWN_BASELINE_BUILD = 3
  MAXIMUM_CANDIDATE = 9_999
  APP_CANDIDATE_SHA = "b7e6f59a20a85a48e2ae02dc72c8b889014ccebf"
  TRUSTED_HELPER_SOURCE_SHA = "3fb04c73f94c1174a668842ec3e50190abef6e6a"
  TRUSTED_HELPER_SHA256 = "13cd9ed9688c4fec9e346bd12c845eac72616b823b57760535f5f667b6d8a38c"
  APP_ID = /\A[1-9][0-9]{5,19}\z/
  RESOURCE_ID = /\A[A-Za-z0-9_-]{1,128}\z/
  BUILD_NUMBER = /\A[1-9][0-9]*\z/
  PROCESSING_STATES = %w[PROCESSING VALID FAILED INVALID].freeze
  INTERNAL_STATES = %w[PROCESSING PROCESSING_EXCEPTION MISSING_EXPORT_COMPLIANCE
    READY_FOR_BETA_TESTING IN_BETA_TESTING EXPIRED IN_EXPORT_COMPLIANCE_REVIEW].freeze

  class SafeError < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  class GetOnlyTransport
    def initialize(delegate)
      @delegate = delegate
    end

    def request(method:, url:, headers:, body:, timeouts:)
      raise SafeError, "READ_ONLY_VIOLATION" unless method == "GET" && body.nil?

      @delegate.request(method: method, url: url, headers: headers, body: nil, timeouts: timeouts)
    end
  end

  class PageCollector
    MAX_PAGES = 50

    def initialize(client)
      @client = client
    end

    def all(path)
      resources = []
      visited = {}
      next_path = path
      page_count = 0
      total_mode = nil
      declared_total = nil

      until next_path.to_s.empty?
        normalized = safe_url(next_path)
        raise SafeError, "PAGINATION_LOOP" if visited.key?(normalized)
        raise SafeError, "PAGINATION_LIMIT" if page_count >= MAX_PAGES

        visited[normalized] = true
        page_count += 1
        payload = @client.get(next_path)
        raise SafeError, "PAGINATION_RESPONSE_INVALID" unless payload.is_a?(Hash)

        data = payload["data"]
        raise SafeError, "PAGINATION_RESPONSE_INVALID" unless data.is_a?(Array)

        present, total = page_total(payload)
        current_mode = present ? :present : :absent
        total_mode ||= current_mode
        raise SafeError, "PAGINATION_TOTAL_CHANGED" unless total_mode == current_mode
        if present
          declared_total ||= total
          raise SafeError, "PAGINATION_TOTAL_CHANGED" unless declared_total == total
        end

        resources.concat(data)
        if declared_total && resources.length > declared_total
          raise SafeError, "PAGINATION_TOTAL_MISMATCH"
        end

        links = payload["links"]
        raise SafeError, "PAGINATION_RESPONSE_INVALID" if links && !links.is_a?(Hash)

        next_path = links && links["next"]
        unless next_path.nil? || (next_path.is_a?(String) && !next_path.empty?)
          raise SafeError, "PAGINATION_RESPONSE_INVALID"
        end
        safe_url(next_path) unless next_path.to_s.empty?
      end

      if declared_total && resources.length != declared_total
        raise SafeError, "PAGINATION_TOTAL_MISMATCH"
      end

      resources
    end

    private

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

    def safe_url(path)
      uri = URI.join("#{IOSBaselineRelease::API_ORIGIN}/", path)
      valid = uri.is_a?(URI::HTTPS) &&
        uri.host == URI(IOSBaselineRelease::API_ORIGIN).host &&
        uri.port == 443 &&
        uri.path.start_with?("/v1/") &&
        uri.userinfo.nil? && uri.fragment.nil?
      raise IOSBaselineRelease::SafeError, "UNSAFE_ASC_URL" unless valid

      uri.to_s
    rescue URI::InvalidURIError
      raise IOSBaselineRelease::SafeError, "UNSAFE_ASC_URL"
    end
  end

  class Inventory
    def initialize(client:, clock: -> { Time.now })
      @client = client
      @pages = PageCollector.new(client)
      @clock = clock
    end

    def run(delivery_build_number: nil, tester_group_id: nil)
      delivery_number = delivery_configuration!(delivery_build_number, tester_group_id)
      @delivery_resource = nil
      app = exact_app!
      version = exact_version!(app.fetch("id"))
      builds = exact_builds!(version.fetch("id"), delivery_number: delivery_number)
      numbers = builds.map { |build| build.fetch("buildNumber") }
      raise SafeError, "KNOWN_BASELINE_MISSING" unless numbers.include?(KNOWN_BASELINE_BUILD)

      candidate = [KNOWN_BASELINE_BUILD, numbers.max].max + 1
      raise SafeError, "CANDIDATE_LIMIT_EXCEEDED" if candidate > MAXIMUM_CANDIDATE

      report = {
        "schema" => "ios-baseline-build-inventory/v1",
        "observedAt" => observation_time,
        "candidateSHA" => APP_CANDIDATE_SHA,
        "helperSHA" => TRUSTED_HELPER_SOURCE_SHA,
        "version" => VERSION,
        "platform" => PLATFORM,
        "builds" => builds.sort_by { |build| build.fetch("buildNumber") },
        "count" => builds.length,
        "candidate" => candidate
      }
      if delivery_number
        report["delivery"] = delivery!(app.fetch("id"), tester_group_id, delivery_number)
      end
      report
    end

    private

    def exact_app!
      apps = @pages.all("/v1/apps?" + URI.encode_www_form(
        "filter[bundleId]" => BUNDLE_ID,
        "limit" => 200
      ))
      raise SafeError, "APP_NOT_FOUND" if apps.empty?
      raise SafeError, "APP_AMBIGUOUS" unless apps.length == 1

      app = apps.first
      valid = app.is_a?(Hash) && app["type"] == "apps" &&
        app["id"].is_a?(String) && APP_ID.match?(app["id"]) &&
        app["attributes"].is_a?(Hash) && app["attributes"]["bundleId"] == BUNDLE_ID
      raise SafeError, "APP_INVALID" unless valid

      app
    end

    def exact_version!(app_id)
      versions = @pages.all("/v1/preReleaseVersions?" + URI.encode_www_form(
        "filter[app]" => app_id,
        "filter[version]" => VERSION,
        "filter[platform]" => PLATFORM,
        "include" => "app",
        "limit" => 200
      ))
      raise SafeError, "VERSION_NOT_FOUND" if versions.empty?
      raise SafeError, "VERSION_AMBIGUOUS" unless versions.length == 1

      version = versions.first
      relationship = version.is_a?(Hash) && version.dig("relationships", "app", "data")
      valid = version.is_a?(Hash) && version["type"] == "preReleaseVersions" &&
        version["id"].is_a?(String) && RESOURCE_ID.match?(version["id"]) &&
        version["attributes"].is_a?(Hash) &&
        version["attributes"]["version"] == VERSION && version["attributes"]["platform"] == PLATFORM &&
        relationship.is_a?(Hash) && relationship["type"] == "apps" && relationship["id"] == app_id
      raise SafeError, "VERSION_INVALID" unless valid

      version
    end

    def exact_builds!(version_id, delivery_number: nil)
      resources = @pages.all("/v1/builds?" + URI.encode_www_form(
        "filter[preReleaseVersion]" => version_id,
        "include" => "preReleaseVersion",
        "limit" => 200
      ))
      raise SafeError, "BUILDS_NOT_FOUND" if resources.empty?

      ids = {}
      numbers = {}
      resources.map do |resource|
        build = exact_build!(resource, version_id)
        id = resource.fetch("id")
        number = build.fetch("buildNumber")
        raise SafeError, "BUILD_ID_DUPLICATE" if ids.key?(id)
        raise SafeError, "BUILD_NUMBER_DUPLICATE" if numbers.key?(number)

        ids[id] = true
        numbers[number] = true
        @delivery_resource = resource if number == delivery_number
        build
      end
    end

    def exact_build!(resource, version_id)
      attributes = resource.is_a?(Hash) && resource["attributes"]
      relationship = resource.is_a?(Hash) && resource.dig("relationships", "preReleaseVersion", "data")
      valid_resource = resource.is_a?(Hash) && resource["type"] == "builds" &&
        resource["id"].is_a?(String) && RESOURCE_ID.match?(resource["id"]) &&
        attributes.is_a?(Hash) && relationship.is_a?(Hash) &&
        relationship["type"] == "preReleaseVersions" && relationship["id"] == version_id
      raise SafeError, "BUILD_RESOURCE_INVALID" unless valid_resource

      raw_number = attributes["version"]
      raise SafeError, "BUILD_NUMBER_INVALID" unless raw_number.is_a?(String) && BUILD_NUMBER.match?(raw_number)

      number = Integer(raw_number, 10)
      state = attributes["processingState"]
      raise SafeError, "BUILD_STATE_INVALID" unless state.is_a?(String) && PROCESSING_STATES.include?(state)

      expired = attributes["expired"]
      raise SafeError, "BUILD_EXPIRED_INVALID" unless expired == true || expired == false

      { "buildNumber" => number, "processingState" => state, "expired" => expired }
    end

    def delivery_configuration!(number, group_id)
      return nil if [number, group_id].all? { |value| value.nil? || value == "" }

      valid = number.is_a?(String) && BUILD_NUMBER.match?(number) &&
        number.length <= 4 && number.to_i <= MAXIMUM_CANDIDATE &&
        group_id.is_a?(String) && RESOURCE_ID.match?(group_id)
      raise SafeError, "DELIVERY_CONFIG_INVALID" unless valid

      number.to_i
    end

    def delivery!(app_id, group_id, number)
      raise SafeError, "DELIVERY_BUILD_NOT_FOUND" unless @delivery_resource

      build_id = @delivery_resource.fetch("id")
      payload = @client.get("/v1/betaGroups/#{group_id}?include=app")
      group = payload.is_a?(Hash) && payload["data"]
      attributes = group.is_a?(Hash) && group["attributes"]
      relationships = group.is_a?(Hash) && group["relationships"]
      app_link = relationships.is_a?(Hash) && relationships["app"]
      relationship = app_link.is_a?(Hash) && app_link["data"]
      valid = group.is_a?(Hash) && group["type"] == "betaGroups" && group["id"] == group_id &&
        attributes.is_a?(Hash) && attributes["name"] == "Test" &&
        attributes["isInternalGroup"] == true &&
        (!attributes.key?("hasAccessToAllBuilds") || [true, false].include?(attributes["hasAccessToAllBuilds"])) &&
        relationship.is_a?(Hash) && relationship["type"] == "apps" && relationship["id"] == app_id
      raise SafeError, "DELIVERY_GROUP_INVALID" unless valid

      payload = @client.get("/v1/builds/#{build_id}/buildBetaDetail")
      detail = payload.is_a?(Hash) && payload["data"]
      valid = detail.is_a?(Hash) && detail["type"] == "buildBetaDetails" &&
        detail["id"].is_a?(String) && RESOURCE_ID.match?(detail["id"]) && detail["attributes"].is_a?(Hash)
      raise SafeError, "DELIVERY_DETAIL_INVALID" unless valid

      state = detail["attributes"]["internalBuildState"]
      raise SafeError, "DELIVERY_STATE_INVALID" unless INTERNAL_STATES.include?(state)

      {
        "buildNumber" => number,
        "processingState" => @delivery_resource.fetch("attributes").fetch("processingState"),
        "internalBuildState" => state,
        "isInternalGroup" => attributes.fetch("isInternalGroup"),
        "hasAccessToAllBuilds" => attributes["hasAccessToAllBuilds"],
        "appMatches" => true,
        "assignedViaBuilds" => assigned!("/v1/betaGroups/#{group_id}/builds?limit=200", build_id),
        "assignedViaRelationship" => assigned!("/v1/betaGroups/#{group_id}/relationships/builds?limit=200", build_id)
      }
    end

    def assigned!(path, build_id)
      ids = {}
      @pages.all(path).each do |resource|
        valid = resource.is_a?(Hash) && resource["type"] == "builds" &&
          resource["id"].is_a?(String) && RESOURCE_ID.match?(resource["id"])
        raise SafeError, "DELIVERY_LINKAGE_INVALID" unless valid
        raise SafeError, "DELIVERY_LINKAGE_DUPLICATE" if ids.key?(resource["id"])

        ids[resource["id"]] = true
      end
      ids.key?(build_id)
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

  def self.run_cli(arguments, env: ENV, out: $stdout, err: $stderr, transport: nil, clock: -> { Time.now })
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
    client = IOSBaselineRelease::Client.new(transport: guarded, token_provider: provider)
    out.puts(JSON.generate(Inventory.new(client: client, clock: clock).run(
      delivery_build_number: env["DELIVERY_BUILD_NUMBER"], tester_group_id: env["TESTER_GROUP_ID"]
    )))
    0
  rescue SafeError => error
    err.puts(JSON.generate("code" => error.code))
    1
  rescue IOSBaselineRelease::SafeError => error
    err.puts(JSON.generate("code" => error.code))
    1
  rescue StandardError
    err.puts(JSON.generate("code" => "INVENTORY_FAILED"))
    1
  end
end

if $PROGRAM_NAME == __FILE__
  exit IOSBaselineBuildInventory.run_cli(ARGV)
end
