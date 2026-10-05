# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class BlizzardReleaseControllerTest < Minitest::Test
  BASELINE = "0830294eff5b8cd86324545ed00689648c70bd23"
  WORKFLOW = File.expand_path("../../.github/workflows/ios-baseline.yml", __dir__)

  def setup
    @jobs = YAML.safe_load(File.read(WORKFLOW)).fetch("jobs")
  end

  def test_exact_reviewed_release_pin_and_unchanged_metadata_pin
    env = @jobs.fetch("validate-source").fetch("steps").first.fetch("env")
    assert_equal "6aa9477e98f84757b22451a12890bed898d89b84", env.fetch("TRUSTED_RELEASE_SOURCE_SHA")
    assert_equal "3fb04c73f94c1174a668842ec3e50190abef6e6a", env.fetch("TRUSTED_SOURCE_SHA")
  end

  def test_exact_baseline_is_fetched_and_checked_before_flutter_tests
    steps = @jobs.fetch("test-source").fetch("steps")
    fetch_index = steps.index { |step| step["name"] == "Fetch exact presentation contract baseline" }
    refute_nil fetch_index, "Shallow source checkout must receive the immutable contract baseline"
    assert_equal "git fetch --no-tags --depth=1 origin #{BASELINE}\ngit cat-file -e '#{BASELINE}^{commit}'\n",
                 steps.fetch(fetch_index).fetch("run")
    assert_operator fetch_index, :>, steps.index { |step| step["name"] == "Verify exact checked-out source" }
    assert_operator fetch_index, :<, steps.index { |step| step["name"] == "Run full Flutter tests" }
    checkout = steps.find { |step| step.key?("uses") && step.fetch("uses").start_with?("actions/checkout@") }
    assert_equal 1, checkout.fetch("with").fetch("fetch-depth")
    assert_equal false, checkout.fetch("with").fetch("persist-credentials")
  end
end
