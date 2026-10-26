# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "json"
require "rbconfig"
require "stringio"
require_relative "../../scripts/testflight_access"

class TestFlightFixtureError < StandardError
  attr_reader :code

  def initialize(code)
    @code = code
    super(code)
  end
end

class TestFlightFixtureClient
  attr_reader :posts

  def initialize(tester: nil, assigned: false, processing: "VALID", version: "0.1.0",
    invitation_error: nil, invitation_exception: nil, review_state: nil)
    @tester = tester
    @assigned = assigned
    @processing = processing
    @version = version
    @invitation_error = invitation_error
    @invitation_exception = invitation_exception
    @review_state = review_state
    @posts = []
  end

  def all_pages(path)
    case path
    when %r{\A/v1/apps\?}
      [app]
    when %r{\A/v1/builds\?}
      [build]
    when %r{\A/v1/betaTesters\?}
      @tester ? [@tester] : []
    when "/v1/betaTesters/tester-1/builds?limit=200"
      @assigned ? [build] : []
    when "/v1/betaTesters/tester-1/apps?limit=200"
      @assigned ? [app] : []
    when %r{\A/v1/betaAppReviewSubmissions\?}
      @review_state ? [submission(@review_state)] : []
    when %r{\A/v1/apps/app-1/betaGroups\?}
      [{"type" => "betaGroups", "id" => "internal-only",
        "attributes" => {"name" => "Test", "isInternalGroup" => true}}]
    else
      raise "unexpected collection: #{path}"
    end
  end

  def get(path)
    case path
    when "/v1/builds/build-37"
      {"data" => build}
    when "/v1/builds/build-37/preReleaseVersion"
      {"data" => {"type" => "preReleaseVersions", "id" => "train-1",
        "attributes" => {"version" => @version, "platform" => "IOS"}}}
    when "/v1/builds/build-37/app"
      {"data" => app}
    when "/v1/apps/app-1/betaAppReviewDetail"
      {"data" => {"type" => "betaAppReviewDetails", "id" => "review-detail-1"}}
    else
      raise "unexpected get: #{path}"
    end
  end

  def post(path, body)
    @posts << {path: path, body: body}
    case path
    when "/v1/betaTesters"
      @tester = tester
      @assigned = true
      {"data" => @tester}
    when "/v1/builds/build-37/relationships/individualTesters"
      @assigned = true
      {"data" => []}
    when "/v1/betaTesterInvitations"
      raise @invitation_exception if @invitation_exception
      raise TestFlightFixtureError, @invitation_error if @invitation_error

      {"data" => {"type" => "betaTesterInvitations", "id" => "invitation-1"}}
    when "/v1/betaAppReviewSubmissions"
      @review_state = "WAITING_FOR_REVIEW"
      {"data" => submission(@review_state)}
    else
      raise "unexpected post: #{path}"
    end
  end

  private

  def app
    {"type" => "apps", "id" => "app-1", "attributes" => {"bundleId" => "com.womaninred.baseline"}}
  end

  def build
    {"type" => "builds", "id" => "build-37",
      "attributes" => {"version" => "37", "processingState" => @processing}}
  end

  def tester
    {"type" => "betaTesters", "id" => "tester-1", "attributes" => {"email" => "owner@example.test"}}
  end

  def submission(state)
    {"type" => "betaAppReviewSubmissions", "id" => "submission-1",
      "attributes" => {"betaReviewState" => state}}
  end
end

class TestFlightAccessImportTest < Minitest::Test
  SCRIPT = File.expand_path("../../scripts/testflight_access.rb", __dir__)

  def test_script_can_be_required_without_apple_helper_or_credentials
    output, status = Open3.capture2e({}, RbConfig.ruby, "-e", "require ARGV.fetch(0)", SCRIPT,
      unsetenv_others: true)

    assert status.success?, output
  end
end

