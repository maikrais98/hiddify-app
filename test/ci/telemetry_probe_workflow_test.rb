require "minitest/autorun"
require "yaml"

class TelemetryProbeWorkflowTest < Minitest::Test
  PATH = File.expand_path("../..", __dir__) + "/.github/workflows/telemetry-probe.yml"

  def workflow
    assert File.exist?(PATH), "A protected ingestion-only probe workflow is required"
    YAML.load_file(PATH)
  end

  def test_manual_main_only_and_no_signing_ready_change
    data = workflow
    trigger = data["on"] || data[true]
    assert_equal ["workflow_dispatch"], trigger.keys
    assert_equal({}, data["permissions"])
    job = data.fetch("jobs").fetch("probe")
    assert_equal "${{ github.ref == 'refs/heads/main' }}", job.fetch("if")
    assert_equal "release-signing", job.fetch("environment")
    assert_equal "ubuntu-latest", job.fetch("runs-on")
    assert_equal 3, job.fetch("timeout-minutes")
    refute_includes File.read(PATH), "RELEASE_ENVIRONMENT_READY"
    refute_match(/gh\s+(api|variable|secret)|xcodebuild|altool|codesign|flutter build/, File.read(PATH))
  end

  def test_readiness_and_exact_provenance_precede_ingestion_credentials
    steps = workflow.fetch("jobs").fetch("probe").fetch("steps")
    guard = steps.index { |step| step["name"] == "Require protected probe readiness" }
    provenance = steps.index { |step| step["name"] == "Validate reviewed source and controller" }
    send = steps.index { |step| step["id"] == "probe" }
    assert guard && provenance && send
    assert_operator guard, :<, send
    assert_operator provenance, :<, send
    assert_equal "${{ vars.TELEMETRY_PROBE_READY }}", steps[guard].fetch("env").fetch("PROBE_READY")
    assert_includes steps[guard].fetch("run"), 'test "$PROBE_READY" = "true"'
    assert_equal "19092ea5bdcec9b16a38dc792b66af45b29787a7", steps[provenance].fetch("env").fetch("TRUSTED_SOURCE_SHA")
    assert_includes steps[provenance].fetch("run"), 'test "$SOURCE_SHA" = "$TRUSTED_SOURCE_SHA"'
    assert_includes steps[provenance].fetch("run"), 'test "$(git rev-parse HEAD)" = "$CONTROLLER_SHA"'
  end

  def test_exposes_only_existing_ingestion_credentials
    steps = workflow.fetch("jobs").fetch("probe").fetch("steps")
    credential_steps = steps.select { |step| step.fetch("env", {}).values.any? { |value| value.to_s.include?("secrets.") } }
    assert_equal 1, credential_steps.length
    assert_equal %w[BETTERSTACK_LOGS_URL BETTERSTACK_SOURCE_TOKEN SENTRY_DSN], credential_steps.first.fetch("env").keys.sort
    assert_includes credential_steps.first.fetch("run"), "scripts/telemetry_probe.py"
  end

  def test_retains_only_the_closed_receipt
    uploads = workflow.fetch("jobs").fetch("probe").fetch("steps").select { |step| step["uses"].to_s.start_with?("actions/upload-artifact@") }
    assert_equal 1, uploads.length
    assert_equal "${{ runner.temp }}/telemetry-probe-receipt.json", uploads.first.fetch("with").fetch("path")
    assert_equal "error", uploads.first.fetch("with").fetch("if-no-files-found")
    assert_equal 7, uploads.first.fetch("with").fetch("retention-days")
  end
end
