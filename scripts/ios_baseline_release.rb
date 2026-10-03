#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "openssl"
require "set"
require "timeout"
require "time"
require "tmpdir"
require "uri"

module IOSBaselineRelease
  API_ORIGIN = "https://api.appstoreconnect.apple.com"
  READY_STATES = %w[READY_FOR_BETA_TESTING IN_BETA_TESTING].freeze
  PROCESSING_FAILURE_STATES = %w[FAILED INVALID PROCESSING_EXCEPTION].freeze
  BETA_FAILURE_STATES = %w[
    MISSING_EXPORT_COMPLIANCE
    READY_FOR_BETA_SUBMISSION
    WAITING_FOR_BETA_REVIEW
    IN_BETA_REVIEW
    BETA_REVIEW_REJECTED
    PROCESSING_EXCEPTION
    FAILED
    INVALID
    EXPIRED
  ].freeze

  Response = Struct.new(:status, :headers, :body, keyword_init: true)

  class SafeError < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  Config = Struct.new(
    :issuer_id,
    :key_id,
    :private_key,
    :app_id,
    :bundle_id,
    :group_id,
    :tester_id,
    :version,
    :build_number,
    :ipa_path,
    :poll_attempts,
    :poll_interval,
    keyword_init: true
  ) do
    BASELINE_BUNDLE_ID = "com.womaninred.baseline"

    def self.from_env(env, operation:)
      values = {
        issuer_id: required(env, "APPSTORE_ISSUER_ID"),
        key_id: required(env, "APPSTORE_API_KEY_ID"),
        private_key: required(env, "APPSTORE_API_PRIVATE_KEY"),
        app_id: required(env, "ASC_APP_ID"),
        bundle_id: required(env, "BUNDLE_ID"),
        group_id: required(env, "TESTER_GROUP_ID"),
        tester_id: required(env, "TESTER_ID"),
        version: required(env, "VERSION"),
        build_number: required(env, "BUILD_NUMBER")
      }

      validate(values[:issuer_id], /\A[A-Za-z0-9-]{3,128}\z/, "APPSTORE_ISSUER_ID")
      validate(values[:key_id], /\A[A-Za-z0-9]{3,64}\z/, "APPSTORE_API_KEY_ID")
      validate(values[:app_id], /\A[1-9][0-9]{5,19}\z/, "ASC_APP_ID")
      raise SafeError, "INVALID_BUNDLE_ID" unless values[:bundle_id] == BASELINE_BUNDLE_ID
      validate(values[:group_id], /\A[A-Za-z0-9-]{1,128}\z/, "TESTER_GROUP_ID")
      validate(values[:tester_id], /\A[A-Za-z0-9-]{1,128}\z/, "TESTER_ID")
      validate(values[:version], /\A[0-9]+(?:\.[0-9]+){1,2}\z/, "VERSION")
      validate(values[:build_number], /\A[1-9][0-9]*\z/, "BUILD_NUMBER")

      ipa_path = nil
      if operation == "upload"
        raw_path = required(env, "IPA_PATH")
        raise SafeError, "INVALID_IPA_PATH" unless File.file?(raw_path) && File.extname(raw_path).downcase == ".ipa"

        ipa_path = File.realpath(raw_path)
      end

      poll_attempts = positive_integer(env.fetch("POLL_ATTEMPTS", "80"), "POLL_ATTEMPTS", maximum: 240)
      poll_interval = nonnegative_number(env.fetch("POLL_INTERVAL_SECONDS", "15"), "POLL_INTERVAL_SECONDS", maximum: 300)

      new(**values, ipa_path: ipa_path, poll_attempts: poll_attempts, poll_interval: poll_interval)
    end

    def self.required(env, name)
      value = env[name].to_s
      raise SafeError, "MISSING_#{name}" if value.empty?

      value
    end

    def self.validate(value, pattern, name)
      raise SafeError, "INVALID_#{name}" unless pattern.match?(value)
    end

    def self.positive_integer(value, name, maximum:)
      parsed = Integer(value, exception: false)
      raise SafeError, "INVALID_#{name}" unless parsed&.positive? && parsed <= maximum

      parsed
    end

    def self.nonnegative_number(value, name, maximum:)
      parsed = Float(value, exception: false)
      raise SafeError, "INVALID_#{name}" unless parsed && parsed >= 0 && parsed <= maximum

      parsed
    end
  end

  class JwtProvider
    def initialize(issuer_id:, key_id:, private_key:, clock: -> { Time.now.to_i })
      @issuer_id = issuer_id
      @key_id = key_id
      @key = OpenSSL::PKey.read(private_key)
      unless @key.is_a?(OpenSSL::PKey::EC) && @key.private? && @key.group.curve_name == "prime256v1"
        raise SafeError, "INVALID_API_PRIVATE_KEY"
      end
      @clock = clock
    rescue OpenSSL::PKey::PKeyError, OpenSSL::PKey::ECError
      raise SafeError, "INVALID_API_PRIVATE_KEY"
    end

    def call
      now = @clock.call.to_i
      header = { alg: "ES256", kid: @key_id, typ: "JWT" }
      payload = { iss: @issuer_id, iat: now, exp: now + (19 * 60), aud: "appstoreconnect-v1" }
      signing_input = [header, payload].map { |part| base64url(JSON.generate(part)) }.join(".")
      sequence = OpenSSL::ASN1.decode(@key.sign("SHA256", signing_input))
      unless sequence.is_a?(OpenSSL::ASN1::Sequence) && sequence.value.length == 2
        raise SafeError, "JWT_GENERATION_FAILED"
      end
      signature = sequence.value.map do |integer|
        hex = integer.value.to_i.to_s(16)
        hex = "0#{hex}" if hex.length.odd?
        bytes = [hex].pack("H*")
        raise SafeError, "JWT_GENERATION_FAILED" if bytes.bytesize > 32

        bytes.rjust(32, "\0")
      end.join
      "#{signing_input}.#{base64url(signature)}"
    rescue OpenSSL::OpenSSLError
      raise SafeError, "JWT_GENERATION_FAILED"
    end

    private

    def base64url(value)
      Base64.urlsafe_encode64(value, padding: false)
    end
  end

  class NetHTTPTransport
    def request(method:, url:, headers:, body:, timeouts:)
      uri = URI.parse(url)
      request_class = method == "POST" ? Net::HTTP::Post : Net::HTTP::Get
      request = request_class.new(uri)
      headers.each { |name, value| request[name] = value }
      request.body = body if body
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = timeouts.fetch(:connect)
      http.read_timeout = timeouts.fetch(:read)
      http.write_timeout = timeouts.fetch(:write) if http.respond_to?(:write_timeout=)
      response = http.request(request)
      Response.new(
        status: response.code.to_i,
        headers: response.each_header.to_h.transform_keys(&:downcase),
        body: response.body.to_s
      )
    end
  end

  class Client
    MAX_PAGES = 50
    TRANSIENT_ERRORS = [IOError, EOFError, Timeout::Error, SocketError, SystemCallError].freeze

    def initialize(transport:, token_provider:, sleeper: ->(seconds) { sleep(seconds) }, max_retries: 4,
      clock: -> { Time.now.to_i }, random: -> { Random.rand },
      timeouts: { connect: 15, read: 30, write: 30 })
      @transport = transport
      @token_provider = token_provider
      @sleeper = sleeper
      @max_retries = max_retries
      @clock = clock
      @random = random
      @timeouts = timeouts
    end

    def get(path)
      request("GET", path)
    end

    def post(path, body, retry_request: false)
      request("POST", path, body: body, retry_request: retry_request)
    end

    def all_pages(path)
      values = []
      next_path = path
      visited = Set.new
      page_count = 0
      until next_path.to_s.empty?
        normalized = absolute_url(next_path)
        raise SafeError, "ASC_PAGINATION_LOOP" if visited.include?(normalized)
        raise SafeError, "ASC_PAGINATION_LIMIT" if page_count >= MAX_PAGES

        visited << normalized
        page_count += 1
        payload = get(next_path)
        raise SafeError, "ASC_RESPONSE_INVALID" unless payload.is_a?(Hash)
        data = payload.fetch("data") { raise SafeError, "ASC_RESPONSE_INVALID" }
        raise SafeError, "ASC_RESPONSE_INVALID" unless data.is_a?(Array)
        links = payload["links"]
        raise SafeError, "ASC_RESPONSE_INVALID" if links && !links.is_a?(Hash)

        values.concat(data)
        next_path = links && links["next"]
        unless next_path.nil? || (next_path.is_a?(String) && !next_path.empty?)
          raise SafeError, "ASC_RESPONSE_INVALID"
        end
        validate_next_link!(next_path) unless next_path.to_s.empty?
      end
      values
    end

    private

    def request(method, path, body: nil, retry_request: true)
      url = absolute_url(path)
      attempts = 0
      loop do
        attempts += 1
        response = @transport.request(
          method: method,
          url: url,
          headers: {
            "Authorization" => "Bearer #{@token_provider.call}",
            "Content-Type" => "application/json"
          },
          body: body && JSON.generate(body),
          timeouts: @timeouts
        )
        status = response.status.to_i
        return {} if status == 204
        return parse_json(response.body) if status.between?(200, 299)

        retryable = status == 429 || status.between?(500, 599)
        if retry_request && retryable && attempts <= @max_retries
          @sleeper.call(retry_delay(response.headers, attempts))
          next
        end
        raise SafeError, "ASC_HTTP_#{status}"
      rescue *TRANSIENT_ERRORS
        if retry_request && attempts <= @max_retries
          @sleeper.call(retry_delay({}, attempts))
          next
        end
        raise SafeError, "ASC_TRANSPORT_FAILED"
      end
    end

    def absolute_url(path)
      uri = URI.join("#{API_ORIGIN}/", path)
      safe = uri.is_a?(URI::HTTPS) &&
        uri.host == URI(API_ORIGIN).host &&
        uri.port == 443 &&
        uri.path.start_with?("/v1/") &&
        uri.userinfo.nil? &&
        uri.fragment.nil?
      raise SafeError, "UNSAFE_ASC_URL" unless safe

      uri.to_s
    rescue URI::InvalidURIError
      raise SafeError, "UNSAFE_ASC_URL"
    end

    def validate_next_link!(value)
      absolute_url(value)
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError
      raise SafeError, "ASC_RESPONSE_INVALID"
    end

    def retry_delay(headers, attempts)
      raw = headers.to_h.transform_keys { |key| key.to_s.downcase }["retry-after"]
      parsed = Float(raw, exception: false)
      return [[parsed, 0].max, 60].min if parsed

      if raw
        begin
          seconds = Time.httpdate(raw).to_f - Time.at(@clock.call).to_f
          return [[seconds, 0].max, 60].min
        rescue ArgumentError
          # Fall through to bounded exponential backoff.
        end
      end

      base = [2**(attempts - 1), 30].min
      [base + (@random.call.to_f.clamp(0.0, 1.0) * [base * 0.25, 1.0].min), 30].min
    end
  end

  class AltoolUploader
    def initialize(command_runner: nil)
      @command_runner = command_runner || method(:capture_command!)
    end

    def upload!(ipa:, issuer_id:, key_id:, private_key:)
      exact_ipa = File.realpath(ipa)
      Dir.mktmpdir("ios-baseline-altool") do |home|
        key_directory = File.join(home, ".appstoreconnect", "private_keys")
        FileUtils.mkdir_p(key_directory, mode: 0o700)
        key_path = File.join(key_directory, "AuthKey_#{key_id}.p8")
        File.open(key_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(private_key) }
        File.chmod(0o600, key_path)
        @command_runner.call(
          { "API_PRIVATE_KEYS_DIR" => key_directory, "APPSTORE_API_PRIVATE_KEY" => nil },
          "xcrun", "altool", "--upload-app", "--type", "ios", "--file", exact_ipa,
          "--apiKey", key_id, "--apiIssuer", issuer_id
        )
      ensure
        File.delete(key_path) if key_path && File.exist?(key_path)
      end
      true
    end

    private

    def capture_command!(environment, *command)
      _stdout, _stderr, status = Open3.capture3(environment, *command, unsetenv_others: false)
      raise SafeError, "UPLOAD_FAILED" unless status.success?
    rescue SystemCallError
      raise SafeError, "UPLOAD_FAILED"
    end
  end

  # Read-only discovery: sparse resources and relationship identifiers only.
  class MetadataReader
    UUID = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/
    GROUP_NAME = "Test"

    def initialize(env:, transport:, sleeper:, clock:)
      @bundle = Config.required(env, "BUNDLE_ID")
      raise SafeError, "INVALID_BUNDLE_ID" unless @bundle == BASELINE_BUNDLE_ID
      @source = Config.required(env, "SOURCE_SHA")
      Config.validate(@source, /\A[0-9a-f]{40}\z/, "SOURCE_SHA")
      begin
        @key = OpenSSL::PKey.read(Base64.strict_decode64(Config.required(env, "METADATA_PUBLIC_KEY")))
        unless @key.is_a?(OpenSSL::PKey::RSA) && !@key.private? && @key.n.num_bits >= 3072
          raise SafeError, "INVALID_METADATA_PUBLIC_KEY"
        end
      rescue ArgumentError, OpenSSL::OpenSSLError
        raise SafeError, "INVALID_METADATA_PUBLIC_KEY"
      end
      issuer = Config.required(env, "APPSTORE_ISSUER_ID")
      key_id = Config.required(env, "APPSTORE_API_KEY_ID")
      Config.validate(issuer, /\A[A-Za-z0-9-]{3,128}\z/, "APPSTORE_ISSUER_ID")
      Config.validate(key_id, /\A[A-Za-z0-9]{3,64}\z/, "APPSTORE_API_KEY_ID")
      provider = JwtProvider.new(issuer_id: issuer, key_id: key_id,
        private_key: Config.required(env, "APPSTORE_API_PRIVATE_KEY"), clock: clock)
      @client = Client.new(transport: transport, token_provider: provider, sleeper: sleeper)
    end

    def run
      apps = @client.all_pages("/v1/apps?" + URI.encode_www_form(
        "filter[bundleId]" => @bundle, "fields[apps]" => "bundleId", "limit" => 200))
      app = one!(apps, "apps", /\A[1-9][0-9]{5,19}\z/)
      raise SafeError, "METADATA_APP_MISMATCH" unless app["attributes"].is_a?(Hash) && app["attributes"]["bundleId"] == @bundle
      groups = @client.all_pages("/v1/apps/#{app.fetch('id')}/betaGroups?" + URI.encode_www_form(
        "fields[betaGroups]" => "name,isInternalGroup", "limit" => 200))
      unless groups.all? { |group| group.is_a?(Hash) && group["type"] == "betaGroups" && group["attributes"].is_a?(Hash) }
        raise SafeError, "METADATA_RESOURCE_INVALID"
      end
      group = one!(groups.select { |candidate| candidate["attributes"]["name"] == GROUP_NAME }, "betaGroups", UUID)
      raise SafeError, "METADATA_GROUP_NOT_INTERNAL" unless group["attributes"]["isInternalGroup"] == true
      # Apple documents this endpoint as returning tester relationship IDs, without profiles.
      testers = @client.all_pages("/v1/betaGroups/#{group.fetch('id')}/relationships/betaTesters?limit=200")
      tester = one!(testers, "betaTesters", UUID)
      payload = JSON.generate(schema: "ios-baseline-release-metadata/v1", source_sha: @source,
        bundle_id: @bundle, group_name: GROUP_NAME, app_id: app.fetch("id"),
        group_id: group.fetch("id"), tester_id: tester.fetch("id"), tester_count: 1)
      # Ruby 2.6's portable public_encrypt API supports OAEP with SHA-1/MGF1-SHA-1.
      ciphertext = @key.public_encrypt(payload, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)
      { "schema" => "ios-baseline-encrypted-metadata/v1",
        "encrypted_metadata" => Base64.strict_encode64(ciphertext), "member_count" => 1 }
    end

    private

    def one!(resources, type, id_pattern)
      stage = { "apps" => "APP", "betaGroups" => "GROUP", "betaTesters" => "TESTER" }.fetch(type)
      raise SafeError, "METADATA_#{stage}_NOT_FOUND" if resources.empty?
      raise SafeError, "METADATA_#{stage}_AMBIGUOUS" unless resources.length == 1
      item = resources.first
      unless item.is_a?(Hash) && item["type"] == type && item["id"].is_a?(String) && id_pattern.match?(item["id"])
        raise SafeError, "METADATA_RESOURCE_INVALID"
      end
      item
    end
  end

  class Runner
    def initialize(env: ENV, transport: NetHTTPTransport.new, uploader: AltoolUploader.new,
      sleeper: ->(seconds) { sleep(seconds) }, clock: -> { Time.now.to_i })
      @env = env
      @transport = transport
      @uploader = uploader
      @sleeper = sleeper
      @clock = clock
    end

    def run(operation)
      if operation == "metadata"
        return MetadataReader.new(env: @env, transport: @transport, sleeper: @sleeper, clock: @clock).run
      end
      raise SafeError, "INVALID_OPERATION" unless %w[preflight upload status].include?(operation)

      config = Config.from_env(@env, operation: operation)
      token_provider = JwtProvider.new(
        issuer_id: config.issuer_id,
        key_id: config.key_id,
        private_key: config.private_key,
        clock: @clock
      )
      @client = Client.new(transport: @transport, token_provider: token_provider, sleeper: @sleeper)
      @config = config
      app = exact_app!
      group = exact_internal_group!(app.fetch("id"))
      ensure_exact_tester!(group.fetch("id"))

      case operation
      when "preflight"
        ensure_build_absent!(app.fetch("id"))
        { "code" => "PREFLIGHT_OK", "version" => config.version, "buildNumber" => config.build_number }
      when "upload"
        ensure_build_absent!(app.fetch("id"))
        @uploader.upload!(
          ipa: config.ipa_path,
          issuer_id: config.issuer_id,
          key_id: config.key_id,
          private_key: config.private_key
        )
        wait_for_delivery!(app.fetch("id"), group)
      when "status"
        wait_for_delivery!(app.fetch("id"), group)
      end
    end

    private

    def exact_app!
      apps = @client.all_pages("/v1/apps?filter%5BbundleId%5D=#{encode(@config.bundle_id)}&limit=200")
      matches = apps.select do |app|
        app.fetch("id", nil) == @config.app_id && app.dig("attributes", "bundleId") == @config.bundle_id
      end
      raise SafeError, "ASC_APP_MISMATCH" unless apps.length == 1 && matches.length == 1

      matches.first
    end

    def exact_internal_group!(app_id)
      groups = @client.all_pages("/v1/betaGroups?filter%5Bapp%5D=#{encode(app_id)}&limit=200")
      matches = groups.select { |group| group.fetch("id", nil) == @config.group_id }
      raise SafeError, "TESTER_GROUP_MISMATCH" unless matches.length == 1
      raise SafeError, "TESTER_GROUP_NOT_INTERNAL" unless matches.first.dig("attributes", "isInternalGroup") == true

      matches.first
    end

    def ensure_build_absent!(app_id)
      version = exact_version(app_id)
      return unless version

      builds = exact_builds(version.fetch("id"))
      raise SafeError, "BUILD_ALREADY_EXISTS" unless builds.empty?
    end

    def wait_for_delivery!(app_id, group)
      build = wait_for_valid_build!(app_id)
      ensure_assignment!(group.fetch("id"), build.fetch("id"))
      beta_state = wait_for_ready_state!(build.fetch("id"))
      unless assigned?(group.fetch("id"), build.fetch("id"))
        raise SafeError, "GROUP_ASSIGNMENT_NOT_CONFIRMED"
      end
      ensure_exact_tester!(group.fetch("id"))
      {
        "code" => "TESTFLIGHT_READY",
        "version" => @config.version,
        "buildNumber" => @config.build_number,
        "processingState" => "VALID",
        "betaState" => beta_state,
        "assigned" => true
      }
    end

    def wait_for_valid_build!(app_id)
      @config.poll_attempts.times do
        version = exact_version(app_id)
        if version
          builds = exact_builds(version.fetch("id"))
          raise SafeError, "BUILD_AMBIGUOUS" if builds.length > 1
          build = builds.first
          if build
            state = build.dig("attributes", "processingState")
            return build if state == "VALID"
            raise SafeError, "APPLE_PROCESSING_FAILED" if PROCESSING_FAILURE_STATES.include?(state)
          end
        end
        @sleeper.call(@config.poll_interval)
      end
      raise SafeError, "BUILD_NOT_OBSERVABLE"
    end

    def exact_version(app_id)
      versions = @client.all_pages(
        "/v1/preReleaseVersions?filter%5Bapp%5D=#{encode(app_id)}" \
        "&filter%5Bversion%5D=#{encode(@config.version)}&filter%5Bplatform%5D=IOS&limit=200"
      )
      raise SafeError, "VERSION_AMBIGUOUS" if versions.length > 1
      return nil if versions.empty?

      version = versions.first
      attributes = version.fetch("attributes", {})
      unless attributes["version"] == @config.version && attributes["platform"] == "IOS"
        raise SafeError, "VERSION_MISMATCH"
      end
      version
    end

    def exact_builds(version_id)
      builds = @client.all_pages(
        "/v1/builds?filter%5BpreReleaseVersion%5D=#{encode(version_id)}" \
        "&filter%5Bversion%5D=#{encode(@config.build_number)}&limit=200"
      )
      unless builds.all? { |build| build.is_a?(Hash) && build.dig("attributes", "version").to_s == @config.build_number }
        raise SafeError, "BUILD_MISMATCH"
      end
      builds
    end

    def ensure_assignment!(group_id, build_id)
      return true if assigned?(group_id, build_id)

      begin
        @client.post(
          "/v1/betaGroups/#{encode(group_id)}/relationships/builds",
          { "data" => [{ "type" => "builds", "id" => build_id }] },
          retry_request: false
        )
      rescue SafeError
        return true if assigned?(group_id, build_id)

        raise SafeError, "GROUP_ASSIGNMENT_UNCERTAIN"
      end
      raise SafeError, "GROUP_ASSIGNMENT_NOT_CONFIRMED" unless assigned?(group_id, build_id)

      true
    end

    def assigned?(group_id, build_id)
      @client.all_pages("/v1/betaGroups/#{encode(group_id)}/builds?limit=200").any? do |build|
        build.fetch("id", nil) == build_id
      end
    end

    def wait_for_ready_state!(build_id)
      @config.poll_attempts.times do
        payload = @client.get("/v1/builds/#{encode(build_id)}/buildBetaDetail")
        detail = payload.fetch("data") { raise SafeError, "ASC_RESPONSE_INVALID" }
        state = detail.dig("attributes", "internalBuildState")
        return state if READY_STATES.include?(state)
        raise SafeError, "TESTFLIGHT_READINESS_BLOCKED" if BETA_FAILURE_STATES.include?(state)

        @sleeper.call(@config.poll_interval)
      end
      raise SafeError, "TESTFLIGHT_READINESS_TIMEOUT"
    end

    def ensure_exact_tester!(group_id)
      testers = @client.all_pages("/v1/betaGroups/#{encode(group_id)}/betaTesters?limit=200")
      exact = testers.select { |tester| tester.fetch("id", nil) == @config.tester_id }
      raise SafeError, "TESTER_MEMBERSHIP_MISMATCH" unless testers.length == 1 && exact.length == 1

      true
    end

    def encode(value)
      URI.encode_www_form_component(value.to_s)
    end
  end

  def self.run_cli(arguments, env: ENV, out: $stdout, err: $stderr, runner: nil)
    operation = arguments.shift
    unless arguments.empty? && %w[preflight upload status metadata].include?(operation)
      err.puts(JSON.generate("code" => "USAGE_ERROR"))
      return 64
    end

    result = (runner || Runner.new(env: env)).run(operation)
    out.puts(JSON.generate(result))
    0
  rescue SafeError => error
    err.puts(JSON.generate("code" => error.code))
    1
  rescue StandardError
    err.puts(JSON.generate("code" => "UNEXPECTED_RELEASE_ERROR"))
    1
  end
end

if $PROGRAM_NAME == __FILE__
  exit IOSBaselineRelease.run_cli(ARGV.dup)
end
