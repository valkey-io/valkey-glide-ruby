# frozen_string_literal: true

module Lint
  module VectorSearchCommands
    # Use the same path structure as RedisBloom for consistency
    # In CI, modules are mounted to /tmp/modules
    REDISEARCH_MODULE_PATH = "/tmp/modules/redisearch.so"
    REDISEARCH_MODULE_NAME = "search"
    TEST_INDEX = "test_vec_idx"

    def setup
      super
      # Check if RediSearch module is already loaded
      @module_was_loaded = redisearch_loaded?
    rescue Valkey::CommandError => e
      # If MODULE or FT commands aren't enabled, we can't check if module is loaded
      @module_was_loaded = false if e.message.include?("unknown command") ||
                                    e.message.include?("MODULE command not allowed")
    end

    def teardown
      # Clean up database 0 (where indexes are created)

      # Temporarily switch to DB 0 for cleanup
      r.select(0)

      # Clean up test index if it exists
      begin
        r.ft_drop_index(TEST_INDEX, dd: true) if index_exists?(TEST_INDEX)
      rescue Valkey::CommandError => e
        # Ignore errors if index doesn't exist or command not available
        unless e.message.include?("Unknown Index") || e.message.include?("unknown command")
          warn "Warning: Could not drop test index: #{e.message}"
        end
      end

      # Clean up any other test indexes
      begin
        r.ft_drop_index("#{TEST_INDEX}_2", dd: true) if index_exists?("#{TEST_INDEX}_2")
      rescue Valkey::CommandError
        # Ignore - index doesn't exist
      end

      # Flush database 0 to clean up any leftover data
      r.flushdb

      # Only unload module if we loaded it
      if !@module_was_loaded && redisearch_loaded?
        begin
          r.module_unload(REDISEARCH_MODULE_NAME)
        rescue Valkey::CommandError => e
          # RediSearch might not support unloading in some versions
          unless e.message.include?("can't unload") || e.message.include?("data types")
            warn "Warning: Unexpected error unloading RediSearch: #{e.message}"
          end
        end
      end
    rescue StandardError => e
      warn "Warning: Error in teardown: #{e.message}"
    ensure
      # CRITICAL: ALWAYS restore to database 15 (the standard test database)
      # This must happen in the ensure block so it runs even if cleanup fails
      # This is essential for other tests (like test_move, test_copy) that depend on being on DB 15
      begin
        r.select(15) if r && !r.nil?
      rescue StandardError => e
        warn "CRITICAL: Could not restore database to 15: #{e.message}"
      end

      # Call parent teardown
      super
    end

    def test_ft_list
      ensure_redisearch_loaded

      with_db0 do
        # Should return an array (might be empty if no indexes)
        list = r.ft_list
        assert_kind_of Array, list
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_create_basic
      ensure_redisearch_loaded

      with_db0 do
        # Create a simple text index
        result = r.ft_create(TEST_INDEX, "SCHEMA", "title", "TEXT", "price", "NUMERIC")
        assert_equal "OK", result

        # Verify index exists
        assert index_exists?(TEST_INDEX), "Index should exist after creation"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_create_with_vector_field
      ensure_redisearch_loaded

      with_db0 do
        # Create an index with a vector field
        result = r.ft_create(
          TEST_INDEX,
          "ON", "HASH",
          "PREFIX", "1", "doc:",
          "SCHEMA",
          "title", "TEXT",
          "embedding", "VECTOR", "FLAT", "6",
          "TYPE", "FLOAT32",
          "DIM", "128",
          "DISTANCE_METRIC", "COSINE"
        )
        assert_equal "OK", result

        # Verify index exists
        assert index_exists?(TEST_INDEX), "Index should exist after creation"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_info
      ensure_redisearch_loaded

      with_db0 do
        # Create an index first
        r.ft_create(TEST_INDEX, "SCHEMA", "title", "TEXT")

        # Get index info
        # Note: FT.INFO returns a complex Map structure that may not be fully supported yet
        info = r.ft_info(TEST_INDEX)
        assert_kind_of Array, info

        # Info should contain index_name
        assert info.include?("index_name") || info.any? { |item| item.is_a?(Array) && item.include?("index_name") },
               "Info should contain index_name"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_drop_index
      ensure_redisearch_loaded

      with_db0 do
        # Create an index
        r.ft_create(TEST_INDEX, "SCHEMA", "title", "TEXT")
        assert index_exists?(TEST_INDEX)

        # Drop the index
        result = r.ft_drop_index(TEST_INDEX)
        assert_equal "OK", result

        # Verify index no longer exists
        assert !index_exists?(TEST_INDEX), "Index should not exist after drop"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_drop_index_with_dd
      ensure_redisearch_loaded

      with_db0 do
        # Create an index
        r.ft_create(TEST_INDEX, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")

        # Add a document
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "test document"])

        # Drop the index with DD flag (delete documents)
        result = r.ft_drop_index(TEST_INDEX, dd: true)
        assert_equal "OK", result

        # Verify document was deleted
        exists = r.exists("doc:1")
        assert_equal 0, exists, "Document should be deleted with DD flag"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_search_basic
      ensure_redisearch_loaded

      with_db0 do
        # Create an index
        r.ft_create(TEST_INDEX, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")

        # Add documents
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello world"])
        r.send_command(Valkey::RequestType::HSET, ["doc:2", "title", "goodbye world"])

        # Small delay to allow indexing
        sleep 0.1

        # Search for documents
        results = r.ft_search(TEST_INDEX, "hello")
        assert_kind_of Array, results

        # First element should be the count
        count = results[0]
        assert count.is_a?(Integer) || count.is_a?(String), "First element should be result count"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_search_with_options
      ensure_redisearch_loaded

      with_db0 do
        # Create an index
        r.ft_create(TEST_INDEX, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")

        # Add documents
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello world"])
        r.send_command(Valkey::RequestType::HSET, ["doc:2", "title", "goodbye world"])

        sleep 0.1

        # Search with LIMIT and RETURN options
        results = r.ft_search(TEST_INDEX, "world", "LIMIT", "0", "1", "RETURN", "1", "title")
        assert_kind_of Array, results
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_aggregate
      ensure_redisearch_loaded

      with_db0 do
        # Create an index
        r.ft_create(TEST_INDEX, "ON", "HASH", "PREFIX", "1", "product:",
                    "SCHEMA", "category", "TAG", "price", "NUMERIC")

        # Add documents
        r.send_command(Valkey::RequestType::HSET, ["product:1", "category", "electronics", "price", "100"])
        r.send_command(Valkey::RequestType::HSET, ["product:2", "category", "electronics", "price", "200"])
        r.send_command(Valkey::RequestType::HSET, ["product:3", "category", "books", "price", "50"])

        sleep 0.1

        # Run aggregation
        results = r.ft_aggregate(TEST_INDEX, "*", "GROUPBY", "1", "@category",
                                 "REDUCE", "COUNT", "0", "AS", "count")
        assert_kind_of Array, results
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_alias_add
      ensure_redisearch_loaded

      with_db0 do
        # Create an index
        r.ft_create(TEST_INDEX, "SCHEMA", "title", "TEXT")

        # Add an alias
        result = r.ft_alias_add("#{TEST_INDEX}_alias", TEST_INDEX)
        assert_equal "OK", result

        # Clean up alias
        r.ft_alias_del("#{TEST_INDEX}_alias")
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_alias_del
      ensure_redisearch_loaded

      with_db0 do
        # Create an index and alias
        r.ft_create(TEST_INDEX, "SCHEMA", "title", "TEXT")
        r.ft_alias_add("#{TEST_INDEX}_alias", TEST_INDEX)

        # Delete the alias
        result = r.ft_alias_del("#{TEST_INDEX}_alias")
        assert_equal "OK", result
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_alias_update
      ensure_redisearch_loaded

      with_db0 do
        # Create two indexes
        r.ft_create(TEST_INDEX, "SCHEMA", "title", "TEXT")
        r.ft_create("#{TEST_INDEX}_2", "SCHEMA", "title", "TEXT")

        # Create alias for first index
        r.ft_alias_add("#{TEST_INDEX}_alias", TEST_INDEX)

        # Update alias to point to second index
        result = r.ft_alias_update("#{TEST_INDEX}_alias", "#{TEST_INDEX}_2")
        assert_equal "OK", result

        # Clean up
        r.ft_alias_del("#{TEST_INDEX}_alias")
        r.ft_drop_index("#{TEST_INDEX}_2")
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_explain
      ensure_redisearch_loaded

      with_db0 do
        # Create an index
        r.ft_create(TEST_INDEX, "SCHEMA", "title", "TEXT", "price", "NUMERIC")

        # Explain a query
        result = r.ft_explain(TEST_INDEX, "@title:hello @price:[0 100]")
        assert_kind_of String, result
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_explain_cli
      ensure_redisearch_loaded

      with_db0 do
        # Create an index
        r.ft_create(TEST_INDEX, "SCHEMA", "title", "TEXT")

        # Explain query in CLI format (returns an array of lines)
        result = r.ft_explain_cli(TEST_INDEX, "@title:hello")
        assert_kind_of Array, result
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_profile_search
      ensure_redisearch_loaded

      with_db0 do
        # Create an index
        r.ft_create(TEST_INDEX, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello world"])

        sleep 0.1

        # Profile a search query
        # Note: FT.PROFILE returns [search_results, profiling_metrics]
        # We validate search_results work, but skip validating profiling_metrics due to complex nested structures
        begin
          result = r.ft_profile(TEST_INDEX, "SEARCH", "QUERY", "hello")
          assert_kind_of Array, result
          assert result.length >= 1, "Should return at least search results"
          # result[0] would be search results, result[1] would be profiling metrics
        rescue Valkey::CommandError => e
          # Profiling metrics have complex nested structures not fully supported in RESP2 conversion
          raise unless e.message.include?("Array inside map must contain exactly two elements")

          skip("FT.PROFILE profiling metrics conversion not yet fully supported in glide-core")
        end
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_profile_aggregate
      ensure_redisearch_loaded

      with_db0 do
        # Create an index
        r.ft_create(TEST_INDEX, "ON", "HASH", "PREFIX", "1", "product:",
                    "SCHEMA", "category", "TAG", "price", "NUMERIC")
        r.send_command(Valkey::RequestType::HSET, ["product:1", "category", "electronics", "price", "100"])

        sleep 0.1

        # Profile an aggregation query
        # Note: FT.PROFILE returns [aggregation_results, profiling_metrics]
        # We validate aggregation_results work, but skip validating profiling_metrics due to complex nested structures
        begin
          result = r.ft_profile(TEST_INDEX, "AGGREGATE", "QUERY", "*",
                                "GROUPBY", "1", "@category")
          assert_kind_of Array, result
          assert result.length >= 1, "Should return at least aggregation results"
          # result[0] would be aggregation results, result[1] would be profiling metrics
        rescue Valkey::CommandError => e
          # Profiling metrics have complex nested structures not fully supported in RESP2 conversion
          raise unless e.message.include?("Array inside map must contain exactly two elements")

          skip("FT.PROFILE profiling metrics conversion not yet fully supported in glide-core")
        end
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_convenience_method_list
      ensure_redisearch_loaded

      with_db0 do
        list = r.ft(:list)
        assert_kind_of Array, list
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_convenience_method_create
      ensure_redisearch_loaded

      with_db0 do
        result = r.ft(:create, TEST_INDEX, "SCHEMA", "title", "TEXT")
        assert_equal "OK", result
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_convenience_method_search
      ensure_redisearch_loaded

      with_db0 do
        r.ft_create(TEST_INDEX, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello world"])

        sleep 0.1

        results = r.ft(:search, TEST_INDEX, "hello")
        assert_kind_of Array, results
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_convenience_method_drop_index
      ensure_redisearch_loaded

      with_db0 do
        r.ft_create(TEST_INDEX, "SCHEMA", "title", "TEXT")

        result = r.ft(:drop_index, TEST_INDEX)
        assert_equal "OK", result
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    private

    # RediSearch requires database 0, so we wrap operations to ensure we're on the right DB
    def with_db0(&block)
      r.select(0)
      result = block.call
      result
    ensure
      # Always restore to database 15 (the standard test database), even on error
      begin
        r.select(15)
      rescue StandardError => e
        warn "Warning: Could not restore database to 15: #{e.message}"
      end
    end

    def redisearch_loaded?
      # Try to get list of indexes - if it works, RediSearch is loaded
      with_db0 { r.ft_list }
      true
    rescue Valkey::CommandError => e
      return false if e.message.include?("unknown command") ||
                      e.message.include?("MODULE command not allowed")

      raise
    end

    def ensure_redisearch_loaded
      return if redisearch_loaded?

      # Try to load RediSearch module
      begin
        r.module_load(REDISEARCH_MODULE_PATH)
        sleep 0.2 # Give module time to initialize
      rescue Valkey::CommandError => e
        if e.message.include?("No such file") || e.message.include?("cannot open")
          skip("RediSearch module file not available at #{REDISEARCH_MODULE_PATH}")
        elsif e.message.include?("MODULE command not allowed")
          skip("MODULE commands not enabled")
        else
          raise
        end
      end
    end

    def index_exists?(index_name)
      with_db0 do
        list = r.ft_list
        if list.is_a?(Array)
          list.include?(index_name)
        else
          false
        end
      end
    rescue Valkey::CommandError
      false
    end

    def skip_if_redisearch_unavailable(error)
      if error.message.include?("unknown command")
        skip("RediSearch commands not available")
      elsif error.message.include?("MODULE command not allowed")
        skip("MODULE commands not enabled")
      elsif error.message.include?("No such file") || error.message.include?("cannot open")
        skip("RediSearch module file not available")
      else
        raise
      end
    end
  end
end
