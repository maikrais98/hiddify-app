# frozen_string_literal: true

helper_argument = ARGV.first
ARGV.shift if helper_argument && !helper_argument.start_with?("-")

require "base64"
require "digest"
require "json"
require "minitest/autorun"
require "openssl"
require "open3"
require "stringio"
require "fileutils"
require "tmpdir"
require "uri"

HELPER_PATH = helper_argument || ENV["TEST_ONLY_IOS_BASELINE_HELPER_PATH"]
abort "helper path argument is required" unless HELPER_PATH
abort "helper fixture hash mismatch" unless Digest::SHA256.file(HELPER_PATH).hexdigest ==
  "13cd9ed9688c4fec9e346bd12c845eac72616b823b57760535f5f667b6d8a38c"
require File.realpath(HELPER_PATH)

SCRIPT = File.expand_path("../../scripts/ios_baseline_signing_bootstrap.rb", __dir__)
require SCRIPT if File.file?(SCRIPT)

class SigningBootstrapFixtureTransport
  attr_reader :requests

  def initialize(&responder)
    @responder = responder
    @requests = []
  end

  def request(method:, url:, headers:, body:, timeouts:)
    request = { method: method, uri: URI(url), headers: headers, body: body, timeouts: timeouts }
    @requests << request
    payload = @responder.call(request, @requests.length)
    return payload if payload.is_a?(IOSBaselineRelease::Response)

    IOSBaselineRelease::Response.new(status: 200, headers: {}, body: JSON.generate(payload))
  end
end

