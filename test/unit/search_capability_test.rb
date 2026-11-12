# frozen_string_literal: true

# Pure unit tests for Helper::SearchCapability's server-free logic: the
# INKEYS-probe error classifier and the `search.emulate-release`
# CONFIG GET reply parser. No server, no FFI.
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "minitest/autorun"
require "securerandom"
require_relative "../support/helper/search_capability"

class ClassifyInkeysProbeErrorTest < Minitest::Test
  def test_matches_glide_reformatted_spelling
    assert Helper::SearchCapability.inkeys_probe_error?("Unexpected: argument `INKEYS`")
  end

  def test_matches_raw_server_spelling
    assert Helper::SearchCapability.inkeys_probe_error?("Unexpected argument `INKEYS`")
  end

  def test_does_not_match_unrelated_error
    refute Helper::SearchCapability.inkeys_probe_error?("Index: field `AS` does not exist")
  end

  def test_does_not_match_partial_keyword_match
    refute Helper::SearchCapability.inkeys_probe_error?("INKEYS is fine here")
  end
end

class ParseEmulateReleaseLevelTest < Minitest::Test
  def test_hash_reply
    assert_equal "1.3.0", Helper::SearchCapability.parse_emulate_release_level({ "search.emulate-release" => "1.3.0" })
  end

  def test_flat_array_reply
    assert_equal "1.0.0",
                 Helper::SearchCapability.parse_emulate_release_level(["search.emulate-release", "1.0.0"])
  end

  def test_empty_hash_returns_nil
    assert_nil Helper::SearchCapability.parse_emulate_release_level({})
  end

  def test_empty_array_returns_nil
    assert_nil Helper::SearchCapability.parse_emulate_release_level([])
  end

  def test_missing_key_returns_nil
    assert_nil Helper::SearchCapability.parse_emulate_release_level({ "some.other.key" => "value" })
  end

  def test_scalar_returns_nil
    assert_nil Helper::SearchCapability.parse_emulate_release_level("1.3.0")
  end

  def test_nil_returns_nil
    assert_nil Helper::SearchCapability.parse_emulate_release_level(nil)
  end

  def test_odd_length_array_does_not_raise
    assert_nil Helper::SearchCapability.parse_emulate_release_level(["search.emulate-release"])
  end
end
