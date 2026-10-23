# frozen_string_literal: true

module ValkeyTests
  # IAM authentication tests. These are NOT run against AWS. They run against a local
  # server without IAM enforcement, using the placeholder credentials installed by
  # Helper::MockAwsCredentials.
  #
  # IAM auth requires TLS (an IAM token must never traverse plaintext), so the
  # client-creation test connects over the standalone TLS server and skips when no
  # TLS server is available (including the cluster context, which has no TLS endpoint).
  #
  # What they confirm:
  # - `iam_config:` and `username:` reach GLIDE Core, which resolves credentials,
  #   signs a token, and authenticates with it over a TLS connection.
  # - `refresh_iam_token` round-trips through FFI for every ServiceType.
  # - Ruby rejects IAM configuration without a username, Core's IAM interval
  #   validation errors surface as Valkey::CannotConnectError, and refreshing
  #   a client without IAM raises Valkey::CommandError.
  #
  # What they do not confirm:
  # - That the token is valid: the server accepts any AUTH password, so the
  #   signature, cluster name, region, service, and expiry are never checked.
  # - Real AWS credential resolution (profiles, instance metadata, STS).
  # - Automatic refresh at the configured interval.
  # - Behavior against real ElastiCache or MemoryDB.
  module IamAuthentication
    include SslHelper

    IAM_USERNAME = "default"
    IAM_CLUSTER_NAME = "test-cluster"
    IAM_REGION = "us-east-1"

    extend Helper::Parameterized

    parameterized_test(
      :test_iam_client_creation_and_manual_refresh,
      service: [Valkey::ServiceType::ELASTICACHE, Valkey::ServiceType::MEMORYDB]
    ) do |service|
      skip_unless_tls_available

      client = _new_iam_tls_client(username: IAM_USERNAME, iam_config: iam_config(service: service))

      assert_equal "PONG", client.ping
      assert_equal "OK", client.refresh_iam_token
      assert_equal "PONG", client.ping
    ensure
      client&.close
    end

    def test_iam_requires_username
      error = assert_raises(ArgumentError) { _new_client(iam_config: iam_config) }

      assert_includes error.message, "username is required for iam_config"
    end

    # The refresh-interval checks live in GLIDE Core, behind the IAM-requires-TLS
    # guard, so these must connect over TLS to reach the interval validation
    # instead of being rejected for plaintext first.
    def test_invalid_iam_refresh_interval_fails_creation
      skip_unless_tls_available

      error = assert_iam_creation_fails(
        tls: true,
        username: IAM_USERNAME,
        iam_config: iam_config(refresh_interval_seconds: 0)
      )

      assert_includes error.message, "Invalid refresh interval"
    end

    def test_max_iam_refresh_interval_fails_creation
      skip_unless_tls_available

      error = assert_iam_creation_fails(
        tls: true,
        username: IAM_USERNAME,
        iam_config: iam_config(refresh_interval_seconds: 43_200)
      )

      assert_includes error.message, "Invalid refresh interval"
    end

    # "Unknown service type" is rejected in Ruby before Client::new, so this needs
    # no TLS connection and runs in every context.
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

    # IAM auth requires TLS, so build the client against the standalone TLS server
    # (port SSL_PORT) with the suite's CA cert, mirroring the TLS connection tests.
    def _new_iam_tls_client(**options)
      Valkey.new(
        host: "127.0.0.1",
        port: defined?(SSL_PORT) ? SSL_PORT : 6380,
        ssl: true,
        ssl_params: { ca_file: ssl_ca_cert_path },
        timeout: TIMEOUT,
        **options
      )
    end

    # No TLS server exists for the cluster context, and TLS is skipped on platforms
    # where the harness can't stand one up (e.g. macOS CI via SKIP_TLS_TESTS).
    def skip_unless_tls_available
      skip("TLS tests disabled via SKIP_TLS_TESTS") if defined?(SKIP_TLS_TESTS) && SKIP_TLS_TESTS
      skip("no TLS server for the cluster context") if cluster_mode?
      skip("TLS_CERT_DIR is not set") if ENV.fetch("TLS_CERT_DIR", "").empty?
    end

    def iam_config(service: Valkey::ServiceType::ELASTICACHE, refresh_interval_seconds: nil)
      Valkey::IamAuthConfig.new(
        cluster_name: IAM_CLUSTER_NAME,
        service: service,
        region: IAM_REGION,
        refresh_interval_seconds: refresh_interval_seconds
      )
    end

    def assert_iam_creation_fails(tls: false, **options)
      client = nil
      assert_raises(Valkey::CannotConnectError) do
        client = tls ? _new_iam_tls_client(**options) : _new_client(**options)
      end
    ensure
      client&.close
    end
  end
end