class IOSBaselineSigningBootstrapTest < Minitest::Test
  FIXED_TIME = Time.utc(2026, 10, 15, 12, 34, 56)
  TEAM_ID = "M9D72QQJ79"
  APP_BUNDLE = "com.womaninred.baseline"
  EXTENSION_BUNDLE = "com.womaninred.baseline.HiddifyPacketTunnel"
  APP_GROUP = "group.com.womaninred.baseline"
  KEY = OpenSSL::PKey::RSA.new(3072)
  CSR = begin
    value = OpenSSL::X509::Request.new
    value.version = 0
    value.subject = OpenSSL::X509::Name.new([
      ["O", "Blizzard", OpenSSL::ASN1::UTF8STRING],
      ["OU", "Release Engineering", OpenSSL::ASN1::UTF8STRING],
      ["CN", "Blizzard iOS Baseline Distribution", OpenSSL::ASN1::UTF8STRING]
    ])
    value.public_key = KEY.public_key
    value.sign(KEY, OpenSSL::Digest::SHA256.new)
    value.to_pem
  end
  SPKI = Digest::SHA256.hexdigest(KEY.public_key.to_der)
  MANIFEST = {
    "schema" => "ios-baseline-signing-request/v1",
    "createdAt" => "2026-10-15T12:00:00Z",
    "subject" => {
      "commonName" => "Blizzard iOS Baseline Distribution",
      "organization" => "Blizzard",
      "organizationalUnit" => "Release Engineering"
    },
    "keyAlgorithm" => { "name" => "RSA", "bits" => 3072 },
    "spkiSHA256" => SPKI,
    "csrSHA256" => Digest::SHA256.hexdigest(CSR),
    "csrFile" => "request.csr.pem"
  }.freeze

  def setup
    @checkpoint_directory = nil
  end

  def implementation
    assert Object.const_defined?(:IOSBaselineSigningBootstrap), "signing bootstrap implementation is missing"
    IOSBaselineSigningBootstrap
  end

  def certificate(key: KEY, team: TEAM_ID, cloud: false, expired: false,
    common_name: "Apple Distribution: Blizzard (#{team})")
    signing_key = OpenSSL::PKey::RSA.new(2048)
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = 42
    certificate.subject = OpenSSL::X509::Name.parse(
      "/CN=#{common_name}/OU=#{team}/O=Blizzard"
    )
    certificate.issuer = certificate.subject
    certificate.public_key = key.public_key
    certificate.not_before = FIXED_TIME - 60
    certificate.not_after = expired ? FIXED_TIME - 1 : FIXED_TIME + 86_400
    certificate.add_extension(OpenSSL::X509::Extension.new("1.2.840.113635.100.6.1.4", "DER:05:00"))
    if cloud
      certificate.add_extension(OpenSSL::X509::Extension.new("1.2.840.113635.100.6.1.32", "DER:05:00"))
    end
    certificate.sign(signing_key, OpenSSL::Digest::SHA256.new)
    certificate
  end

  def distribution_certificate
    @distribution_certificate ||= certificate
  end

  def cert_resource(id: "certificate-id", certificate: distribution_certificate, type: "DISTRIBUTION")
    {
      "type" => "certificates", "id" => id,
      "attributes" => {
        "certificateType" => type,
        "expirationDate" => certificate.not_after.utc.iso8601,
        "certificateContent" => Base64.strict_encode64(certificate.to_der),
        "privateCanary" => "CERTIFICATE_SECRET_CANARY"
      }
    }
  end

  def bundle_resource(id, identifier)
    { "type" => "bundleIds", "id" => id,
      "attributes" => { "identifier" => identifier, "name" => "BUNDLE_SECRET_CANARY" } }
  end

  def profile_name(role)
    implementation.profile_name(role, SPKI)
  end

  def profile_hash(role, certificate_der: distribution_certificate.to_der, grants: nil, team: TEAM_ID,
    aps: role == :app ? "production" : nil)
    bundle = role == :app ? APP_BUNDLE : EXTENSION_BUNDLE
    network_extensions = grants || (role == :app ?
      %w[app-proxy-provider dns-proxy packet-tunnel-provider] :
      %w[app-proxy-provider content-filter-provider dns-proxy packet-tunnel-provider])
    {
      "UUID" => "PROFILE-#{role.to_s.upcase}-UUID",
      "TeamIdentifier" => [team],
      "ExpirationDate" => FIXED_TIME + 86_400,
      "Entitlements" => {
        "application-identifier" => "#{team}.#{bundle}",
        "com.apple.developer.team-identifier" => team,
        "get-task-allow" => false,
        "beta-reports-active" => true,
        "com.apple.security.application-groups" => [APP_GROUP],
        "com.apple.developer.networking.networkextension" => network_extensions,
        "com.apple.developer.networking.vpn.api" => ["allow-vpn"],
        "aps-environment" => aps
      }.compact,
      "DeveloperCertificates" => [certificate_der]
    }
  end

  def profile_resource(role, id: "profile-#{role}", certificate_der: distribution_certificate.to_der,
    grants: nil, team: TEAM_ID, aps: role == :app ? "production" : nil)
    fingerprint = Digest::SHA256.hexdigest([team, grants, aps, certificate_der].flatten.join("|"))[0, 12]
    content = "CMS:#{role}:#{id}:#{fingerprint}"
    @decoded_profiles ||= {}
    @decoded_profiles[content] = profile_hash(role, certificate_der: certificate_der, grants: grants,
      team: team, aps: aps)
    {
      "type" => "profiles", "id" => id,
      "attributes" => {
        "name" => profile_name(role),
        "profileType" => "IOS_APP_STORE",
        "profileState" => "ACTIVE",
        "expirationDate" => (FIXED_TIME + 86_400).iso8601,
        "profileContent" => Base64.strict_encode64(content),
        "privateCanary" => "PROFILE_SECRET_CANARY"
      }
    }
  end

  def page(data, next_url: nil, total: data.length)
    { "data" => data, "links" => { "next" => next_url }, "meta" => { "paging" => { "total" => total } } }
  end

  def successful_transport(existing_certificate: nil, app_profiles: [], extension_profiles: [], post_failure: nil)
    selected_certificate = existing_certificate || cert_resource
    SigningBootstrapFixtureTransport.new do |request, _number|
      uri = request.fetch(:uri)
      query = URI.decode_www_form(uri.query.to_s).to_h
      if request.fetch(:method) == "GET"
        case uri.path
        when "/v1/certificates"
          page(existing_certificate ? [existing_certificate] : [])
        when "/v1/bundleIds"
          identifier = query.fetch("filter[identifier]")
          id = identifier == APP_BUNDLE ? "bundle-app" : "bundle-extension"
          page([bundle_resource(id, identifier)])
        when "/v1/bundleIds/bundle-app/profiles"
          page(app_profiles)
        when "/v1/bundleIds/bundle-extension/profiles"
          page(extension_profiles)
        else
          raise "unexpected GET #{uri}"
        end
      else
        body = JSON.parse(request.fetch(:body))
        role = if uri.path == "/v1/certificates"
                 :certificate
               elsif body.dig("data", "relationships", "bundleId", "data", "id") == "bundle-app"
                 :app
               else
                 :extension
               end
        raise Timeout::Error, "POST_SECRET_CANARY" if post_failure == role
        case uri.path
        when "/v1/certificates"
          resource = selected_certificate
          resource.merge("attributes" => resource.fetch("attributes").merge(
            "certificateContent" => Base64.strict_encode64(distribution_certificate.to_der)
          ))
          { "data" => resource }
        when "/v1/profiles"
          { "data" => profile_resource(role, id: "created-profile-#{role}",
            certificate_der: distribution_certificate.to_der) }
        else
          raise "unexpected POST #{uri}"
        end
      end
    end
  end

  def runner(transport, mode:, manifest: MANIFEST, env: create_env)
    client = IOSBaselineRelease::Client.new(
      transport: implementation::RestrictedTransport.new(transport),
      token_provider: begin
        count = 0
        -> { count += 1; "fresh-token-#{count}" }
      end,
      sleeper: ->(_seconds) { flunk "bootstrap requests must never retry" },
      max_retries: 0
    )
    implementation::Bootstrap.new(client: client, clock: -> { FIXED_TIME }, profile_decoder: fixture_decoder)
      .run(mode: mode, csr_pem: CSR, manifest: manifest, env: env)
  end

  def fixture_decoder
    decoder = Object.new
    decoded_profiles = @decoded_profiles ||= {}
    decoder.define_singleton_method(:decode) { |cms| decoded_profiles.fetch(cms) }
    decoder
  end

  def create_env
    @checkpoint_directory ||= Dir.mktmpdir("signing-bootstrap-checkpoint")
    path = File.join(@checkpoint_directory, "intent.json")
    unless File.file?(path)
      request = implementation::Request.load(CSR, MANIFEST)
      File.binwrite(path, JSON.generate(implementation.checkpoint(request, clock: -> { FIXED_TIME })) + "\n")
    end
    {
      "IOS_SIGNING_CREATE_AUTHORIZED" => "true",
      "IOS_SIGNING_INTENT_ID" => implementation.intent_id(MANIFEST),
      "IOS_SIGNING_CHECKPOINT_PATH" => path,
      "IOS_SIGNING_CHECKPOINT_SHA256" => Digest::SHA256.file(path).hexdigest,
      "GITHUB_EVENT_NAME" => "workflow_dispatch",
      "GITHUB_REF" => "refs/heads/main",
      "GITHUB_REPOSITORY" => "maikrais98/hiddify-app",
      "GITHUB_RUN_ATTEMPT" => "1"
    }
  end

  def teardown
    FileUtils.remove_entry_secure(@checkpoint_directory) if @checkpoint_directory && File.directory?(@checkpoint_directory)
  end

  def test_request_validation_rejects_manifest_hash_spki_subject_signature_and_key_size_before_api
    cases = []
    cases << MANIFEST.merge("csrSHA256" => "0" * 64)
    cases << MANIFEST.merge("spkiSHA256" => "1" * 64)
    cases << MANIFEST.merge("subject" => MANIFEST.fetch("subject").merge("commonName" => "Personal Name"))
    cases.each do |manifest|
      transport = successful_transport
      assert_raises(implementation::SafeError) { runner(transport, mode: "plan", manifest: manifest, env: {}) }
      assert_empty transport.requests
    end

    small_key = OpenSSL::PKey::RSA.new(2048)
    small_csr = OpenSSL::X509::Request.new
    small_csr.version = 0
    small_csr.subject = OpenSSL::X509::Request.new(CSR).subject
    small_csr.public_key = small_key.public_key
    small_csr.sign(small_key, OpenSSL::Digest::SHA256.new)
    error = assert_raises(implementation::SafeError) do
      implementation::Request.new(small_csr.to_pem,
        MANIFEST.merge("csrSHA256" => Digest::SHA256.hexdigest(small_csr.to_pem),
          "spkiSHA256" => Digest::SHA256.hexdigest(small_key.public_key.to_der))).validate!
    end
    assert_equal "REQUEST_KEY_INVALID", error.code

    wrong_subject = OpenSSL::X509::Request.new
    wrong_subject.version = 0
    wrong_subject.subject = OpenSSL::X509::Name.parse("/O=Blizzard/OU=Release Engineering/CN=Personal Name")
    wrong_subject.public_key = KEY.public_key
    wrong_subject.sign(KEY, OpenSSL::Digest::SHA256.new)
    wrong_subject_pem = wrong_subject.to_pem
    wrong_subject_manifest = MANIFEST.merge("csrSHA256" => Digest::SHA256.hexdigest(wrong_subject_pem))
    error = assert_raises(implementation::SafeError) do
      implementation::Request.load(wrong_subject_pem, wrong_subject_manifest)
    end
    assert_equal "REQUEST_CSR_SUBJECT_INVALID", error.code

    other_key = OpenSSL::PKey::RSA.new(3072)
    wrong_signature = OpenSSL::X509::Request.new
    wrong_signature.version = 0
    wrong_signature.subject = OpenSSL::X509::Request.new(CSR).subject
    wrong_signature.public_key = KEY.public_key
    wrong_signature.sign(other_key, OpenSSL::Digest::SHA256.new)
    wrong_signature_pem = wrong_signature.to_pem
    wrong_signature_manifest = MANIFEST.merge(
      "csrSHA256" => Digest::SHA256.hexdigest(wrong_signature_pem),
      "spkiSHA256" => Digest::SHA256.hexdigest(wrong_signature.public_key.to_der)
    )
    error = assert_raises(implementation::SafeError) do
      implementation::Request.load(wrong_signature_pem, wrong_signature_manifest)
    end
    assert_equal "REQUEST_CSR_SIGNATURE_INVALID", error.code

    request_info = OpenSSL::ASN1.decode(OpenSSL::X509::Request.new(CSR).to_der).value.fetch(0)
    assert_equal SPKI, Digest::SHA256.hexdigest(request_info.value.fetch(2).to_der)
  end

  def test_plan_is_get_only_and_reports_three_missing_resources
    transport = successful_transport
    result = runner(transport, mode: "plan", env: {})

    assert_equal "PLAN_CREATE_CERTIFICATE_AND_PROFILES", result.fetch("code")
    assert_equal %w[certificate appProfile extensionProfile], result.fetch("missing")
    assert transport.requests.all? { |request| request.fetch(:method) == "GET" }
    refute_includes JSON.generate(result), "SECRET_CANARY"
  end

  def test_create_posts_exactly_one_certificate_and_two_profiles_with_allowed_bodies_and_fresh_jwt
    transport = successful_transport
    result = runner(transport, mode: "create")

    assert_equal "SIGNING_BOOTSTRAP_READY", result.fetch("code")
    posts = transport.requests.select { |request| request.fetch(:method) == "POST" }
    assert_equal ["/v1/certificates", "/v1/profiles", "/v1/profiles"],
      posts.map { |request| request.fetch(:uri).path }
    cert_body = JSON.parse(posts.first.fetch(:body))
    assert_equal "DISTRIBUTION", cert_body.dig("data", "attributes", "certificateType")
    assert_equal CSR, cert_body.dig("data", "attributes", "csrContent")
    posts.drop(1).each do |request|
      body = JSON.parse(request.fetch(:body))
      assert_equal "IOS_APP_STORE", body.dig("data", "attributes", "profileType")
      assert_equal "certificate-id", body.dig("data", "relationships", "certificates", "data", 0, "id")
    end
    authorizations = transport.requests.map { |request| request.dig(:headers, "Authorization") }
    assert_equal authorizations.length, authorizations.uniq.length
    assert_equal distribution_certificate.to_der, result.fetch("certificateDER")
    assert_equal %i[app extension], result.fetch("profiles").keys.sort
  end

  def test_plan_resume_and_create_reuse_proven_material_without_posts
    cert = cert_resource
    app = profile_resource(:app, certificate_der: distribution_certificate.to_der)
    extension = profile_resource(:extension, certificate_der: distribution_certificate.to_der)
    %w[plan resume create].each do |mode|
      transport = successful_transport(existing_certificate: cert, app_profiles: [app],
        extension_profiles: [extension])
      result = runner(transport, mode: mode, env: mode == "create" ? create_env : {})
      assert_equal "SIGNING_BOOTSTRAP_READY", result.fetch("code")
      assert_empty transport.requests.select { |request| request.fetch(:method) == "POST" }
    end
  end

  def test_create_gate_fails_closed_for_non_manual_non_main_or_retried_run
    create_env.each_key do |key|
      next unless %w[IOS_SIGNING_CREATE_AUTHORIZED IOS_SIGNING_INTENT_ID IOS_SIGNING_CHECKPOINT_PATH
        IOS_SIGNING_CHECKPOINT_SHA256 GITHUB_EVENT_NAME GITHUB_REF GITHUB_REPOSITORY
        GITHUB_RUN_ATTEMPT].include?(key)

      env = create_env.merge(key => "wrong")
      transport = successful_transport
      assert_raises(implementation::SafeError) { runner(transport, mode: "create", env: env) }
      assert_empty transport.requests
    end
  end

  def test_reconcile_rejects_duplicate_spki_wrong_team_cloud_or_expired_certificate
    cases = [
      [cert_resource(certificate: certificate(team: "WRONGTEAM1")), "CERTIFICATE_TEAM_MISMATCH"],
      [cert_resource(certificate: certificate(common_name: "Unrelated Certificate")),
        "CERTIFICATE_DISTRIBUTION_INVALID"],
      [cert_resource(certificate: certificate(cloud: true)), "CERTIFICATE_CLOUD_MANAGED_FORBIDDEN"],
      [cert_resource(certificate: certificate(expired: true)), "CERTIFICATE_EXPIRED"]
    ]
    cases.each do |resource, code|
      transport = successful_transport(existing_certificate: resource)
      error = assert_raises(implementation::SafeError) { runner(transport, mode: "plan", env: {}) }
      assert_equal code, error.code
    end

    duplicate = successful_transport(existing_certificate: cert_resource)
    responder = duplicate.instance_variable_get(:@responder)
    duplicate.instance_variable_set(:@responder, lambda do |request, number|
      if request.fetch(:method) == "GET" && request.fetch(:uri).path == "/v1/certificates"
        page([cert_resource(id: "one"), cert_resource(id: "two")])
      else
        responder.call(request, number)
      end
    end)
    assert_equal "CERTIFICATE_SPKI_AMBIGUOUS", assert_raises(implementation::SafeError) {
      runner(duplicate, mode: "plan", env: {})
    }.code
  end

  def test_profile_validation_rejects_wrong_team_signer_and_exact_source_grants
    cases = [
      [profile_resource(:app, team: "WRONGTEAM1"), "APP_PROFILE_TEAM_MISMATCH"],
      [profile_resource(:app, certificate_der: certificate(key: OpenSSL::PKey::RSA.new(2048)).to_der),
        "APP_PROFILE_SIGNER_MISMATCH"],
      [profile_resource(:app, grants: %w[packet-tunnel-provider]), "APP_PROFILE_NETWORK_EXTENSION_GRANTS_MISMATCH"],
      [profile_resource(:app, aps: nil), "APP_PROFILE_APS_ENVIRONMENT_REQUIRED"]
    ]
    cases.each do |app, code|
      transport = successful_transport(existing_certificate: cert_resource, app_profiles: [app])
      error = assert_raises(implementation::SafeError) { runner(transport, mode: "plan", env: {}) }
      assert_equal code, error.code
    end
  end

  def test_profile_validation_accepts_apple_grant_supersets_that_cover_every_required_source_grant
    app = profile_resource(:app,
      grants: %w[app-proxy-provider dns-proxy packet-tunnel-provider future-apple-provider])
    extension = profile_resource(:extension,
      grants: %w[app-proxy-provider content-filter-provider dns-proxy packet-tunnel-provider future-apple-provider])
    transport = successful_transport(existing_certificate: cert_resource, app_profiles: [app],
      extension_profiles: [extension])

    result = runner(transport, mode: "plan", env: {})

    assert_equal "SIGNING_BOOTSTRAP_READY", result.fetch("code")
  end

  def test_pagination_origin_path_query_and_duplicates_fail_closed
    mutations = {
      "PAGINATION_DUPLICATE" => ->(uri) { uri.to_s },
      "UNSAFE_ASC_REQUEST" => ->(uri) { uri.to_s.sub("api.appstoreconnect.apple.com", "evil.invalid") },
      "PAGINATION_ROUTE_CHANGED" => ->(uri) { uri.to_s.sub("/v1/certificates", "/v1/profiles") },
      "PAGINATION_QUERY_CHANGED" => ->(uri) { uri.to_s + "&limit=1" }
    }
    mutations.each do |code, mutate|
      transport = successful_transport
      responder = transport.instance_variable_get(:@responder)
      first = true
      transport.instance_variable_set(:@responder, lambda do |request, number|
        if first && request.fetch(:method) == "GET" && request.fetch(:uri).path == "/v1/certificates"
          first = false
          resource = cert_resource(id: "page-one")
          page([resource], next_url: mutate.call(request.fetch(:uri)), total: 2)
        else
          responder.call(request, number)
        end
      end)
      error = assert_raises(implementation::SafeError) { runner(transport, mode: "plan", env: {}) }
      assert_equal code, error.code
    end
  end

  def test_each_unknown_post_outcome_is_reconciled_once_never_reissued_and_stops
    { certificate: "/v1/certificates", app: "/v1/profiles", extension: "/v1/profiles" }.each do |action, failed_path|
      transport = successful_transport(post_failure: action)
      error = assert_raises(implementation::SafeError) { runner(transport, mode: "create") }
      assert_equal "POST_OUTCOME_UNCERTAIN", error.code
      posts = transport.requests.select { |request| request.fetch(:method) == "POST" }
      matching = posts.select do |request|
        next request.fetch(:uri).path == failed_path if action == :certificate
        body = JSON.parse(request.fetch(:body))
        bundle = body.dig("data", "relationships", "bundleId", "data", "id")
        bundle == (action == :app ? "bundle-app" : "bundle-extension")
      end
      assert_equal 1, matching.length
      assert_equal failed_path, posts.last.fetch(:uri).path
      assert_operator transport.requests.count { |request| request.fetch(:method) == "GET" }, :>=, 1
    end
  end

  def test_malformed_json_and_empty_success_post_responses_are_uncertain_and_reconciled_once
    [
      IOSBaselineRelease::Response.new(status: 201, headers: {}, body: "NOT_JSON_SECRET_CANARY"),
      IOSBaselineRelease::Response.new(status: 204, headers: {}, body: "")
    ].each do |failure_response|
      transport = successful_transport
      responder = transport.instance_variable_get(:@responder)
      transport.instance_variable_set(:@responder, lambda do |request, number|
        if request.fetch(:method) == "POST" && request.fetch(:uri).path == "/v1/certificates"
          failure_response
        else
          responder.call(request, number)
        end
      end)
      error = assert_raises(implementation::SafeError) { runner(transport, mode: "create") }
      assert_equal "POST_OUTCOME_UNCERTAIN", error.code
      assert_equal 1, transport.requests.count { |request| request.fetch(:method) == "POST" }
      assert_equal 4, transport.requests.count { |request| request.fetch(:method) == "GET" }
    end
  end

  def test_malformed_certificate_resource_after_success_is_reconciled_once_and_never_reposted
    transport = successful_transport
    responder = transport.instance_variable_get(:@responder)
    transport.instance_variable_set(:@responder, lambda do |request, number|
      if request.fetch(:method) == "POST" && request.fetch(:uri).path == "/v1/certificates"
        { "data" => { "type" => "wrong-resource", "id" => "malformed-certificate", "attributes" => {} } }
      else
        responder.call(request, number)
      end
    end)

    error = assert_raises(implementation::SafeError) { runner(transport, mode: "create") }

    assert_equal "POST_OUTCOME_UNCERTAIN", error.code
    assert_equal 1, transport.requests.count { |request| request.fetch(:method) == "POST" }
    assert_equal 2, transport.requests.count { |request|
      request.fetch(:method) == "GET" && request.fetch(:uri).path == "/v1/certificates"
    }
  end

  def test_malformed_profile_resource_after_success_is_reconciled_once_and_never_reposted
    transport = successful_transport(existing_certificate: cert_resource)
    responder = transport.instance_variable_get(:@responder)
    transport.instance_variable_set(:@responder, lambda do |request, number|
      if request.fetch(:method) == "POST" && request.fetch(:uri).path == "/v1/profiles"
        { "data" => { "type" => "wrong-resource", "id" => "malformed-profile", "attributes" => {} } }
      else
        responder.call(request, number)
      end
    end)

    error = assert_raises(implementation::SafeError) { runner(transport, mode: "create") }

    assert_equal "POST_OUTCOME_UNCERTAIN", error.code
    assert_equal 1, transport.requests.count { |request| request.fetch(:method) == "POST" }
    assert_equal 2, transport.requests.count { |request|
      request.fetch(:method) == "GET" && request.fetch(:uri).path == "/v1/bundleIds/bundle-app/profiles"
    }
  end

  def test_same_profile_resource_id_cannot_be_reused_for_both_targets
    cert = cert_resource
    app = profile_resource(:app, id: "shared-profile", certificate_der: distribution_certificate.to_der)
    extension = profile_resource(:extension, id: "shared-profile", certificate_der: distribution_certificate.to_der)
    transport = successful_transport(existing_certificate: cert, app_profiles: [app],
      extension_profiles: [extension])

    error = assert_raises(implementation::SafeError) { runner(transport, mode: "plan", env: {}) }

    assert_equal "PROFILE_ID_REUSED", error.code
  end

  def test_freshly_created_profiles_cannot_reuse_the_same_resource_id
    transport = successful_transport
    responder = transport.instance_variable_get(:@responder)
    transport.instance_variable_set(:@responder, lambda do |request, number|
      response = responder.call(request, number)
      if request.fetch(:method) == "POST" && request.fetch(:uri).path == "/v1/profiles" && response.is_a?(Hash)
        response.fetch("data")["id"] = "shared-created-profile"
      end
      response
    end)

    error = assert_raises(implementation::SafeError) { runner(transport, mode: "create") }

    assert_equal "PROFILE_ID_REUSED", error.code
    assert_equal 2, transport.requests.count { |request| request.fetch(:uri).path == "/v1/profiles" }
  end

  def test_restricted_transport_rejects_every_other_method_route_query_and_body_shape
    delegate = successful_transport
    guarded = implementation::RestrictedTransport.new(delegate)
    cert_url = "https://api.appstoreconnect.apple.com/v1/certificates?" + URI.encode_www_form(
      "filter[certificateType]" => "DISTRIBUTION,IOS_DISTRIBUTION",
      "fields[certificates]" => "certificateContent,certificateType,expirationDate",
      "limit" => "200"
    )
    failures = [
      ["PATCH", cert_url, nil],
      ["DELETE", cert_url, nil],
      ["GET", cert_url + "&include=devices", nil],
      ["POST", "https://api.appstoreconnect.apple.com/v1/bundleIds", "{}"],
      ["POST", "https://api.appstoreconnect.apple.com/v1/certificates",
        JSON.generate("data" => { "type" => "certificates", "attributes" => { "certificateType" => "DEVELOPMENT", "csrContent" => CSR } })]
    ]
    failures.each do |method, url, body|
      assert_equal "UNSAFE_ASC_REQUEST", assert_raises(implementation::SafeError) {
        guarded.request(method: method, url: url, headers: {}, body: body, timeouts: {})
      }.code
    end
    assert_empty delegate.requests
  end

  def test_cli_writes_safe_partial_receipt_on_secret_canary_failure
    Dir.mktmpdir("bootstrap-cli") do |directory|
      csr_path = File.join(directory, "request.csr.pem")
      manifest_path = File.join(directory, "request.json")
      output = File.join(directory, "output")
      File.binwrite(csr_path, CSR)
      File.binwrite(manifest_path, JSON.generate(MANIFEST))
      transport = SigningBootstrapFixtureTransport.new do |_request, _number|
        raise SocketError, "NETWORK_SECRET_CANARY https://private.invalid"
      end
      stdout = StringIO.new
      stderr = StringIO.new
      api_key = OpenSSL::PKey::EC.generate("prime256v1").to_pem
      env = {
        "APPSTORE_ISSUER_ID" => "issuer-fixture",
        "APPSTORE_API_KEY_ID" => "KEY123",
        "APPSTORE_API_PRIVATE_KEY" => api_key
      }
      status = implementation.run_cli(["plan", HELPER_PATH, csr_path, manifest_path, output],
        env: env, out: stdout, err: stderr, transport: transport, clock: -> { FIXED_TIME },
        client_options: { max_retries: 0 })

      assert_equal 1, status
      receipt = File.binread(File.join(output, "receipt.json"))
      assert_equal "FAILED", JSON.parse(receipt).fetch("status")
      [stdout.string, stderr.string, receipt].each do |text|
        refute_includes text, "SECRET_CANARY"
        refute_includes text, "private.invalid"
        refute_includes text, "fresh-token"
      end
    end
  end

  def test_prepare_writes_only_a_safe_authorized_checkpoint_and_rejects_stale_requests
    Dir.mktmpdir("bootstrap-prepare") do |directory|
      csr_path = File.join(directory, "request.csr.pem")
      manifest_path = File.join(directory, "request.json")
      output = File.join(directory, "output")
      File.binwrite(csr_path, CSR)
      File.binwrite(manifest_path, JSON.generate(MANIFEST))
      stdout = StringIO.new
      stderr = StringIO.new

      status = implementation.run_cli(["prepare", HELPER_PATH, csr_path, manifest_path, output],
        env: {}, out: stdout, err: stderr, clock: -> { FIXED_TIME })

      assert_equal 0, status
      assert_empty stderr.string
      intent = JSON.parse(File.binread(File.join(output, "intent.json")))
      assert_equal true, intent.fetch("authorized")
      assert_equal implementation.intent_id(MANIFEST), intent.fetch("intentId")
      assert_equal SPKI, intent.fetch("spkiSHA256")
      assert_equal TEAM_ID, intent.fetch("teamId")
      encoded = JSON.generate(intent)
      refute_includes encoded, "PRIVATE KEY"
      refute_includes encoded, CSR
      assert_equal "SUCCEEDED", JSON.parse(File.binread(File.join(output, "receipt.json"))).fetch("status")

      stale_output = File.join(directory, "stale-output")
      stale = MANIFEST.merge("createdAt" => "2026-10-13T12:00:00Z")
      File.binwrite(manifest_path, JSON.generate(stale))
      stderr = StringIO.new
      status = implementation.run_cli(["prepare", HELPER_PATH, csr_path, manifest_path, stale_output],
        env: {}, out: StringIO.new, err: stderr, clock: -> { FIXED_TIME })
      assert_equal 1, status
      assert_equal "CREATE_REQUEST_STALE", JSON.parse(stderr.string).fetch("code")
      assert_equal "FAILED", JSON.parse(File.binread(File.join(stale_output, "receipt.json"))).fetch("status")
    end
  end

  def test_create_unknown_outcome_writes_a_safe_partial_receipt_without_retrying
    Dir.mktmpdir("bootstrap-create-unknown") do |directory|
      csr_path = File.join(directory, "request.csr.pem")
      manifest_path = File.join(directory, "request.json")
      output = File.join(directory, "output")
      File.binwrite(csr_path, CSR)
      File.binwrite(manifest_path, JSON.generate(MANIFEST))
      transport = successful_transport(post_failure: :certificate)
      env = create_env.merge(
        "APPSTORE_ISSUER_ID" => "issuer-fixture",
        "APPSTORE_API_KEY_ID" => "KEY123",
        "APPSTORE_API_PRIVATE_KEY" => OpenSSL::PKey::EC.generate("prime256v1").to_pem
      )
      stdout = StringIO.new
      stderr = StringIO.new

      status = implementation.run_cli(["create", HELPER_PATH, csr_path, manifest_path, output],
        env: env, out: stdout, err: stderr, transport: transport, clock: -> { FIXED_TIME },
        client_options: { max_retries: 0 })

      assert_equal 1, status
      assert_empty stdout.string
      assert_equal "POST_OUTCOME_UNCERTAIN", JSON.parse(stderr.string).fetch("code")
      receipt_text = File.binread(File.join(output, "receipt.json"))
      receipt = JSON.parse(receipt_text)
      assert_equal "FAILED", receipt.fetch("status")
      assert_equal "CREATE_CERTIFICATE", receipt.fetch("stage")
      assert_equal false, receipt.fetch("outcomeReconciled")
      assert_equal 1, transport.requests.count { |request| request.fetch(:method) == "POST" }
      refute_includes receipt_text, "SECRET_CANARY"
      refute_includes receipt_text, "PRIVATE KEY"
    end
  end

  def test_extension_unknown_outcome_receipt_keeps_confirmed_certificate_and_app_profile_refs
    Dir.mktmpdir("bootstrap-extension-unknown") do |directory|
      csr_path = File.join(directory, "request.csr.pem")
      manifest_path = File.join(directory, "request.json")
      output = File.join(directory, "output")
      File.binwrite(csr_path, CSR)
      File.binwrite(manifest_path, JSON.generate(MANIFEST))
      transport = successful_transport(post_failure: :extension)
      env = create_env.merge(
        "APPSTORE_ISSUER_ID" => "issuer-fixture",
        "APPSTORE_API_KEY_ID" => "KEY123",
        "APPSTORE_API_PRIVATE_KEY" => OpenSSL::PKey::EC.generate("prime256v1").to_pem
      )

      status = implementation.run_cli(["create", HELPER_PATH, csr_path, manifest_path, output],
        env: env, out: StringIO.new, err: StringIO.new, transport: transport, clock: -> { FIXED_TIME },
        client_options: { max_retries: 0 }, profile_decoder: fixture_decoder)

      assert_equal 1, status
      receipt = JSON.parse(File.binread(File.join(output, "receipt.json")))
      confirmed = receipt.fetch("confirmed")
      assert_equal "certificate-id", confirmed.dig("certificate", "id")
      assert_match(/\A[0-9a-f]{64}\z/, confirmed.dig("certificate", "sha256"))
      assert_equal "created-profile-app", confirmed.dig("profiles", "app", "id")
      assert_match(/\A[0-9a-f]{64}\z/, confirmed.dig("profiles", "app", "sha256"))
      refute confirmed.fetch("profiles").key?("extension")
    end
  end

  def test_untrusted_helper_failure_in_a_fresh_process_is_closed_and_has_no_traceback_or_canary
    Dir.mktmpdir("bootstrap-untrusted-helper") do |directory|
      helper = File.join(directory, "helper.rb")
      File.binwrite(helper, "HELPER_SECRET_CANARY\n")
      output, process = Open3.capture2e("ruby", SCRIPT, "plan", helper, "missing.csr", "missing.json",
        File.join(directory, "output"))

      refute process.success?
      assert_equal({ "code" => "HELPER_HASH_MISMATCH" }, JSON.parse(output))
      refute_includes output, "CANARY"
      refute_includes output, "traceback"
      refute_includes output, SCRIPT
    end
  end

  def test_cli_usage_failure_is_closed_even_before_the_helper_is_loaded
    stdout = StringIO.new
    stderr = StringIO.new

    status = implementation.run_cli([], env: {}, out: stdout, err: stderr)

    assert_equal 1, status
    assert_empty stdout.string
    assert_equal({ "code" => "USAGE_ERROR" }, JSON.parse(stderr.string))

    output, process = Open3.capture2e("ruby", SCRIPT)
    refute process.success?
    assert_equal({ "code" => "USAGE_ERROR" }, JSON.parse(output))
  end
end
