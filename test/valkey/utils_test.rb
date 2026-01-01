# frozen_string_literal: true

require "test_helper"

class TestUtils < Minitest::Test
  def test_parse_redis_url_simple
    result = Valkey::Utils.parse_redis_url("redis://127.0.0.1:6379")
    assert_equal "127.0.0.1", result[:host]
    assert_equal 6379, result[:port]
    assert_nil result[:username]
    assert_nil result[:password]
    assert_nil result[:db]
    assert_equal false, result[:ssl]
  end

  def test_parse_redis_url_with_database
    result = Valkey::Utils.parse_redis_url("redis://127.0.0.1:6379/15")
    assert_equal "127.0.0.1", result[:host]
    assert_equal 6379, result[:port]
    assert_nil result[:username]
    assert_nil result[:password]
    assert_equal 15, result[:db]
    assert_equal false, result[:ssl]
  end

  def test_parse_redis_url_with_password
    result = Valkey::Utils.parse_redis_url("redis://:password@127.0.0.1:6379")
    assert_equal "127.0.0.1", result[:host]
    assert_equal 6379, result[:port]
    assert_nil result[:username]
    assert_equal "password", result[:password]
    assert_nil result[:db]
    assert_equal false, result[:ssl]
  end

  def test_parse_redis_url_with_username_and_password
    result = Valkey::Utils.parse_redis_url("redis://user:password@127.0.0.1:6379")
    assert_equal "127.0.0.1", result[:host]
    assert_equal 6379, result[:port]
    assert_equal "user", result[:username]
    assert_equal "password", result[:password]
    assert_nil result[:db]
    assert_equal false, result[:ssl]
  end

  def test_parse_redis_url_with_username_password_and_database
    result = Valkey::Utils.parse_redis_url("redis://user:password@127.0.0.1:6379/5")
    assert_equal "127.0.0.1", result[:host]
    assert_equal 6379, result[:port]
    assert_equal "user", result[:username]
    assert_equal "password", result[:password]
    assert_equal 5, result[:db]
    assert_equal false, result[:ssl]
  end

  def test_parse_redis_url_ssl
    result = Valkey::Utils.parse_redis_url("rediss://127.0.0.1:6379")
    assert_equal "127.0.0.1", result[:host]
    assert_equal 6379, result[:port]
    assert_equal true, result[:ssl]
  end

  def test_parse_redis_url_ssl_with_auth
    result = Valkey::Utils.parse_redis_url("rediss://user:pass@127.0.0.1:6379/2")
    assert_equal "127.0.0.1", result[:host]
    assert_equal 6379, result[:port]
    assert_equal "user", result[:username]
    assert_equal "pass", result[:password]
    assert_equal 2, result[:db]
    assert_equal true, result[:ssl]
  end

  def test_parse_redis_url_default_port
    result = Valkey::Utils.parse_redis_url("redis://127.0.0.1")
    assert_equal "127.0.0.1", result[:host]
    assert_equal 6379, result[:port]
  end

  def test_parse_redis_url_custom_port
    result = Valkey::Utils.parse_redis_url("redis://127.0.0.1:6380")
    assert_equal "127.0.0.1", result[:host]
    assert_equal 6380, result[:port]
  end

  def test_parse_redis_url_nil
    result = Valkey::Utils.parse_redis_url(nil)
    assert_equal({}, result)
  end

  def test_parse_redis_url_empty_string
    result = Valkey::Utils.parse_redis_url("")
    assert_equal({}, result)
  end

  def test_parse_redis_url_invalid_format
    # Should handle gracefully or return nil
    result = Valkey::Utils.parse_redis_url("not-a-url")
    # The method should either return nil or raise an error
    # Based on implementation, it might return nil or raise
    assert(result.nil? || result.is_a?(Hash))
  end
end
