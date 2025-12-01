# frozen_string_literal: true

module Lint
  module VectorSearchCommands
    INDEX_NAME = "test_idx"
    ALIAS_NAME = "test_alias"

    def setup
      super
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
      # Clean up test index and alias
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
      super
    end

    def test_ft_list
      target_version "2.0" do
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
        # Create a simple index
        result = r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:")
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
        # Create index first
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:")

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
        # Create index first
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:")

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
        # Create index first
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:")

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
        # Create index first
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:")

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
        # Create index and alias first
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:")
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
        # Create index and alias first
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:")
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
        # Create two indexes
        index1 = "#{INDEX_NAME}_1"
        index2 = "#{INDEX_NAME}_2"
        r.ft_create(index1, "ON", "HASH", "PREFIX", "1", "doc1:")
        r.ft_create(index2, "ON", "HASH", "PREFIX", "1", "doc2:")

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
        # Create index with schema
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT", "body", "TEXT")

        # Add some documents
        r.hset("doc:1", "title", "hello world", "body", "test content")
        r.hset("doc:2", "title", "foo bar", "body", "another test")

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
        # Create index with schema
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT", "body", "TEXT")

        # Add some documents
        r.hset("doc:1", "title", "hello world", "body", "test content")
        r.hset("doc:2", "title", "foo bar", "body", "another test")

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
        # Create index with schema
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT", "category", "TAG")

        # Add some documents
        r.hset("doc:1", "title", "hello world", "category", "tech")
        r.hset("doc:2", "title", "foo bar", "category", "tech")

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
        # Create index with schema
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT", "category", "TAG")

        # Add some documents
        r.hset("doc:1", "title", "hello world", "category", "tech")
        r.hset("doc:2", "title", "foo bar", "category", "tech")

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
        # Create index with schema
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")

        # Explain query in CLI format
        explanation = r.ft_explain_cli(INDEX_NAME, "hello world")
        assert_kind_of String, explanation
        assert !explanation.empty?, "Explanation should not be empty"
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end

    def test_ft_profile
      target_version "2.0" do
        # Create index with schema
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT")

        # Add some documents
        r.hset("doc:1", "title", "hello world")
        r.hset("doc:2", "title", "foo bar")

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
        # Create index with schema
        r.ft_create(INDEX_NAME, "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT", "category", "TAG")

        # Add some documents
        r.hset("doc:1", "title", "hello world", "category", "tech")
        r.hset("doc:2", "title", "foo bar", "category", "tech")

        # Profile an aggregate query
        results = r.ft_profile(INDEX_NAME, "AGGREGATE", "*", "GROUPBY", "1", "@category")
        assert_kind_of Array, results
      rescue Valkey::CommandError => e
        skip("RediSearch module not available") if e.message.include?("unknown command") || e.message.include?("FT")
        raise
      end
    end
  end
end
