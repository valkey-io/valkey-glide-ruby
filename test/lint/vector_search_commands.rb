# frozen_string_literal: true

require "valkey/request_type"

module Lint
  module VectorSearchCommands
    INDEX_NAME = "test_idx"
    ALIAS_NAME = "test_alias"
    # Common RediSearch module paths - adjust based on your installation
    # CI mounts modules at /tmp/modules, so that's checked first
    REDISEARCH_MODULE_PATHS = [
      "/tmp/modules/redisearch.so", # CI/Docker mount path
      "/usr/lib/redis/modules/redisearch.so",
      "/opt/redis-stack/lib/redisearch.so",
      "/usr/local/lib/redis/modules/redisearch.so",
      ENV["REDISEARCH_MODULE_PATH"]
    ].compact.freeze

    def setup
      super
      # RediSearch requires database 0 - switch to it
      r.select(0)
      
      # Try to ensure RediSearch module is loaded
      ensure_redisearch_loaded

      # Clean up any existing index/alias from previous test runs
      begin
        r.ft_drop_index(INDEX_NAME)
      rescue Valkey::CommandError
        # Index doesn't exist, that's fine
      end
      begin
        r.ft_alias_del(ALIAS_NAME)
      rescue Valkey::CommandError
        # Alias doesn't exist, that's fine
      end
    end

    def teardown
      # Clean up test index and alias (on database 0)
      r.select(0)
      begin
        r.ft_drop_index(INDEX_NAME)
      rescue Valkey::CommandError
        # Ignore errors during cleanup
      end
      begin
        r.ft_alias_del(ALIAS_NAME)
      rescue Valkey::CommandError
        # Ignore errors during cleanup
      end
      # Switch back to test database (15)
      r.select(15)
      super
    end

    def test_ft_list
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # FT.LIST should return an array
        list = r.ft_list
        assert_kind_of Array, list
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_create
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create a simple index with schema (schema is required)
        result = r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")
        assert_equal "OK", result

        # Verify index exists in list
        list = r.ft_list
        assert_includes list, INDEX_NAME
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_create_with_schema
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create an index with schema
        result = r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT", "body", "TEXT")
        assert_equal "OK", result

        # Verify index exists
        list = r.ft_list
        assert_includes list, INDEX_NAME
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_drop_index
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create index first (with schema)
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")

        # Drop the index
        result = r.ft_drop_index(INDEX_NAME)
        assert_equal "OK", result

        # Verify index is gone
        list = r.ft_list
        refute_includes list, INDEX_NAME
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_drop_index_with_dd
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create index first (with schema)
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")

        # Drop the index with DD option
        result = r.ft_drop_index(INDEX_NAME, dd: true)
        assert_equal "OK", result
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_info
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create index first (with schema)
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")

        # Get index info
        info = r.ft_info(INDEX_NAME)
        assert_kind_of Array, info
        assert !info.empty?, "Info should contain data"
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_alias_add
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create index first (with schema)
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")

        # Add alias
        result = r.ft_alias_add(ALIAS_NAME, INDEX_NAME)
        assert_equal "OK", result

        # Verify alias exists
        aliases = r.ft_alias_list
        assert_includes aliases, ALIAS_NAME
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_alias_del
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create index and alias first (with schema)
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")
        r.ft_alias_add(ALIAS_NAME, INDEX_NAME)

        # Delete alias
        result = r.ft_alias_del(ALIAS_NAME)
        assert_equal "OK", result

        # Verify alias is gone
        aliases = r.ft_alias_list
        refute_includes aliases, ALIAS_NAME
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_alias_list
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create index and alias first (with schema)
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")
        r.ft_alias_add(ALIAS_NAME, INDEX_NAME)

        # List aliases
        aliases = r.ft_alias_list
        assert_kind_of Array, aliases
        assert_includes aliases, ALIAS_NAME
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_alias_update
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create two indexes (with schemas)
        index1 = "#{INDEX_NAME}_1"
        index2 = "#{INDEX_NAME}_2"
        r.ft_create(index1, "ON", "HASH", "PREFIX", "1", "doc1:", "SCHEMA", "title", "TEXT")
        r.ft_create(index2, "ON", "HASH", "PREFIX", "1", "doc2:", "SCHEMA", "title", "TEXT")

        # Add alias pointing to first index
        r.ft_alias_add(ALIAS_NAME, index1)

        # Update alias to point to second index
        result = r.ft_alias_update(ALIAS_NAME, index2)
        assert_equal "OK", result

        # Clean up
        r.ft_drop_index(index1)
        r.ft_drop_index(index2)
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_search
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create index with schema
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT", "body", "TEXT")

        # Add some documents using send_command (hset not available as method)
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello world", "body", "test content"])
        r.send_command(Valkey::RequestType::HSET, ["doc:2", "title", "foo bar", "body", "another test"])

        # Search
        results = r.ft_search(INDEX_NAME, "hello")
        assert_kind_of Array, results
        assert !results.empty?, "Search should return results"
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_search_with_options
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create index with schema
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT", "body", "TEXT")

        # Add some documents using send_command (hset not available as method)
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello world", "body", "test content"])
        r.send_command(Valkey::RequestType::HSET, ["doc:2", "title", "foo bar", "body", "another test"])

        # Search with LIMIT and RETURN options
        results = r.ft_search(INDEX_NAME, "*", "LIMIT", "0", "10", "RETURN", "1", "title")
        assert_kind_of Array, results
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_aggregate
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create index with schema
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT", "category", "TAG")

        # Add some documents
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello world", "category", "tech"])
        r.send_command(Valkey::RequestType::HSET, ["doc:2", "title", "foo bar", "category", "tech"])

        # Aggregate query
        results = r.ft_aggregate(INDEX_NAME, "*")
        assert_kind_of Array, results
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_aggregate_with_groupby
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create index with schema
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT", "category", "TAG")

        # Add some documents
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello world", "category", "tech"])
        r.send_command(Valkey::RequestType::HSET, ["doc:2", "title", "foo bar", "category", "tech"])

        # Aggregate with GROUPBY
        results = r.ft_aggregate(INDEX_NAME, "*", "GROUPBY", "1", "@category", "REDUCE", "COUNT", "0")
        assert_kind_of Array, results
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_explain
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create index with schema
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")

        # Explain query
        explanation = r.ft_explain(INDEX_NAME, "hello world")
        assert_kind_of String, explanation
        assert !explanation.empty?, "Explanation should not be empty"
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_explain_cli
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create index with schema
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")

        # Explain query in CLI format (returns Array of lines)
        explanation = r.ft_explain_cli(INDEX_NAME, "hello world")
        assert_kind_of Array, explanation
        assert !explanation.empty?, "Explanation should not be empty"
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_profile
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create index with schema
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")

        # Add some documents
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello world"])
        r.send_command(Valkey::RequestType::HSET, ["doc:2", "title", "foo bar"])

        # Profile a search query
        results = r.ft_profile(INDEX_NAME, "SEARCH", "hello")
        assert_kind_of Array, results
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_profile_aggregate
      target_version "2.0" do
        skip("RediSearch module not available") unless redisearch_available?

        # Create index with schema
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT", "category", "TAG")

        # Add some documents
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello world", "category", "tech"])
        r.send_command(Valkey::RequestType::HSET, ["doc:2", "title", "foo bar", "category", "tech"])

        # Profile an aggregate query
        results = r.ft_profile(INDEX_NAME, "AGGREGATE", "*", "GROUPBY", "1", "@category")
        assert_kind_of Array, results
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    private

    def redisearch_available?
      # Try to list indexes - if it works, RediSearch is available
      r.ft_list
      true
    rescue Valkey::CommandError => e
      return false if e.message.include?("unknown command") || e.message.include?("FT")

      raise
    end

    def ensure_redisearch_loaded
      return if redisearch_available?

      # Try to load RediSearch module from common paths
      loaded = false
      REDISEARCH_MODULE_PATHS.each do |path|
        next unless path && File.exist?(path)

        # Skip empty files (created as placeholders when download fails)
        next if File.size(path).zero?

        begin
          r.module_load(path)
          # Give it a moment to load
          sleep 0.2
          if redisearch_available?
            loaded = true
            break
          end
        rescue Valkey::CommandError => e
          # If MODULE commands aren't enabled, we can't load modules
          break if e.message.include?("MODULE command not allowed")

          # If file doesn't exist or can't be loaded, try next path
          next if e.message.include?("No such file") || e.message.include?("cannot open")
        end
      end
      loaded
    rescue StandardError => e
      # Ignore errors during module loading attempt
      warn "Warning: Could not load RediSearch module: #{e.message}" if ENV["VERBOSE"]
    end
  end
end
