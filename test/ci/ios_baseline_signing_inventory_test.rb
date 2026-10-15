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
require "yaml"

HELPER_PATH = helper_argument || ENV["TEST_ONLY_IOS_BASELINE_HELPER_PATH"]
abort "helper path argument is required" unless HELPER_PATH
abort "helper fixture hash mismatch" unless Digest::SHA256.file(HELPER_PATH).hexdigest ==
  "13cd9ed9688c4fec9e346bd12c845eac72616b823b57760535f5f667b6d8a38c"

require File.realpath(HELPER_PATH)

SCRIPT = File.expand_path("../../scripts/ios_baseline_signing_inventory.rb", __dir__)
WORKFLOW = File.expand_path("../../.github/workflows/ios-baseline-signing-inventory.yml", __dir__)
require SCRIPT if File.file?(SCRIPT)

class SigningInventoryFixtureTransport
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

class IOSBaselineSigningInventoryTest < Minitest::Test
  FIXED_TIME = Time.utc(2026, 10, 15, 9, 10, 11)
  APP_BUNDLE = "com.womaninred.baseline"
  EXTENSION_BUNDLE = "com.womaninred.baseline.HiddifyPacketTunnel"
  CERTIFICATE_FIELDS = "certificateType,expirationDate,activated"
  CERTIFICATE_TYPES_FILTER = "DEVELOPMENT,IOS_DEVELOPMENT,DISTRIBUTION,IOS_DISTRIBUTION"
  PROFILE_FIELDS = "profileType,profileState,expirationDate"

  def implementation
    assert Object.const_defined?(:IOSBaselineSigningInventory), "signing inventory implementation is missing"
    IOSBaselineSigningInventory
  end

  def certificate(id, type:, expires:, activated:, canary: id)
    {
      "type" => "certificates",
      "id" => id,
      "attributes" => {
        "certificateType" => type,
        "expirationDate" => expires,
        "activated" => activated,
        "name" => "NAME_CANARY_#{canary}",
        "serialNumber" => "SERIAL_CANARY_#{canary}",
        "certificateContent" => "CERT_CONTENT_CANARY_#{canary}"
      }
    }
  end

  def bundle(id, identifier)
    {
      "type" => "bundleIds",
      "id" => id,
      "attributes" => { "identifier" => identifier, "name" => "BUNDLE_NAME_CANARY" }
    }
  end

  def profile(id, type:, state:, expires:, canary: id)
    {
      "type" => "profiles",
      "id" => id,
      "attributes" => {
        "profileType" => type,
        "profileState" => state,
        "expirationDate" => expires,
        "name" => "PROFILE_NAME_CANARY_#{canary}",
        "uuid" => "UUID_CANARY_#{canary}",
        "profileContent" => "PROFILE_CONTENT_CANARY_#{canary}"
      }
    }
  end

  def fixtures
    @fixtures ||= {
      cert_dev: certificate("cert-dev-private", type: "DEVELOPMENT",
        expires: "2027-01-02T03:04:05Z", activated: true),
      cert_dist: certificate("cert-dist-private", type: "DISTRIBUTION",
        expires: "2027-03-04T05:06:07Z", activated: true),
      cert_old: certificate("cert-old-private", type: "IOS_DISTRIBUTION",
        expires: "2025-01-02T03:04:05Z", activated: false),
      app_active: profile("profile-app-active-private", type: "IOS_APP_STORE", state: "ACTIVE",
        expires: "2027-03-04T05:06:07Z"),
      app_invalid: profile("profile-app-invalid-private", type: "IOS_APP_DEVELOPMENT", state: "INVALID",
        expires: "2025-01-02T03:04:05Z"),
      extension_active: profile("profile-extension-active-private", type: "IOS_APP_STORE", state: "ACTIVE",
        expires: "2027-03-04T05:06:07Z")
    }
  end

  def successful_transport(bundle_resources: {})
    data = fixtures
    SigningInventoryFixtureTransport.new do |uri, _request_number|
      query = URI.decode_www_form(uri.query.to_s).to_h
      case uri.path
      when "/v1/certificates"
        if query["cursor"] == "second"
          page([data.fetch(:cert_old)], total: 3)
        else
          page([data.fetch(:cert_dev), data.fetch(:cert_dist)], next_url: next_url(uri, "second"), total: 3)
        end
      when "/v1/bundleIds"
        identifier = query.fetch("filter[identifier]")
        id = identifier == APP_BUNDLE ? "bundle-app-private" : "bundle-extension-private"
        resources = bundle_resources.fetch(identifier) { [bundle(id, identifier)] }
        page(resources, total: resources.length)
      when "/v1/bundleIds/bundle-app-private/profiles"
        page([data.fetch(:app_active), data.fetch(:app_invalid)], total: 2)
      when "/v1/bundleIds/bundle-extension-private/profiles"
        page([data.fetch(:extension_active)], total: 1)
      when "/v1/profiles/profile-app-active-private/certificates"
        page([data.fetch(:cert_dist)], total: 1)
      when "/v1/profiles/profile-app-invalid-private/certificates"
        page([data.fetch(:cert_dev)], total: 1)
      when "/v1/profiles/profile-extension-active-private/certificates"
        page([data.fetch(:cert_dist)], total: 1)
      else
        raise "unexpected fixture path"
      end
    end
  end

  def page(data, next_url: nil, total: nil)
    payload = { "data" => data, "links" => { "next" => next_url } }
    payload["meta"] = { "paging" => { "total" => total } } unless total.nil?
    payload
  end

  def next_url(uri, cursor)
    pairs = URI.decode_www_form(uri.query.to_s).reject { |key, _| key == "cursor" }
    pairs << ["cursor", cursor]
    "https://api.appstoreconnect.apple.com#{uri.path}?#{URI.encode_www_form(pairs)}"
  end

  def inventory(transport)
    guarded = implementation::GetOnlyTransport.new(transport)
    counter = 0
    client = IOSBaselineRelease::Client.new(
      transport: guarded,
      token_provider: -> { counter += 1; "fixture-token-#{counter}" },
      sleeper: ->(_seconds) { flunk "inventory fixtures must not retry" },
      max_retries: 0
    )
    implementation::Inventory.new(client: client, clock: -> { FIXED_TIME })
  end

  def test_complete_inventory_is_aggregated_and_contains_no_sensitive_metadata
    transport = successful_transport
    report = inventory(transport).run

    assert_equal "ios-baseline-signing-inventory/v1", report.fetch("schema")
    assert_equal "2026-10-15T09:10:11Z", report.fetch("observedAt")
    assert_equal implementation::TRUSTED_HELPER_SOURCE_SHA, report.fetch("helperSHA")
    refute report.key?("status")
    refute report.key?("complete")
    refute report.key?("unavailableAssociations")

    certificates = report.fetch("certificates")
    assert_equal 3, certificates.fetch("count")
    assert_equal({ "DEVELOPMENT" => 1, "DISTRIBUTION" => 1, "IOS_DISTRIBUTION" => 1 },
      certificates.fetch("byType"))
    assert_equal({ "false" => 1, "true" => 2 }, certificates.fetch("byActivated"))
    assert_equal ["2025-01-02T03:04:05Z", "2027-01-02T03:04:05Z", "2027-03-04T05:06:07Z"],
      certificates.fetch("expirationDates")
    assert_equal %w[certificate-001 certificate-002 certificate-003],
      certificates.fetch("items").map { |item| item.fetch("certificateRef") }

    targets = report.fetch("targets")
    assert_equal [APP_BUNDLE, EXTENSION_BUNDLE], targets.map { |target| target.fetch("bundleIdentifier") }
    app = targets.first
    assert_equal 2, app.fetch("profileCount")
    assert_equal({ "IOS_APP_DEVELOPMENT" => 1, "IOS_APP_STORE" => 1 }, app.fetch("byType"))
    assert_equal({ "ACTIVE" => 1, "INVALID" => 1 }, app.fetch("byState"))
    assert_equal 1, targets.last.fetch("profileCount")
    assert_equal ["certificate-002"], targets.last.fetch("profiles").first.fetch("certificateRefs")

    encoded = JSON.generate(report)
    forbidden = %w[
      cert-dev-private cert-dist-private cert-old-private bundle-app-private bundle-extension-private
      profile-app-active-private profile-app-invalid-private profile-extension-active-private
      NAME_CANARY SERIAL_CANARY CERT_CONTENT_CANARY PROFILE_NAME_CANARY UUID_CANARY PROFILE_CONTENT_CANARY
      fixture-token https:// api.appstoreconnect.apple.com
    ]
    forbidden.each { |value| refute_includes encoded, value }

    assert transport.requests.all? { |request| request.fetch(:method) == "GET" && request.fetch(:body).nil? }
    queries = transport.requests.map { |request| URI.decode_www_form(URI(request.fetch(:url)).query.to_s).to_h }
    assert_equal [APP_BUNDLE, EXTENSION_BUNDLE],
      queries.map { |query| query["filter[identifier]"] }.compact.sort
    assert queries.any? { |query| query["fields[certificates]"] == CERTIFICATE_FIELDS }
    root_certificate_query = queries.find { |query| query.key?("filter[certificateType]") }
    refute_nil root_certificate_query
    assert_equal CERTIFICATE_TYPES_FILTER, root_certificate_query.fetch("filter[certificateType]")
    assert queries.any? { |query| query["fields[profiles]"] == PROFILE_FIELDS }
    refute_match(/name|serialNumber|certificateContent|profileContent|uuid|devices|include/i,
      transport.requests.map { |request| request.fetch(:url) }.join("\n"))
  end

  def test_exact_bundle_selects_exact_identifier_from_prefix_matches
    transport = successful_transport(bundle_resources: {
      APP_BUNDLE => [
        bundle("bundle-app-private", APP_BUNDLE),
        bundle("bundle-extension-private", EXTENSION_BUNDLE)
      ]
    })

    report = inventory(transport).run

    assert_equal [APP_BUNDLE, EXTENSION_BUNDLE],
      report.fetch("targets").map { |target| target.fetch("bundleIdentifier") }
  end

  def test_exact_bundle_rejects_multiple_exact_identifier_matches
    transport = successful_transport(bundle_resources: {
      APP_BUNDLE => [
        bundle("bundle-app-private", APP_BUNDLE),
        bundle("bundle-app-duplicate-private", APP_BUNDLE)
      ]
    })

    error = assert_raises(implementation::SafeError) { inventory(transport).run }

    assert_equal "BUNDLE_ID_AMBIGUOUS", error.code
  end

  def test_exact_bundle_reports_not_found_when_only_prefix_matches_exist
    transport = successful_transport(bundle_resources: {
      APP_BUNDLE => [bundle("bundle-extension-private", EXTENSION_BUNDLE)]
    })

    error = assert_raises(implementation::SafeError) { inventory(transport).run }

    assert_equal "BUNDLE_ID_NOT_FOUND", error.code
  end

  def test_transport_rejects_mutations_unsafe_routes_and_query_injection
    delegate = successful_transport
    guarded = implementation::GetOnlyTransport.new(delegate)
    valid = "https://api.appstoreconnect.apple.com/v1/certificates?" + URI.encode_www_form(
      "filter[certificateType]" => CERTIFICATE_TYPES_FILTER,
      "fields[certificates]" => CERTIFICATE_FIELDS,
      "limit" => "200"
    )
    unsafe_fields = "https://api.appstoreconnect.apple.com/v1/certificates?" + URI.encode_www_form(
      "filter[certificateType]" => CERTIFICATE_TYPES_FILTER,
      "fields[certificates]" => "certificateType,serialNumber",
      "limit" => "200"
    )

    failures = [
      ["POST", valid, "{}", "READ_ONLY_VIOLATION"],
      ["GET", valid.sub("api.appstoreconnect.apple.com", "private.invalid"), nil, "UNSAFE_ASC_REQUEST"],
      ["GET", valid.sub("/v1/certificates", "/v1/devices"), nil, "UNSAFE_ASC_REQUEST"],
      ["GET", "#{valid}&fields[certificates]=certificateContent", nil, "UNSAFE_ASC_REQUEST"],
      ["GET", unsafe_fields, nil, "UNSAFE_ASC_REQUEST"],
      ["GET", "#{valid}&include=devices", nil, "UNSAFE_ASC_REQUEST"]
    ]

    failures.each do |method, url, body, code|
      error = assert_raises(implementation::SafeError) do
        guarded.request(method: method, url: url, headers: {}, body: body, timeouts: {})
      end
      assert_equal code, error.code
    end
    assert_empty delegate.requests
  end

  def test_pagination_is_complete_and_fails_closed_on_loop_duplicate_total_or_route_drift
    collector_class = implementation::PageCollector

    duplicate = successful_transport
    duplicate.instance_variable_set(:@responder, lambda do |uri, _|
      query = URI.decode_www_form(uri.query.to_s).to_h
      resource = fixtures.fetch(:cert_dev)
      query["cursor"] ? page([resource], total: 2) : page([resource], next_url: next_url(uri, "second"), total: 2)
    end)
    assert_equal "PAGINATION_DUPLICATE", assert_raises(implementation::SafeError) {
      inventory(duplicate).run
    }.code

    looped = SigningInventoryFixtureTransport.new do |uri, _|
      page([], next_url: uri.to_s, total: 0)
    end
    client = fixture_client(looped)
    path = certificate_path
    assert_equal "PAGINATION_LOOP", assert_raises(implementation::SafeError) {
      collector_class.new(client).all(path)
    }.code

    mismatch = SigningInventoryFixtureTransport.new { |_uri, _| page([], total: 1) }
    assert_equal "PAGINATION_TOTAL_MISMATCH", assert_raises(implementation::SafeError) {
      collector_class.new(fixture_client(mismatch)).all(path)
    }.code

    drift = SigningInventoryFixtureTransport.new do |uri, _|
      page([], next_url: uri.to_s.sub("bundle-app-private", "bundle-extension-private"), total: 0)
    end
    profile_path = "/v1/bundleIds/bundle-app-private/profiles?" + URI.encode_www_form(
      "fields[profiles]" => PROFILE_FIELDS, "limit" => 200
    )
    assert_equal "PAGINATION_ROUTE_CHANGED", assert_raises(implementation::SafeError) {
      collector_class.new(fixture_client(drift)).all(profile_path)
    }.code
  end

  def test_unknown_enums_dates_and_certificate_associations_are_rejected
    cases = {
      "CERTIFICATE_TYPE_INVALID" => [:cert_dev, "certificateType", "PRIVATE_UNKNOWN"],
      "CERTIFICATE_ACTIVATED_INVALID" => [:cert_dev, "activated", "true"],
      "CERTIFICATE_EXPIRATION_INVALID" => [:cert_dev, "expirationDate", "tomorrow"],
      "PROFILE_TYPE_INVALID" => [:app_active, "profileType", "PRIVATE_UNKNOWN"],
      "PROFILE_STATE_INVALID" => [:app_active, "profileState", "PRIVATE_UNKNOWN"],
      "PROFILE_EXPIRATION_INVALID" => [:app_active, "expirationDate", "tomorrow"]
    }

    cases.each do |code, (fixture_key, attribute, value)|
      transport = successful_transport
      fixtures.fetch(fixture_key).fetch("attributes")[attribute] = value
      error = assert_raises(implementation::SafeError) { inventory(transport).run }
      assert_equal code, error.code
      @fixtures = nil
    end

    transport = successful_transport
    unknown = certificate("cert-not-global-private", type: "DISTRIBUTION",
      expires: "2027-03-04T05:06:07Z", activated: true)
    original = transport.instance_variable_get(:@responder)
    transport.instance_variable_set(:@responder, lambda do |uri, number|
      if uri.path == "/v1/profiles/profile-app-active-private/certificates"
        page([unknown], total: 1)
      else
        original.call(uri, number)
      end
    end)
    error = assert_raises(implementation::SafeError) { inventory(transport).run }
    assert_equal "CERTIFICATE_ASSOCIATION_INVALID", error.code
  end

  def test_missing_or_null_activation_is_reported_without_inventing_state
    transport = successful_transport
    fixtures.fetch(:cert_dev).fetch("attributes").delete("activated")
    fixtures.fetch(:cert_dist).fetch("attributes")["activated"] = nil

    report = inventory(transport).run

    certificates = report.fetch("certificates")
    assert_equal({ "NOT_REPORTED" => 2, "false" => 1 }, certificates.fetch("byActivated"))
    values = certificates.fetch("items").map { |item| item.fetch("activated") }
    assert_equal ["NOT_REPORTED", "NOT_REPORTED", false], values
    refute_includes JSON.generate(report), "true"
  end

  def test_optional_paging_total_and_opaque_cursor_forms_are_supported
    requests = 0
    transport = SigningInventoryFixtureTransport.new do |uri, _|
      requests += 1
      if requests == 1
        next_page = next_url(uri, "opaque+value/with:parts=")
        payload = page([fixtures.fetch(:cert_dev)], next_url: next_page)
        payload["meta"] = { "paging" => { "limit" => 200, "nextCursor" => "opaque" } }
        payload
      else
        page([fixtures.fetch(:cert_dist)])
      end
    end

    resources = implementation::PageCollector.new(fixture_client(transport)).all(certificate_path)

    assert_equal %w[cert-dev-private cert-dist-private], resources.map { |resource| resource.fetch("id") }
    assert_equal 2, requests
  end

  def test_pagination_cannot_switch_an_allowed_bundle_filter
    initial = "/v1/bundleIds?" + URI.encode_www_form(
      "filter[identifier]" => APP_BUNDLE,
      "fields[bundleIds]" => "identifier",
      "limit" => 200
    )
    transport = SigningInventoryFixtureTransport.new do |uri, _|
      changed = URI.decode_www_form(uri.query.to_s).map do |key, value|
        [key, key == "filter[identifier]" ? EXTENSION_BUNDLE : value]
      end
      changed << ["cursor", "second"]
      page([], next_url: "https://api.appstoreconnect.apple.com#{uri.path}?#{URI.encode_www_form(changed)}")
    end

    error = assert_raises(implementation::SafeError) do
      implementation::PageCollector.new(fixture_client(transport)).all(initial)
    end
    assert_equal "PAGINATION_QUERY_CHANGED", error.code
    assert_equal 1, transport.requests.length
  end

  def test_cli_success_and_http_or_network_failure_emit_only_closed_json
    out = StringIO.new
    err = StringIO.new
    status = implementation.run_cli([HELPER_PATH], env: cli_env, out: out, err: err,
      transport: successful_transport, clock: -> { FIXED_TIME }, client_options: { max_retries: 0 })
    assert_equal 0, status
    assert_empty err.string
    assert_equal "ios-baseline-signing-inventory/v1", JSON.parse(out.string).fetch("schema")

    failures = [
      [SigningInventoryFixtureTransport.new { |_uri, _| IOSBaselineRelease::Response.new(
        status: 403, headers: { "private" => "HEADER_CANARY" }, body: "BODY_CANARY https://private.invalid"
      ) }, "ASC_HTTP_403", "CERTIFICATES_LIST"],
      [SigningInventoryFixtureTransport.new { |_uri, _| raise SocketError, "NETWORK_CANARY private.invalid" },
        "ASC_TRANSPORT_FAILED", "CERTIFICATES_LIST"]
    ]
    failures.each do |transport, expected, stage|
      out = StringIO.new
      err = StringIO.new
      status = implementation.run_cli([HELPER_PATH], env: cli_env, out: out, err: err,
        transport: transport, clock: -> { FIXED_TIME },
        client_options: { max_retries: 0, sleeper: ->(_seconds) {} })
      assert_equal 1, status
      assert_empty out.string
      assert_equal({ "code" => expected, "stage" => stage }, JSON.parse(err.string))
      refute_match(/CANARY|private|https?:|BEGIN.*PRIVATE KEY/i, err.string)
    end

    Dir.mktmpdir("signing-helper") do |directory|
      altered = File.join(directory, "helper.rb")
      File.write(altered, "raise 'PRIVATE_CANARY'\n")
      out = StringIO.new
      err = StringIO.new
      status = implementation.run_cli([altered], env: {}, out: out, err: err)
      assert_equal 1, status
      assert_empty out.string
      assert_equal({ "code" => "HELPER_HASH_MISMATCH" }, JSON.parse(err.string))
      refute_includes err.string, "PRIVATE_CANARY"
    end
  end

  def test_non_profile_association_404_reports_only_a_fixed_safe_stage
    failures = {
      "CERTIFICATES_LIST" => "/v1/certificates",
      "BUNDLE_LOOKUP_APP" => ["/v1/bundleIds", APP_BUNDLE],
      "BUNDLE_PROFILES_APP" => "/v1/bundleIds/bundle-app-private/profiles",
      "BUNDLE_LOOKUP_EXTENSION" => ["/v1/bundleIds", EXTENSION_BUNDLE],
      "BUNDLE_PROFILES_EXTENSION" => "/v1/bundleIds/bundle-extension-private/profiles"
    }

    failures.each do |expected_stage, selector|
      transport = failing_transport(selector)
      out = StringIO.new
      err = StringIO.new
      status = implementation.run_cli([HELPER_PATH], env: cli_env, out: out, err: err,
        transport: transport, clock: -> { FIXED_TIME }, client_options: { max_retries: 0 })

      assert_equal 1, status
      assert_empty out.string
      assert_equal({ "code" => "ASC_HTTP_404", "stage" => expected_stage }, JSON.parse(err.string))
      refute_match(
        /bundle-(?:app|extension)-private|profile-(?:app|extension)|cert-(?:dev|dist|old)-private|CANARY|https?:/i,
        err.string
      )
    end
  end

  def test_profile_certificate_404_returns_partial_receipt_with_unknown_association
    transport = failing_transport("/v1/profiles/profile-app-active-private/certificates")
    out = StringIO.new
    err = StringIO.new

    status = implementation.run_cli([HELPER_PATH], env: cli_env, out: out, err: err,
      transport: transport, clock: -> { FIXED_TIME }, client_options: { max_retries: 0 })

    assert_equal 0, status
    assert_empty err.string
    report = JSON.parse(out.string)
    assert_equal "ios-baseline-signing-inventory-partial/v1", report.fetch("schema")
    assert_equal "PARTIAL", report.fetch("status")
    assert_equal false, report.fetch("complete")
    assert_equal [{ "code" => "ASC_HTTP_404", "stage" => "PROFILE_CERTIFICATES_APP_001" }],
      report.fetch("unavailableAssociations")
    assert_equal 3, report.fetch("certificates").fetch("count")
    assert_equal({ "DEVELOPMENT" => 1, "DISTRIBUTION" => 1, "IOS_DISTRIBUTION" => 1 },
      report.fetch("certificates").fetch("byType"))
    assert_equal ["2025-01-02T03:04:05Z", "2027-01-02T03:04:05Z", "2027-03-04T05:06:07Z"],
      report.fetch("certificates").fetch("expirationDates")
    assert_equal [2, 1], report.fetch("targets").map { |target| target.fetch("profileCount") }
    profiles = report.fetch("targets").flat_map { |target| target.fetch("profiles") }
    assert profiles.first.key?("certificateRefs")
    assert_nil profiles.first.fetch("certificateRefs")
    assert_equal [["certificate-001"], ["certificate-002"]],
      profiles.drop(1).map { |profile| profile.fetch("certificateRefs") }
    refute_match(
      /bundle-(?:app|extension)-private|profile-(?:app|extension)|cert-(?:dev|dist|old)-private|CANARY|https?:/i,
      out.string
    )
  end

  def test_multiple_profile_certificate_404s_remain_distinct_unknown_associations
    transport = failing_transport(
      "/v1/profiles/profile-app-active-private/certificates",
      "/v1/profiles/profile-extension-active-private/certificates"
    )

    report = inventory(transport).run

    assert_equal "ios-baseline-signing-inventory-partial/v1", report.fetch("schema")
    assert_equal false, report.fetch("complete")
    assert_equal [
      { "code" => "ASC_HTTP_404", "stage" => "PROFILE_CERTIFICATES_APP_001" },
      { "code" => "ASC_HTTP_404", "stage" => "PROFILE_CERTIFICATES_EXTENSION_001" }
    ], report.fetch("unavailableAssociations")
    profiles = report.fetch("targets").flat_map { |target| target.fetch("profiles") }
    assert_nil profiles.fetch(0).fetch("certificateRefs")
    assert_equal ["certificate-001"], profiles.fetch(1).fetch("certificateRefs")
    assert_nil profiles.fetch(2).fetch("certificateRefs")
  end

  def test_failure_after_partial_association_still_fails_closed_without_receipt
    transport = selected_failure_transport do |uri|
      case uri.path
      when "/v1/profiles/profile-app-active-private/certificates"
        http_failure(uri, 404)
      when "/v1/bundleIds/bundle-extension-private/profiles"
        http_failure(uri, 500)
      end
    end
    out = StringIO.new
    err = StringIO.new

    status = implementation.run_cli([HELPER_PATH], env: cli_env, out: out, err: err,
      transport: transport, clock: -> { FIXED_TIME }, client_options: { max_retries: 0 })

    assert_equal 1, status
    assert_empty out.string
    assert_equal({ "code" => "ASC_HTTP_500", "stage" => "BUNDLE_PROFILES_EXTENSION" },
      JSON.parse(err.string))
  end

  def test_profile_association_errors_other_than_404_remain_fatal
    cases = [
      [->(uri) { http_failure(uri, 403) }, { "code" => "ASC_HTTP_403", "stage" => "PROFILE_CERTIFICATES_APP_001" }],
      [->(_uri) { raise SocketError, "NETWORK_CANARY private.invalid" },
        { "code" => "ASC_TRANSPORT_FAILED", "stage" => "PROFILE_CERTIFICATES_APP_001" }],
      [->(_uri) { IOSBaselineRelease::Response.new(status: 200, headers: {}, body: "BODY_CANARY") },
        { "code" => "ASC_RESPONSE_INVALID", "stage" => "PROFILE_CERTIFICATES_APP_001" }],
      [->(_uri) { raise RuntimeError, "EXCEPTION_CANARY private.invalid" },
        { "code" => "SIGNING_INVENTORY_FAILED" }]
    ]

    cases.each do |failure, expected|
      selector = "/v1/profiles/profile-app-active-private/certificates"
      transport = selected_failure_transport(selector => failure)
      out = StringIO.new
      err = StringIO.new
      status = implementation.run_cli([HELPER_PATH], env: cli_env, out: out, err: err,
        transport: transport, clock: -> { FIXED_TIME }, client_options: { max_retries: 0 })

      assert_equal 1, status
      assert_empty out.string
      assert_equal expected, JSON.parse(err.string)
      refute_match(/CANARY|private|https?:|bundle-|profile-|cert-/i, err.string)
    end
  end

  def test_unknown_api_exception_remains_generic_and_does_not_expose_stage_or_exception
    transport = SigningInventoryFixtureTransport.new do |_uri, _|
      raise RuntimeError, "EXCEPTION_CANARY https://private.invalid/bundle-app-private"
    end
    out = StringIO.new
    err = StringIO.new

    status = implementation.run_cli([HELPER_PATH], env: cli_env, out: out, err: err,
      transport: transport, clock: -> { FIXED_TIME }, client_options: { max_retries: 0 })

    assert_equal 1, status
    assert_empty out.string
    assert_equal({ "code" => "SIGNING_INVENTORY_FAILED" }, JSON.parse(err.string))
    refute_match(/stage|CANARY|private|https?:/i, err.string)
  end

  def test_workflow_keeps_tests_secretless_and_credentials_in_one_protected_get_only_job
    doc = workflow
    assert_empty doc.fetch("permissions")
    jobs = doc.fetch("jobs")
    assert_equal %w[inventory test-probe], jobs.keys.sort
    probe = jobs.fetch("test-probe")
    refute_match(/secrets\./, probe.to_yaml)
    assert_includes probe.fetch("steps").last.fetch("run"),
      "ruby test/ci/ios_baseline_signing_inventory_test.rb .asc-trusted-source/scripts/ios_baseline_release.rb"

    job = jobs.fetch("inventory")
    assert_equal "${{ github.ref == 'refs/heads/main' && github.repository == 'maikrais98/hiddify-app' }}", job.fetch("if")
    assert_equal "release-publish", job.fetch("environment")
    assert_equal "test-probe", job.fetch("needs")
    assert_equal({ "contents" => "read" }, job.fetch("permissions"))
    refute job.key?("env")
    steps = job.fetch("steps")
    assert_equal "${{ vars.RELEASE_ENVIRONMENT_READY }}",
      steps.first.fetch("env").fetch("RELEASE_ENVIRONMENT_READY")
    credential_steps = steps.select { |step| step.to_yaml.include?("secrets.") }
    assert_equal 1, credential_steps.length
    assert_equal %w[APPSTORE_API_KEY_ID APPSTORE_API_PRIVATE_KEY APPSTORE_ISSUER_ID],
      credential_steps.first.fetch("env").keys.sort
    assert_includes credential_steps.first.fetch("run"), "umask 077"
    commands = steps.select { |step| step.key?("run") }.map { |step| step.fetch("run") }.join("\n")
    refute_match(/POST|PATCH|DELETE|create|revoke|upload|xcodebuild|altool/i, commands)
  end

  def test_workflow_pins_helper_actions_checkout_and_safe_receipt
    doc = workflow
    doc.fetch("jobs").each_value do |job|
      checkout = job.fetch("steps").select { |step| step["uses"] ==
        "actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803" }
      assert_equal 2, checkout.length
      assert_equal "${{ github.sha }}", checkout.first.fetch("with").fetch("ref")
      assert_equal implementation::TRUSTED_HELPER_SOURCE_SHA, checkout.last.fetch("with").fetch("ref")
      checkout.each do |step|
        assert_equal false, step.fetch("with").fetch("persist-credentials")
        assert_equal 1, step.fetch("with").fetch("fetch-depth")
      end
      verify = job.fetch("steps").find { |step| step["name"] == "Verify pinned API helper" }
      assert_includes verify.fetch("run"), implementation::TRUSTED_HELPER_SHA256
      job.fetch("steps").select { |step| step.key?("uses") }.each do |step|
        assert_match(/@[0-9a-f]{40}\z/, step.fetch("uses"))
      end
    end

    steps = doc.fetch("jobs").fetch("inventory").fetch("steps")
    artifact = steps.find { |step| step["uses"].to_s.start_with?("actions/upload-artifact@") }
    assert_equal "ios-baseline-signing-inventory", artifact.fetch("with").fetch("name")
    assert_equal "ios-baseline-signing-inventory.json", artifact.fetch("with").fetch("path")
    assert_equal 7, artifact.fetch("with").fetch("retention-days")
    assert_equal "success()", artifact.fetch("if")
  end

  private

  def failing_transport(*selectors)
    selected_failure_transport do |uri|
      http_failure(uri, 404) if selectors.any? { |selector| selected?(uri, selector) }
    end
  end

  def selected_failure_transport(failures = nil, &block)
    successful = successful_transport
    responder = successful.instance_variable_get(:@responder)
    SigningInventoryFixtureTransport.new do |uri, request_number|
      failure = if block
                  block.call(uri)
                else
                  match = failures.find { |selector, _value| selected?(uri, selector) }
                  match && match.fetch(1).call(uri)
                end
      failure || responder.call(uri, request_number)
    end
  end

  def selected?(uri, selector)
    return uri.path == selector unless selector.is_a?(Array)

    query = URI.decode_www_form(uri.query.to_s).to_h
    uri.path == selector.fetch(0) && query["filter[identifier]"] == selector.fetch(1)
  end

  def http_failure(uri, status)
    IOSBaselineRelease::Response.new(
      status: status,
      headers: { "private" => "HEADER_CANARY" },
      body: "BODY_CANARY https://private.invalid#{uri.path}"
    )
  end

  def fixture_client(transport)
    IOSBaselineRelease::Client.new(
      transport: implementation::GetOnlyTransport.new(transport),
      token_provider: -> { "fixture-token" },
      sleeper: ->(_seconds) {},
      max_retries: 0
    )
  end

  def certificate_path
    "/v1/certificates?" + URI.encode_www_form(
      "filter[certificateType]" => CERTIFICATE_TYPES_FILTER,
      "fields[certificates]" => CERTIFICATE_FIELDS,
      "limit" => 200
    )
  end

  def cli_env
    {
      "APPSTORE_ISSUER_ID" => "fixture-issuer",
      "APPSTORE_API_KEY_ID" => "FIXTUREKEY",
      "APPSTORE_API_PRIVATE_KEY" => OpenSSL::PKey::EC.generate("prime256v1").to_pem
    }
  end

  def workflow
    assert File.file?(WORKFLOW), "signing inventory workflow is missing"
    YAML.safe_load(File.read(WORKFLOW))
  end
end
