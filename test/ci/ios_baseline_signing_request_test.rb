# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "openssl"
require "open3"
require "tmpdir"

SCRIPT = File.expand_path("../../scripts/ios_baseline_signing_request.rb", __dir__)
require SCRIPT if File.file?(SCRIPT)

class IOSBaselineSigningRequestTest < Minitest::Test
  FIXED_TIME = Time.utc(2026, 10, 15, 12, 34, 56)
  REQUEST_PASSWORD = "request-password-fixture-with-enough-entropy"
  P12_PASSWORD = "p12-password-fixture-with-enough-entropy"

  class RecordingValidator
    attr_reader :arguments

    def validate_material!(**arguments)
      @arguments = arguments
      Object.new
    end
  end

  def implementation
    assert Object.const_defined?(:IOSBaselineSigningRequest), "signing request implementation is missing"
    IOSBaselineSigningRequest
  end

  def preparation
    implementation::Preparation.new(
      clock: -> { FIXED_TIME },
      password_generator: -> { REQUEST_PASSWORD }
    )
  end

  def assembly(validator)
    implementation::Assembly.new(
      clock: -> { FIXED_TIME },
      password_generator: -> { P12_PASSWORD },
      validator: validator
    )
  end

  def with_request
    Dir.mktmpdir("ios-signing-request-test") do |parent|
      directory = File.join(parent, "request")
      preparation.run(directory)
      yield directory
    end
  end

  def test_prepare_creates_encrypted_rsa_2048_csr_and_public_request_manifest
    with_request do |directory|
      key_path = File.join(directory, "private-key.pem")
      password_path = File.join(directory, "private-key-password.txt")
      csr_path = File.join(directory, "request.csr.pem")
      manifest_path = File.join(directory, "request.json")

      assert_equal 0o700, File.stat(directory).mode & 0o777
      assert_equal 0o600, File.stat(key_path).mode & 0o777
      assert_equal 0o600, File.stat(password_path).mode & 0o777
      assert_equal 0o644, File.stat(csr_path).mode & 0o777
      assert_equal 0o644, File.stat(manifest_path).mode & 0o777
      assert_equal REQUEST_PASSWORD, File.binread(password_path)
      assert_raises(OpenSSL::PKey::PKeyError) { OpenSSL::PKey.read(File.binread(key_path)) }

      key = OpenSSL::PKey.read(File.binread(key_path), REQUEST_PASSWORD)
      assert_instance_of OpenSSL::PKey::RSA, key
      assert_equal 2048, key.n.num_bits

      csr = OpenSSL::X509::Request.new(File.binread(csr_path))
      assert csr.verify(csr.public_key)
      assert_equal "/O=Blizzard/OU=Release Engineering/CN=Blizzard iOS Baseline Distribution", csr.subject.to_s
      assert_equal key.public_key.to_der, csr.public_key.to_der

      manifest = JSON.parse(File.binread(manifest_path))
      expected_spki = Digest::SHA256.hexdigest(key.public_key.to_der)
      assert_equal "ios-baseline-signing-request/v1", manifest.fetch("schema")
      assert_equal "2026-10-15T12:34:56Z", manifest.fetch("createdAt")
      assert_equal({
        "commonName" => "Blizzard iOS Baseline Distribution",
        "organization" => "Blizzard",
        "organizationalUnit" => "Release Engineering"
      }, manifest.fetch("subject"))
      assert_equal({ "name" => "RSA", "bits" => 2048 }, manifest.fetch("keyAlgorithm"))
      assert_equal expected_spki, manifest.fetch("spkiSHA256")
      assert_equal Digest::SHA256.file(csr_path).hexdigest, manifest.fetch("csrSHA256")
      assert_equal "request.csr.pem", manifest.fetch("csrFile")
      refute_includes File.binread(manifest_path), REQUEST_PASSWORD
      refute_includes File.binread(manifest_path), "PRIVATE KEY"
    end
  end

  def test_prepare_refuses_an_existing_directory_without_touching_it
    Dir.mktmpdir("ios-signing-request-existing") do |directory|
      sentinel = File.join(directory, "keep")
      File.write(sentinel, "unchanged")

      error = assert_raises(implementation::SafeError) { preparation.run(directory) }

      assert_equal "REQUEST_DIRECTORY_EXISTS", error.code
      assert_equal "unchanged", File.binread(sentinel)
      refute File.exist?(File.join(directory, "private-key.pem"))
    end
  end

  def test_assemble_matches_certificate_to_csr_and_key_then_delegates_material_validation
    with_request do |directory|
      certificate_path = issue_certificate_for_request(directory)
      app_profile = write_fixture(directory, "app.mobileprovision", "APP_PROFILE_CMS")
      extension_profile = write_fixture(directory, "extension.mobileprovision", "EXTENSION_PROFILE_CMS")
      validator = RecordingValidator.new

      result = assembly(validator).run(directory, certificate_path, app_profile, extension_profile)

      assembled = File.join(directory, "assembled")
      p12_path = File.join(assembled, "distribution.p12")
      password_path = File.join(assembled, "distribution-p12-password.txt")
      digest_path = File.join(assembled, "certificate-sha256.txt")
      assert_equal assembled, result.fetch("directory")
      assert_equal 0o700, File.stat(assembled).mode & 0o777
      assert_equal 0o600, File.stat(p12_path).mode & 0o777
      assert_equal 0o600, File.stat(password_path).mode & 0o777
      assert_equal 0o644, File.stat(digest_path).mode & 0o777
      assert_equal P12_PASSWORD, File.binread(password_path)

      certificate = OpenSSL::X509::Certificate.new(File.binread(certificate_path))
      certificate_sha256 = Digest::SHA256.hexdigest(certificate.to_der)
      assert_equal "#{certificate_sha256}\n", File.binread(digest_path)
      p12_der = File.binread(p12_path)
      p12 = OpenSSL::PKCS12.new(p12_der, P12_PASSWORD)
      assert_equal certificate.to_der, p12.certificate.to_der
      assert_equal certificate.public_key.to_der, p12.key.public_key.to_der

      arguments = validator.arguments
      assert_equal p12_der, arguments.fetch(:p12_der)
      assert_equal P12_PASSWORD, arguments.fetch(:p12_password)
      assert_equal certificate_sha256, arguments.fetch(:pinned_certificate_sha256)
      assert_equal "APP_PROFILE_CMS", arguments.fetch(:app_profile_cms)
      assert_equal "EXTENSION_PROFILE_CMS", arguments.fetch(:extension_profile_cms)
      assert_equal FIXED_TIME, arguments.fetch(:now)
    end
  end

  def test_assemble_rejects_a_certificate_for_another_key_before_writing_outputs
    with_request do |directory|
      certificate_path = issue_certificate_for_request(directory, key: OpenSSL::PKey::RSA.new(2048))
      app_profile = write_fixture(directory, "app.mobileprovision", "APP_PROFILE_CMS")
      extension_profile = write_fixture(directory, "extension.mobileprovision", "EXTENSION_PROFILE_CMS")
      validator = RecordingValidator.new

      error = assert_raises(implementation::SafeError) do
        assembly(validator).run(directory, certificate_path, app_profile, extension_profile)
      end

      assert_equal "CERTIFICATE_SPKI_MISMATCH", error.code
      refute File.exist?(File.join(directory, "assembled"))
      assert_nil validator.arguments
    end
  end

  def test_assemble_rejects_a_personal_subject_even_when_the_csr_is_resigned_and_manifest_rehashed
    with_request do |directory|
      password = File.binread(File.join(directory, "private-key-password.txt"))
      key = OpenSSL::PKey.read(File.binread(File.join(directory, "private-key.pem")), password)
      csr = OpenSSL::X509::Request.new
      csr.version = 0
      csr.subject = OpenSSL::X509::Name.parse("/CN=Personal Name")
      csr.public_key = key.public_key
      csr.sign(key, OpenSSL::Digest::SHA256.new)
      csr_path = File.join(directory, "request.csr.pem")
      File.binwrite(csr_path, csr.to_pem)
      manifest_path = File.join(directory, "request.json")
      manifest = JSON.parse(File.binread(manifest_path))
      manifest["csrSHA256"] = Digest::SHA256.file(csr_path).hexdigest
      File.binwrite(manifest_path, JSON.pretty_generate(manifest) + "\n")
      certificate_path = issue_certificate_for_request(directory)
      app_profile = write_fixture(directory, "app.mobileprovision", "APP_PROFILE_CMS")
      extension_profile = write_fixture(directory, "extension.mobileprovision", "EXTENSION_PROFILE_CMS")

      error = assert_raises(implementation::SafeError) do
        assembly(RecordingValidator.new).run(directory, certificate_path, app_profile, extension_profile)
      end

      assert_equal "REQUEST_CSR_SUBJECT_INVALID", error.code
      refute File.exist?(File.join(directory, "assembled"))
    end
  end

  def test_assemble_refuses_to_replace_existing_output
    with_request do |directory|
      certificate_path = issue_certificate_for_request(directory)
      app_profile = write_fixture(directory, "app.mobileprovision", "APP_PROFILE_CMS")
      extension_profile = write_fixture(directory, "extension.mobileprovision", "EXTENSION_PROFILE_CMS")
      Dir.mkdir(File.join(directory, "assembled"))

      error = assert_raises(implementation::SafeError) do
        assembly(RecordingValidator.new).run(directory, certificate_path, app_profile, extension_profile)
      end

      assert_equal "ASSEMBLED_DIRECTORY_EXISTS", error.code
    end
  end

  def test_cli_prepare_reports_only_public_artifact_paths_and_fingerprint
    Dir.mktmpdir("ios-signing-request-cli") do |parent|
      directory = File.join(parent, "request")
      output, status = Open3.capture2e("ruby", SCRIPT, "prepare", directory)

      assert status.success?, output
      assert_match(/\ASTATUS=REQUEST_PREPARED\n/, output)
      assert_includes output, "CSR=#{directory}/request.csr.pem\n"
      assert_includes output, "REQUEST_MANIFEST=#{directory}/request.json\n"
      assert_match(/SPKI_SHA256=[0-9a-f]{64}\n\z/, output)
      password = File.binread(File.join(directory, "private-key-password.txt"))
      refute_includes output, password
      refute_includes output, "PRIVATE KEY"
    end
  end

  private

  def issue_certificate_for_request(directory, key: nil)
    request = OpenSSL::X509::Request.new(File.binread(File.join(directory, "request.csr.pem")))
    signing_key = key || OpenSSL::PKey::RSA.new(2048)
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = 1
    certificate.subject = OpenSSL::X509::Name.parse("/CN=Apple Distribution: Blizzard (M9D72QQJ79)/OU=M9D72QQJ79/O=Blizzard")
    certificate.issuer = certificate.subject
    certificate.public_key = key ? key.public_key : request.public_key
    certificate.not_before = FIXED_TIME - 60
    certificate.not_after = FIXED_TIME + 86_400
    certificate.sign(signing_key, OpenSSL::Digest::SHA256.new)
    write_fixture(directory, "distribution.cer", certificate.to_der)
  end

  def write_fixture(directory, name, contents)
    path = File.join(directory, name)
    File.binwrite(path, contents)
    path
  end

end
