#!/usr/bin/env ruby
# frozen_string_literal: true
require_relative '../source/scripts/ios_baseline_release'

module LumaTestFlightAccess
  BUNDLE = 'com.womaninred.baseline'
  module_function

  def one(values, code)
    raise IOSBaselineRelease::SafeError, code unless values.length == 1
    values.first
  end

  def run(env: ENV)
    provider = IOSBaselineRelease::JwtProvider.new(
      issuer_id: env.fetch('APPSTORE_ISSUER_ID'), key_id: env.fetch('APPSTORE_API_KEY_ID'),
      private_key: env.fetch('APPSTORE_API_PRIVATE_KEY'))
    client = IOSBaselineRelease::Client.new(transport: IOSBaselineRelease::NetHTTPTransport.new, token_provider: provider)
    app = one(client.all_pages('/v1/apps?' + URI.encode_www_form('filter[bundleId]' => BUNDLE, 'limit' => 200)), 'APP_IDENTITY_AMBIGUOUS')
    raise IOSBaselineRelease::SafeError, 'APP_IDENTITY_MISMATCH' unless app.dig('attributes', 'bundleId') == BUNDLE
    app_id = app.fetch('id')
    groups = client.all_pages("/v1/apps/#{app_id}/betaGroups?limit=200")
    builds = client.all_pages('/v1/builds?' + URI.encode_www_form('filter[app]' => app_id, 'limit' => 200))
    operation = env.fetch('OPERATION')
    if operation == 'inventory'
      numbers = builds.map { |build| build.dig('attributes', 'version') }.select { |value| /\A[1-9][0-9]*\z/.match?(value.to_s) }.map(&:to_i)
      candidate = [38, numbers.max.to_i + 1].max
      return {code: 'TESTFLIGHT_INVENTORY', bundle_id: BUNDLE,
        groups: groups.map { |group| {name: group.dig('attributes', 'name'), internal: group.dig('attributes', 'isInternalGroup')} },
        builds: builds.map { |build| {build: build.dig('attributes', 'version'), processing: build.dig('attributes', 'processingState')} },
        next_free_build: candidate}
    end
    raise IOSBaselineRelease::SafeError, 'INVALID_OPERATION' unless operation == 'invite'
    email = env.fetch('LUMA_REQUESTED_TESTER_EMAIL').strip
    raise IOSBaselineRelease::SafeError, 'INVALID_TESTER_EMAIL' unless /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/.match?(email)
    matches = client.all_pages('/v1/betaTesters?' + URI.encode_www_form('filter[email]' => email, 'limit' => 200))
    raise IOSBaselineRelease::SafeError, 'TESTER_EMAIL_AMBIGUOUS' if matches.length > 1
    tester = matches.first
    if tester.nil?
      external = groups.reject { |group| group.dig('attributes', 'isInternalGroup') }
      group = one(external, 'EXTERNAL_GROUP_REQUIRED')
      tester = client.post('/v1/betaTesters', {data: {type: 'betaTesters', attributes: {email: email},
        relationships: {betaGroups: {data: [{type: 'betaGroups', id: group.fetch('id')}]}}}}).fetch('data')
    end
    raise IOSBaselineRelease::SafeError, 'TESTER_EMAIL_MISMATCH' unless tester.dig('attributes', 'email').to_s.casecmp?(email)
    tester_id = tester.fetch('id')
    apps = client.all_pages("/v1/betaTesters/#{tester_id}/apps?limit=200")
    unless apps.any? { |candidate| candidate['id'] == app_id }
      external = groups.reject { |group| group.dig('attributes', 'isInternalGroup') }
      group = one(external, 'EXTERNAL_GROUP_REQUIRED')
      client.post("/v1/betaTesters/#{tester_id}/relationships/betaGroups", {data: [{type: 'betaGroups', id: group.fetch('id')}]})
    end
    client.post('/v1/betaTesterInvitations', {data: {type: 'betaTesterInvitations', relationships: {
      app: {data: {type: 'apps', id: app_id}}, betaTester: {data: {type: 'betaTesters', id: tester_id}}}}})
    verified_apps = client.all_pages("/v1/betaTesters/#{tester_id}/apps?limit=200")
    raise IOSBaselineRelease::SafeError, 'TESTER_APP_ASSIGNMENT_MISSING' unless verified_apps.any? { |candidate| candidate['id'] == app_id }
    {code: 'TESTFLIGHT_INVITATION_SENT', bundle_id: BUNDLE, tester_app_assigned: true, invitation_accepted_by_apple: true}
  end
end

begin
  puts JSON.generate(LumaTestFlightAccess.run)
rescue IOSBaselineRelease::SafeError => error
  warn JSON.generate(code: error.code)
  exit 1
rescue StandardError
  warn JSON.generate(code: 'UNEXPECTED_TESTFLIGHT_ACCESS_ERROR')
  exit 1
end
