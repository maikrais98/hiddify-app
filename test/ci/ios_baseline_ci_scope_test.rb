# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class IOSBaselineCIScopeTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  CI_WORKFLOW = File.join(ROOT, ".github/workflows/ci.yml")
  BUILD_WORKFLOW = File.join(ROOT, ".github/workflows/build.yml")
  SCOPE_WORKFLOW = File.join(ROOT, ".github/workflows/ios-baseline-ci-scope.yml")

  PR_BASE_IGNORE = %w[
    **.md
    docs/**
    test.configs/**
    .vscode/
    appcast.xml
  ].freeze

  PUSH_BASE_IGNORE = %w[
    **.md
    docs/**
    .vscode/
    appcast.xml
  ].freeze

  RELEASE_ONLY_PATHS = %w[
    .github/workflows/ci.yml
    .github/workflows/ios-baseline.yml
    .github/workflows/ios-baseline-signing-inventory.yml
    .github/workflows/ios-baseline-manual-signing.yml
    .github/workflows/ios-baseline-signing-bootstrap.yml
    .github/workflows/ios-baseline-ci-scope.yml
    scripts/ios_baseline_signing_inventory.rb
    scripts/ios_baseline_manual_signing.rb
    scripts/ios_baseline_signing_request.rb
    scripts/ios_baseline_signing_bootstrap.rb
    test/ci/ios_baseline_ci_scope_test.rb
    test/ci/ios_baseline_manual_signing_test.rb
    test/ci/ios_baseline_manual_signing_workflow_test.rb
    test/ci/ios_baseline_persistent_signing_gate_test.rb
    test/ci/ios_baseline_signing_diagnostics_test.rb
    test/ci/ios_baseline_signing_inventory_test.rb
    test/ci/ios_baseline_signing_request_test.rb
    test/ci/ios_baseline_signing_bootstrap_test.rb
    test/ci/ios_baseline_signing_bootstrap_workflow_test.rb
    test/ci/blizzard_release_controller_test.rb
  ].freeze

  SCOPE_WORKFLOW_PATHS = RELEASE_ONLY_PATHS.freeze

  APP_PATH_FIXTURES = %w[
    lib/main.dart
    ios/Runner/AppDelegate.swift
    ios/Runner.entitlements
    ios/Runner.xcodeproj/project.pbxproj
    ios/Podfile
    ios/Frameworks/Hiddify.framework/Info.plist
    scripts/prepare_ios_baseline_core.sh
    scripts/apply_hiddify_core_patch.sh
    .github/workflows/build.yml
    pubspec.lock
    hiddify-core/go.mod
  ].freeze

  def setup
    @ci = load_yaml(CI_WORKFLOW)
    @on = @ci.fetch("on") { @ci.fetch(true) }
  end

  def test_general_ci_has_only_explicit_release_scope_ignores_for_each_event
    assert_equal (PR_BASE_IGNORE + RELEASE_ONLY_PATHS).sort,
                 trigger("pull_request").fetch("paths-ignore").sort
    assert_equal (PUSH_BASE_IGNORE + RELEASE_ONLY_PATHS).sort,
                 trigger("push").fetch("paths-ignore").sort
  end

  def test_paths_ignore_semantics_skip_only_all_ignored_changes_and_handle_renames
    RELEASE_ONLY_PATHS.each do |path|
      refute triggers?("pull_request", [path]), path
      refute triggers?("push", [path]), path
    end

    APP_PATH_FIXTURES.each do |path|
      assert triggers?("pull_request", [path]), "pull_request must run for #{path}"
      assert triggers?("push", [path]), "push must run for #{path}"
    end

    %w[
      .github/workflows/ios-baseline-inventory.yml
      .github/workflows/ios-baseline-builds.yml
      scripts/ios_baseline_build_inventory.rb
      test/ci/ios_baseline_build_inventory_test.rb
      test/ci/ios_baseline_build_inventory_workflow_test.rb
    ].each do |path|
      assert triggers?("pull_request", [path]), "uncovered release path must run pull_request CI: #{path}"
      assert triggers?("push", [path]), "uncovered release path must run push CI: #{path}"
    end

    assert triggers?("pull_request", [RELEASE_ONLY_PATHS.first, "lib/main.dart"])
    assert triggers?("push", ["lib/main.dart", RELEASE_ONLY_PATHS.first])
    assert triggers?("pull_request", ["lib/main.dart", RELEASE_ONLY_PATHS.first])
    assert triggers?("push", [RELEASE_ONLY_PATHS.first, "lib/main.dart"])
    assert triggers?("pull_request", ["scripts/ios_baseline_signing_request.rb", "ios/Runner/AppDelegate.swift"])
    assert triggers?("push", ["ios/Runner/AppDelegate.swift", "scripts/ios_baseline_signing_request.rb"])

    assert triggers?("pull_request", ["config/unknown-selector-input.txt"])
    assert triggers?("push", ["config/unknown-selector-input.txt"])
    assert triggers?("pull_request", ["scripts/ios_baseline_unlisted.rb"])
    assert triggers?("push", [".github/workflows/ios-baseline-unlisted.yml"])
  end

  def test_preexisting_event_specific_ignore_rules_remain_intact
    %w[README.md docs/guide.txt .vscode/settings.json appcast.xml].each do |path|
      refute triggers?("pull_request", [path]), path
      refute triggers?("push", [path]), path
    end

    refute triggers?("pull_request", ["test.configs/fixture.json"])
    assert triggers?("push", ["test.configs/fixture.json"])
  end

  def test_general_ci_keeps_the_reusable_build_contract
    assert_equal({}, @ci.fetch("permissions"))
    assert_equal ["run"], @ci.fetch("jobs").keys
    job = @ci.fetch("jobs").fetch("run")
    assert_equal %w[if permissions uses with], job.keys.sort
    assert_equal "./.github/workflows/build.yml", job.fetch("uses")
    assert_equal({ "contents" => "read" }, job.fetch("permissions"))
    assert_equal "${{!contains(github.event.head_commit.message, 'release: version')}}", job.fetch("if")
    assert_equal({ "upload-artifact" => "${{ github.event_name == 'push' }}" }, job.fetch("with"))

    build = load_yaml(BUILD_WORKFLOW)
    build_on = build.fetch("on") { build.fetch(true) }
    assert build_on.key?("workflow_call")
    assert_equal %w[build ios-build test], build.fetch("jobs").keys.sort
    assert_includes build.fetch("jobs").fetch("test").to_yaml, "flutter test"
    assert_includes build.fetch("jobs").fetch("ios-build").to_yaml, "flutter build ios"
  end

  def test_scope_workflow_is_secretless_ubuntu_yaml_only_check
    workflow = load_yaml(SCOPE_WORKFLOW)
    workflow_on = workflow.fetch("on") { workflow.fetch(true) }
    paths = workflow_on.fetch("pull_request").fetch("paths")
    assert_equal SCOPE_WORKFLOW_PATHS.sort, paths.sort
    assert_equal({}, workflow.fetch("permissions"))

    job = workflow.fetch("jobs").fetch("test-scope")
    assert_equal "ubuntu-latest", job.fetch("runs-on")
    assert_equal({ "contents" => "read" }, job.fetch("permissions"))
    text = job.to_yaml
    refute_match(/secrets\.|flutter|xcodebuild|macos|build\.yml/, text)
    assert_includes text, "ruby test/ci/ios_baseline_ci_scope_test.rb"
  end

  def test_excluded_production_scripts_have_dedicated_test_workflow_coverage
    coverage = {
      "scripts/ios_baseline_signing_inventory.rb" => [
        ".github/workflows/ios-baseline-signing-inventory.yml",
        %w[ios_baseline_signing_inventory_test.rb ios_baseline_persistent_signing_gate_test.rb
           ios_baseline_signing_diagnostics_test.rb blizzard_release_controller_test.rb]
      ],
      "scripts/ios_baseline_manual_signing.rb" => [
        ".github/workflows/ios-baseline-manual-signing.yml",
        %w[ios_baseline_manual_signing_test.rb ios_baseline_signing_request_test.rb
           ios_baseline_manual_signing_workflow_test.rb]
      ],
      "scripts/ios_baseline_signing_request.rb" => [
        ".github/workflows/ios-baseline-manual-signing.yml",
        %w[ios_baseline_signing_request_test.rb ios_baseline_manual_signing_workflow_test.rb]
      ]
    }

    bootstrap_script = File.join(ROOT, "scripts/ios_baseline_signing_bootstrap.rb")
    if File.file?(bootstrap_script)
      bootstrap_tests = Dir[File.join(ROOT, "test/ci/*bootstrap*test.rb")].map { |path| File.basename(path) }
      coverage["scripts/ios_baseline_signing_bootstrap.rb"] = [
        ".github/workflows/ios-baseline-signing-bootstrap.yml", bootstrap_tests
      ]
    end

    coverage.each do |script, (workflow_path, tests)|
      assert File.file?(File.join(ROOT, script)), "excluded script is missing: #{script}"
      workflow = File.join(ROOT, workflow_path)
      assert File.file?(workflow), "dedicated test workflow is missing: #{workflow_path}"
      document = load_yaml(workflow)
      test_jobs = document.fetch("jobs").select { |name, _job| name.to_s.match?(/test|probe/) }
      refute_empty test_jobs, "dedicated secretless test job is missing: #{workflow_path}"
      text = test_jobs.to_yaml
      refute_match(/secrets\./, text, workflow_path)
      refute_empty tests, "no dedicated tests found for #{script}"
      tests.each { |test| assert_includes text, "test/ci/#{test}", workflow_path }
    end
  end

  private

  def load_yaml(path)
    YAML.safe_load(File.read(path), aliases: true)
  end

  def trigger(event)
    @on.fetch(event)
  end

  def triggers?(event, changed_paths)
    patterns = trigger(event).fetch("paths-ignore")
    changed_paths.any? { |path| !ignored_by_github?(path, patterns) }
  end

  # These are the GitHub path-ignore forms used by this workflow. A workflow
  # is skipped only when every changed path, including both sides of a rename,
  # is ignored.
  def ignored_by_github?(path, patterns)
    patterns.any? do |pattern|
      case pattern
      when "**.md"
        path.end_with?(".md")
      when ".vscode/"
        path == ".vscode" || path.start_with?(".vscode/")
      when /\A(.+)\/\*\*\z/
        base = Regexp.last_match(1)
        path == base || path.start_with?("#{base}/")
      else
        path == pattern
      end
    end
  end
end
