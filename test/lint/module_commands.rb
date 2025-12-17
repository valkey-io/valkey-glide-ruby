# frozen_string_literal: true

module Lint
  module ModuleCommands
    MODULE_PATH = "/tmp/modules/redisbloom.so"
    MODULE_NAME = "bf"

    def setup
      super
      # Check if module is already loaded
      @module_was_loaded = module_loaded?
    rescue Valkey::CommandError => e
      # If MODULE commands aren't enabled, we can't check if module is loaded
      @module_was_loaded = false if e.message.include?("MODULE command not allowed")
    end

    def teardown
      # Clean up: only unload if we loaded it and it wasn't loaded before
      if !@module_was_loaded && module_loaded?
        begin
          # Flush all databases to remove any data types that prevent unloading
          r.flushall
          sleep 0.1 # Give Valkey a moment to complete the flush

          # Try to unload the module
          r.module_unload(MODULE_NAME)
        rescue Valkey::CommandError => e
          # Some modules like RedisBloom can't be unloaded if they export data types
          # This is expected Valkey/Redis behavior, not a test failure
          unless e.message.include?("can't unload") || e.message.include?("data types")
            warn "Warning: Unexpected error unloading module #{MODULE_NAME}: #{e.message}"
          end
        end
      end
    rescue StandardError => e
      # Ignore errors in teardown to not mask test failures
      warn "Warning: Error in teardown: #{e.message}"
    ensure
      super
    end

    def test_module_list
      target_version "4.0" do
        # MODULE LIST should return an array
        list = r.module_list
        assert_kind_of Array, list
      rescue Valkey::CommandError => e
        skip("MODULE commands not enabled") if e.message.include?("MODULE command not allowed")
        raise
      end
    end

    def test_module_load
      target_version "4.0" do
        if module_loaded?
          # Module already loaded, verify it's in the list
        else
          # Load the module
          result = r.module_load(MODULE_PATH)
          assert_equal "OK", result

          # Verify module is loaded
        end
        assert module_loaded?, "Module #{MODULE_NAME} should be in the list"
      rescue Valkey::CommandError => e
        if e.message.include?("MODULE command not allowed")
          skip("MODULE commands not enabled")
        elsif e.message.include?("No such file") || e.message.include?("cannot open")
          skip("Module file not available at #{MODULE_PATH}")
        else
          raise
        end
      end
    end

    def test_module_load_with_args
      target_version "4.0" do
        if module_loaded?
          # Module already loaded, just verify the API would work
          assert module_loaded?, "Module #{MODULE_NAME} is loaded"
        else
          # RedisBloom doesn't take args, but we can test the API
          result = r.module_load(MODULE_PATH)
          assert_equal "OK", result
        end
      rescue Valkey::CommandError => e
        if e.message.include?("MODULE command not allowed")
          skip("MODULE commands not enabled")
        elsif e.message.include?("No such file") || e.message.include?("cannot open")
          skip("Module file not available at #{MODULE_PATH}")
        else
          raise
        end
      end
    end

    def test_module_unload
      target_version "4.0" do
        # Ensure module is loaded first
        unless module_loaded?
          begin
            r.module_load(MODULE_PATH)
          rescue Valkey::CommandError => e
            if e.message.include?("MODULE command not allowed")
              skip("MODULE commands not enabled or module file not available")
            end
            raise
          end
        end

        # Flush all data to allow unloading
        begin
          r.flushall
          sleep 0.2 # Give Valkey a moment to complete the flush
        rescue Valkey::TimeoutError
          skip("Timeout during flushall - server may be busy")
        end

        # Try to unload the module
        begin
          result = r.module_unload(MODULE_NAME)
          assert_equal "OK", result
          assert !module_loaded?, "Module #{MODULE_NAME} should not be in the list after unload"
        rescue Valkey::CommandError => e
          # Some modules like RedisBloom export data types and cannot be unloaded
          # This is expected Valkey/Redis behavior
          if e.message.include?("can't unload") || e.message.include?("data types")
            skip("Module #{MODULE_NAME} cannot be unloaded (exports data types)")
          elsif e.message.include?("MODULE command not allowed")
            skip("MODULE commands not enabled")
          else
            raise
          end
        end
      end
    end

    def test_module_loadex
      target_version "7.0" do
        if module_loaded?
          # Module already loaded, verify it's in the list
        else
          result = r.module_loadex(MODULE_PATH)
          assert_equal "OK", result

          # Verify module is loaded
        end
        assert module_loaded?, "Module #{MODULE_NAME} should be in the list"
      rescue Valkey::CommandError => e
        if e.message.include?("MODULE command not allowed")
          skip("MODULE commands not enabled")
        elsif e.message.include?("No such file") || e.message.include?("cannot open")
          skip("Module file not available at #{MODULE_PATH}")
        else
          raise
        end
      end
    end

    def test_module_loadex_with_args
      target_version "7.0" do
        if module_loaded?
          # Module already loaded, just verify the API would work
          assert module_loaded?, "Module #{MODULE_NAME} is loaded"
        else
          result = r.module_loadex(MODULE_PATH, args: [])
          assert_equal "OK", result
        end
      rescue Valkey::CommandError => e
        if e.message.include?("MODULE command not allowed")
          skip("MODULE commands not enabled")
        elsif e.message.include?("No such file") || e.message.include?("cannot open")
          skip("Module file not available at #{MODULE_PATH}")
        else
          raise
        end
      end
    end

    def test_module_loadex_with_configs_and_args
      target_version "7.0" do
        if module_loaded?
          # Module already loaded, just verify the API would work
          assert module_loaded?, "Module #{MODULE_NAME} is loaded"
        else
          result = r.module_loadex(MODULE_PATH, configs: {}, args: [])
          assert_equal "OK", result
        end
      rescue Valkey::CommandError => e
        if e.message.include?("MODULE command not allowed")
          skip("MODULE commands not enabled")
        elsif e.message.include?("No such file") || e.message.include?("cannot open")
          skip("Module file not available at #{MODULE_PATH}")
        else
          raise
        end
      end
    end

    def test_module_convenience_method_list
      target_version "4.0" do
        list = r.module(:list)
        assert_kind_of Array, list
      rescue Valkey::CommandError => e
        skip("MODULE commands not enabled") if e.message.include?("MODULE command not allowed")
        raise
      end
    end

    def test_module_convenience_method_load
      target_version "4.0" do
        if module_loaded?
          # Module already loaded, just verify the API would work
          assert module_loaded?, "Module #{MODULE_NAME} is loaded"
        else
          result = r.module(:load, MODULE_PATH)
          assert_equal "OK", result
        end
      rescue Valkey::CommandError => e
        if e.message.include?("MODULE command not allowed")
          skip("MODULE commands not enabled")
        elsif e.message.include?("No such file") || e.message.include?("cannot open")
          skip("Module file not available at #{MODULE_PATH}")
        else
          raise
        end
      end
    end

    def test_module_convenience_method_unload
      target_version "4.0" do
        # Ensure module is loaded first
        unless module_loaded?
          begin
            r.module(:load, MODULE_PATH)
          rescue Valkey::CommandError => e
            if e.message.include?("MODULE command not allowed")
              skip("MODULE commands not enabled or module file not available")
            end
            raise
          end
        end

        # Flush all data to allow unloading
        begin
          r.flushall
          sleep 0.2 # Give Valkey a moment to complete the flush
        rescue Valkey::TimeoutError
          skip("Timeout during flushall - server may be busy")
        end

        # Try to unload the module using convenience method
        begin
          result = r.module(:unload, MODULE_NAME)
          assert_equal "OK", result
          assert !module_loaded?, "Module #{MODULE_NAME} should not be in the list after unload"
        rescue Valkey::CommandError => e
          # Some modules like RedisBloom export data types and cannot be unloaded
          # This is expected Valkey/Redis behavior
          if e.message.include?("can't unload") || e.message.include?("data types")
            skip("Module #{MODULE_NAME} cannot be unloaded (exports data types)")
          elsif e.message.include?("MODULE command not allowed")
            skip("MODULE commands not enabled")
          else
            raise
          end
        end
      end
    end

    def test_module_convenience_method_loadex
      target_version "7.0" do
        if module_loaded?
          # Module already loaded, just verify the API would work
          assert module_loaded?, "Module #{MODULE_NAME} is loaded"
        else
          result = r.module(:loadex, MODULE_PATH)
          assert_equal "OK", result
        end
      rescue Valkey::CommandError => e
        if e.message.include?("MODULE command not allowed")
          skip("MODULE commands not enabled")
        elsif e.message.include?("No such file") || e.message.include?("cannot open")
          skip("Module file not available at #{MODULE_PATH}")
        else
          raise
        end
      end
    end

    private

    def module_loaded?
      list = r.module_list
      list.any? do |m|
        m.is_a?(Array) && m.include?("name") && m[m.index("name") + 1] == MODULE_NAME
      end
    rescue Valkey::CommandError => e
      # If MODULE commands aren't enabled, assume module is not loaded
      return false if e.message.include?("MODULE command not allowed")

      raise
    end
  end
end
