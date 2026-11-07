# frozen_string_literal: true
require 'minitest/autorun'
require 'yaml'
require 'json'
require 'digest'
require 'open3'

class IosLuma555ControllerTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  SOURCE = '9a15af24fc838190525d80370493ec546a7a2ec1'
  CORE = '7b14e3a657a000d0200bb40f30b3d6796854219bb0b5b72c38e3f4d456601a8b'
  def setup
    @jobs = YAML.safe_load(File.read(File.join(ROOT, '.github/workflows/ios-baseline.yml'))).fetch('jobs')
  end
  def test_current_source_checks_and_coupled_core_pins
    steps = @jobs.fetch('test-source').fetch('steps')
    commands = steps.map { |s| s['run'] }.join("\n")
    %w[foreground_setup_mode_test blizzard_runtime_boundary_test native_diagnostics_privacy_test].each { |old| refute_includes commands, old }
    %w[flutter\ analyze flutter\ test vpn_manager_manual_policy_test.sh ios_baseline_workflow_test.rb].each { |current| assert_includes commands, current }
    step = steps.find { |s| s['name'] == 'Prepare digest-bound official iOS core' }
    assert_equal CORE, step.fetch('env').fetch('CORE_ARCHIVE_SHA256')
    assert_equal '111283683', step.fetch('env').fetch('CORE_ARCHIVE_SIZE')
    %w[test-source sign-baseline].each do |job|
      core = @jobs.fetch(job).fetch('steps').find { |s| s['name'] == 'Prepare digest-bound official iOS core' }
      assert_includes core.fetch('run'), '/download/v5.5.5/'
      assert_includes core.fetch('run'), '"$CORE_ARCHIVE_SHA256"'
    end
    assert_equal CORE, @jobs.fetch('sign-baseline').fetch('env').fetch('CORE_ARCHIVE_SHA256')
    upload = @jobs.fetch('upload-testflight').fetch('steps').find { |s| s['name'] == 'Verify source, version, build, digest, and signed identity' }.fetch('run')
    assert_includes upload, CORE
    assert_includes upload, '111283683'
  end
  def test_visuals_and_official_diagnostics_do_not_require_custom_telemetry
    sign = @jobs.fetch('sign-baseline').to_s
    assert_includes sign, '--dart-define=BLIZZARD_VISUALS=true'
    %w[BETTERSTACK SENTRY_DSN prepare_telemetry TELEMETRY_SOURCE_MISSING].each { |old| refute_includes sign, old }
    assert_includes @jobs.fetch('preflight-upload').to_s, 'Revalidate live app, group, version, and build collision'
  end
  def test_digest_bound_approval_step_executes_and_rejects_wrong_source_or_low_build
    step = @jobs.fetch('verify-release-approval').fetch('steps').last
    env = step.fetch('env').merge('REQUESTED_SOURCE_SHA'=>SOURCE,'REQUESTED_VERSION'=>'0.1.0','REQUESTED_BUILD_NUMBER'=>'46')
    assert_equal SOURCE, env.fetch('EXPECTED_SOURCE_SHA')
    assert_equal '46', env.fetch('EXPECTED_MINIMUM_BUILD_NUMBER')
    approval = JSON.parse(File.read(File.join(ROOT,"release/reference-approvals/#{SOURCE}.json")))
    assert_equal '2026-11-07T20:59:12Z', approval.fetch('approver').fetch('created_at')
    assert_includes approval.fetch('visual_acceptance').fetch('reason'), 'сделай релиз в тест флайт и ок на гитхаб даю'
    [{}, {'REQUESTED_SOURCE_SHA'=>'0'*40}, {'REQUESTED_BUILD_NUMBER'=>'45'}, {'EXPECTED_EVIDENCE_SHA256'=>'0'*64}, {'EXPECTED_APPROVAL_SHA256'=>'0'*64}].each_with_index do |change,index|
      output,status = Open3.capture2e(env.merge(change), 'bash','-e','-o','pipefail','-c',step.fetch('run'),chdir:ROOT)
      assert_equal index.zero?, status.success?, output
    end
  end
end
