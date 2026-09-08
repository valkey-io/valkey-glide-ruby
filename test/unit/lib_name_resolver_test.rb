# frozen_string_literal: true

require "test_helper"

# Unit tests for `Valkey.resolve_lib_name`.
class TestLibNameResolverUnit < Minitest::Test
  def test_default_when_nothing_configured
    assert_equal "GlideRuby", Valkey.resolve_lib_name
  end

  # Pinned as a literal so a change to the constant is deliberate.
  def test_default_lib_name_constant_value
    assert_equal "GlideRuby", Valkey::DEFAULT_LIB_NAME
  end

  def test_lib_name_override
    assert_equal "CustomLib", Valkey.resolve_lib_name(lib_name: "CustomLib")
  end

  def test_tag_only_appends_to_default
    assert_equal "GlideRuby(tag)", Valkey.resolve_lib_name(client_info_tag: "tag")
  end

  def test_lib_name_and_tag_combine
    assert_equal "CustomLib(tag)", Valkey.resolve_lib_name(lib_name: "CustomLib", client_info_tag: "tag")
  end

  # An empty string is truthy in Ruby, so each empty form needs its own guard.
  # Empty means "not configured", matching glide-core's empty-means-absent rule.

  def test_empty_lib_name_falls_back_to_default
    assert_equal "GlideRuby", Valkey.resolve_lib_name(lib_name: "")
  end

  def test_empty_tag_produces_no_suffix
    assert_equal "GlideRuby", Valkey.resolve_lib_name(client_info_tag: "")
  end

  def test_both_empty_falls_back_to_default
    assert_equal "GlideRuby", Valkey.resolve_lib_name(lib_name: "", client_info_tag: "")
  end

  def test_empty_lib_name_with_tag_uses_default_base
    assert_equal "GlideRuby(tag)", Valkey.resolve_lib_name(lib_name: "", client_info_tag: "tag")
  end

  def test_lib_name_with_empty_tag_produces_no_suffix
    assert_equal "CustomLib", Valkey.resolve_lib_name(lib_name: "CustomLib", client_info_tag: "")
  end

  def test_never_composes_empty_parentheses
    ["", nil].each do |tag|
      refute_includes Valkey.resolve_lib_name(lib_name: "CustomLib", client_info_tag: tag), "()"
    end
  end

  def test_symbol_values_are_accepted
    assert_equal "CustomLib(tag)", Valkey.resolve_lib_name(lib_name: :CustomLib, client_info_tag: :tag)
  end

  def test_false_is_rejected_rather_than_stringified
    error = assert_raises(ArgumentError) { Valkey.resolve_lib_name(lib_name: false) }
    assert_match(/lib_name must be a String, Symbol, or nil/, error.message)
  end

  def test_arbitrary_object_is_rejected
    error = assert_raises(ArgumentError) { Valkey.resolve_lib_name(lib_name: Object.new) }
    assert_match(/lib_name must be a String, Symbol, or nil/, error.message)
  end

  def test_integer_tag_is_rejected
    error = assert_raises(ArgumentError) { Valkey.resolve_lib_name(client_info_tag: 42) }
    assert_match(/client_info_tag must be a String, Symbol, or nil/, error.message)
  end

  def test_explicit_nil_values_are_absent
    assert_equal "GlideRuby", Valkey.resolve_lib_name(lib_name: nil, client_info_tag: nil)
  end

  # Core's name grammar starts at \x21, so "GlideRuby( )" is rejected at
  # client creation rather than folded to absent here.
  def test_whitespace_only_values_are_not_folded_to_absent
    assert_equal "GlideRuby( )", Valkey.resolve_lib_name(client_info_tag: " ")
    assert_equal " ", Valkey.resolve_lib_name(lib_name: " ")
  end

  def test_rejects_invalid_utf8_bytes
    error = assert_raises(ArgumentError) do
      Valkey.resolve_lib_name(lib_name: "\xC3".dup.force_encoding("UTF-8"))
    end
    assert_match(/lib_name must not contain an invalid UTF-8 byte sequence/, error.message)
  end

  def test_rejects_binary_string_not_representable_as_utf8
    error = assert_raises(ArgumentError) do
      Valkey.resolve_lib_name(lib_name: "ab\xFFc".dup.force_encoding("ASCII-8BIT"))
    end
    assert_match(/lib_name must be convertible to UTF-8/, error.message)
  end

  def test_accepts_binary_string_that_is_representable_as_utf8
    assert_equal "plain", Valkey.resolve_lib_name(lib_name: "plain".dup.force_encoding("ASCII-8BIT"))
  end

  def test_accepts_other_encodings_convertible_to_utf8
    assert_equal "café", Valkey.resolve_lib_name(lib_name: "caf\xE9".dup.force_encoding("ISO-8859-1"))
  end

  def test_accepts_valid_non_ascii_utf8
    assert_equal "café", Valkey.resolve_lib_name(lib_name: "café")
  end

  def test_encoding_guard_applies_to_the_tag_too
    error = assert_raises(ArgumentError) do
      Valkey.resolve_lib_name(client_info_tag: "\xC3".dup.force_encoding("UTF-8"))
    end
    assert_match(/client_info_tag must not contain an invalid UTF-8/, error.message)
  end
end
