#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "openssl"
require "securerandom"
require "time"

module IOSBaselineSigningRequest
  TEAM_ID = "M9D72QQJ79"
  REQUEST_SCHEMA = "ios-baseline-signing-request/v1"
  REQUEST_DIRECTORY_MODE = 0o700
  PRIVATE_FILE_MODE = 0o600
  PUBLIC_FILE_MODE = 0o644
  KEY_BITS = 2048
  SUBJECT_FIELDS = [
    ["O", "Blizzard", OpenSSL::ASN1::UTF8STRING],
    ["OU", "Release Engineering", OpenSSL::ASN1::UTF8STRING],
    ["CN", "Blizzard iOS Baseline Distribution", OpenSSL::ASN1::UTF8STRING]
  ].freeze
  SUBJECT_MANIFEST = {
    "commonName" => "Blizzard iOS Baseline Distribution",
    "organization" => "Blizzard",
    "organizationalUnit" => "Release Engineering"
  }.freeze

  class SafeError < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  module Files
    module_function

    def write_exclusive(path, contents, mode)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
        file.binmode
        file.write(contents)
        file.flush
        file.fsync
      end
      File.chmod(mode, path)
    rescue Errno::EEXIST
      raise SafeError, "OUTPUT_FILE_EXISTS"
    end
  end

  class Preparation
    def initialize(clock: -> { Time.now.utc }, password_generator: -> { SecureRandom.base64(48) })
      @clock = clock
      @password_generator = password_generator
    end

    def run(directory)
      directory = File.expand_path(directory)
      begin
        Dir.mkdir(directory, REQUEST_DIRECTORY_MODE)
      rescue Errno::EEXIST
        raise SafeError, "REQUEST_DIRECTORY_EXISTS"
      rescue Errno::ENOENT
        raise SafeError, "REQUEST_PARENT_MISSING"
      end
      File.chmod(REQUEST_DIRECTORY_MODE, directory)

      begin
        password = @password_generator.call
        raise SafeError, "PASSWORD_GENERATION_FAILED" unless password.is_a?(String) && password.bytesize >= 32

        key = OpenSSL::PKey::RSA.new(KEY_BITS)
        csr = build_csr(key)
        csr_pem = csr.to_pem
        spki_sha256 = Digest::SHA256.hexdigest(key.public_key.to_der)
        manifest = request_manifest(csr_pem, spki_sha256)

        Files.write_exclusive(File.join(directory, "private-key.pem"),
          key.export(OpenSSL::Cipher.new("aes-256-cbc"), password), PRIVATE_FILE_MODE)
        Files.write_exclusive(File.join(directory, "private-key-password.txt"), password, PRIVATE_FILE_MODE)
        Files.write_exclusive(File.join(directory, "request.csr.pem"), csr_pem, PUBLIC_FILE_MODE)
        Files.write_exclusive(File.join(directory, "request.json"),
          JSON.pretty_generate(manifest) + "\n", PUBLIC_FILE_MODE)

        {
          "directory" => directory,
          "csr" => File.join(directory, "request.csr.pem"),
          "manifest" => File.join(directory, "request.json"),
          "spkiSHA256" => spki_sha256
        }
      rescue StandardError
        FileUtils.remove_entry_secure(directory) if File.directory?(directory)
        raise
      end
    rescue OpenSSL::OpenSSLError
      raise SafeError, "REQUEST_CRYPTOGRAPHY_FAILED"
    end

    private

    def build_csr(key)
      request = OpenSSL::X509::Request.new
      request.version = 0
      request.subject = OpenSSL::X509::Name.new(SUBJECT_FIELDS)
      request.public_key = key.public_key
      request.sign(key, OpenSSL::Digest::SHA256.new)
      request
    end

    def request_manifest(csr_pem, spki_sha256)
      {
        "schema" => REQUEST_SCHEMA,
        "createdAt" => @clock.call.utc.iso8601,
        "subject" => SUBJECT_MANIFEST,
        "keyAlgorithm" => { "name" => "RSA", "bits" => KEY_BITS },
        "spkiSHA256" => spki_sha256,
        "csrSHA256" => Digest::SHA256.hexdigest(csr_pem),
        "csrFile" => "request.csr.pem"
      }
    end
  end

  class Assembly
    def initialize(clock: -> { Time.now.utc }, password_generator: -> { SecureRandom.base64(48) }, validator: nil)
      @clock = clock
      @password_generator = password_generator
      @validator = validator
    end

    def run(directory, certificate_path, app_profile_path, extension_profile_path)
      directory = File.expand_path(directory)
      output_directory = File.join(directory, "assembled")
      raise SafeError, "ASSEMBLED_DIRECTORY_EXISTS" if File.exist?(output_directory)

      key, csr, manifest = load_request(directory)
      certificate = load_certificate(certificate_path)
      validate_public_keys!(key, csr, certificate, manifest)

      password = @password_generator.call
      raise SafeError, "PASSWORD_GENERATION_FAILED" unless password.is_a?(String) && password.bytesize >= 32

      p12_der = OpenSSL::PKCS12.create(
        password,
        "Blizzard iOS Baseline Distribution",
        key,
        certificate
      ).to_der
      certificate_sha256 = Digest::SHA256.hexdigest(certificate.to_der)
      app_profile_cms = File.binread(app_profile_path)
      extension_profile_cms = File.binread(extension_profile_path)
      validator.validate_material!(
        p12_der: p12_der,
        p12_password: password,
        pinned_certificate_sha256: certificate_sha256,
        app_profile_cms: app_profile_cms,
        extension_profile_cms: extension_profile_cms,
        now: @clock.call.utc
      )

      begin
        Dir.mkdir(output_directory, REQUEST_DIRECTORY_MODE)
      rescue Errno::EEXIST
        raise SafeError, "ASSEMBLED_DIRECTORY_EXISTS"
      end
      File.chmod(REQUEST_DIRECTORY_MODE, output_directory)
      begin
        Files.write_exclusive(File.join(output_directory, "distribution.p12"), p12_der, PRIVATE_FILE_MODE)
        Files.write_exclusive(File.join(output_directory, "distribution-p12-password.txt"),
          password, PRIVATE_FILE_MODE)
        Files.write_exclusive(File.join(output_directory, "certificate-sha256.txt"),
          "#{certificate_sha256}\n", PUBLIC_FILE_MODE)
      rescue StandardError
        FileUtils.remove_entry_secure(output_directory) if File.directory?(output_directory)
        raise
      end

      { "directory" => output_directory, "certificateSHA256" => certificate_sha256 }
    rescue Errno::ENOENT, Errno::EACCES
      raise SafeError, "SIGNING_INPUT_UNREADABLE"
    rescue OpenSSL::PKCS12::PKCS12Error, OpenSSL::PKey::PKeyError, OpenSSL::X509::RequestError,
           OpenSSL::X509::CertificateError
      raise SafeError, "SIGNING_INPUT_INVALID"
    end

    private

    def validator
      return @validator if @validator

      require_relative "ios_baseline_manual_signing"
      IOSBaselineManualSigning
    end

    def load_request(directory)
      key_path = File.join(directory, "private-key.pem")
      password = File.binread(File.join(directory, "private-key-password.txt"))
      csr_bytes = File.binread(File.join(directory, "request.csr.pem"))
      manifest_bytes = File.binread(File.join(directory, "request.json"))
      key = OpenSSL::PKey.read(File.binread(key_path), password)
      csr = OpenSSL::X509::Request.new(csr_bytes)
      manifest = JSON.parse(manifest_bytes)

      valid_manifest = manifest.is_a?(Hash) && manifest["schema"] == REQUEST_SCHEMA &&
        manifest["csrFile"] == "request.csr.pem" &&
        manifest["csrSHA256"] == Digest::SHA256.hexdigest(csr_bytes) &&
        manifest["keyAlgorithm"] == { "name" => "RSA", "bits" => KEY_BITS } &&
        manifest["subject"] == SUBJECT_MANIFEST
      raise SafeError, "REQUEST_MANIFEST_INVALID" unless valid_manifest
      raise SafeError, "REQUEST_CSR_INVALID" unless csr.verify(csr.public_key)
      expected_subject = OpenSSL::X509::Name.new(SUBJECT_FIELDS)
      raise SafeError, "REQUEST_CSR_SUBJECT_INVALID" unless csr.subject.to_der == expected_subject.to_der
      raise SafeError, "REQUEST_KEY_INVALID" unless key.is_a?(OpenSSL::PKey::RSA) && key.n.num_bits == KEY_BITS

      [key, csr, manifest]
    rescue JSON::ParserError
      raise SafeError, "REQUEST_MANIFEST_INVALID"
    end

    def load_certificate(path)
      OpenSSL::X509::Certificate.new(File.binread(path))
    end

    def validate_public_keys!(key, csr, certificate, manifest)
      key_public_der = key.public_key.to_der
      raise SafeError, "REQUEST_KEY_CSR_MISMATCH" unless csr.public_key.to_der == key_public_der
      key_spki = key.public_key.to_der
      raise SafeError, "REQUEST_SPKI_MISMATCH" unless manifest["spkiSHA256"] == Digest::SHA256.hexdigest(key_spki)
      raise SafeError, "CERTIFICATE_SPKI_MISMATCH" unless certificate.public_key.to_der == key_public_der
    end
  end

  class CLI
    def self.run(arguments, out: $stdout, err: $stderr)
      command, *values = arguments
      case command
      when "prepare"
        raise SafeError, "USAGE" unless values.length == 1

        result = Preparation.new.run(values.fetch(0))
        out.puts "STATUS=REQUEST_PREPARED"
        out.puts "CSR=#{result.fetch("csr")}"
        out.puts "REQUEST_MANIFEST=#{result.fetch("manifest")}"
        out.puts "SPKI_SHA256=#{result.fetch("spkiSHA256")}"
      when "assemble"
        raise SafeError, "USAGE" unless values.length == 4

        result = Assembly.new.run(*values)
        out.puts "STATUS=SIGNING_MATERIAL_ASSEMBLED"
        out.puts "ASSEMBLED_DIRECTORY=#{result.fetch("directory")}"
        out.puts "CERTIFICATE_SHA256=#{result.fetch("certificateSHA256")}"
      else
        raise SafeError, "USAGE"
      end
      0
    rescue SafeError => error
      err.puts "ERROR_CODE=#{error.code}"
      1
    rescue StandardError => error
      code = error.respond_to?(:code) ? error.code : "SIGNING_REQUEST_FAILED"
      err.puts "ERROR_CODE=#{code}"
      1
    end
  end
end

exit(IOSBaselineSigningRequest::CLI.run(ARGV)) if $PROGRAM_NAME == __FILE__
