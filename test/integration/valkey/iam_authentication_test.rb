# frozen_string_literal: true

module ValkeyTests
  module IamAuthentication
    AWS_CREDENTIALS = {
      "AWS_ACCESS_KEY_ID" => "test_access_key",
      "AWS_SECRET_ACCESS_KEY" => "test_secret_key",
      "AWS_SESSION_TOKEN" => "test_session_token"
    }.freeze
    IAM_USERNAME = "default"
    IAM_CLUSTER_NAME = "test-cluster"
    IAM_REGION = "us-east-1"

    def test_iam_client_creation_and_manual_refresh_with_mock_credentials
      with_mock_aws_credentials do
        client = nil

        begin
          client = _new_client(
            username: IAM_USERNAME,
            iam_config: Valkey::IamAuthConfig.new(
              cluster_name: IAM_CLUSTER_NAME,
              service: iam_service,
              region: IAM_REGION
            )
          )

          assert_equal "PONG", client.ping
          assert_equal "OK", client.refresh_iam_token
          assert_equal "PONG", client.ping
        ensure
          client&.close
        end
      end
    end

    private

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
end
