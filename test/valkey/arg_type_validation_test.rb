# frozen_string_literal: true

module ValkeyTests
  # Tests that nil and other unsupported types are rejected with TypeError
  # instead of being silently coerced to empty string via #to_s (fixes #191).
  module ArgTypeValidation
    def test_nil_arg_raises_type_error
      assert_raises(TypeError) { r.set("key", nil) }
    end

    def test_nil_key_raises_type_error
      assert_raises(TypeError) { r.get(nil) }
    end

    def test_array_arg_raises_type_error
      assert_raises(TypeError) { r.set("key", [1, 2, 3]) }
    end

    def test_hash_arg_raises_type_error
      assert_raises(TypeError) { r.set("key", { a: 1 }) }
    end

    def test_string_arg_accepted
      assert_equal "OK", r.set("arg_type:str", "hello")
      assert_equal "hello", r.get("arg_type:str")
    end

    def test_symbol_arg_accepted
      assert_equal "OK", r.set("arg_type:sym", :world)
      assert_equal "world", r.get("arg_type:sym")
    end

    def test_integer_arg_accepted
      assert_equal "OK", r.set("arg_type:int", 42)
      assert_equal "42", r.get("arg_type:int")
    end

    def test_float_arg_accepted
      assert_equal "OK", r.set("arg_type:float", 3.14)
      assert_equal "3.14", r.get("arg_type:float")
    end

    def test_nil_in_call_raises_type_error
      assert_raises(TypeError) { r.call("SET", "key", nil) }
    end

    def test_type_error_message_includes_class_name
      err = assert_raises(TypeError) { r.set("key", nil) }
      assert_match(/NilClass/, err.message)
    end
  end
end
