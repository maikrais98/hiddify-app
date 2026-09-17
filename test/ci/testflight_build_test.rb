# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../.github/testflight_build'

class ScriptedAppStoreConnect < AppStoreConnect
  attr_reader :paths, :posts

  def initialize(&responses)
    @paths = []
    @posts = []
    @responses = responses
  end

  private

  def app_id
    'app-id'
  end

  def get(path)
    @paths << path
    @responses.call(path)
  end

  def post(path, body)
    @posts << [path, body]
  end
end

class TestFlightBuildTest < Minitest::Test
  def test_next_number_treats_requested_build_as_a_minimum
    assert_equal 7, next_number(%w[1 3 6], minimum: 5)
    assert_equal 9, next_number(%w[1 3], minimum: 9)
  end

  def test_ios_build_lookup_follows_pagination
    client = ScriptedAppStoreConnect.new do |path|
      case path
      when /preReleaseVersions/
        {'data' => [{'id' => 'version-id', 'attributes' => {'version' => '0.0.1', 'platform' => 'IOS'}}]}
      when /builds\?/
        {'data' => [{'attributes' => {'version' => '1'}}], 'links' => {'next' => '/builds-page-2'}}
      when '/builds-page-2'
        {'data' => [{'attributes' => {'version' => '4'}}], 'links' => {'next' => nil}}
      else
        flunk("unexpected path: #{path}")
      end
    end

    assert_equal 5, client.next_build('0.0.1', 2)
    assert client.paths.any? { |path| path.include?('filter%5Bplatform%5D=IOS') }
  end

  def test_pre_release_version_rejects_non_ios_response
    client = ScriptedAppStoreConnect.new do |_path|
      {'data' => [{'id' => 'version-id', 'attributes' => {'version' => '0.0.1', 'platform' => 'MAC_OS'}}]}
    end

    error = assert_raises(RuntimeError) { client.send(:pre_release_version, '0.0.1') }
    assert_includes error.message, 'expected IOS 0.0.1'
  end

  def test_exact_build_polling_uses_build_number_filter
    client = ScriptedAppStoreConnect.new do |path|
      if path.include?('preReleaseVersions')
        {'data' => [{'id' => 'version-id', 'attributes' => {'version' => '0.0.1', 'platform' => 'IOS'}}]}
      else
        {'data' => []}
      end
    end

    client.send(:builds_for, '0.0.1', build_number: 7)

    assert client.paths.any? { |path| path.include?('filter%5Bversion%5D=7') }
  end

  def test_group_lookup_follows_pagination
    client = ScriptedAppStoreConnect.new do |path|
      case path
      when /betaGroups\?/
        {
          'data' => [{'id' => 'first', 'attributes' => {'name' => 'First'}}],
          'links' => {'next' => '/groups-page-2'},
        }
      when '/groups-page-2'
        {'data' => [{'id' => 'target', 'attributes' => {'name' => 'Target'}}]}
      else
        flunk("unexpected path: #{path}")
      end
    end

    assert_equal 'target', client.send(:existing_group, 'Target').fetch('id')
  end

  def test_actionable_beta_states_report_precise_gates
    client = ScriptedAppStoreConnect.new { |_path| flunk('network should not be used') }

    processing = assert_raises(RuntimeError) { client.send(:evaluate_beta_state, 'PROCESSING_EXCEPTION') }
    compliance = assert_raises(RuntimeError) { client.send(:evaluate_beta_state, 'MISSING_EXPORT_COMPLIANCE') }

    assert_includes processing.message, 'processing exception'
    assert_includes compliance.message, 'Export compliance gate'
  end

  def test_resume_does_not_reassign_a_build_already_in_the_group
    client = ScriptedAppStoreConnect.new do |path|
      assert_equal '/v1/betaGroups/group-id/builds?limit=200', path
      {'data' => [{'id' => 'build-id'}]}
    end

    client.send(:assign_group, {'id' => 'build-id'}, {'id' => 'group-id'})

    assert_empty client.posts
  end
end
