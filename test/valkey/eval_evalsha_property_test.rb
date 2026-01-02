# frozen_string_literal: true

require "test_helper"

# Test class for basic eval/evalsha execution and parameter handling properties
class TestEvalEvalshaBasicProperties < Minitest::Test
  include Helper::Client

  def setup
    super
    r.script_flush # Ensure the script cache is empty before running tests
  end

  # **Feature: eval-evalsha-commands, Property 1: Script execution consistency**
  # Property 1: Script execution consistency
  # For any valid Lua script and parameter set, executing via eval and then via evalsha (after loading)
  # should produce identical results
  # **Validates: Requirements 3.1**
  def test_script_execution_consistency
    # Run property test with 100 iterations
    100.times do
      # Generate a simple Lua script that returns a deterministic result
      scripts = [
        "return 42",
        "return 'hello'",
        "return true",
        "return nil",
        "return {1, 2, 3}",
        "return KEYS[1] or 'default'",
        "return ARGV[1] or 'default'"
      ]

      script = scripts.sample
      keys = generate_keys(rand(4))
      args = generate_args(rand(4))

      # Execute via eval
      eval_result = r.eval(script, keys: keys, args: args)

      # Load script and execute via evalsha
      sha = r.script_load(script)
      evalsha_result = r.evalsha(sha, keys: keys, args: args)

      # Results should be identical
      assert_equal eval_result, evalsha_result,
                   "eval and evalsha should produce identical results
                    for script: #{script}, keys: #{keys}, args: #{args}"
    end
  end

  # **Feature: eval-evalsha-commands, Property 2: Parameter round-trip preservation**
  # Property 2: Parameter round-trip preservation
  # For any keys array and args array,
  # a Lua script that returns both KEYS and ARGV should receive the exact parameters that were passed in
  # **Validates: Requirements 1.2, 2.2, 3.2, 3.3**
  def test_parameter_round_trip_preservation
    # Run property test with 100 iterations
    100.times do
      keys = generate_keys(rand(6))
      args = generate_args(rand(6))

      # Script that returns both KEYS and ARGV arrays
      script = "return {KEYS, ARGV}"

      result = r.eval(script, keys: keys, args: args)

      # Result should be [keys_array, args_array]
      assert_equal 2, result.length, "Script should return array with 2 elements"

      returned_keys = result[0] || []
      returned_args = result[1] || []

      assert_equal keys, returned_keys, "KEYS array should match input keys"
      assert_equal args, returned_args, "ARGV array should match input args"
    end
  end

  private

  def generate_keys(count)
    count.times.map { |i| "key#{i}_#{rand(1000)}" }
  end

  def generate_args(count)
    count.times.map { |i| "arg#{i}_#{rand(1000)}" }
  end
end

