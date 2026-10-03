# frozen_string_literal: true

require "json"
require "digest"
require "minitest/autorun"
require "openssl"
require "stringio"

require_relative "../../scripts/ios_baseline_identity_inventory"

class IosBaselineIdentityInventoryTest < Minitest::Test
  Response = Struct.new(:code, :body, keyword_init: true)

  class GetOnlyTransport
    attr_reader :requests

    def initialize(responses)
      @responses = responses.transform_values(&:dup)
      @requests = []
    end

    def get(uri, headers:)
      @requests << { method: "GET", uri: uri.to_s, authorization: headers.fetch("Authorization") }
      queue = @responses.fetch(uri.to_s) { raise "unexpected request" }
      raise "response queue exhausted" if queue.empty?

      queue.shift
    end
  end

  def test_collects_only_safe_read_only_inventory_and_follows_same_origin_pagination
    transport = GetOnlyTransport.new(
      bundle_url("com.womaninred.baseline") => [json_response(bundle_page(
        [],
        "https://api.appstoreconnect.apple.com/v1/bundleIds?cursor=app-page-2"
      ))],
      "https://api.appstoreconnect.apple.com/v1/bundleIds?cursor=app-page-2" => [
        json_response(bundle_page([bundle("candidate-app-resource", "com.womaninred.baseline")]))
      ],
      bundle_url("com.womaninred.baseline.HiddifyPacketTunnel") => [
        json_response(bundle_page([bundle("candidate-extension-resource", "com.womaninred.baseline.HiddifyPacketTunnel")]))
      ],
      bundle_url("com.womaninred.app") => [
        json_response(bundle_page([bundle("old-app-resource", "com.womaninred.app", seed_id: "M9D72QQJ79")]))
      ],
      apps_url("com.womaninred.baseline") => [
        json_response(data: [{ type: "apps", id: "app-store-resource", attributes: { bundleId: "com.womaninred.baseline", name: "private-name" } }])
      ],
      capability_url("candidate-app-resource") => [
        json_response(data: [{ type: "bundleIdCapabilities", id: "capability-resource", attributes: { capabilityType: "APP_GROUPS", settings: [{ key: "SECRET_SETTING" }] } }])
      ],
      capability_url("candidate-extension-resource") => [
        json_response(data: [{ type: "bundleIdCapabilities", id: "capability-resource-2", attributes: { capabilityType: "NETWORK_EXTENSIONS" } }])
      ],
      profiles_url("candidate-app-resource") => [
        json_response(data: [profile("ACTIVE", "IOS_APP_STORE", "2030-01-02T03:04:05Z")])
      ],
      profiles_url("candidate-extension-resource") => [
        json_response(data: [profile("INVALID", "IOS_APP_DEVELOPMENT", "2029-01-02T03:04:05Z")])
      ]
    )

    result = inventory(transport).collect
    encoded = JSON.generate(result)

    assert_equal "OK", result.fetch("status")
    assert_equal "REGISTERED", result.dig("identities", "app", "bundle_id", "status")
    assert_equal "REGISTERED", result.dig("identities", "extension", "bundle_id", "status")
    assert_equal ["APP_GROUPS"], result.dig("identities", "app", "capabilities")
    assert_equal({ "ACTIVE" => 1 }, result.dig("identities", "app", "profiles", "states"))
    assert_equal "REGISTERED", result.dig("app_store_record", "status")
    assert_equal "UNSUPPORTED_BY_API", result.dig("app_group", "status")
    assert_equal "group.com.womaninred.baseline", result.dig("app_group", "identifier")
    assert_equal "VERIFIED", result.dig("team", "status")
    assert_equal "M9D72QQJ79", result.dig("team", "observed_id")
    assert_equal true, result.dig("team", "match_to_previous_team")
    assert_equal "UNVERIFIED", result.dig("team", "candidate_assignment")
    assert_equal 1, result.dig("team", "old_bundle_id_registered_count")
    assert transport.requests.all? { |request| request.fetch(:method) == "GET" }
    assert transport.requests.all? { |request| request.fetch(:authorization) == "Bearer test-token" }

    %w[
      candidate-app-resource candidate-extension-resource old-app-resource app-store-resource
      capability-resource profile-uuid profile-body@example.com PRIVATE_PROFILE_BODY
      private-name SECRET_SETTING
    ].each do |forbidden|
      refute_includes encoded, forbidden
    end
  end

  def test_reports_unregistered_candidates_without_claiming_global_availability
    transport = GetOnlyTransport.new(
      bundle_url("com.womaninred.baseline") => [json_response(data: [])],
      bundle_url("com.womaninred.baseline.HiddifyPacketTunnel") => [json_response(data: [])],
      bundle_url("com.womaninred.app") => [json_response(data: [])],
      apps_url("com.womaninred.baseline") => [json_response(data: [])]
    )

    result = inventory(transport).collect

    assert_equal "UNREGISTERED", result.dig("identities", "app", "bundle_id", "status")
    assert_equal "UNREGISTERED", result.dig("identities", "extension", "bundle_id", "status")
    assert_equal "UNVERIFIED", result.dig("identities", "app", "bundle_id", "global_availability")
    refute result.dig("identities", "app", "bundle_id").key?("globally_available")
    assert_equal "PENDING_CREATE_ATTEMPT", result.dig("identities", "app", "bundle_id", "availability_evidence")
    assert_equal "UNVERIFIED", result.dig("team", "status")
  end

  def test_does_not_verify_team_when_old_bundle_seed_is_absent_or_different
    [nil, "AAAAAAAAAA"].each do |seed_id|
      old_bundle = bundle("old-app-resource", "com.womaninred.app", seed_id: seed_id)
      transport = GetOnlyTransport.new(
        bundle_url("com.womaninred.baseline") => [json_response(data: [])],
        bundle_url("com.womaninred.baseline.HiddifyPacketTunnel") => [json_response(data: [])],
        bundle_url("com.womaninred.app") => [json_response(data: [old_bundle])],
        apps_url("com.womaninred.baseline") => [json_response(data: [])]
      )

      result = inventory(transport).collect

      assert_equal "UNVERIFIED", result.dig("team", "status")
      assert_equal false, result.dig("team", "match_to_previous_team")
      assert_equal "UNVERIFIED", result.dig("team", "candidate_assignment")
    end
  end

  def test_fails_closed_on_non_success_status_without_leaking_response_body
    transport = GetOnlyTransport.new(
      bundle_url("com.womaninred.baseline") => [
        Response.new(code: "403", body: '{"errors":[{"detail":"secret@example.com key-material"}]}')
      ]
    )

    error = assert_raises(AppleIdentityInventory::SafeError) { inventory(transport).collect }

    assert_equal "HTTP_STATUS_403", error.code
    refute_includes error.message, "secret@example.com"
    refute_includes error.message, "key-material"
  end

  def test_fails_closed_on_malformed_json
    transport = GetOnlyTransport.new(
      bundle_url("com.womaninred.baseline") => [Response.new(code: "200", body: "private malformed response")]
    )

    error = assert_raises(AppleIdentityInventory::SafeError) { inventory(transport).collect }

    assert_equal "MALFORMED_RESPONSE", error.code
    refute_includes error.message, "private malformed response"
  end

  def test_rejects_foreign_or_non_https_pagination_links
    [
      "https://example.invalid/v1/bundleIds?cursor=secret",
      "http://api.appstoreconnect.apple.com/v1/bundleIds?cursor=secret",
      "https://api.appstoreconnect.apple.com/not-v1/bundleIds?cursor=secret"
    ].each do |next_link|
      transport = GetOnlyTransport.new(
        bundle_url("com.womaninred.baseline") => [json_response(bundle_page([], next_link))]
      )

      error = assert_raises(AppleIdentityInventory::SafeError) { inventory(transport).collect }
      assert_equal "UNSAFE_PAGINATION_LINK", error.code
    end
  end

  def test_rejects_pagination_loops_and_excessive_page_counts
    first_url = bundle_url("com.womaninred.baseline")
    loop_transport = GetOnlyTransport.new(
      first_url => [json_response(bundle_page([], first_url))]
    )

    error = assert_raises(AppleIdentityInventory::SafeError) { inventory(loop_transport).collect }
    assert_equal "PAGINATION_LOOP", error.code

    responses = {}
    current = first_url
    51.times do |index|
      following = "https://api.appstoreconnect.apple.com/v1/bundleIds?cursor=page-#{index + 1}"
      responses[current] = [json_response(bundle_page([], following))]
      current = following
    end
    error = assert_raises(AppleIdentityInventory::SafeError) do
      inventory(GetOnlyTransport.new(responses)).collect
    end
    assert_equal "PAGINATION_LIMIT", error.code
  end

  def test_cli_emits_only_a_safe_error_code
    output = StringIO.new

    exit_code = AppleIdentityInventory::CLI.run(
      env: {
        "APPSTORE_ISSUER_ID" => "issuer-secret",
        "APPSTORE_API_KEY_ID" => "key-secret"
      },
      out: output
    )

    assert_equal 1, exit_code
    assert_equal({ "schema" => "ios-baseline-identity-inventory/v1", "status" => "FAILED", "error_code" => "MISSING_CREDENTIALS" }, JSON.parse(output.string))
    refute_includes output.string, "issuer-secret"
    refute_includes output.string, "key-secret"
  end

  def test_token_provider_creates_an_es256_jwt_without_exposing_key_material
    private_key = OpenSSL::PKey::EC.generate("prime256v1").to_pem
    token = AppleIdentityInventory::TokenProvider.new(
      issuer_id: "issuer-id",
      key_id: "key-id",
      private_key: private_key,
      clock: -> { 1_700_000_000 }
    ).call

    header_segment, payload_segment, signature_segment = token.split(".")
    header = JSON.parse(base64url_decode(header_segment))
    payload = JSON.parse(base64url_decode(payload_segment))

    assert_equal({ "alg" => "ES256", "kid" => "key-id", "typ" => "JWT" }, header)
    assert_equal "issuer-id", payload.fetch("iss")
    assert_equal "appstoreconnect-v1", payload.fetch("aud")
    assert_equal 1_700_000_000, payload.fetch("iat")
    assert_equal 1_700_001_100, payload.fetch("exp")
    assert_equal 64, base64url_decode(signature_segment).bytesize
    refute_includes token, private_key
  end

  def test_workflow_is_protected_pinned_and_verifies_the_script_before_exposing_secrets
    root = File.expand_path("../..", __dir__)
    workflow = File.read(File.join(root, ".github/workflows/ios-baseline-inventory.yml"))
    script_digest = Digest::SHA256.file(File.join(root, "scripts/ios_baseline_identity_inventory.rb")).hexdigest

    assert_includes workflow, "sourceSHA:"
    assert_includes workflow, "environment: release-publish"
    assert_includes workflow, "RELEASE_ENVIRONMENT_READY"
    assert_includes workflow, "runs-on: macos-15"
    assert_includes workflow, "permissions: {}"
    assert_includes workflow, "contents: read"
    assert_includes workflow, "actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803"
    assert_includes workflow, "persist-credentials: false"
    assert_includes workflow, "actions/upload-artifact@b7c566a772e6b6bfb58ed0dc250532a479d7789f"
    assert_includes workflow, "name: ios-baseline-identity-inventory"
    assert_includes workflow, script_digest
    assert_includes workflow, "ruby test/ci/ios_baseline_identity_inventory_test.rb"
    assert_includes workflow, "needs: test-source"
    assert_includes workflow, "id: read-inventory"
    assert_includes workflow, "if: ${{ always() && (steps.read-inventory.outcome == 'success' || steps.read-inventory.outcome == 'failure') }}"
    refute_includes workflow, "pull_request_target"

    digest_position = workflow.index("Verify trusted inventory script")
    secret_position = workflow.index("APPSTORE_API_PRIVATE_KEY: ${{ secrets.APPSTORE_API_PRIVATE_KEY }}")
    refute_nil digest_position
    refute_nil secret_position
    assert_operator digest_position, :<, secret_position
  end

  private

  def inventory(transport)
    AppleIdentityInventory::Inventory.new(transport: transport, token_provider: -> { "test-token" })
  end

  def json_response(payload)
    Response.new(code: "200", body: JSON.generate(payload))
  end

  def bundle(type_id, identifier, seed_id: nil)
    attributes = { identifier: identifier, name: "private bundle name" }
    attributes[:seedId] = seed_id if seed_id
    { type: "bundleIds", id: type_id, attributes: attributes }
  end

  def bundle_page(data, next_link = nil)
    payload = { data: data }
    payload[:links] = { next: next_link } if next_link
    payload
  end

  def profile(state, profile_type, expiration_date)
    {
      type: "profiles",
      id: "profile-resource",
      attributes: {
        name: "private profile name",
        profileState: state,
        profileType: profile_type,
        expirationDate: expiration_date,
        uuid: "profile-uuid",
        profileContent: "PRIVATE_PROFILE_BODY",
        email: "profile-body@example.com"
      }
    }
  end

  def bundle_url(identifier)
    "https://api.appstoreconnect.apple.com/v1/bundleIds?fields%5BbundleIds%5D=identifier%2CseedId&filter%5Bidentifier%5D=#{identifier}&limit=200"
  end

  def apps_url(identifier)
    "https://api.appstoreconnect.apple.com/v1/apps?fields%5Bapps%5D=bundleId&filter%5BbundleId%5D=#{identifier}&limit=200"
  end

  def capability_url(resource_id)
    "https://api.appstoreconnect.apple.com/v1/bundleIds/#{resource_id}/bundleIdCapabilities?fields%5BbundleIdCapabilities%5D=capabilityType&limit=200"
  end

  def profiles_url(resource_id)
    "https://api.appstoreconnect.apple.com/v1/bundleIds/#{resource_id}/profiles?fields%5Bprofiles%5D=expirationDate%2CprofileState%2CprofileType&limit=200"
  end

  def base64url_decode(value)
    value += "=" * ((4 - value.length % 4) % 4)
    value.tr("-_", "+/").unpack1("m0")
  end
end
