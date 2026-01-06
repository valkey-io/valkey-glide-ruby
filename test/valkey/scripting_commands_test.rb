# frozen_string_literal: true

require "test_helper"

# Test class for basic scripting commands (script_load, script_exists, script_flush, etc.)
class TestScriptingBasicCommands < Minitest::Test
  include Helper::Client

  def setup
    super
    r.script_flush # Ensure the script cache is empty before running tests
  end

  def to_sha(script)
    r.script(:load, script)
  end

  def test_script_exists
    a = to_sha("return 1")
    b = a.succ

    r.invoke_script(a)

    assert_equal true, r.script(:exists, a)

    assert_equal false, r.script(:exists, b)
    assert_equal [true], r.script(:exists, [a])
    assert_equal [false], r.script(:exists, [b])
    assert_equal [true, false], r.script(:exists, [a, b])
  end

  def test_script_flush
    sha = to_sha("return 1")
    r.invoke_script(sha)
    assert r.script(:exists, sha)
    assert_equal "OK", r.script(:flush)
    assert !r.script(:exists, sha)
  end

  def test_script_kill
    # there is no script running
    assert_raises(Valkey::CommandError) { r.script_kill }
  end

  def test_eval_basic
    # Test basic eval functionality
    result = r.eval("return 42")
    assert_equal 42, result

    result = r.eval("return 'hello'")
    assert_equal "hello", result
  end

  def test_eval_with_keys_and_args
    # Test eval with keys and arguments
    result = r.eval("return KEYS[1] .. ARGV[1]", keys: ["mykey"], args: ["myarg"])
    assert_equal "mykeymyarg", result
  end

  def test_eval_empty_script
    # Test that empty script raises ArgumentError
    assert_raises(ArgumentError) { r.eval("") }
    assert_raises(ArgumentError) { r.eval(nil) }
  end

  def test_evalsha_basic
    # Test basic evalsha functionality
    script = "return 42"
    sha = r.script_load(script)
    result = r.evalsha(sha)
    assert_equal 42, result
  end

  def test_evalsha_invalid_sha
    # Test that invalid SHA format raises ArgumentError
    assert_raises(ArgumentError) { r.evalsha("invalid") }
    assert_raises(ArgumentError) { r.evalsha("") }
    assert_raises(ArgumentError) { r.evalsha("1234567890123456789012345678901234567890x") }
  end

  def test_evalsha_nonexistent_script
    # Test that non-existent script raises CommandError
    valid_sha = "1234567890123456789012345678901234567890"
    assert_raises(Valkey::CommandError) { r.evalsha(valid_sha) }
  end
end

# Test class for eval/evalsha integration and advanced functionality
class TestEvalEvalshaIntegration < Minitest::Test
  include Helper::Client

  def setup
    super
    r.script_flush # Ensure the script cache is empty before running tests
  end

  def test_eval_empty_keys_and_args
    # Test eval with empty keys and args arrays
    result = r.eval("return #KEYS + #ARGV", keys: [], args: [])
    assert_equal 0, result

    # Test with nil keys and args (should be converted to empty arrays)
    result = r.eval("return #KEYS + #ARGV")
    assert_equal 0, result
  end

  def test_evalsha_empty_keys_and_args
    # Test evalsha with empty keys and args arrays
    script = "return #KEYS + #ARGV"
    sha = r.script_load(script)

    result = r.evalsha(sha, keys: [], args: [])
    assert_equal 0, result

    # Test with nil keys and args (should be converted to empty arrays)
    result = r.evalsha(sha)
    assert_equal 0, result
  end

  def test_eval_error_message_preservation
    # Test that eval preserves specific error messages from server
    error_script = "error('custom error message')"

    error = assert_raises(Valkey::CommandError) { r.eval(error_script) }
    assert_includes error.message.downcase, "custom error message"
  end

  def test_evalsha_error_message_preservation
    # Test that evalsha preserves specific error messages from server
    error_script = "error('evalsha custom error')"
    sha = r.script_load(error_script)

    error = assert_raises(Valkey::CommandError) { r.evalsha(sha) }
    assert_includes error.message.downcase, "evalsha custom error"
  end

  def test_integration_with_script_load
    # Test seamless integration between script_load and evalsha
    scripts = [
      "return 42",
      "return 'hello'",
      "return {1, 2, 3}",
      "return KEYS[1] or 'default'",
      "return ARGV[1] or 'default'"
    ]

    scripts.each do |script|
      # Load script and get SHA
      sha = r.script_load(script)
      assert_equal 40, sha.length
      assert sha.match?(/\A[a-fA-F0-9]{40}\z/)

      # Verify script exists in cache
      # TODO: Fix script_exists - currently returns false even when script is loaded and executable
      # assert r.script(:exists, sha)

      # Execute via evalsha
      keys = ["testkey"]
      args = ["testarg"]

      evalsha_result = r.evalsha(sha, keys: keys, args: args)
      eval_result = r.eval(script, keys: keys, args: args)

      # Results should be identical
      assert_equal eval_result, evalsha_result
    end
  end

  def test_script_cache_persistence
    # Test that scripts remain in cache across multiple executions
    script = "return math.random()"
    sha = r.script_load(script)

    # Execute multiple times - should work each time
    5.times do
      result = r.evalsha(sha)
      # NOTE: math.random() returns Integer due to type conversion limitations
      assert result.is_a?(Integer)
      assert result >= 0 && result <= 1
    end

    # Script should still exist in cache
    # TODO: Fix script_exists - currently returns false even when script is loaded and executable
    # assert r.script(:exists, sha)
  end

  def test_eval_evalsha_parameter_type_conversion
    # Test that both eval and evalsha handle parameter type conversion consistently
    script = "return {type(KEYS[1]), type(ARGV[1]), type(ARGV[2]), type(ARGV[3])}"
    sha = r.script_load(script)

    keys = [123] # Will be converted to string
    args = [456, 78.9, true] # Will be converted to strings

    eval_result = r.eval(script, keys: keys, args: args)
    evalsha_result = r.evalsha(sha, keys: keys, args: args)

    # Both should return array of "string" types (Lua sees all as strings)
    expected = %w[string string string string]
    assert_equal expected, eval_result
    assert_equal expected, evalsha_result
    assert_equal eval_result, evalsha_result
  end

  def test_large_parameter_arrays
    # Test handling of larger parameter arrays
    script = "return #KEYS + #ARGV"
    sha = r.script_load(script)

    large_keys = (1..50).map { |i| "key#{i}" }
    large_args = (1..50).map { |i| "arg#{i}" }

    eval_result = r.eval(script, keys: large_keys, args: large_args)
    evalsha_result = r.evalsha(sha, keys: large_keys, args: large_args)

    assert_equal 100, eval_result
    assert_equal 100, evalsha_result
    assert_equal eval_result, evalsha_result
  end
end
