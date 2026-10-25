# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "open3"

class IOSBaselineBuildInventoryWorkflowTest < Minitest::Test
  WORKFLOW = File.expand_path("../../.github/workflows/ios-baseline-builds.yml", __dir__)
  SOURCE = "3fb04c73f94c1174a668842ec3e50190abef6e6a"
  HELPER_HASH = "13cd9ed9688c4fec9e346bd12c845eac72616b823b57760535f5f667b6d8a38c"
  CHECKOUT = "actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803"

  def workflow
    YAML.safe_load(File.read(WORKFLOW))
  end

  def test_credentials_are_only_in_main_only_protected_inventory_after_tests
    doc = workflow
    assert_empty doc.fetch("permissions")
    jobs = doc.fetch("jobs")
    assert_equal %w[inventory test-probe], jobs.keys.sort
    probe = jobs.fetch("test-probe")
    refute_match(/secrets\./, probe.to_yaml)
    job = jobs.fetch("inventory")
    assert_equal "${{ github.ref == 'refs/heads/main' && github.repository == 'maikrais98/hiddify-app' }}", job.fetch("if")
    assert_equal "release-publish", job.fetch("environment")
    assert_equal "test-probe", job.fetch("needs")
    assert_equal({"contents" => "read"}, job.fetch("permissions"))
    assert_operator job.fetch("timeout-minutes"), :<=, 10
    steps = job.fetch("steps")
    guard = steps.first
    assert_equal "${{ vars.RELEASE_ENVIRONMENT_READY }}", guard.fetch("env").fetch("RELEASE_ENVIRONMENT_READY")
    guarded = steps.select { |step| step.to_yaml.include?("secrets.") }
    assert_equal 1, guarded.length
    assert_equal "Read complete Apple build inventory", guarded.first.fetch("name")
    assert_equal %w[APPSTORE_API_KEY_ID APPSTORE_API_PRIVATE_KEY APPSTORE_ISSUER_ID DELIVERY_BUILD_NUMBER MARKETING_VERSION MINIMUM_BUILD TESTER_GROUP_ID], guarded.first.fetch("env").keys.sort
    refute job.key?("env")
    refute_match(/xcodebuild|altool|\.rb (upload|status)|POST|PATCH|DELETE/, steps.to_yaml)
  end

  def test_optional_delivery_read_is_validated_before_protected_credentials
    doc = workflow
    trigger = doc["on"] || doc[true]
    dispatch = trigger.fetch("workflow_dispatch")
    assert_instance_of Hash, dispatch, "Optional diagnostic input is missing"
    input = dispatch.fetch("inputs").fetch("deliveryBuildNumber")
    assert_equal "string", input.fetch("type")
    assert_equal "", input.fetch("default")
    assert_equal false, input.fetch("required")
    probe = doc.fetch("jobs").fetch("test-probe")
    refute probe.key?("environment")
    validation = probe.fetch("steps").first
    assert_equal "Validate inventory inputs", validation.fetch("name")
    assert_equal "${{ inputs.deliveryBuildNumber }}", validation.fetch("env").fetch("DELIVERY_BUILD_NUMBER")
    refute_includes validation.to_yaml, "secrets."
    ["0", "-1", "1.0", "16x", "10000", "16\n"].each do |value|
      _out, status = Open3.capture2e({"MARKETING_VERSION" => "0.1.0", "MINIMUM_BUILD" => "28",
        "DELIVERY_BUILD_NUMBER" => value}, "bash", "-e", "-c", validation.fetch("run"))
      refute status.success?, "invalid diagnostic build must fail before credentials"
    end
    ["", "1", "16", "9999"].each do |value|
      _out, status = Open3.capture2e({"MARKETING_VERSION" => "0.1.0", "MINIMUM_BUILD" => "28",
        "DELIVERY_BUILD_NUMBER" => value}, "bash", "-e", "-c", validation.fetch("run"))
      assert status.success?
    end
    read = doc.fetch("jobs").fetch("inventory").fetch("steps").find { |step| step["name"] == "Read complete Apple build inventory" }
    assert_equal "${{ inputs.deliveryBuildNumber }}", read.fetch("env").fetch("DELIVERY_BUILD_NUMBER")
    assert_equal "${{ inputs.deliveryBuildNumber != '' && secrets.IOS_BASELINE_TESTER_GROUP_ID || '' }}", read.fetch("env").fetch("TESTER_GROUP_ID")
  end

  def test_inventory_target_inputs_have_safe_defaults_and_are_validated_before_credentials
    doc = workflow
    trigger = doc["on"] || doc[true]
    inputs = trigger.fetch("workflow_dispatch").fetch("inputs")
    assert_equal "0.1.0", inputs.fetch("marketingVersion").fetch("default")
    assert_equal "28", inputs.fetch("minimumBuild").fetch("default")
    assert_equal "string", inputs.fetch("marketingVersion").fetch("type")
    assert_equal "string", inputs.fetch("minimumBuild").fetch("type")

    probe = doc.fetch("jobs").fetch("test-probe")
    validation = probe.fetch("steps").first
    assert_equal "Validate inventory inputs", validation.fetch("name")
    assert_equal "${{ inputs.marketingVersion || '0.1.0' }}", validation.fetch("env").fetch("MARKETING_VERSION")
    assert_equal "${{ inputs.minimumBuild || '28' }}", validation.fetch("env").fetch("MINIMUM_BUILD")
    refute_includes validation.to_yaml, "secrets."
    [["0.1.0", "28"], ["10.20.30", "9999"]].each do |version, build|
      _out, status = Open3.capture2e({"MARKETING_VERSION" => version, "MINIMUM_BUILD" => build,
        "DELIVERY_BUILD_NUMBER" => ""}, "bash", "-e", "-c", validation.fetch("run"))
      assert status.success?
    end
    [["0.1", "28"], ["01.1.0", "28"], ["0.1.0", "0"], ["0.1.0", "10000"]].each do |version, build|
      _out, status = Open3.capture2e({"MARKETING_VERSION" => version, "MINIMUM_BUILD" => build,
        "DELIVERY_BUILD_NUMBER" => ""}, "bash", "-e", "-c", validation.fetch("run"))
      refute status.success?
    end

    read = doc.fetch("jobs").fetch("inventory").fetch("steps").find { |step| step["name"] == "Read complete Apple build inventory" }
    assert_equal "${{ inputs.marketingVersion || '0.1.0' }}", read.fetch("env").fetch("MARKETING_VERSION")
    assert_equal "${{ inputs.minimumBuild || '28' }}", read.fetch("env").fetch("MINIMUM_BUILD")
  end

  def test_readiness_guard_fails_closed_before_credentials
    run = workflow.fetch("jobs").fetch("inventory").fetch("steps").first.fetch("run")
    [nil, "false", "TRUE", "true "].each do |value|
      _out, status = Open3.capture2e({"RELEASE_ENVIRONMENT_READY" => value}, "bash", "-e", "-c", run)
      refute status.success?, "Readiness #{value.inspect} must not expose credentials"
    end
    _out, status = Open3.capture2e({"RELEASE_ENVIRONMENT_READY" => "true"}, "bash", "-e", "-c", run)
    assert status.success?
  end

  def test_both_jobs_use_same_exact_controller_and_trusted_helper_without_checkout_credentials
    jobs = workflow.fetch("jobs")
    jobs.each_value do |job|
      checkout = job.fetch("steps").select { |step| step["uses"] == CHECKOUT }
      assert_equal 2, checkout.length
      assert_equal "${{ github.sha }}", checkout.first.fetch("with").fetch("ref")
      assert_equal SOURCE, checkout.last.fetch("with").fetch("ref")
      assert_equal ".asc-trusted-source", checkout.last.fetch("with").fetch("path")
      checkout.each do |step|
        assert_equal false, step.fetch("with").fetch("persist-credentials")
        assert_equal 1, step.fetch("with").fetch("fetch-depth")
      end
      verify = job.fetch("steps").find { |step| step["name"] == "Verify pinned API helper" }
      refute_nil verify
      assert_includes verify.fetch("run"), SOURCE
      assert_includes verify.fetch("run"), HELPER_HASH
      job.fetch("steps").select { |step| step.key?("uses") }.each do |step|
        assert_match(/@[0-9a-f]{40}\z/, step.fetch("uses"))
      end
    end
  end

  def test_only_safe_inventory_receipt_is_retained
    steps = workflow.fetch("jobs").fetch("inventory").fetch("steps")
    read = steps.find { |step| step["name"] == "Read complete Apple build inventory" }
    assert_includes read.fetch("run"), "umask 077"
    assert_includes read.fetch("run"), "ruby scripts/ios_baseline_build_inventory.rb .asc-trusted-source/scripts/ios_baseline_release.rb"
    assert_includes read.fetch("run"), "> ios-baseline-builds.json"
    artifact = steps.find { |step| step["uses"].to_s.start_with?("actions/upload-artifact@") }
    assert_equal "ios-baseline-builds", artifact.fetch("with").fetch("name")
    assert_equal "ios-baseline-builds.json", artifact.fetch("with").fetch("path")
    assert_equal 7, artifact.fetch("with").fetch("retention-days")
    assert_equal "error", artifact.fetch("with").fetch("if-no-files-found")
    assert_equal "success()", artifact.fetch("if")
  end
end
