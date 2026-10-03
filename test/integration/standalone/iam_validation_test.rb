# frozen_string_literal: true

require "test_helper"

class TestStandaloneIamValidation < Minitest::Test
  include Helper::Client

  AWS_CREDENTIALS = {
    "AWS_ACCESS_KEY_ID" => "test_access_key",
    "AWS_SECRET_ACCESS_KEY" => "test_secret_key",
    "AWS_SESSION_TOKEN" => "test_session_token"
  }.freeze

  def test_iam_requires_username
    error = assert_iam_creation_fails(
      iam_config: iam_config
    )

    assert_includes error.message, "IAM authentication requires a username"
  end

  def test_invalid_iam_refresh_interval_fails_creation
    error = assert_iam_creation_fails(
      username: "default",
      iam_config: iam_config(refresh_interval_seconds: 0)
    )

    assert_includes error.message, "Invalid refresh interval"
  end

  def test_max_iam_refresh_interval_fails_creation
    error = assert_iam_creation_fails(
      username: "default",
      iam_config: iam_config(refresh_interval_seconds: 43_200)
    )

    assert_includes error.message, "Invalid refresh interval"
  end

  def test_invalid_iam_service_fails_creation
    error = assert_iam_creation_fails(
      username: "default",
      iam_config: iam_config(service: "OTHER")
    )

    assert_includes error.message, "Unknown service type"
  end

  def test_refresh_iam_token_without_iam
    error = assert_raises(Valkey::CommandError) { valkey.refresh_iam_token }

    assert_includes error.message, "No IAM token manager configured"
  end

  private

  def iam_config(service: Valkey::ServiceType::ELASTICACHE, refresh_interval_seconds: nil)
    Valkey::IamAuthConfig.new(
      cluster_name: "test-cluster",
      service: service,
      region: "us-east-1",
      refresh_interval_seconds: refresh_interval_seconds
    )
  end

  def assert_iam_creation_fails(**options)
    with_mock_aws_credentials do
      client = nil

      begin
        error = assert_raises(Valkey::CannotConnectError) do
          client = _new_client(**options)
        end
        return error
      ensure
        client&.close
      end
    end
  end

  def with_mock_aws_credentials
    previous_credentials = AWS_CREDENTIALS.to_h { |name, _value| [name, ENV.fetch(name, nil)] }
    AWS_CREDENTIALS.each { |name, value| ENV[name] = value }
    yield
  ensure
    previous_credentials&.each do |name, value|
      if value.nil?
        ENV.delete(name)
      else
        ENV[name] = value
      end
    end
  end
end
