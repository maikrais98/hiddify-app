# frozen_string_literal: true

helper_argument = ARGV.first
ARGV.shift if helper_argument && !helper_argument.start_with?("-")

require "digest"
require "json"
require "minitest/autorun"
require "openssl"
require "stringio"
require "tmpdir"
require "uri"

HELPER_PATH = helper_argument || ENV["TEST_ONLY_IOS_BASELINE_HELPER_PATH"]
abort "helper path argument is required" unless HELPER_PATH
abort "helper fixture hash mismatch" unless Digest::SHA256.file(HELPER_PATH).hexdigest ==
  "13cd9ed9688c4fec9e346bd12c845eac72616b823b57760535f5f667b6d8a38c"

require File.realpath(HELPER_PATH)
require_relative "../../scripts/ios_baseline_build_inventory"

class InventoryFixtureTransport
  attr_reader :requests

  def initialize(&responder)
    @responder = responder
    @requests = []
  end

  def request(method:, url:, headers:, body:, timeouts:)
    @requests << { method: method, url: url, headers: headers, body: body, timeouts: timeouts }
    payload = @responder.call(URI(url), @requests.length)
    return payload if payload.is_a?(IOSBaselineRelease::Response)

    IOSBaselineRelease::Response.new(status: 200, headers: {}, body: JSON.generate(payload))
  end
end

