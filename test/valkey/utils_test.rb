# frozen_string_literal: true

module ValkeyTests
  module Utils
    def test_parse_redis_url_simple
      result = ::Valkey::Utils.parse_redis_url("redis://127.0.0.1:6379")
      assert_equal "127.0.0.1", result[:host]
      assert_equal 6379, result[:port]
      assert_nil result[:username]
      assert_nil result[:password]
      assert_nil result[:db]
      assert_equal false, result[:ssl]
    end

    def test_parse_redis_url_with_database
      result = ::Valkey::Utils.parse_redis_url("redis://127.0.0.1:6379/15")
      assert_equal "127.0.0.1", result[:host]
      assert_equal 6379, result[:port]
      assert_nil result[:username]
      assert_nil result[:password]
      assert_equal 15, result[:db]
      assert_equal false, result[:ssl]
    end

    def test_parse_redis_url_with_password
      result = ::Valkey::Utils.parse_redis_url("redis://:password@127.0.0.1:6379")
      assert_equal "127.0.0.1", result[:host]
      assert_equal 6379, result[:port]
      assert_nil result[:username]
      assert_equal "password", result[:password]
      assert_nil result[:db]
      assert_equal false, result[:ssl]
    end

    def test_parse_redis_url_with_username_and_password
      result = ::Valkey::Utils.parse_redis_url("redis://user:password@127.0.0.1:6379")
      assert_equal "127.0.0.1", result[:host]
      assert_equal 6379, result[:port]
      assert_equal "user", result[:username]
      assert_equal "password", result[:password]
      assert_nil result[:db]
      assert_equal false, result[:ssl]
    end

    def test_parse_redis_url_with_username_password_and_database
      result = ::Valkey::Utils.parse_redis_url("redis://user:password@127.0.0.1:6379/5")
      assert_equal "127.0.0.1", result[:host]
      assert_equal 6379, result[:port]
      assert_equal "user", result[:username]
      assert_equal "password", result[:password]
      assert_equal 5, result[:db]
      assert_equal false, result[:ssl]
    end

    def test_parse_redis_url_ssl
      result = ::Valkey::Utils.parse_redis_url("rediss://127.0.0.1:6379")
      assert_equal "127.0.0.1", result[:host]
      assert_equal 6379, result[:port]
      assert_equal true, result[:ssl]
    end

    def test_parse_redis_url_ssl_with_auth
      result = ::Valkey::Utils.parse_redis_url("rediss://user:pass@127.0.0.1:6379/2")
      assert_equal "127.0.0.1", result[:host]
      assert_equal 6379, result[:port]
      assert_equal "user", result[:username]
      assert_equal "pass", result[:password]
      assert_equal 2, result[:db]
      assert_equal true, result[:ssl]
    end

    def test_parse_redis_url_default_port
      result = ::Valkey::Utils.parse_redis_url("redis://127.0.0.1")
      assert_equal "127.0.0.1", result[:host]
      assert_equal 6379, result[:port]
    end

    def test_parse_redis_url_custom_port
      result = ::Valkey::Utils.parse_redis_url("redis://127.0.0.1:6380")
      assert_equal "127.0.0.1", result[:host]
      assert_equal 6380, result[:port]
    end

    def test_parse_redis_url_nil
      result = ::Valkey::Utils.parse_redis_url(nil)
      assert_equal({}, result)
    end

    def test_parse_redis_url_empty_string
      result = ::Valkey::Utils.parse_redis_url("")
      assert_equal({}, result)
    end

    def test_parse_redis_url_invalid_format
      error = assert_raises(ArgumentError) { ::Valkey::Utils.parse_redis_url("not-a-url") }
      assert_match(/not-a-url/, error.message)
    end

    def test_parse_redis_url_trailing_slash
      result = ::Valkey::Utils.parse_redis_url("redis://myhost.example.com:6380/")
      assert_equal "myhost.example.com", result[:host]
      assert_equal 6380, result[:port]
      assert_nil result[:db]
      assert_equal false, result[:ssl]
    end

    def test_parse_redis_url_ipv6_host
      result = ::Valkey::Utils.parse_redis_url("redis://[::1]:6379/0")
      assert_equal "::1", result[:host]
      assert_equal 6379, result[:port]
      assert_equal 0, result[:db]
    end

    def test_parse_redis_url_valkey_scheme
      result = ::Valkey::Utils.parse_redis_url("valkey://myhost.example.com:6380/0")
      assert_equal "myhost.example.com", result[:host]
      assert_equal 6380, result[:port]
      assert_equal 0, result[:db]
      assert_equal false, result[:ssl]
    end

    def test_parse_redis_url_valkeys_scheme_enables_tls
      result = ::Valkey::Utils.parse_redis_url("valkeys://user:pass@myhost.example.com:6380/2")
      assert_equal "myhost.example.com", result[:host]
      assert_equal 6380, result[:port]
      assert_equal "user", result[:username]
      assert_equal "pass", result[:password]
      assert_equal 2, result[:db]
      assert_equal true, result[:ssl]
    end

    def test_parse_redis_url_unknown_scheme_raises
      error = assert_raises(ArgumentError) { ::Valkey::Utils.parse_redis_url("http://localhost:6379") }
      assert_match(/scheme must be one of/, error.message)
    end

    def test_parse_redis_url_missing_host_raises
      error = assert_raises(ArgumentError) { ::Valkey::Utils.parse_redis_url("redis://") }
      assert_match(/missing host/, error.message)
    end

    def test_parse_redis_url_non_integer_db_raises
      error = assert_raises(ArgumentError) do
        ::Valkey::Utils.parse_redis_url("redis://localhost:6379/not-a-number")
      end
      assert_match(/database must be a non-negative integer/, error.message)
    end

    def test_parse_redis_url_error_message_redacts_credentials
      # Non-integer db (validated after URI parse)
      error = assert_raises(ArgumentError) do
        ::Valkey::Utils.parse_redis_url("redis://user:supersecret@localhost:6379/not-a-number")
      end
      refute_match(/supersecret/, error.message)
      assert_match(/REDACTED/, error.message)

      # URI.parse itself failing — must not leak the password from the underlying error
      error = assert_raises(ArgumentError) do
        ::Valkey::Utils.parse_redis_url("redis://user:supersecret@bad-host:notaport/x")
      end
      refute_match(/supersecret/, error.message)
      assert_match(/REDACTED/, error.message)

      # Password containing `/` — must still redact, not slip through userinfo
      error = assert_raises(ArgumentError) do
        ::Valkey::Utils.parse_redis_url("redis://user:sup/er/secret@bad-host:notaport/x")
      end
      refute_match(%r{sup/er/secret}, error.message)
      assert_match(/REDACTED/, error.message)

      # Password containing raw `@`
      error = assert_raises(ArgumentError) do
        ::Valkey::Utils.parse_redis_url("redis://user:p@ss@bad-host:notaport/x")
      end
      refute_match(/p@ss/, error.message)
      assert_match(/REDACTED/, error.message)
    end
  end
end
