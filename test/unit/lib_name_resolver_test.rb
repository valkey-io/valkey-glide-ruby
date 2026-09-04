# frozen_string_literal: true

require "test_helper"

# Unit tests for Valkey.resolve_lib_name — the pure resolver behind the
# `CLIENT SETINFO LIB-NAME` value. These need no running server and make no
# connection; they cover the whole composition matrix in the Ruby layer only.
#
# They are not, however, dependency-free: requiring test_helper loads `valkey`,
# which dlopens the native library at require time, so a checkout without a built
# library cannot load this file.
#
# Character validity is intentionally NOT tested here, because it is not the
# wrapper's concern — glide-core validates the composed name before client
# creation (valkey-io/valkey-glide#6891). What is tested is composition and the
# empty-means-absent normalization, which the wrapper does own.
class TestLibNameResolverUnit < Minitest::Test
  def test_default_when_nothing_configured
    assert_equal "GlideRuby", Valkey.resolve_lib_name
  end

  # Pins the constant's literal value. The previous
  # `assert_equal Valkey::DEFAULT_LIB_NAME, Valkey.resolve_lib_name` was
  # tautological — both sides resolve through the same constant, so it passed
  # even if the constant were changed to something invalid.
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

  # Regression: an empty override with a tag previously composed "(tag)", which
  # glide-core rejects because the name must not start with a parenthesis.
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

  # Previously any object was accepted via a blanket `to_s`. `lib_name: false`
  # was the sharp edge — a caller passing a predicate got a client identifying
  # itself to the server as "false" with no error. Arbitrary objects also let
  # non-Valkey exceptions (JSON::GeneratorError, or anything raised by the
  # object's own #to_s) escape Valkey.new, breaking the documented
  # `rescue Valkey::BaseError` contract.
  #
  # This is a type check, not character validation — character validity is still
  # glide-core's responsibility.
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

  # F-16/F-04: whitespace-only is NOT folded to absent — it is passed through and
  # rejected by core. This is settled policy, not incidental: client-side
  # filtering is deliberately not performed, because the server is the authority
  # on library-name validity and its error is the intended feedback for what is a
  # caller mistake. Core's grammar excludes 0x20 (its ranges start at \x21), so
  # "GlideRuby( )" fails validation and surfaces as Valkey::CannotConnectError at
  # client creation.
  #
  # Do NOT "fix" this by normalizing whitespace away. Empty and whitespace are
  # different cases on purpose: empty means absent (core returns Ok for it),
  # whitespace is invalid input.
  def test_whitespace_only_values_are_not_folded_to_absent
    assert_equal "GlideRuby( )", Valkey.resolve_lib_name(client_info_tag: " ")
    assert_equal " ", Valkey.resolve_lib_name(lib_name: " ")
  end

  # --- Encoding preconditions ---
  #
  # These guards shipped untested, and that is precisely why the contract below
  # took three rounds to close. Each earlier attempt fixed the reported INPUT
  # rather than the PROPERTY, so the next input class slipped through:
  #
  #   attempt 1: no check        -> false, custom #to_s, and all bad bytes escaped
  #   attempt 2: valid_encoding? -> binary strings still escaped (every byte
  #                                 sequence is "valid" ASCII-8BIT)
  #   attempt 3: #encode alone   -> a String already tagged UTF-8 but holding
  #                                 invalid bytes still escaped (#encode is a
  #                                 no-op when the encoding already matches)
  #
  # So the decisive test is the property one at the end of this section, not the
  # per-input cases above it.

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
    # ISO-8859-1 "café" converts cleanly, so it passes the wrapper untouched and
    # is left for glide-core to judge — bytes are screened here, characters are not.
    assert_equal "café", Valkey.resolve_lib_name(lib_name: "caf\xE9".dup.force_encoding("ISO-8859-1"))
  end

  def test_accepts_valid_non_ascii_utf8
    # Character validity is core's call, not ours: this must NOT raise here.
    assert_equal "café", Valkey.resolve_lib_name(lib_name: "café")
  end

  def test_encoding_guard_applies_to_the_tag_too
    error = assert_raises(ArgumentError) do
      Valkey.resolve_lib_name(client_info_tag: "\xC3".dup.force_encoding("UTF-8"))
    end
    assert_match(/client_info_tag must not contain an invalid UTF-8/, error.message)
  end
end