class IOSBaselineBuildInventoryTest < Minitest::Test
  APP_ID = "123456789"
  TRAIN_ID = "opaque-train-001"
  FIXED_TIME = Time.utc(2026, 10, 14, 8, 9, 10)

  def app(id: APP_ID, bundle: "com.womaninred.baseline")
    { "type" => "apps", "id" => id, "attributes" => { "bundleId" => bundle } }
  end

  def train(id: TRAIN_ID, app_id: APP_ID, version: "0.0.1", platform: "IOS")
    {
      "type" => "preReleaseVersions", "id" => id,
      "attributes" => { "version" => version, "platform" => platform },
      "relationships" => { "app" => { "data" => { "type" => "apps", "id" => app_id } } }
    }
  end

  def build(number, id: nil, state: "VALID", expired: false, train_id: TRAIN_ID)
    id ||= "opaque-build-#{number}"
    {
      "type" => "builds", "id" => id,
      "attributes" => { "version" => number.to_s, "processingState" => state, "expired" => expired },
      "relationships" => {
        "preReleaseVersion" => {
          "data" => { "type" => "preReleaseVersions", "id" => train_id }
        }
      }
    }
  end

  def successful_transport(build_pages: [[build(3)]], build_totals: nil)
    InventoryFixtureTransport.new do |uri, _request_number|
      params = URI.decode_www_form(uri.query.to_s).to_h
      case uri.path
      when "/v1/apps"
        { "data" => [app], "links" => { "next" => nil } }
      when "/v1/preReleaseVersions"
        version = train
        version = version.reject { |key, _value| key == "relationships" } unless params["include"] == "app"
        { "data" => [version], "links" => { "next" => nil } }
      when "/v1/builds"
        page = Integer(params.fetch("page", "1"))
        next_url = page < build_pages.length ? "https://api.appstoreconnect.apple.com/v1/builds?#{uri.query}&page=#{page + 1}" : nil
        payload = { "data" => build_pages.fetch(page - 1), "links" => { "next" => next_url } }
        payload["meta"] = { "paging" => { "total" => build_totals.fetch(page - 1) } } if build_totals
        payload
      else
        flunk "unexpected request path: #{uri.path}"
      end
    end
  end

  def inventory(transport)
    guarded = IOSBaselineBuildInventory::GetOnlyTransport.new(transport)
    client = IOSBaselineRelease::Client.new(
      transport: guarded,
      token_provider: -> { "fixture-token" },
      sleeper: ->(_seconds) { flunk "inventory requests must not retry in tests" },
      max_retries: 0
    )
    IOSBaselineBuildInventory::Inventory.new(client: client, clock: -> { FIXED_TIME })
  end

  def test_all_build_states_and_expired_records_consume_the_maximum_across_pages
    transport = successful_transport(build_pages: [
      [build(1), build(3), build(7, state: "PROCESSING")],
      [build(9, state: "FAILED", expired: true)]
    ])

    report = inventory(transport).run

    assert_equal [1, 3, 7, 9], report.fetch("builds").map { |item| item.fetch("buildNumber") }
    assert_equal 10, report.fetch("candidate")
    assert_equal 4, report.fetch("count")
    assert_equal "FAILED", report.fetch("builds").last.fetch("processingState")
    assert_equal true, report.fetch("builds").last.fetch("expired")
    assert_equal "2026-10-14T08:09:10Z", report.fetch("observedAt")
  end

  def test_gaps_are_not_filled_and_known_baseline_must_be_observed
    assert_equal 8, inventory(successful_transport(build_pages: [[build(3), build(7)]])).run.fetch("candidate")

    error = assert_raises(IOSBaselineBuildInventory::SafeError) do
      inventory(successful_transport(build_pages: [[build(1), build(7)]])).run
    end
    assert_equal "KNOWN_BASELINE_MISSING", error.code
  end

  def test_queries_are_exact_and_do_not_filter_build_state_number_or_expiry
    transport = successful_transport
    inventory(transport).run

    requests = transport.requests
    assert requests.all? { |request| request.fetch(:method) == "GET" && request.fetch(:body).nil? }
    app_query = URI.decode_www_form(URI(requests[0].fetch(:url)).query).to_h
    version_query = URI.decode_www_form(URI(requests[1].fetch(:url)).query).to_h
    build_query = URI.decode_www_form(URI(requests[2].fetch(:url)).query).to_h
    assert_equal "com.womaninred.baseline", app_query.fetch("filter[bundleId]")
    assert_equal APP_ID, version_query.fetch("filter[app]")
    assert_equal "0.0.1", version_query.fetch("filter[version]")
    assert_equal "IOS", version_query.fetch("filter[platform]")
    assert_equal "app", version_query.fetch("include")
    assert_equal TRAIN_ID, build_query.fetch("filter[preReleaseVersion]")
    assert_equal "preReleaseVersion", build_query.fetch("include")
    refute build_query.keys.any? { |key| key.match?(/version|state|expired/i) && key != "filter[preReleaseVersion]" }
  end

  def test_get_only_guard_rejects_mutating_requests
    guarded = IOSBaselineBuildInventory::GetOnlyTransport.new(successful_transport)
    error = assert_raises(IOSBaselineBuildInventory::SafeError) do
      guarded.request(method: "POST", url: "https://api.appstoreconnect.apple.com/v1/builds",
        headers: {}, body: "{}", timeouts: {})
    end
    assert_equal "READ_ONLY_VIOLATION", error.code
  end

  def test_ambiguous_app_or_train_is_rejected
    ambiguous_app = InventoryFixtureTransport.new do |uri, _|
      if uri.path == "/v1/apps"
        { "data" => [app, app(id: "987654321")] }
      else
        flunk "inventory must stop after ambiguous app"
      end
    end
    assert_equal "APP_AMBIGUOUS", assert_raises(IOSBaselineBuildInventory::SafeError) {
      inventory(ambiguous_app).run
    }.code

    ambiguous_train = InventoryFixtureTransport.new do |uri, _|
      case uri.path
      when "/v1/apps" then { "data" => [app] }
      when "/v1/preReleaseVersions" then { "data" => [train, train(id: "another-opaque-train")] }
      else flunk "inventory must stop after ambiguous train"
      end
    end
    assert_equal "VERSION_AMBIGUOUS", assert_raises(IOSBaselineBuildInventory::SafeError) {
      inventory(ambiguous_train).run
    }.code
  end

  def test_malformed_relationships_attributes_nonintegers_and_unknown_values_are_rejected
    invalid_builds = [
      build(3, train_id: "another-opaque-train"),
      build("3.0", id: "opaque-invalid-number"),
      build(3, state: "MYSTERY"),
      build(3).tap { |item| item.fetch("attributes")["expired"] = "false" }
    ]

    invalid_builds.each do |invalid|
      error = assert_raises(IOSBaselineBuildInventory::SafeError) do
        inventory(successful_transport(build_pages: [[invalid]])).run
      end
      assert_match(/BUILD_/, error.code)
    end
  end

  def test_duplicate_ids_and_build_numbers_are_rejected
    duplicate_id = build(4, id: build(3).fetch("id"))
    error = assert_raises(IOSBaselineBuildInventory::SafeError) do
      inventory(successful_transport(build_pages: [[build(3), duplicate_id]])).run
    end
    assert_equal "BUILD_ID_DUPLICATE", error.code

    duplicate_number = build(3, id: "different-opaque-build")
    error = assert_raises(IOSBaselineBuildInventory::SafeError) do
      inventory(successful_transport(build_pages: [[build(3), duplicate_number]])).run
    end
    assert_equal "BUILD_NUMBER_DUPLICATE", error.code
  end

  def test_unsafe_pagination_transport_and_http_failures_never_produce_a_candidate
    unsafe = InventoryFixtureTransport.new do |uri, _|
      case uri.path
      when "/v1/apps" then { "data" => [app] }
      when "/v1/preReleaseVersions" then { "data" => [train] }
      when "/v1/builds"
        { "data" => [build(3)], "links" => { "next" => "https://fixture-secret.invalid/v1/builds?page=2" } }
      end
    end
    assert_equal "UNSAFE_ASC_URL", assert_raises(IOSBaselineRelease::SafeError) { inventory(unsafe).run }.code

    [
      IOSBaselineRelease::Response.new(status: 403, headers: {}, body: "fixture-private-body"),
      :transport_failure
    ].each do |failure|
      transport = InventoryFixtureTransport.new do |_uri, _|
        raise SocketError, "fixture-private-host" if failure == :transport_failure

        failure
      end
      assert_raises(IOSBaselineRelease::SafeError) { inventory(transport).run }
    end
  end

  def test_candidate_above_maximum_is_rejected
    error = assert_raises(IOSBaselineBuildInventory::SafeError) do
      inventory(successful_transport(build_pages: [[build(3), build(9_999)]])).run
    end
    assert_equal "CANDIDATE_LIMIT_EXCEEDED", error.code
  end

  def test_opaque_path_safe_resource_ids_are_accepted
    report = inventory(successful_transport(build_pages: [[build(3, id: "Build_opaque-3")]])).run

    assert_equal 4, report.fetch("candidate")
  end

  def cli_env
    private_key = OpenSSL::PKey::EC.generate("prime256v1").to_pem
    {
      "APPSTORE_ISSUER_ID" => "fixture-issuer",
      "APPSTORE_API_KEY_ID" => "FIXTUREKEY",
      "APPSTORE_API_PRIVATE_KEY" => private_key
    }
  end

  def assert_cli_pagination_failure(expected_code, transport)
    out = StringIO.new
    err = StringIO.new
    status = IOSBaselineBuildInventory.run_cli([HELPER_PATH], env: cli_env, out: out, err: err,
      transport: transport, clock: -> { FIXED_TIME })

    assert_equal 1, status
    assert_empty out.string
    assert_equal({ "code" => expected_code }, JSON.parse(err.string))
    refute_match(/opaque|fixture|https?:|PRIVATE KEY|#{APP_ID}/i, err.string)
  end

  def test_cli_rejects_declared_total_larger_than_the_last_available_page
    assert_cli_pagination_failure("PAGINATION_TOTAL_MISMATCH",
      successful_transport(build_pages: [[build(3)]], build_totals: [2]))
  end

  def test_cli_rejects_noninteger_declared_total
    assert_cli_pagination_failure("PAGINATION_TOTAL_INVALID",
      successful_transport(build_pages: [[build(3)]], build_totals: ["1"]))
  end

  def test_cli_rejects_declared_total_that_changes_between_pages
    assert_cli_pagination_failure("PAGINATION_TOTAL_CHANGED", successful_transport(
      build_pages: [[build(3)], [build(4)]], build_totals: [2, 3]
    ))
  end

  def test_cli_report_is_safe_and_hash_mismatch_error_is_stable
    transport = successful_transport(build_pages: [[build(3), build(5, state: "INVALID", expired: true)]])
    private_key = OpenSSL::PKey::EC.generate("prime256v1").to_pem
    env = {
      "APPSTORE_ISSUER_ID" => "fixture-issuer",
      "APPSTORE_API_KEY_ID" => "FIXTUREKEY",
      "APPSTORE_API_PRIVATE_KEY" => private_key
    }
    out = StringIO.new
    err = StringIO.new

    status = IOSBaselineBuildInventory.run_cli([HELPER_PATH], env: env, out: out, err: err,
      transport: transport, clock: -> { FIXED_TIME })

    assert_equal 0, status
    assert_empty err.string
    parsed = JSON.parse(out.string)
    assert_equal "ios-baseline-build-inventory/v1", parsed.fetch("schema")
    assert_equal 6, parsed.fetch("candidate")
    assert_equal IOSBaselineBuildInventory::APP_CANDIDATE_SHA, parsed.fetch("candidateSHA")
    assert_equal IOSBaselineBuildInventory::TRUSTED_HELPER_SOURCE_SHA, parsed.fetch("helperSHA")
    authorizations = transport.requests.map { |request| request.fetch(:headers).fetch("Authorization") }
    assert_equal transport.requests.length, authorizations.uniq.length
    forbidden = [APP_ID, TRAIN_ID, "fixture-issuer", "FIXTUREKEY", "PRIVATE KEY", "api.appstoreconnect.apple.com"]
    forbidden.each { |value| refute_includes out.string, value }

    Dir.mktmpdir("inventory-helper") do |directory|
      altered = File.join(directory, "helper.rb")
      File.write(altered, "raise 'fixture-secret-executed'\n")
      out = StringIO.new
      err = StringIO.new
      status = IOSBaselineBuildInventory.run_cli([altered], env: {}, out: out, err: err)
      assert_equal 1, status
      assert_empty out.string
      assert_equal({ "code" => "HELPER_HASH_MISMATCH" }, JSON.parse(err.string))
      refute_includes err.string, "fixture-secret"
    end

    failure = InventoryFixtureTransport.new do |_uri, _|
      IOSBaselineRelease::Response.new(status: 403, headers: { "fixture-header" => "fixture-secret" },
        body: "fixture-private-id https://fixture-secret.invalid/private")
    end
    out = StringIO.new
    err = StringIO.new
    status = IOSBaselineBuildInventory.run_cli([HELPER_PATH], env: env, out: out, err: err,
      transport: failure, clock: -> { FIXED_TIME })
    assert_equal 1, status
    assert_empty out.string
    assert_equal({ "code" => "ASC_HTTP_403" }, JSON.parse(err.string))
    refute_match(/fixture|https?:|PRIVATE KEY|#{APP_ID}/i, err.string)
  end
end

class IOSBaselineBuildInventoryTest
  GROUP_ID = "private-group-id"

  def delivery_group
    { "type" => "betaGroups", "id" => GROUP_ID,
      "attributes" => { "name" => "Test", "isInternalGroup" => true, "hasAccessToAllBuilds" => false },
      "relationships" => { "app" => { "data" => { "type" => "apps", "id" => APP_ID } } } }
  end

  def delivery_transport(group: delivery_group, state: "READY_FOR_BETA_TESTING", target_builds: [build(16)],
    linked: true, override: nil)
    InventoryFixtureTransport.new do |uri, _|
      custom = override&.call(uri)
      next custom unless custom.nil?
      params = URI.decode_www_form(uri.query.to_s).to_h
      case uri.path
      when "/v1/apps" then { "data" => [app] }
      when "/v1/preReleaseVersions" then { "data" => [train] }
      when "/v1/builds"
        params["page"] == "2" ? { "data" => target_builds } :
          { "data" => [build(3)], "links" => { "next" => "#{uri}&page=2" } }
      when "/v1/betaGroups/#{GROUP_ID}" then { "data" => group }
      when "/v1/builds/opaque-build-16/buildBetaDetail"
        { "data" => { "type" => "buildBetaDetails", "id" => "private-beta-detail",
          "attributes" => { "internalBuildState" => state } } }
      when "/v1/betaGroups/#{GROUP_ID}/builds", "/v1/betaGroups/#{GROUP_ID}/relationships/builds"
        if params["page"] == "2"
          { "data" => linked ? [{ "type" => "builds", "id" => "opaque-build-16" }] : [] }
        else
          { "data" => [{ "type" => "builds", "id" => "opaque-build-3" }],
            "links" => { "next" => "#{uri}&page=2" } }
        end
      else flunk "unexpected fixture request"
      end
    end
  end

  def delivery_run(transport)
    inventory(transport).run(delivery_build_number: "16", tester_group_id: GROUP_ID)
  end

  def test_delivery_reports_only_closed_fields_with_full_pagination_and_gets
    transport = delivery_transport
    report = delivery_run(transport)
    assert_equal({ "buildNumber" => 16, "processingState" => "VALID",
      "internalBuildState" => "READY_FOR_BETA_TESTING", "isInternalGroup" => true,
      "hasAccessToAllBuilds" => false, "appMatches" => true,
      "assignedViaBuilds" => true, "assignedViaRelationship" => true }, report.fetch("delivery"))
    assert transport.requests.all? { |r| r[:method] == "GET" && r[:body].nil? }
    assert_equal 3, transport.requests.count { |r| URI(r[:url]).query.to_s.include?("page=2") }
    refute_match(/#{APP_ID}|opaque|private|#{GROUP_ID}|Test|fixture-token/, JSON.generate(report))
  end

  def test_delivery_optional_all_builds_attribute_and_absent_assignments
    group = delivery_group
    group["attributes"].delete("hasAccessToAllBuilds")
    delivery = delivery_run(delivery_transport(group: group, linked: false)).fetch("delivery")
    assert_nil delivery["hasAccessToAllBuilds"]
    assert_equal false, delivery["assignedViaBuilds"]
    assert_equal false, delivery["assignedViaRelationship"]
  end

  def test_delivery_rejects_missing_or_ambiguous_target_and_unknown_state
    [[[], "DELIVERY_BUILD_NOT_FOUND"], [[build(16), build(16, id: "another-build")], "BUILD_NUMBER_DUPLICATE"]].each do |builds, code|
      assert_equal code, assert_raises(IOSBaselineBuildInventory::SafeError) {
        delivery_run(delivery_transport(target_builds: builds))
      }.code
    end
    assert_equal "DELIVERY_STATE_INVALID", assert_raises(IOSBaselineBuildInventory::SafeError) {
      delivery_run(delivery_transport(state: "private unexpected body"))
    }.code
  end

  def test_delivery_group_binding_and_fields_fail_closed
    variants = [
      ->(g) { g["id"] = "wrong-group" },
      ->(g) { g["relationships"]["app"]["data"]["id"] = "987654321" },
      ->(g) { g["relationships"].delete("app") },
      ->(g) { g["attributes"]["name"] = "other group" },
      ->(g) { g["attributes"]["isInternalGroup"] = "true" },
      ->(g) { g["attributes"]["isInternalGroup"] = false },
      ->(g) { g["attributes"]["hasAccessToAllBuilds"] = "false" }
    ]
    variants.each do |mutate|
      group = delivery_group
      mutate.call(group)
      assert_equal "DELIVERY_GROUP_INVALID", assert_raises(IOSBaselineBuildInventory::SafeError) {
        delivery_run(delivery_transport(group: group))
      }.code
    end
  end

  def test_delivery_linkage_malformed_duplicates_and_incomplete_pagination_fail_closed
    [
      [{ "data" => [{ "type" => "betaGroups", "id" => "opaque-build-16" }] }, "DELIVERY_LINKAGE_INVALID"],
      [{ "data" => [{ "type" => "builds", "id" => "same" }] * 2 }, "DELIVERY_LINKAGE_DUPLICATE"],
      [{ "data" => [], "meta" => { "paging" => { "total" => 1 } } }, "PAGINATION_TOTAL_MISMATCH"]
    ].each do |payload, code|
      override = ->(uri) { payload if uri.path.end_with?("relationships/builds") }
      assert_equal code, assert_raises(IOSBaselineBuildInventory::SafeError) {
        delivery_run(delivery_transport(override: override))
      }.code
    end
  end

  def test_delivery_cli_opt_in_and_legacy_compatibility
    [false, true].each do |enabled|
      env = cli_env
      env.merge!("DELIVERY_BUILD_NUMBER" => "16", "TESTER_GROUP_ID" => GROUP_ID) if enabled
      out = StringIO.new
      err = StringIO.new
      transport = enabled ? delivery_transport : successful_transport
      status = IOSBaselineBuildInventory.run_cli([HELPER_PATH], env: env, out: out, err: err,
        transport: transport, clock: -> { FIXED_TIME })
      assert_equal 0, status
      assert_empty err.string
      assert_equal enabled, JSON.parse(out.string).key?("delivery")
      refute_match(/private|opaque|#{APP_ID}|PRIVATE KEY|fixture-issuer|FIXTUREKEY/, out.string)
      assert_equal 3, transport.requests.length unless enabled
    end
  end

  def test_delivery_cli_partial_or_invalid_configuration_never_calls_apple
    [{ "DELIVERY_BUILD_NUMBER" => "16" }, { "TESTER_GROUP_ID" => GROUP_ID },
      { "DELIVERY_BUILD_NUMBER" => "16/private", "TESTER_GROUP_ID" => GROUP_ID },
      { "DELIVERY_BUILD_NUMBER" => "16", "TESTER_GROUP_ID" => "private/path" }].each do |extra|
      out = StringIO.new
      err = StringIO.new
      transport = InventoryFixtureTransport.new { flunk "invalid delivery config must not call Apple" }
      status = IOSBaselineBuildInventory.run_cli([HELPER_PATH], env: cli_env.merge(extra), out: out, err: err,
        transport: transport, clock: -> { FIXED_TIME })
      assert_equal 1, status
      assert_empty out.string
      assert_equal({ "code" => "DELIVERY_CONFIG_INVALID" }, JSON.parse(err.string))
    end
  end

  def test_delivery_cli_http_failure_never_leaks_raw_response
    override = lambda do |uri|
      if uri.path.end_with?("buildBetaDetail")
        IOSBaselineRelease::Response.new(status: 403, headers: { "private-header" => "private-secret" },
          body: "private-body secret-id")
      end
    end
    out = StringIO.new
    err = StringIO.new
    status = IOSBaselineBuildInventory.run_cli([HELPER_PATH],
      env: cli_env.merge("DELIVERY_BUILD_NUMBER" => "16", "TESTER_GROUP_ID" => GROUP_ID),
      out: out, err: err, transport: delivery_transport(override: override), clock: -> { FIXED_TIME })
    assert_equal 1, status
    assert_empty out.string
    assert_equal({ "code" => "ASC_HTTP_403" }, JSON.parse(err.string))
  end
end

class IOSBaselineBuildInventoryTest
  def test_delivery_accepts_every_documented_internal_state
    %w[PROCESSING PROCESSING_EXCEPTION MISSING_EXPORT_COMPLIANCE READY_FOR_BETA_TESTING
      IN_BETA_TESTING EXPIRED IN_EXPORT_COMPLIANCE_REVIEW].each do |state|
      assert_equal state, delivery_run(delivery_transport(state: state)).fetch("delivery").fetch("internalBuildState")
    end
  end

  def test_delivery_does_not_conflate_the_two_assignment_reads
    override = ->(uri) { { "data" => [] } if uri.path.end_with?("relationships/builds") }
    delivery = delivery_run(delivery_transport(override: override)).fetch("delivery")
    assert_equal true, delivery["assignedViaBuilds"]
    assert_equal false, delivery["assignedViaRelationship"]
  end

  def test_delivery_malformed_nested_group_and_detail_fail_closed
    group = delivery_group.merge("relationships" => "private malformed relationship")
    assert_equal "DELIVERY_GROUP_INVALID", assert_raises(IOSBaselineBuildInventory::SafeError) {
      delivery_run(delivery_transport(group: group))
    }.code
    [nil, [], { "type" => "builds", "id" => "private-detail", "attributes" => {} }].each do |detail|
      override = ->(uri) { { "data" => detail } if uri.path.end_with?("buildBetaDetail") }
      assert_equal "DELIVERY_DETAIL_INVALID", assert_raises(IOSBaselineBuildInventory::SafeError) {
        delivery_run(delivery_transport(override: override))
      }.code
    end
  end

  def test_delivery_number_bounds_and_explicit_empty_legacy_environment
    %w[0 10000 016 -1].each do |number|
      assert_equal "DELIVERY_CONFIG_INVALID", assert_raises(IOSBaselineBuildInventory::SafeError) {
        inventory(successful_transport).run(delivery_build_number: number, tester_group_id: GROUP_ID)
      }.code
    end
    out = StringIO.new
    err = StringIO.new
    status = IOSBaselineBuildInventory.run_cli([HELPER_PATH],
      env: cli_env.merge("DELIVERY_BUILD_NUMBER" => "", "TESTER_GROUP_ID" => ""),
      out: out, err: err, transport: successful_transport, clock: -> { FIXED_TIME })
    assert_equal 0, status
    assert_empty err.string
    refute JSON.parse(out.string).key?("delivery")
  end
end