class TestFlightAccessTest < Minitest::Test
  EMAIL = "owner@example.test"
  BUILD_ID = "build-37"

  def invite_env
    {"OPERATION" => "invite", "BUILD_NUMBER" => "37", "LUMA_REQUESTED_TESTER_EMAIL" => EMAIL}
  end

  def beta_review_env
    {"OPERATION" => "beta-review", "BUILD_NUMBER" => "37"}
  end

  def test_new_tester_is_created_for_exact_build_without_group_membership
    client = TestFlightFixtureClient.new

    report = LumaTestFlightAccess.run(env: invite_env, client: client)

    create = client.posts.find { |request| request.fetch(:path) == "/v1/betaTesters" }
    assert_equal({data: {type: "betaTesters", attributes: {email: EMAIL}, relationships: {
      builds: {data: [{type: "builds", id: BUILD_ID}]}
    }}}, create.fetch(:body))
    refute client.posts.any? { |request| request.fetch(:path).include?("betaGroups") }
    assert_equal "TESTFLIGHT_INVITATION_SENT", report.fetch(:code)
    refute_includes JSON.generate(report), EMAIL
    refute_includes JSON.generate(report), BUILD_ID
  end

  def test_existing_tester_already_on_build_is_not_added_twice
    existing = {"type" => "betaTesters", "id" => "tester-1", "attributes" => {"email" => EMAIL}}
    client = TestFlightFixtureClient.new(tester: existing, assigned: true)

    LumaTestFlightAccess.run(env: invite_env, client: client)

    refute client.posts.any? { |request| request.fetch(:path).include?("individualTesters") }
    assert_equal 1, client.posts.count { |request| request.fetch(:path) == "/v1/betaTesterInvitations" }
  end

  def test_existing_tester_is_added_through_build_relationship
    existing = {"type" => "betaTesters", "id" => "tester-1", "attributes" => {"email" => EMAIL}}
    client = TestFlightFixtureClient.new(tester: existing)

    LumaTestFlightAccess.run(env: invite_env, client: client)

    add = client.posts.find { |request| request.fetch(:path).include?("individualTesters") }
    assert_equal "/v1/builds/build-37/relationships/individualTesters", add.fetch(:path)
    assert_equal({data: [{type: "betaTesters", id: "tester-1"}]}, add.fetch(:body))
  end

  def test_non_valid_build_fails_closed_before_any_write
    client = TestFlightFixtureClient.new(processing: "PROCESSING")

    error = assert_raises(LumaTestFlightAccess::SafeError) do
      LumaTestFlightAccess.run(env: invite_env, client: client)
    end

    assert_equal "BUILD_NOT_VALID", error.code
    assert_empty client.posts
  end

  def test_missing_build_number_is_a_safe_validation_error
    client = TestFlightFixtureClient.new
    env = invite_env.reject { |key, _value| key == "BUILD_NUMBER" }

    error = assert_raises(LumaTestFlightAccess::SafeError) do
      LumaTestFlightAccess.run(env: env, client: client)
    end

    assert_equal "INVALID_BUILD_NUMBER", error.code
    assert_empty client.posts
  end

  def test_wrong_marketing_version_fails_closed_before_any_write
    client = TestFlightFixtureClient.new(version: "0.1.1")

    error = assert_raises(LumaTestFlightAccess::SafeError) do
      LumaTestFlightAccess.run(env: invite_env, client: client)
    end

    assert_equal "BUILD_MARKETING_VERSION_MISMATCH", error.code
    assert_empty client.posts
  end

  def test_pending_external_gate_is_reported_as_not_sent
    client = TestFlightFixtureClient.new(invitation_error: "ASC_INVITATION_REJECTED", review_state: "WAITING_FOR_REVIEW")

    report = LumaTestFlightAccess.run(env: invite_env, client: client)

    assert_equal "TESTFLIGHT_INVITATION_NOT_SENT", report.fetch(:code)
    assert_equal "ASC_INVITATION_REJECTED", report.fetch(:safe_error_code)
    assert_equal "WAITING_FOR_REVIEW", report.fetch(:beta_review_state)
    assert_equal false, report.fetch(:invitation_accepted_by_apple)
    refute_includes report.values, "TESTFLIGHT_INVITATION_SENT"
  end

  def test_cli_returns_failure_and_preserves_not_sent_receipt
    client = TestFlightFixtureClient.new(
      invitation_error: "ASC_INVITATION_REJECTED", review_state: "WAITING_FOR_REVIEW"
    )
    out = StringIO.new
    err = StringIO.new

    status = LumaTestFlightAccess.run_cli(env: invite_env, out: out, err: err, client: client)

    assert_equal 1, status
    receipt = JSON.parse(out.string)
    assert_equal "TESTFLIGHT_INVITATION_NOT_SENT", receipt.fetch("code")
    assert_equal false, receipt.fetch("invitation_accepted_by_apple")
    assert_equal "ASC_INVITATION_REJECTED", receipt.fetch("safe_error_code")
    assert_empty err.string
  end

  def test_unstructured_invitation_failure_is_not_mislabeled_as_external_gate
    client = TestFlightFixtureClient.new(invitation_exception: RuntimeError.new("private transport detail"))

    error = assert_raises(RuntimeError) do
      LumaTestFlightAccess.run(env: invite_env, client: client)
    end

    assert_equal "private transport detail", error.message
  end

  def test_beta_review_reuses_existing_metadata_and_submits_exact_build
    client = TestFlightFixtureClient.new

    report = LumaTestFlightAccess.run(env: beta_review_env, client: client)

    submission = client.posts.find { |request| request.fetch(:path) == "/v1/betaAppReviewSubmissions" }
    assert_equal({data: {type: "betaAppReviewSubmissions", relationships: {
      build: {data: {type: "builds", id: BUILD_ID}}
    }}}, submission.fetch(:body))
    assert_equal "TESTFLIGHT_BETA_REVIEW_SUBMITTED", report.fetch(:code)
    assert_equal "WAITING_FOR_REVIEW", report.fetch(:beta_review_state)
  end

  def test_workflow_exposes_build_and_beta_review_without_embedding_email
    workflow = File.read(File.expand_path("../../.github/workflows/ios-testflight-access.yml", __dir__))

    assert_includes workflow, "buildNumber:"
    assert_includes workflow, "- beta-review"
    assert_includes workflow, 'BUILD_NUMBER: ${{ inputs.buildNumber }}'
    assert_includes workflow, 'LUMA_REQUESTED_TESTER_EMAIL: ${{ secrets.LUMA_INVITE_20261027_EMAIL }}'
    assert_match(/- name: Retain safe operation receipt\n\s+if: always\(\)/, workflow)
    refute_includes workflow, EMAIL
  end
end
