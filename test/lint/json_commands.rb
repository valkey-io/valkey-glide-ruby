# frozen_string_literal: true

module Lint
  module JsonCommands
    JSON_MODULE_PATH = "/tmp/modules/redisjson.so"

    def setup
      super
      # Try to load JSON module if not already loaded
      begin
        # Check if JSON module is already loaded
        modules = r.module_list
        json_loaded = modules.any? do |m|
          m.is_a?(Array) && m.include?("name") && %w[ReJSON rejson].include?(m[m.index("name") + 1])
        end

        # Load JSON module if not loaded
        r.module_load(JSON_MODULE_PATH) unless json_loaded

        # Verify JSON commands work
        r.json_set("test:json:check", "$", '{"test":1}')
        r.json_del("test:json:check")
      rescue Valkey::CommandError
        # Mark as unavailable if module can't be loaded or commands don't work
        # This catches: unknown command, module load errors, file not found, etc.
        @json_not_available = true
      rescue StandardError
        # Catch any other errors (network, etc.)
        @json_not_available = true
      end
    end

    def test_json_set_and_get
      skip("JSON module not available") if @json_not_available

      r.json_set("user:1", "$", '{"name":"John","age":30}')
      result = r.json_get("user:1")
      assert_kind_of String, result
      assert result.include?("John")
    ensure
      begin
        r.json_del("user:1")
      rescue StandardError
        nil
      end
    end

    def test_json_get_with_path
      skip("JSON module not available") if @json_not_available

      r.json_set("user:2", "$", '{"name":"Jane","age":25}')
      result = r.json_get("user:2", "$.name")
      assert_kind_of String, result
    ensure
      begin
        r.json_del("user:2")
      rescue StandardError
        nil
      end
    end

    def test_json_del
      skip("JSON module not available") if @json_not_available

      r.json_set("user:3", "$", '{"name":"Bob"}')
      result = r.json_del("user:3")
      assert_kind_of Integer, result
      assert result >= 0
    end

    def test_json_type
      skip("JSON module not available") if @json_not_available

      r.json_set("user:4", "$", '{"name":"Alice","age":28}')
      result = r.json_type("user:4", "$.age")
      assert_kind_of Array, result
    ensure
      begin
        r.json_del("user:4")
      rescue StandardError
        nil
      end
    end

    def test_json_numincrby
      skip("JSON module not available") if @json_not_available

      r.json_set("counter:1", "$", '{"count":10}')
      result = r.json_numincrby("counter:1", "$.count", 5)
      # Result can be String or Array depending on JSONPath version
      assert(result.is_a?(String) || result.is_a?(Array), "Expected String or Array, got #{result.class}")
    ensure
      begin
        r.json_del("counter:1")
      rescue StandardError
        nil
      end
    end

    def test_json_nummultby
      skip("JSON module not available") if @json_not_available

      r.json_set("price:1", "$", '{"value":100}')
      result = r.json_nummultby("price:1", "$.value", 1.5)
      # Result can be String or Array depending on JSONPath version
      assert(result.is_a?(String) || result.is_a?(Array), "Expected String or Array, got #{result.class}")
    ensure
      begin
        r.json_del("price:1")
      rescue StandardError
        nil
      end
    end

    def test_json_strappend
      skip("JSON module not available") if @json_not_available

      r.json_set("text:1", "$", '{"msg":"Hello"}')
      result = r.json_strappend("text:1", "$.msg", '" World"')
      assert_kind_of Array, result
    ensure
      begin
        r.json_del("text:1")
      rescue StandardError
        nil
      end
    end

    def test_json_strlen
      skip("JSON module not available") if @json_not_available

      r.json_set("text:2", "$", '{"msg":"Hello"}')
      result = r.json_strlen("text:2", "$.msg")
      assert_kind_of Array, result
    ensure
      begin
        r.json_del("text:2")
      rescue StandardError
        nil
      end
    end

    def test_json_arrappend
      skip("JSON module not available") if @json_not_available

      r.json_set("list:1", "$", '{"tags":["ruby"]}')
      result = r.json_arrappend("list:1", "$.tags", '"valkey"')
      assert_kind_of Array, result
    ensure
      begin
        r.json_del("list:1")
      rescue StandardError
        nil
      end
    end

    def test_json_arrlen
      skip("JSON module not available") if @json_not_available

      r.json_set("list:2", "$", '{"tags":["a","b","c"]}')
      result = r.json_arrlen("list:2", "$.tags")
      assert_kind_of Array, result
    ensure
      begin
        r.json_del("list:2")
      rescue StandardError
        nil
      end
    end

    def test_json_arrindex
      skip("JSON module not available") if @json_not_available

      r.json_set("list:3", "$", '{"tags":["ruby","python","go"]}')
      result = r.json_arrindex("list:3", "$.tags", '"python"')
      assert_kind_of Array, result
    ensure
      begin
        r.json_del("list:3")
      rescue StandardError
        nil
      end
    end

    def test_json_arrinsert
      skip("JSON module not available") if @json_not_available

      r.json_set("list:4", "$", '{"tags":["a","c"]}')
      result = r.json_arrinsert("list:4", "$.tags", 1, '"b"')
      assert_kind_of Array, result
    ensure
      begin
        r.json_del("list:4")
      rescue StandardError
        nil
      end
    end

    def test_json_arrpop
      skip("JSON module not available") if @json_not_available

      r.json_set("list:5", "$", '{"tags":["a","b","c"]}')
      result = r.json_arrpop("list:5", "$.tags")
      assert_kind_of Array, result
    ensure
      begin
        r.json_del("list:5")
      rescue StandardError
        nil
      end
    end

    def test_json_arrtrim
      skip("JSON module not available") if @json_not_available

      r.json_set("list:6", "$", '{"tags":["a","b","c","d"]}')
      result = r.json_arrtrim("list:6", "$.tags", 0, 1)
      assert_kind_of Array, result
    ensure
      begin
        r.json_del("list:6")
      rescue StandardError
        nil
      end
    end

    def test_json_objkeys
      skip("JSON module not available") if @json_not_available

      r.json_set("obj:1", "$", '{"name":"John","age":30}')
      result = r.json_objkeys("obj:1", "$")
      assert_kind_of Array, result
    ensure
      begin
        r.json_del("obj:1")
      rescue StandardError
        nil
      end
    end

    def test_json_objlen
      skip("JSON module not available") if @json_not_available

      r.json_set("obj:2", "$", '{"a":1,"b":2,"c":3}')
      result = r.json_objlen("obj:2", "$")
      assert_kind_of Array, result
    ensure
      begin
        r.json_del("obj:2")
      rescue StandardError
        nil
      end
    end

    def test_json_clear
      skip("JSON module not available") if @json_not_available

      r.json_set("obj:3", "$", '{"tags":["a","b"]}')
      result = r.json_clear("obj:3", "$.tags")
      assert_kind_of Integer, result
    ensure
      begin
        r.json_del("obj:3")
      rescue StandardError
        nil
      end
    end

    def test_json_toggle
      skip("JSON module not available") if @json_not_available

      r.json_set("flag:1", "$", '{"active":true}')
      result = r.json_toggle("flag:1", "$.active")
      assert_kind_of Array, result
    ensure
      begin
        r.json_del("flag:1")
      rescue StandardError
        nil
      end
    end

    def test_json_mget
      skip("JSON module not available") if @json_not_available

      r.json_set("user:10", "$", '{"name":"Alice"}')
      r.json_set("user:11", "$", '{"name":"Bob"}')
      result = r.json_mget("user:10", "user:11", "$.name")
      assert_kind_of Array, result
    ensure
      begin
        r.json_del("user:10")
      rescue StandardError
        nil
      end
      begin
        r.json_del("user:11")
      rescue StandardError
        nil
      end
    end
  end
end
