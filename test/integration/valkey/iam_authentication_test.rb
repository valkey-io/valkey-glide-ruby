# frozen_string_literal: true

module ValkeyTests
  # IAM authentication tests. These are NOT run against AWS. They run against a local
  # server without IAM enforcement, using the placeholder credentials installed by
  # Helper::MockAwsCredentials.
  #
  # What they confirm:
  # - `iam_config:` and `username:` reach GLIDE Core, which resolves credentials,
  #   signs a token, and authenticates with it in standalone and cluster mode.
  # - `refresh_iam_token` round-trips through FFI for every ServiceType.
  # - Core's IAM validation errors surface as Valkey::CannotConnectError, and
  #   refreshing a client without IAM raises Valkey::CommandError.
  #
  # What they do not confirm:
  # - That the token is valid: the server accepts any AUTH password, so the
  #   signature, cluster name, region, service, and expiry are never checked.
  # - Real AWS credential resolution (profiles, instance metadata, STS).
  # - Automatic refresh at the configured interval.
  # - Behavior against real ElastiCache or MemoryDB, including required TLS.
  module IamAuthentication
    IAM_USERNAME = "default"
    IAM_CLUSTER_NAME = "test-cluster"
    IAM_REGION = "us-east-1"

    extend Helper::Parameterized

    parameterized_test(
      :test_iam_client_creation_and_manual_refresh,
      service: [Valkey::ServiceType::ELASTICACHE, Valkey::ServiceType::MEMORYDB]
    ) do |service|
      client = _new_client(username: IAM_USERNAME, iam_config: iam_config(service: service))

      assert_equal "PONG", client.ping
      assert_equal "OK", client.refresh_iam_token
      assert_equal "PONG", client.ping
    ensure
      client&.close
    end

    def test_iam_requires_username
      error = assert_iam_creation_fails(iam_config: iam_config)

      assert_includes error.message, "IAM authentication requires a username"
    end

    def test_invalid_iam_refresh_interval_fails_creation
      error = assert_iam_creation_fails(
        username: IAM_USERNAME,
        iam_config: iam_config(refresh_interval_seconds: 0)
      )

      assert_includes error.message, "Invalid refresh interval"
    end

    def test_max_iam_refresh_interval_fails_creation
      error = assert_iam_creation_fails(
        username: IAM_USERNAME,
        iam_config: iam_config(refresh_interval_seconds: 43_200)
      )

      assert_includes error.message, "Invalid refresh interval"
    end

    def test_invalid_iam_service_fails_creation
      error = assert_iam_creation_fails(
        username: IAM_USERNAME,
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
        cluster_name: IAM_CLUSTER_NAME,
        service: service,
        region: IAM_REGION,
        refresh_interval_seconds: refresh_interval_seconds
      )
    end

    def assert_iam_creation_fails(**options)
      client = nil
      assert_raises(Valkey::CannotConnectError) { client = _new_client(**options) }
    ensure
      client&.close
    end
  end
end
