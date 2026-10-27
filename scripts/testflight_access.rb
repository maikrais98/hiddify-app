#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "uri"

module LumaTestFlightAccess
  BUNDLE = "com.womaninred.baseline"
  MARKETING_VERSION = "0.1.0"
  BUILD_NUMBER = /\A[1-9][0-9]{0,3}\z/
  SAFE_CODE = /\A[A-Z][A-Z0-9_]{0,79}\z/

  class SafeError < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  module_function

  def one(values, code)
    raise SafeError, code unless values.is_a?(Array) && values.length == 1

    values.first
  end

  def run(env: ENV, client: nil)
    client ||= apple_client(env)
    app = exact_app(client)
    app_id = app.fetch("id")
    operation = env.fetch("OPERATION")
    return inventory(client, app_id) if operation == "inventory"

    raise SafeError, "INVALID_OPERATION" unless %w[invite beta-review].include?(operation)

    build_number = env["BUILD_NUMBER"].to_s
    raise SafeError, "INVALID_BUILD_NUMBER" unless BUILD_NUMBER.match?(build_number)

    build = exact_valid_build(client, app_id, build_number)
    if operation == "beta-review"
      return submit_beta_review(client, app_id, build.fetch("id"), build_number)
    end

    invite(client, env, app_id, build.fetch("id"), build_number)
  end

  def exact_app(client)
    app = one(client.all_pages("/v1/apps?" + URI.encode_www_form(
      "filter[bundleId]" => BUNDLE, "limit" => 200
    )), "APP_IDENTITY_AMBIGUOUS")
    raise SafeError, "APP_IDENTITY_MISMATCH" unless app.dig("attributes", "bundleId") == BUNDLE

    app
  end

  def exact_valid_build(client, app_id, build_number)
    match = one(client.all_pages("/v1/builds?" + URI.encode_www_form(
      "filter[app]" => app_id, "filter[version]" => build_number, "limit" => 200
    )), "BUILD_IDENTITY_AMBIGUOUS")
    build_id = match.fetch("id")
    build = client.get("/v1/builds/#{build_id}").fetch("data")
    unless build["id"] == build_id && build.dig("attributes", "version") == build_number
      raise SafeError, "BUILD_IDENTITY_MISMATCH"
    end
    raise SafeError, "BUILD_NOT_VALID" unless build.dig("attributes", "processingState") == "VALID"

    version = client.get("/v1/builds/#{build_id}/preReleaseVersion").fetch("data")
    unless version.dig("attributes", "version") == MARKETING_VERSION &&
        version.dig("attributes", "platform") == "IOS"
      raise SafeError, "BUILD_MARKETING_VERSION_MISMATCH"
    end

    build_app = client.get("/v1/builds/#{build_id}/app").fetch("data")
    unless build_app["id"] == app_id && build_app.dig("attributes", "bundleId") == BUNDLE
      raise SafeError, "BUILD_APP_MISMATCH"
    end

    build
  rescue KeyError, TypeError
    raise SafeError, "BUILD_RESPONSE_INVALID"
  end

  def inventory(client, app_id)
    groups = client.all_pages("/v1/apps/#{app_id}/betaGroups?limit=200")
    builds = client.all_pages("/v1/builds?" + URI.encode_www_form("filter[app]" => app_id, "limit" => 200))
    numbers = builds.map { |build| build.dig("attributes", "version") }
      .select { |value| BUILD_NUMBER.match?(value.to_s) }.map(&:to_i)
    {
      code: "TESTFLIGHT_INVENTORY", bundle_id: BUNDLE,
      groups: groups.map { |group| {
        name: group.dig("attributes", "name"), internal: group.dig("attributes", "isInternalGroup")
      } },
      builds: builds.map { |build| {
        build: build.dig("attributes", "version"), processing: build.dig("attributes", "processingState")
      } },
      next_free_build: [38, numbers.max.to_i + 1].max
    }
  end

  def invite(client, env, app_id, build_id, build_number)
    email = env.fetch("LUMA_REQUESTED_TESTER_EMAIL").strip
    raise SafeError, "INVALID_TESTER_EMAIL" unless /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/.match?(email)

    matches = client.all_pages("/v1/betaTesters?" + URI.encode_www_form(
      "filter[email]" => email, "limit" => 200
    ))
    raise SafeError, "TESTER_EMAIL_AMBIGUOUS" if matches.length > 1

    tester = matches.first
    if tester.nil?
      tester = client.post("/v1/betaTesters", {data: {
        type: "betaTesters", attributes: {email: email}, relationships: {
          builds: {data: [{type: "builds", id: build_id}]}
        }
      }}).fetch("data")
    end
    raise SafeError, "TESTER_EMAIL_MISMATCH" unless tester.dig("attributes", "email").to_s.casecmp?(email)

    tester_id = tester.fetch("id")
    tester_builds = client.all_pages("/v1/betaTesters/#{tester_id}/builds?limit=200")
    unless tester_builds.any? { |candidate| candidate["id"] == build_id }
      client.post("/v1/builds/#{build_id}/relationships/individualTesters", {
        data: [{type: "betaTesters", id: tester_id}]
      })
    end
    verify_tester_scope(client, tester_id, app_id, build_id)

    begin
      client.post("/v1/betaTesterInvitations", {data: {
        type: "betaTesterInvitations", relationships: {
          app: {data: {type: "apps", id: app_id}},
          betaTester: {data: {type: "betaTesters", id: tester_id}}
        }
      }})
    rescue StandardError => error
      raise unless error.respond_to?(:code)

      return {
        code: "TESTFLIGHT_INVITATION_NOT_SENT", bundle_id: BUNDLE,
        marketing_version: MARKETING_VERSION, build_number: build_number,
        tester_app_assigned: true, tester_build_assigned: true,
        invitation_accepted_by_apple: false, safe_error_code: sanitized_code(error),
        beta_review_state: beta_review_state(client, build_id)
      }
    end

    {
      code: "TESTFLIGHT_INVITATION_SENT", bundle_id: BUNDLE,
      marketing_version: MARKETING_VERSION, build_number: build_number,
      tester_app_assigned: true, tester_build_assigned: true,
      invitation_accepted_by_apple: true
    }
  rescue KeyError, TypeError
    raise SafeError, "TESTER_RESPONSE_INVALID"
  end

  def verify_tester_scope(client, tester_id, app_id, build_id)
    builds = client.all_pages("/v1/betaTesters/#{tester_id}/builds?limit=200")
    raise SafeError, "TESTER_BUILD_ASSIGNMENT_MISSING" unless builds.any? { |candidate| candidate["id"] == build_id }

    apps = client.all_pages("/v1/betaTesters/#{tester_id}/apps?limit=200")
    raise SafeError, "TESTER_APP_ASSIGNMENT_MISSING" unless apps.any? { |candidate| candidate["id"] == app_id }
  end

  def submit_beta_review(client, app_id, build_id, build_number)
    detail = client.get("/v1/apps/#{app_id}/betaAppReviewDetail").fetch("data")
    raise SafeError, "BETA_REVIEW_METADATA_MISSING" unless detail.is_a?(Hash) && detail["type"] == "betaAppReviewDetails"

    existing = beta_review_submissions(client, build_id)
    raise SafeError, "BETA_REVIEW_SUBMISSION_AMBIGUOUS" if existing.length > 1
    submission = existing.first
    code = "TESTFLIGHT_BETA_REVIEW_EXISTS"
    if submission.nil?
      submission = client.post("/v1/betaAppReviewSubmissions", {data: {
        type: "betaAppReviewSubmissions", relationships: {
          build: {data: {type: "builds", id: build_id}}
        }
      }}).fetch("data")
      code = "TESTFLIGHT_BETA_REVIEW_SUBMITTED"
    end
    state = submission.dig("attributes", "betaReviewState")
    raise SafeError, "BETA_REVIEW_STATE_MISSING" unless state.is_a?(String) && !state.empty?

    {
      code: code, bundle_id: BUNDLE, marketing_version: MARKETING_VERSION,
      build_number: build_number, beta_review_state: state
    }
  rescue KeyError, TypeError
    raise SafeError, "BETA_REVIEW_RESPONSE_INVALID"
  end

  def beta_review_submissions(client, build_id)
    client.all_pages("/v1/betaAppReviewSubmissions?" + URI.encode_www_form(
      "filter[build]" => build_id, "limit" => 200
    ))
  end

  def beta_review_state(client, build_id)
    submissions = beta_review_submissions(client, build_id)
    return "MISSING" if submissions.empty?
    return "AMBIGUOUS" unless submissions.length == 1

    state = submissions.first.dig("attributes", "betaReviewState")
    state.is_a?(String) && !state.empty? ? state : "UNKNOWN"
  rescue StandardError
    "UNAVAILABLE"
  end

  def sanitized_code(error)
    candidate = error.respond_to?(:code) ? error.code.to_s : "ASC_INVITATION_FAILED"
    SAFE_CODE.match?(candidate) ? candidate : "ASC_INVITATION_FAILED"
  end

  def apple_client(env)
    require_relative "../source/scripts/ios_baseline_release"
    provider = IOSBaselineRelease::JwtProvider.new(
      issuer_id: env.fetch("APPSTORE_ISSUER_ID"),
      key_id: env.fetch("APPSTORE_API_KEY_ID"),
      private_key: env.fetch("APPSTORE_API_PRIVATE_KEY")
    )
    IOSBaselineRelease::Client.new(
      transport: IOSBaselineRelease::NetHTTPTransport.new,
      token_provider: provider
    )
  end

  def run_cli(env: ENV, out: $stdout, err: $stderr, client: nil)
    receipt = run(env: env, client: client)
    out.puts(JSON.generate(receipt))
    receipt[:code] == "TESTFLIGHT_INVITATION_NOT_SENT" ? 1 : 0
  rescue SafeError => error
    err.puts(JSON.generate(code: error.code))
    1
  rescue StandardError => error
    err.puts(JSON.generate(code: sanitized_code(error)))
    1
  end
end

exit LumaTestFlightAccess.run_cli if $PROGRAM_NAME == __FILE__
