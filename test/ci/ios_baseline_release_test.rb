# frozen_string_literal: true

require "json"
require "fileutils"
require "minitest/autorun"
require "openssl"
require "stringio"
require "tmpdir"
require "time"

require_relative "../../scripts/ios_baseline_release"

class IOSBaselineReleaseTest < Minitest::Test
  APP_ID = "1234567890"
  BUNDLE_ID = "com.womaninred.baseline"
  GROUP_ID = "group-existing"
  VERSION = "0.0.1"
  BUILD = "1"

  class RouteTransport
    attr_reader :requests

    def initialize(&handler)
      @handler = handler
      @requests = []
    end

    def request(**request)
      @requests << request
      @handler.call(request, @requests)
    end
  end

  class RecordingUploader
    attr_reader :calls

    def initialize(error: nil)
      @error = error
      @calls = []
    end

    def upload!(ipa:, issuer_id:, key_id:, private_key:)
      @calls << { ipa: ipa, issuer_id: issuer_id, key_id: key_id, private_key: private_key }
      raise @error if @error

      true
    end
  end

  def setup
    @key = OpenSSL::PKey::EC.generate("prime256v1").to_pem
    @base_env = {
      "APPSTORE_ISSUER_ID" => "issuer-safe",
      "APPSTORE_API_KEY_ID" => "KEYSAFE123",
      "APPSTORE_API_PRIVATE_KEY" => @key,
      "ASC_APP_ID" => APP_ID,
      "BUNDLE_ID" => BUNDLE_ID,
      "TESTER_GROUP_ID" => GROUP_ID,
      "TESTER_ID" => "self-tester-id",
      "VERSION" => VERSION,
      "BUILD_NUMBER" => BUILD,
      "POLL_ATTEMPTS" => "3",
      "POLL_INTERVAL_SECONDS" => "0"
    }
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_upload_validates_fixed_identity_and_rejects_wrong_app_before_uploader
    uploader = RecordingUploader.new
    transport = RouteTransport.new do |request, _requests|
      if request.fetch(:url).include?("/v1/apps?")
        response(data: [resource("apps", "different-app", "bundleId" => BUNDLE_ID)])
      else
        flunk("unexpected API request")
      end
    end

    error = assert_raises(IOSBaselineRelease::SafeError) do
      runner(env: upload_env, transport: transport, uploader: uploader).run("upload")
    end
    assert_equal "ASC_APP_MISMATCH", error.code
    assert_empty uploader.calls
  end

  def test_preflight_requires_requested_existing_internal_group_belonging_to_app
    uploader = RecordingUploader.new
    transport = RouteTransport.new do |request, _requests|
      case request.fetch(:url)
      when /\/v1\/apps\?/
        response(data: [resource("apps", APP_ID, "bundleId" => BUNDLE_ID)])
      when /\/v1\/betaGroups\?/
        response(data: [resource("betaGroups", "another-group", "isInternalGroup" => true)])
      else
        flunk("unexpected API request")
      end
    end

    error = assert_raises(IOSBaselineRelease::SafeError) do
      runner(env: @base_env, transport: transport, uploader: uploader).run("preflight")
    end
    assert_equal "TESTER_GROUP_MISMATCH", error.code
    assert_empty uploader.calls
    refute transport.requests.any? { |request| request.fetch(:method) == "POST" }
  end

  def test_preflight_rejects_wrong_tester_before_signing_or_upload
    uploader = RecordingUploader.new
    transport = standard_transport do |request|
      if request.fetch(:url).include?("/betaGroups/#{GROUP_ID}/betaTesters")
        response(data: [resource("betaTesters", "unexpected-tester")])
      end
    end

    error = assert_raises(IOSBaselineRelease::SafeError) do
      runner(env: @base_env, transport: transport, uploader: uploader).run("preflight")
    end
    assert_equal "TESTER_MEMBERSHIP_MISMATCH", error.code
    assert_empty uploader.calls
    refute transport.requests.any? { |request| request.fetch(:method) == "POST" }
  end

  def test_upload_rejects_existing_version_and_build_collision_before_altool
    uploader = RecordingUploader.new
    transport = standard_transport do |request|
      if request.fetch(:url).include?("/v1/preReleaseVersions?")
        response(data: [pre_release_version])
      elsif request.fetch(:url).include?("/v1/builds?")
        response(data: [build_resource])
      end
    end

    error = assert_raises(IOSBaselineRelease::SafeError) do
      runner(env: upload_env, transport: transport, uploader: uploader).run("upload")
    end
    assert_equal "BUILD_ALREADY_EXISTS", error.code
    assert_empty uploader.calls
  end

  def test_exact_build_query_rejects_mismatched_live_result
    transport = standard_transport do |request|
      if request.fetch(:url).include?("/v1/preReleaseVersions?")
        response(data: [pre_release_version])
      elsif request.fetch(:url).include?("/v1/builds?")
        response(data: [resource("builds", "wrong", "version" => "999", "processingState" => "VALID")])
      end
    end

    error = assert_raises(IOSBaselineRelease::SafeError) do
      runner(env: @base_env, transport: transport).run("status")
    end
    assert_equal "BUILD_MISMATCH", error.code
  end

  def test_status_resumes_exact_build_without_ipa_or_upload
    uploader = RecordingUploader.new
    transport = ready_transport(assigned_initially: true)

    result = runner(env: @base_env, transport: transport, uploader: uploader).run("status")

    assert_equal "TESTFLIGHT_READY", result.fetch("code")
    assert_equal VERSION, result.fetch("version")
    assert_equal BUILD, result.fetch("buildNumber")
    assert_equal "VALID", result.fetch("processingState")
    assert_equal "READY_FOR_BETA_TESTING", result.fetch("betaState")
    assert_equal true, result.fetch("assigned")
    assert_empty uploader.calls
  end

  def test_final_proof_requires_exactly_the_requested_existing_tester
    transport = standard_transport do |request|
      url = request.fetch(:url)
      if url.include?("/v1/preReleaseVersions?")
        response(data: [pre_release_version])
      elsif url.include?("/v1/builds?")
        response(data: [build_resource])
      elsif url.include?("/buildBetaDetail")
        response(data: resource("buildBetaDetails", "detail", "internalBuildState" => "READY_FOR_BETA_TESTING"))
      elsif url.include?("/betaGroups/#{GROUP_ID}/builds")
        response(data: [build_resource])
      elsif url.include?("/betaGroups/#{GROUP_ID}/betaTesters")
        response(data: [resource("betaTesters", "unexpected-tester")])
      end
    end

    error = assert_raises(IOSBaselineRelease::SafeError) do
      runner(env: @base_env, transport: transport).run("status")
    end
    assert_equal "TESTER_MEMBERSHIP_MISMATCH", error.code
    refute transport.requests.any? { |request| request.fetch(:method) == "POST" && request.fetch(:url).include?("betaTesters") }
  end

  def test_upload_uses_one_exact_ipa_then_waits_for_final_proof
    uploader = RecordingUploader.new
    preflight_complete = false
    transport = standard_transport do |request|
      url = request.fetch(:url)
      if url.include?("/v1/preReleaseVersions?")
        unless preflight_complete
          preflight_complete = true
          response(data: [])
        else
          response(data: [pre_release_version])
        end
      elsif url.include?("/v1/builds?")
        response(data: [build_resource])
      elsif url.include?("/buildBetaDetail")
        response(data: resource("buildBetaDetails", "detail", "internalBuildState" => "IN_BETA_TESTING"))
      elsif url.include?("/betaGroups/#{GROUP_ID}/builds")
        response(data: [build_resource])
      end
    end

    result = runner(env: upload_env, transport: transport, uploader: uploader).run("upload")

    assert_equal "TESTFLIGHT_READY", result.fetch("code")
    assert_equal 1, uploader.calls.length
    assert_equal File.realpath(@ipa_path), uploader.calls.first.fetch(:ipa)
  end

  def test_group_assignment_rechecks_relationship_after_uncertain_post_without_reposting
    relationship_reads = 0
    post_count = 0
    transport = standard_transport do |request|
      url = request.fetch(:url)
      if url.include?("/v1/preReleaseVersions?")
        response(data: [pre_release_version])
      elsif url.include?("/v1/builds?")
        response(data: [build_resource])
      elsif url.include?("/buildBetaDetail")
        response(data: resource("buildBetaDetails", "detail", "internalBuildState" => "READY_FOR_BETA_TESTING"))
      elsif url.include?("/betaGroups/#{GROUP_ID}/builds")
        relationship_reads += 1
        response(data: relationship_reads == 1 ? [] : [build_resource])
      elsif request.fetch(:method) == "POST"
        post_count += 1
        response(status: 503, data: [])
      end
    end

    result = runner(env: @base_env, transport: transport).run("status")

    assert_equal "TESTFLIGHT_READY", result.fetch("code")
    assert_equal 1, post_count
    assert_operator relationship_reads, :>=, 2
  end

  def test_final_proof_rechecks_group_assignment_after_beta_becomes_ready
    relationship_reads = 0
    transport = standard_transport do |request|
      url = request.fetch(:url)
      if url.include?("/v1/preReleaseVersions?")
        response(data: [pre_release_version])
      elsif url.include?("/v1/builds?")
        response(data: [build_resource])
      elsif url.include?("/buildBetaDetail")
        response(data: resource("buildBetaDetails", "detail", "internalBuildState" => "READY_FOR_BETA_TESTING"))
      elsif url.include?("/betaGroups/#{GROUP_ID}/builds")
        relationship_reads += 1
        response(data: relationship_reads == 1 ? [build_resource] : [])
      end
    end

    error = assert_raises(IOSBaselineRelease::SafeError) do
      runner(env: @base_env, transport: transport).run("status")
    end
    assert_equal "GROUP_ASSIGNMENT_NOT_CONFIRMED", error.code
    assert_equal 2, relationship_reads
  end

  def test_processing_and_readiness_polling_are_bounded_and_fail_closed
    transport = standard_transport do |request|
      if request.fetch(:url).include?("/v1/preReleaseVersions?")
        response(data: [])
      end
    end
    error = assert_raises(IOSBaselineRelease::SafeError) do
      runner(env: @base_env.merge("POLL_ATTEMPTS" => "2"), transport: transport).run("status")
    end
    assert_equal "BUILD_NOT_OBSERVABLE", error.code
    assert_equal 2, transport.requests.count { |request| request.fetch(:url).include?("/v1/preReleaseVersions?") }
  end

  def test_api_client_follows_pagination_retries_429_and_5xx_and_refreshes_jwt
    tokens = []
    token_provider = lambda do
      token = "token-#{tokens.length + 1}"
      tokens << token
      token
    end
    attempt = 0
    transport = RouteTransport.new do |request, _requests|
      attempt += 1
      case attempt
      when 1
        response(status: 429, headers: { "retry-after" => "0" }, data: [])
      when 2
        response(status: 502, data: [])
      when 3
        response(data: [resource("builds", "first")], next_link: "https://api.appstoreconnect.apple.com/v1/builds?page=2")
      else
        response(data: [resource("builds", "second")])
      end
    end
    client = IOSBaselineRelease::Client.new(
      transport: transport,
      token_provider: token_provider,
      sleeper: ->(_seconds) {},
      max_retries: 3
    )

    builds = client.all_pages("/v1/builds")

    assert_equal %w[first second], builds.map { |build| build.fetch("id") }
    assert_equal 4, tokens.length
    assert_equal tokens, transport.requests.map { |request| request.dig(:headers, "Authorization").delete_prefix("Bearer ") }
  end

  def test_retry_after_http_date_is_honored_and_5xx_backoff_has_bounded_jitter
    now = Time.utc(2026, 10, 3, 12, 0, 0)
    sleeps = []
    attempts = 0
    transport = RouteTransport.new do |_request, _requests|
      attempts += 1
      case attempts
      when 1
        response(status: 429, headers: { "Retry-After" => (now + 4).httpdate }, data: [])
      when 2
        response(status: 503, data: [])
      else
        response(data: [])
      end
    end
    client = IOSBaselineRelease::Client.new(
      transport: transport,
      token_provider: -> { "safe-token" },
      sleeper: ->(seconds) { sleeps << seconds },
      clock: -> { now.to_i },
      random: -> { 0.5 },
      max_retries: 3
    )

    assert_equal [], client.all_pages("/v1/builds")
    assert_equal 4.0, sleeps[0]
    assert_operator sleeps[1], :>, 2.0
    assert_operator sleeps[1], :<=, 2.5
  end

  def test_transport_retry_uses_bounded_jitter
    sleeps = []
    attempts = 0
    transport = RouteTransport.new do |_request, _requests|
      attempts += 1
      raise Timeout::Error if attempts == 1

      response(data: [])
    end
    client = IOSBaselineRelease::Client.new(
      transport: transport,
      token_provider: -> { "safe-token" },
      sleeper: ->(seconds) { sleeps << seconds },
      random: -> { 0.5 },
      max_retries: 1
    )

    assert_equal [], client.all_pages("/v1/builds")
    assert_operator sleeps.fetch(0), :>, 1.0
    assert_operator sleeps.fetch(0), :<=, 1.25
  end

  def test_api_errors_never_include_response_body_or_credentials
    private_marker = "private-response-marker"
    transport = RouteTransport.new do |_request, _requests|
      IOSBaselineRelease::Response.new(status: 403, headers: {}, body: private_marker)
    end
    client = IOSBaselineRelease::Client.new(
      transport: transport,
      token_provider: -> { "secret-token" },
      sleeper: ->(_seconds) {},
      max_retries: 0
    )

    error = assert_raises(IOSBaselineRelease::SafeError) { client.get("/v1/apps") }
    assert_equal "ASC_HTTP_403", error.code
    refute_includes error.message, private_marker
    refute_includes error.message, "secret-token"
  end

  def test_malformed_api_document_fails_with_a_closed_error
    [{ "data" => {} }, []].each do |document|
      transport = RouteTransport.new do |_request, _requests|
        IOSBaselineRelease::Response.new(status: 200, headers: {}, body: JSON.generate(document))
      end
      client = IOSBaselineRelease::Client.new(
        transport: transport,
        token_provider: -> { "safe-token" },
        sleeper: ->(_seconds) {}
      )
      error = assert_raises(IOSBaselineRelease::SafeError) { client.all_pages("/v1/apps") }
      assert_equal "ASC_RESPONSE_INVALID", error.code
    end
  end

  def test_pagination_rejects_cross_origin_nonstandard_port_userinfo_fragment_and_cycles
    unsafe_links = [
      "http://api.appstoreconnect.apple.com/v1/builds?page=2",
      "https://example.invalid/v1/builds?page=2",
      "https://api.appstoreconnect.apple.com:444/v1/builds?page=2",
      "https://user@api.appstoreconnect.apple.com/v1/builds?page=2",
      "https://api.appstoreconnect.apple.com/v2/builds?page=2",
      "https://api.appstoreconnect.apple.com/v1/builds?page=2#fragment"
    ]
    unsafe_links.each do |next_link|
      transport = RouteTransport.new do |_request, _requests|
        response(data: [], next_link: next_link)
      end
      client = IOSBaselineRelease::Client.new(
        transport: transport,
        token_provider: -> { "safe-token" },
        sleeper: ->(_seconds) {}
      )
      error = assert_raises(IOSBaselineRelease::SafeError) { client.all_pages("/v1/builds") }
      assert_equal "UNSAFE_ASC_URL", error.code
    end

    page = "https://api.appstoreconnect.apple.com/v1/builds?page=1"
    transport = RouteTransport.new { |_request, _requests| response(data: [], next_link: page) }
    client = IOSBaselineRelease::Client.new(
      transport: transport,
      token_provider: -> { "safe-token" },
      sleeper: ->(_seconds) {}
    )
    error = assert_raises(IOSBaselineRelease::SafeError) { client.all_pages(page) }
    assert_equal "ASC_PAGINATION_LOOP", error.code
  end

  def test_pagination_has_a_hard_page_limit
    transport = RouteTransport.new do |_request, requests|
      response(data: [], next_link: "https://api.appstoreconnect.apple.com/v1/builds?page=#{requests.length + 1}")
    end
    client = IOSBaselineRelease::Client.new(
      transport: transport,
      token_provider: -> { "safe-token" },
      sleeper: ->(_seconds) {}
    )
    error = assert_raises(IOSBaselineRelease::SafeError) { client.all_pages("/v1/builds?page=1") }
    assert_equal "ASC_PAGINATION_LIMIT", error.code
    assert_operator transport.requests.length, :<=, IOSBaselineRelease::Client::MAX_PAGES
  end

  def test_jwt_is_es256_prime256v1_raw_signature_and_rejects_other_keys
    provider = IOSBaselineRelease::JwtProvider.new(
      issuer_id: "issuer-safe",
      key_id: "KEYSAFE123",
      private_key: @key,
      clock: -> { 1_800_000_000 }
    )
    header_segment, payload_segment, signature_segment = provider.call.split(".")
    header = JSON.parse(Base64.urlsafe_decode64(header_segment))
    payload = JSON.parse(Base64.urlsafe_decode64(payload_segment))
    signature = Base64.urlsafe_decode64(signature_segment)
    assert_equal "ES256", header.fetch("alg")
    assert_equal "appstoreconnect-v1", payload.fetch("aud")
    assert_equal 19 * 60, payload.fetch("exp") - payload.fetch("iat")
    assert_equal 64, signature.bytesize

    rsa_key = OpenSSL::PKey::RSA.new(1024).to_pem
    error = assert_raises(IOSBaselineRelease::SafeError) do
      IOSBaselineRelease::JwtProvider.new(
        issuer_id: "issuer-safe", key_id: "KEYSAFE123", private_key: rsa_key
      )
    end
    assert_equal "INVALID_API_PRIVATE_KEY", error.code

    wrong_curve = OpenSSL::PKey::EC.generate("secp384r1").to_pem
    error = assert_raises(IOSBaselineRelease::SafeError) do
      IOSBaselineRelease::JwtProvider.new(
        issuer_id: "issuer-safe", key_id: "KEYSAFE123", private_key: wrong_curve
      )
    end
    assert_equal "INVALID_API_PRIVATE_KEY", error.code
  end

  def test_altool_key_is_chmod_0600_and_always_removed
    upload_env
    observed_key_path = nil
    command_runner = lambda do |environment, *command|
      assert_equal "xcrun", command[0]
      assert_nil environment["APPSTORE_API_PRIVATE_KEY"]
      assert_equal ["altool", "--upload-app", "--type", "ios", "--file", File.realpath(@ipa_path),
                    "--apiKey", "KEYSAFE123", "--apiIssuer", "issuer-safe"], command.drop(1)
      refute environment.key?("HOME")
      key_directory = environment.fetch("API_PRIVATE_KEYS_DIR")
      assert_equal "700", format("%o", File.stat(key_directory).mode & 0o777)
      observed_key_path = File.join(key_directory, "AuthKey_KEYSAFE123.p8")
      assert_equal "600", format("%o", File.stat(observed_key_path).mode & 0o777)
      assert_equal @key, File.read(observed_key_path)
      raise IOSBaselineRelease::SafeError.new("UPLOAD_FAILED")
    end
    uploader = IOSBaselineRelease::AltoolUploader.new(command_runner: command_runner)

    assert_raises(IOSBaselineRelease::SafeError) do
      uploader.upload!(ipa: @ipa_path, issuer_id: "issuer-safe", key_id: "KEYSAFE123", private_key: @key)
    end
    refute File.exist?(observed_key_path)
    refute Dir.exist?(File.dirname(observed_key_path))
  end

  def test_cli_closes_unexpected_errors_without_exposing_the_message
    out = StringIO.new
    err = StringIO.new
    unsafe_runner = Object.new
    def unsafe_runner.run(_operation)
      raise "PRIVATE HTTP BODY AND TOKEN"
    end

    status = IOSBaselineRelease.run_cli(["status"], env: @base_env, out: out, err: err, runner: unsafe_runner)

    assert_equal 1, status
    assert_empty out.string
    assert_equal({ "code" => "UNEXPECTED_RELEASE_ERROR" }, JSON.parse(err.string))
    refute_includes err.string, "PRIVATE"
  end

  def test_config_rejects_non_exact_inputs_without_echoing_them
    invalid = {
      "ASC_APP_ID" => "not-numeric",
      "BUNDLE_ID" => "com.womaninred.other",
      "TESTER_GROUP_ID" => "bad group",
      "VERSION" => "latest",
      "BUILD_NUMBER" => "0"
    }
    invalid.each do |name, value|
      error = assert_raises(IOSBaselineRelease::SafeError) do
        IOSBaselineRelease::Config.from_env(@base_env.merge(name => value), operation: "status")
      end
      assert_equal "INVALID_#{name}", error.code
      refute_includes error.message, value unless value.empty?
    end
  end

  private

  def runner(env:, transport:, uploader: RecordingUploader.new)
    IOSBaselineRelease::Runner.new(
      env: env,
      transport: transport,
      uploader: uploader,
      sleeper: ->(_seconds) {}
    )
  end

  def upload_env
    @tmpdir ||= Dir.mktmpdir("ios-baseline-release-test")
    @ipa_path ||= begin
      path = File.join(@tmpdir, "Baseline.ipa")
      File.binwrite(path, "signed-ipa-fixture")
      path
    end
    @base_env.merge("IPA_PATH" => @ipa_path)
  end

  def standard_transport(&custom)
    RouteTransport.new do |request, _requests|
      overridden = custom&.call(request)
      next overridden if overridden

      case request.fetch(:url)
      when /\/v1\/apps\?/
        response(data: [resource("apps", APP_ID, "bundleId" => BUNDLE_ID)])
      when /\/v1\/betaGroups\?/
        response(data: [resource("betaGroups", GROUP_ID, "isInternalGroup" => true)])
      when /\/v1\/betaGroups\/#{GROUP_ID}\/betaTesters/
        response(data: [resource("betaTesters", "self-tester-id")])
      else
        flunk("unexpected API request #{request.fetch(:method)} #{request.fetch(:url)}")
      end
    end
  end

  def ready_transport(assigned_initially:)
    standard_transport do |request|
      url = request.fetch(:url)
      if url.include?("/v1/preReleaseVersions?")
        response(data: [pre_release_version])
      elsif url.include?("/v1/builds?")
        response(data: [build_resource])
      elsif url.include?("/buildBetaDetail")
        response(data: resource("buildBetaDetails", "detail", "internalBuildState" => "READY_FOR_BETA_TESTING"))
      elsif url.include?("/betaGroups/#{GROUP_ID}/builds")
        response(data: assigned_initially ? [build_resource] : [])
      elsif url.include?("/betaGroups/#{GROUP_ID}/betaTesters")
        response(data: [resource("betaTesters", "self-tester-id")])
      end
    end
  end

  def resource(type, id, attributes = {})
    { "type" => type, "id" => id, "attributes" => attributes }
  end

  def pre_release_version
    resource("preReleaseVersions", "version-id", "version" => VERSION, "platform" => "IOS")
  end

  def build_resource
    resource("builds", "build-id", "version" => BUILD, "processingState" => "VALID")
  end

  def response(status: 200, data:, headers: {}, next_link: nil)
    body = { "data" => data }
    body["links"] = { "next" => next_link } if next_link
    IOSBaselineRelease::Response.new(status: status, headers: headers, body: JSON.generate(body))
  end
end
