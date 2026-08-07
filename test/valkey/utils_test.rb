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

    # Regression tests for issue #184: userinfo containing percent-encoded
    # reserved characters must decode when parsed out of a redis:// URL,
    # otherwise the value flows through `Valkey#initialize`'s re-encoding step
    # and reaches the server double-encoded.
    def test_parse_redis_url_percent_encoded_password
      result = ::Valkey::Utils.parse_redis_url("redis://:p%40ss@127.0.0.1:6379")
      assert_equal "p@ss", result[:password]
    end

    def test_parse_redis_url_percent_encoded_username
      result = ::Valkey::Utils.parse_redis_url("redis://us%3Aer:pw@127.0.0.1:6379")
      assert_equal "us:er", result[:username]
      assert_equal "pw", result[:password]
    end

    def test_parse_redis_url_percent_encoded_space_and_plus_in_password
      # `%20` decodes to space; a literal `+` stays literal (RFC 3986 userinfo,
      # NOT application/x-www-form-urlencoded).
      result = ::Valkey::Utils.parse_redis_url("redis://:hello%20world+plus@127.0.0.1:6379")
      assert_equal "hello world+plus", result[:password]
    end

    def test_parse_redis_url_non_ascii_password
      # 'é' -> UTF-8 bytes 0xC3 0xA9 -> "%C3%A9"
      result = ::Valkey::Utils.parse_redis_url("redis://:caf%C3%A9@127.0.0.1:6379")
      assert_equal "café", result[:password]
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

    # --- HashifyStreamEntries -------------------------------------------------
    # Stream replies arrive in several shapes depending on cluster mode, RESP
    # protocol version, and where recursive Map-flattening lands. The lambda
    # must always produce redis-rb's `[[id, {field => value, ...}], ...]`.

    def test_hashify_stream_entries_nil_returns_empty
      assert_equal [], ::Valkey::Utils::HashifyStreamEntries.call(nil)
    end

    def test_hashify_stream_entries_empty_array_returns_empty
      assert_equal [], ::Valkey::Utils::HashifyStreamEntries.call([])
    end

    def test_hashify_stream_entries_non_stream_shape_returns_empty
      assert_equal [], ::Valkey::Utils::HashifyStreamEntries.call("nope")
      assert_equal [], ::Valkey::Utils::HashifyStreamEntries.call(42)
    end

    # Standalone default: MAP responses get recursively flattened at the FFI
    # layer, so the entry values arrive as a flat `[k, v, k, v]` array.
    def test_hashify_stream_entries_flat_pair_of_pairs
      reply = [["0-1", %w[name alice age 30]], ["0-2", %w[name bob age 40]]]
      result = ::Valkey::Utils::HashifyStreamEntries.call(reply)
      assert_equal [["0-1", { "name" => "alice", "age" => "30" }],
                    ["0-2", { "name" => "bob",   "age" => "40" }]], result
    end

    # Some responses arrive as fully-flat: [id, pairs, id, pairs, ...].
    def test_hashify_stream_entries_fully_flat_array
      reply = ["0-1", %w[name alice age 30], "0-2", %w[name bob age 40]]
      result = ::Valkey::Utils::HashifyStreamEntries.call(reply)
      assert_equal [["0-1", { "name" => "alice", "age" => "30" }],
                    ["0-2", { "name" => "bob",   "age" => "40" }]], result
    end

    # Cluster mode / RESP3: the outer MAP stays a Hash, and glide-core's
    # ArrayOfPairs is preserved as `[[k, v], [k, v]]`.
    def test_hashify_stream_entries_hash_of_pair_of_pairs
      reply = {
        "0-1" => [%w[name alice], %w[age 30]],
        "0-2" => [%w[name bob],   %w[age 40]]
      }
      result = ::Valkey::Utils::HashifyStreamEntries.call(reply)
      # Hash key order is preserved in Ruby, so we can compare directly.
      assert_equal [["0-1", { "name" => "alice", "age" => "30" }],
                    ["0-2", { "name" => "bob",   "age" => "40" }]], result
    end

    # Array of `[id, [[k, v], [k, v]]]` — pair-of-pairs preserved by core.
    def test_hashify_stream_entries_array_of_pair_of_pairs
      reply = [["0-1", [%w[name alice], %w[age 30]]]]
      result = ::Valkey::Utils::HashifyStreamEntries.call(reply)
      assert_equal [["0-1", { "name" => "alice", "age" => "30" }]], result
    end

    # RESP3: the inner MAP is delivered as a Ruby Hash directly.
    def test_hashify_stream_entries_hash_inner_value
      reply = [["0-1", { "name" => "alice", "age" => "30" }]]
      result = ::Valkey::Utils::HashifyStreamEntries.call(reply)
      assert_equal [["0-1", { "name" => "alice", "age" => "30" }]], result
    end

    def test_hashify_stream_entries_nil_inner_value_yields_empty_hash
      reply = [["0-1", nil]]
      result = ::Valkey::Utils::HashifyStreamEntries.call(reply)
      assert_equal [["0-1", {}]], result
    end

    # --- HashifyStreamAutoclaim -----------------------------------------------

    def test_hashify_stream_autoclaim_array_entries
      reply = ["1-1", [["0-1", %w[name alice]]], []]
      result = ::Valkey::Utils::HashifyStreamAutoclaim.call(reply)
      assert_equal "1-1", result["next"]
      assert_equal [["0-1", { "name" => "alice" }]], result["entries"]
    end

    # Regression: cluster/RESP3 hands the entries slot as a Hash. The old
    # `reply[1].is_a?(Array)` guard silently dropped every claimed entry.
    def test_hashify_stream_autoclaim_hash_entries
      reply = ["1-1", { "0-1" => [%w[name alice]] }, []]
      result = ::Valkey::Utils::HashifyStreamAutoclaim.call(reply)
      assert_equal "1-1", result["next"]
      assert_equal [["0-1", { "name" => "alice" }]], result["entries"]
    end

    def test_hashify_stream_autoclaim_nil_entries
      reply = ["0-0", nil, []]
      result = ::Valkey::Utils::HashifyStreamAutoclaim.call(reply)
      assert_equal "0-0", result["next"]
      assert_equal [], result["entries"]
    end
  end
end