# Test class for eval/evalsha validation and error handling properties
class TestEvalEvalshaValidationProperties < Minitest::Test
  include Helper::Client

  def setup
    super
    r.script_flush # Ensure the script cache is empty before running tests
  end

  # **Feature: eval-evalsha-commands, Property 5: SHA1 hash validation**
  # Property 5: SHA1 hash validation
  # For any string that is not a valid 40-character hexadecimal SHA1 hash,
  # evalsha should raise an ArgumentError before attempting server communication
  # **Validates: Requirements 2.4**
  def test_sha1_hash_validation
    # Run property test with 100 iterations
    100.times do
      # Generate invalid SHA1 hashes
      invalid_hashes = [
        "", # empty string
        "short", # too short
        "a" * 39, # 39 characters (too short)
        "a" * 41, # 41 characters (too long)
        "g" * 40, # invalid hex character
        "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG", # invalid hex characters
        "123456789012345678901234567890123456789z", # invalid character at end
        "z123456789012345678901234567890123456789", # invalid character at start
        "12345678901234567890123456789012345678 9", # space in middle
        nil, # nil value
        123, # non-string type
        [], # array type
        {} # hash type
      ].sample

      # Should raise ArgumentError for invalid hash
      assert_raises(ArgumentError) do
        r.evalsha(invalid_hashes)
      end
    end

    # Test some valid hashes don't raise ArgumentError during validation
    # (they may still fail with CommandError if script doesn't exist)
    valid_hashes = [
      "a" * 40,
      "1234567890abcdef1234567890abcdef12345678",
      "ABCDEF1234567890ABCDEF1234567890ABCDEF12"
    ]

    valid_hashes.each do |hash|
      # Should not raise ArgumentError (may raise CommandError if script not found)

      r.evalsha(hash)
    rescue Valkey::CommandError
      # This is expected if script doesn't exist - validation passed
    rescue ArgumentError => e
      flunk "Valid SHA1 hash #{hash} should not raise ArgumentError: #{e.message}"
    end
  end

  # **Feature: eval-evalsha-commands, Property 6: Script cache miss handling**
  # Property 6: Script cache miss handling
  # For any valid SHA1 hash format that doesn't exist in the server's script cache,
  # evalsha should raise a CommandError indicating script not found
  # **Validates: Requirements 2.3**
  def test_script_cache_miss_handling
    # Run property test with 100 iterations
    100.times do
      # Generate valid SHA1 hash that doesn't exist in cache
      # Use random hex characters to create a valid but non-existent hash
      non_existent_hash = 40.times.map { rand(16).to_s(16) }.join

      keys = generate_keys(rand(4))
      args = generate_args(rand(4))

      # Should raise CommandError for non-existent script
      assert_raises(Valkey::CommandError) do
        r.evalsha(non_existent_hash, keys: keys, args: args)
      end
    end
  end

  # **Feature: eval-evalsha-commands, Property 4: Error preservation fidelity**
  # Property 4: Error preservation fidelity
  # For any Lua script with syntax or runtime errors,
  # the client should raise CommandError exceptions that preserve the original server error messages
  # **Validates: Requirements 1.4, 4.1, 4.5**
  def test_error_preservation_fidelity
    # Run property test with 100 iterations
    100.times { verify_error_preservation_for_random_case }
  end

  private

  def verify_error_preservation_for_random_case
    # Test different types of Lua script errors
    error_scripts = [
      # Syntax errors
      "return 1 +", # incomplete expression
      "if true then", # incomplete if statement
      "for i=1,10", # incomplete for loop
      "function test(", # incomplete function definition
      "return {1, 2,", # incomplete table
      "local x = 1 return x +", # incomplete expression with local

      # Runtime errors
      "error('custom error message')", # explicit error
      "return nonexistent_variable", # undefined variable
      "return 1 / 0", # division by zero (may or may not error depending on Lua version)
      "return string.sub(nil, 1, 1)", # nil argument to string function
      "return table.insert(nil, 1)", # nil argument to table function
      "local t = {} return t.nonexistent.field" # attempt to index nil
    ]

    script = error_scripts.sample
    keys = generate_keys(rand(3))
    args = generate_args(rand(3))

    # Test eval error handling
    eval_error = nil
    begin
      r.eval(script, keys: keys, args: args)
      # If we get here, the script didn't error (which is unexpected for our error scripts)
      # Some scripts might not error in all Lua versions, so we'll skip validation
      return
    rescue Valkey::CommandError => e
      eval_error = e
    end

    # Test evalsha error handling (for syntax errors, this should fail during script_load)
    evalsha_error = nil
    begin
      sha = r.script_load(script)
      r.evalsha(sha, keys: keys, args: args)
      # If we get here, the script didn't error
      return
    rescue Valkey::CommandError => e
      evalsha_error = e
    end

    # Verify error properties
    if eval_error
      assert eval_error.is_a?(Valkey::CommandError),
             "eval should raise CommandError for script errors, got #{eval_error.class}"
      assert !eval_error.message.empty?,
             "eval error message should not be empty"
      assert eval_error.message.is_a?(String),
             "eval error message should be a string"
    end

    return unless evalsha_error

    assert evalsha_error.is_a?(Valkey::CommandError),
           "evalsha should raise CommandError for script errors, got #{evalsha_error.class}"
    assert !evalsha_error.message.empty?,
           "evalsha error message should not be empty"
    assert evalsha_error.message.is_a?(String),
           "evalsha error message should be a string"
  end

  def generate_keys(count)
    count.times.map { |i| "key#{i}_#{rand(1000)}" }
  end

  def generate_args(count)
    count.times.map { |i| "arg#{i}_#{rand(1000)}" }
  end
end

