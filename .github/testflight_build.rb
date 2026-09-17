#!/usr/bin/env ruby
# frozen_string_literal: true

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'uri'

def next_number(values, minimum: 1)
  numeric = values.map { |value| Integer(value, exception: false) }.compact
  [numeric.max.to_i + 1, minimum, 1].max
end

class AppStoreConnect
  API = 'https://api.appstoreconnect.apple.com'.freeze

  def initialize
    @issuer_id = ENV.fetch('APPSTORE_ISSUER_ID')
    @key_id = ENV.fetch('APPSTORE_API_KEY_ID')
    @private_key = OpenSSL::PKey.read(ENV.fetch('APPSTORE_API_PRIVATE_KEY'))
    @bundle_id = ENV.fetch('APP_BUNDLE_ID', 'com.womaninred.app')
  end

  def next_build(marketing_version, minimum = 1)
    builds = builds_for(marketing_version)
    next_number(builds.map { |build| build.dig('attributes', 'version') }, minimum: minimum)
  end

  def wait_and_assign(marketing_version, build_number, group_name)
    build = wait_for_valid_build(marketing_version, build_number)
    group = existing_group(group_name)
    assign_group(build, group)
    state = wait_for_testflight_readiness(build, group)
    puts "#{marketing_version} (#{build_number}) processingState=VALID #{state} group=#{group.dig('attributes', 'name')} Ready to Test"
  end

  private

  def app_id
    @app_id ||= begin
      apps = get("/v1/apps?filter%5BbundleId%5D=#{URI.encode_www_form_component(@bundle_id)}&limit=1").fetch('data')
      raise "App Store Connect app not found for #{@bundle_id}" unless apps.length == 1

      apps.first.fetch('id')
    end
  end

  def pre_release_version(marketing_version)
    versions = all_pages(
      "/v1/preReleaseVersions?filter%5Bapp%5D=#{app_id}" \
      "&filter%5Bversion%5D=#{URI.encode_www_form_component(marketing_version)}" \
      "&filter%5Bplatform%5D=IOS&limit=200",
    )
    return nil if versions.empty?
    raise "Ambiguous IOS pre-release version: #{marketing_version}" unless versions.length == 1

    version = versions.first
    attributes = version.fetch('attributes')
    unless attributes['version'] == marketing_version && attributes['platform'] == 'IOS'
      raise "App Store Connect returned #{attributes['platform']} #{attributes['version']}; expected IOS #{marketing_version}"
    end
    version
  end

  def builds_for(marketing_version, build_number: nil)
    version = pre_release_version(marketing_version)
    return [] unless version

    path = "/v1/builds?filter%5BpreReleaseVersion%5D=#{version.fetch('id')}&limit=200"
    path += "&filter%5Bversion%5D=#{URI.encode_www_form_component(build_number.to_s)}" if build_number
    all_pages(path)
  end

  def wait_for_valid_build(marketing_version, build_number)
    80.times do
      builds = builds_for(marketing_version, build_number: build_number)
      raise "Ambiguous App Store build: #{marketing_version} (#{build_number})" if builds.length > 1

      build = builds.first
      if build
        state = build.dig('attributes', 'processingState')
        return build if state == 'VALID'
        if %w[FAILED INVALID PROCESSING_EXCEPTION].include?(state)
          raise "Apple processing failed: #{marketing_version} (#{build_number}) is #{state}"
        end
      end
      sleep 30
    end
    raise "Apple processing timeout for #{marketing_version} (#{build_number})"
  end

  def existing_group(requested_name)
    groups = all_pages("/v1/betaGroups?filter%5Bapp%5D=#{app_id}&limit=200")
    unless requested_name.to_s.empty?
      return groups.find { |group| group.dig('attributes', 'name') == requested_name } ||
        raise("Existing TestFlight group not found: #{requested_name}")
    end
    return groups.first if groups.length == 1

    raise "Set TESTFLIGHT_GROUP_NAME because App Store Connect has #{groups.length} existing groups"
  end

  def assign_group(build, group)
    assigned = all_pages("/v1/betaGroups/#{group.fetch('id')}/builds?limit=200")
    return if assigned.any? { |candidate| candidate.fetch('id') == build.fetch('id') }

    post(
      "/v1/betaGroups/#{group.fetch('id')}/relationships/builds",
      data: [{type: 'builds', id: build.fetch('id')}],
    )
  end

  def wait_for_testflight_readiness(build, group)
    state_key = group.dig('attributes', 'isInternalGroup') ? 'internalBuildState' : 'externalBuildState'
    60.times do
      detail = get("/v1/builds/#{build.fetch('id')}/buildBetaDetail").fetch('data')
      state = detail.dig('attributes', state_key)
      return "#{state_key}=#{state}" if evaluate_beta_state(state) == :ready

      sleep 15
    end
    raise "TestFlight readiness timeout for build #{build.fetch('id')}"
  end

  def evaluate_beta_state(state)
    return :ready if %w[READY_FOR_BETA_TESTING IN_BETA_TESTING].include?(state)
    return :wait if %w[PROCESSING BETA_REVIEW_APPROVED].include?(state)
    raise "Export compliance gate: TestFlight state is #{state}" if state == 'MISSING_EXPORT_COMPLIANCE'
    if %w[READY_FOR_BETA_SUBMISSION WAITING_FOR_BETA_REVIEW IN_BETA_REVIEW].include?(state)
      raise "Beta App Review gate: TestFlight state is #{state}"
    end
    raise "Beta App Review rejected: TestFlight state is #{state}" if state == 'BETA_REVIEW_REJECTED'
    raise "TestFlight processing exception: #{state}" if state == 'PROCESSING_EXCEPTION'
    raise "TestFlight readiness failed: #{state}" if %w[FAILED INVALID EXPIRED].include?(state)

    raise "Unexpected TestFlight state: #{state.inspect}"
  end

  def all_pages(path)
    data = []
    loop do
      response = get(path)
      data.concat(response.fetch('data'))
      path = response.dig('links', 'next')
      break if path.to_s.empty?
    end
    data
  end

  def get(path)
    request(Net::HTTP::Get, path)
  end

  def post(path, body)
    request(Net::HTTP::Post, path, body)
  end

  def request(method, path, body = nil)
    uri = URI.join(API, path)
    http_request = method.new(uri)
    http_request['Authorization'] = "Bearer #{token}"
    http_request['Content-Type'] = 'application/json'
    http_request.body = JSON.generate(body) if body
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(http_request) }
    return {} if response.code == '204'
    return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

    raise "App Store Connect #{response.code}: #{response.body}"
  end

  def token
    now = Time.now.to_i
    header = {alg: 'ES256', kid: @key_id, typ: 'JWT'}
    payload = {iss: @issuer_id, iat: now, exp: now + 19 * 60, aud: 'appstoreconnect-v1'}
    signing_input = [header, payload].map { |part| base64url(JSON.generate(part)) }.join('.')
    der = @private_key.sign('SHA256', signing_input)
    sequence = OpenSSL::ASN1.decode(der)
    signature = sequence.value.map { |integer| [integer.value.to_s(16).rjust(64, '0')].pack('H*') }.join
    "#{signing_input}.#{base64url(signature)}"
  end

  def base64url(value)
    Base64.urlsafe_encode64(value, padding: false)
  end
end

if $PROGRAM_NAME == __FILE__
  command, marketing_version, build_number, group_name = ARGV
  case command
  when 'next-number'
    puts next_number(ARGV.drop(2), minimum: Integer(marketing_version))
  when 'next'
    puts AppStoreConnect.new.next_build(marketing_version, Integer(build_number || 1))
  when 'wait-and-assign'
    AppStoreConnect.new.wait_and_assign(marketing_version, Integer(build_number), group_name)
  else
    warn 'Usage: testflight_build.rb next VERSION [MINIMUM] | wait-and-assign VERSION BUILD [GROUP] | next-number MINIMUM [BUILD...]'
    exit 64
  end
end
