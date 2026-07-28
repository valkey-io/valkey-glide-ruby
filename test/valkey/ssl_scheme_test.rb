# frozen_string_literal: true

require "test_helper"

# Unit tests for TLS scheme selection from the :ssl option.
#
class TestSslScheme < Minitest::Test
  # Raised by the stubbed FFI call once it has captured the URI, to abort
  # Valkey#initialize before it tries to touch a real connection pointer.
  class SchemeCaptured < StandardError; end

  # Returns the URI scheme ("rediss" or "redis") that Valkey#initialize builds
  # for the given :ssl option, intercepting the native client creation.
  def scheme_for(options)
    captured_uri = nil
    intercept = lambda do |uri, *_rest|
      captured_uri = uri
      raise SchemeCaptured
    end

    Valkey::Bindings.stub(:create_client_from_uri, intercept) do
      assert_raises(SchemeCaptured) do
        Valkey.new({ host: "localhost", port: 6379 }.merge(options))
      end
    end

    captured_uri.start_with?("rediss://") ? "rediss" : "redis"
  end

  def test_boolean_true_enables_tls
    assert_equal "rediss", scheme_for(ssl: true)
  end

  def test_string_true_enables_tls
    assert_equal "rediss", scheme_for(ssl: "true")
  end

  def test_integer_one_enables_tls
    assert_equal "rediss", scheme_for(ssl: 1)
  end

  def test_string_one_enables_tls
    assert_equal "rediss", scheme_for(ssl: "1")
  end

  def test_uppercase_true_string_enables_tls
    assert_equal "rediss", scheme_for(ssl: "TRUE")
  end

  def test_yes_string_enables_tls
    assert_equal "rediss", scheme_for(ssl: "yes")
  end

  def test_truthy_symbol_enables_tls
    assert_equal "rediss", scheme_for(ssl: :enabled)
  end

  def test_truthy_object_enables_tls
    assert_equal "rediss", scheme_for(ssl: Object.new)
  end

  def test_boolean_false_selects_plaintext
    assert_equal "redis", scheme_for(ssl: false)
  end

  def test_nil_selects_plaintext
    assert_equal "redis", scheme_for(ssl: nil)
  end

  def test_absent_ssl_option_selects_plaintext
    assert_equal "redis", scheme_for({})
  end
end