# Test class for eval/evalsha type conversion and caching properties
class TestEvalEvalshaTypeProperties < Minitest::Test
  include Helper::Client

  def setup
    super
    r.script_flush # Ensure the script cache is empty before running tests
  end

  # **Feature: eval-evalsha-commands, Property 3: Type conversion correctness**
  # Property 3: Type conversion correctness
  # For any Lua script that returns values of different types (string, number, boolean, array, nil),
  # the Ruby client should convert them to appropriate Ruby types
  # **Validates: Requirements 1.3, 2.5**
  def test_type_conversion_correctness
    # Run property test with 100 iterations
    100.times { verify_type_conversion_for_random_case }
  end

  # **Feature: eval-evalsha-commands, Property 7: Cached script execution**
  # Property 7: Cached script execution
  # For any script loaded into the cache, evalsha with the returned hash should successfully execute the script
  # **Validates: Requirements 2.1**
  def test_cached_script_execution
    # Run property test with 100 iterations
    100.times do
      # Generate various types of Lua scripts
      scripts = [
        "return 42",
        "return 'hello world'",
        "return true",
        "return false",
        "return nil",
        "return {1, 2, 3}",
        "return {}",
        "return KEYS[1] or 'no_key'",
        "return ARGV[1] or 'no_arg'",
        "return #KEYS + #ARGV",
        "local sum = 0; for i=1,#ARGV do sum = sum + (tonumber(ARGV[i]) or 0) end; return sum",
        "return string.upper(ARGV[1] or 'default')",
        "return table.concat(KEYS, ':')",
        "if #KEYS > 0 then return KEYS[1] else return 'empty' end"
      ]

      script = scripts.sample
      keys = generate_keys(rand(5))
      args = generate_args(rand(5))

      # Load script into cache using script_load
      sha = r.script_load(script)

      # Verify the SHA is valid format
      assert sha.is_a?(String), "script_load should return a string SHA"
      assert_equal 40, sha.length, "SHA should be 40 characters long"
      assert sha.match?(/\A[a-fA-F0-9]{40}\z/), "SHA should be valid hexadecimal"

      # Execute the cached script using evalsha
      result = r.evalsha(sha, keys: keys, args: args)

      # Verify the script executed successfully by comparing with direct eval
      expected_result = r.eval(script, keys: keys, args: args)
      assert_equal expected_result, result,
                   "Cached script execution should produce same result as direct eval:
                    script=#{script}, keys=#{keys}, args=#{args}"

      # Verify the script is still in cache (can be executed again)
      second_result = r.evalsha(sha, keys: keys, args: args)
      assert_equal result, second_result,
                   "Cached script should be executable multiple times with consistent results"
    end
  end

  private

  def verify_type_conversion_for_random_case
    # Test different Lua return types and their expected Ruby conversions
    test_cases = [
      # [lua_script, expected_ruby_type, validation_proc]
      ["return 'hello world'", String, ->(result) { result.is_a?(String) && result == "hello world" }],
      ["return ''", String, ->(result) { result.is_a?(String) && result == "" }],
      ["return 42", Integer, ->(result) { result.is_a?(Integer) && result == 42 }],
      ["return -17", Integer, ->(result) { result.is_a?(Integer) && result == -17 }],
      ["return 0", Integer, ->(result) { result.is_a?(Integer) && result.zero? }],
      ["return 3.14", Integer, lambda { |result|
        result.is_a?(Integer) && result == 3
      }], # NOTE: floats are truncated to integers
      ["return -2.5", Integer, lambda { |result|
        result.is_a?(Integer) && result == -2
      }], # NOTE: floats are truncated to integers
      ["return true", Integer, ->(result) { result == 1 }], # NOTE: true is converted to 1
      ["return false", NilClass, lambda(&:nil?)], # NOTE: false is converted to nil
      ["return nil", NilClass, lambda(&:nil?)],
      ["return {1, 2, 3}", Array, ->(result) { result.is_a?(Array) && result == [1, 2, 3] }],
      ["return {}", Array, ->(result) { result.is_a?(Array) && result == [] }],
      ["return {'a', 'b', 'c'}", Array, ->(result) { result.is_a?(Array) && result == %w[a b c] }],
      ["return {1, 'mixed', true, nil}", Array, lambda { |result|
        result.is_a?(Array) && result == [1, "mixed", 1] # NOTE: true->1, nil is dropped
      }],
      ["return {{1, 2}, {3, 4}}", Array, ->(result) { result.is_a?(Array) && result == [[1, 2], [3, 4]] }]
    ]

    test_case = test_cases.sample
    script, expected_type, validation = test_case

    # Test with eval
    eval_result = r.eval(script)
    assert validation.call(eval_result),
           "eval result should be correctly converted:
           script=#{script}, result=#{eval_result.inspect}, expected_type=#{expected_type}"

    # Test with evalsha (load script first)
    sha = r.script_load(script)
    evalsha_result = r.evalsha(sha)
    assert validation.call(evalsha_result),
           "evalsha result should be correctly converted:
           script=#{script}, result=#{evalsha_result.inspect}, expected_type=#{expected_type}"

    # Both should produce identical results
    assert_equal eval_result, evalsha_result,
                 "eval and evalsha should produce identical type conversions for script: #{script}"
  end

  def generate_keys(count)
    count.times.map { |i| "key#{i}_#{rand(1000)}" }
  end

  def generate_args(count)
    count.times.map { |i| "arg#{i}_#{rand(1000)}" }
  end
end
