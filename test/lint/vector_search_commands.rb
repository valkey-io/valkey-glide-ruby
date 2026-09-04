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

      # Clean up test index unconditionally
      begin
        r.ft_drop_index(TEST_INDEX)
      rescue Valkey::CommandError
        # Ignore - index doesn't exist or command not available
      end

      # Clean up any other test indexes
      begin
        r.ft_drop_index("#{TEST_INDEX}_2")
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
          # RediSearch might not support unloading in some versions, or MODULE command
          # may not be allowed (e.g., enable-module-command not set on server)
          unless e.message.include?("can't unload") || e.message.include?("data types") ||
                 e.message.include?("MODULE command not allowed")
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
        result = r.ft_create(TEST_INDEX,
                             [Valkey::Search::TextField.new("title"),
                              Valkey::Search::NumericField.new("price")])
        assert_equal "OK", result

        # Verify index exists
        list = r.ft_list
        assert list.include?(TEST_INDEX), "Index should exist after creation"
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
          [Valkey::Search::TextField.new("title"),
           Valkey::Search::VectorField.flat("embedding", dim: 128, metric: :cosine)],
          on: :hash, prefixes: ["doc:"]
        )
        assert_equal "OK", result

        # Verify index exists
        list = r.ft_list
        assert list.include?(TEST_INDEX), "Index should exist after creation"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_info
      ensure_redisearch_loaded

      with_db0 do
        # Create an index first
        r.ft_create(TEST_INDEX, [Valkey::Search::TextField.new("title")])

        # Get index info
        # Note: FT.INFO returns a MAP structure from glide-core
        info = r.ft_info(TEST_INDEX)
        assert_kind_of Hash, info

        # Info should contain index_name
        assert info.key?("index_name"), "Info should contain index_name"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_drop_index
      ensure_redisearch_loaded

      with_db0 do
        # Create an index
        r.ft_create(TEST_INDEX, [Valkey::Search::TextField.new("title")])

        # Verify index exists (use ft_list directly since we're already in db0)
        list = r.ft_list
        assert list.include?(TEST_INDEX), "Index should exist after creation"

        # Drop the index
        result = r.ft_drop_index(TEST_INDEX)
        assert_equal "OK", result

        # Verify index no longer exists
        list = r.ft_list
        assert !list.include?(TEST_INDEX), "Index should not exist after drop"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_drop_index_preserves_documents
      ensure_redisearch_loaded

      with_db0 do
        # Create an index
        r.ft_create(TEST_INDEX, [Valkey::Search::TextField.new("title")],
                    on: :hash, prefixes: ["doc:"])

        # Add a document
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "test document"])

        # NOTE: Valkey's native FT.DROPINDEX does not support the DD flag.
        # DD is a Redis Stack (RediSearch module) extension. On Valkey, dropping
        # an index never deletes the underlying keys. We test that ft_drop_index
        # works without DD and that documents are preserved.
        result = r.ft_drop_index(TEST_INDEX)
        assert_equal "OK", result

        # On Valkey, documents are preserved after dropping an index (no DD needed)
        exists = r.exists("doc:1")
        assert_equal 1, exists, "Document should be preserved after FT.DROPINDEX on Valkey"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_search_basic
      ensure_redisearch_loaded

      with_db0 do
        # Create an index
        r.ft_create(TEST_INDEX, [Valkey::Search::TextField.new("title")],
                    on: :hash, prefixes: ["doc:"])

        # Add documents
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello world"])
        r.send_command(Valkey::RequestType::HSET, ["doc:2", "title", "goodbye world"])

        # Small delay to allow indexing
        sleep 0.1

        # Search for documents
        results = r.ft_search(TEST_INDEX, "hello")
        assert_instance_of Valkey::Search::SearchResult, results
        assert_kind_of Integer, results.total_results
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_search_with_options
      ensure_redisearch_loaded

      with_db0 do
        # Create an index
        r.ft_create(TEST_INDEX, [Valkey::Search::TextField.new("title")],
                    on: :hash, prefixes: ["doc:"])

        # Add documents
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello world"])
        r.send_command(Valkey::RequestType::HSET, ["doc:2", "title", "goodbye world"])

        sleep 0.1

        # Search with LIMIT and RETURN options
        results = r.ft_search(TEST_INDEX, "world", limit: { offset: 0, count: 1 }, return_fields: ["title"])
        assert_instance_of Valkey::Search::SearchResult, results
        assert_operator results.documents.length, :<=, 1
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    def test_ft_aggregate
      ensure_redisearch_loaded

      with_db0 do
        # Create an index
        r.ft_create(TEST_INDEX,
                    [Valkey::Search::TagField.new("category"),
                     Valkey::Search::NumericField.new("price")],
                    on: :hash, prefixes: ["product:"])

        # Add documents
        r.send_command(Valkey::RequestType::HSET, ["product:1", "category", "electronics", "price", "100"])
        r.send_command(Valkey::RequestType::HSET, ["product:2", "category", "electronics", "price", "200"])
        r.send_command(Valkey::RequestType::HSET, ["product:3", "category", "books", "price", "50"])

        sleep 0.1

        # Run aggregation with a numeric filter that matches all documents.
        # LOAD is required for GROUPBY to see @category; without it the server
        # collapses all documents into one ungrouped row instead of erroring.
        results = r.ft_aggregate(TEST_INDEX, "@price:[0 +inf]",
                                 load: ["@category"],
                                 clauses: [Valkey::Search::GroupBy.new(
                                   ["@category"],
                                   reducers: [Valkey::Search::Reducer.count(as: "count")]
                                 )])
        assert_kind_of Array, results
        rows = aggregate_rows(results)
        assert_equal 2, rows.length, "electronics and books should group into two rows"
        assert_equal 3, rows.sum { |h| Integer(h["count"]) }, "COUNT should total the three seeded docs"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # ------------------------------------------------------------------
    # Builder-API integration coverage.
    #
    # These exercise the Valkey::Search::* builder path of ft_create against a
    # live search module. Like the rest of this suite they are module-gated:
    # they skip when the search module / native library is unavailable, so they
    # remain pending-integration in environments without a live search module.
    # ------------------------------------------------------------------

    # create index with text and numeric fields via the builder API.
    def test_ft_create_builder_text_and_numeric
      ensure_redisearch_loaded

      with_db0 do
        result = r.ft_create(TEST_INDEX,
                             [Valkey::Search::TextField.new("title", sortable: true),
                              Valkey::Search::NumericField.new("price", sortable: true)])
        assert_equal "OK", result
        assert_includes r.ft_list, TEST_INDEX, "Index should exist after builder create"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # create index with an HNSW vector field via the builder API.
    def test_ft_create_builder_vector_hnsw
      ensure_redisearch_loaded

      with_db0 do
        result = r.ft_create(TEST_INDEX,
                             [Valkey::Search::VectorField.hnsw("embedding", dim: 128, metric: :cosine,
                                                                            m: 16, ef_construction: 200)],
                             on: :hash, prefixes: ["doc:"])
        assert_equal "OK", result
        assert_includes r.ft_list, TEST_INDEX
        # Same reasoning as the FLAT case: pin the stored algorithm so a builder
        # emitting the wrong one cannot pass on "OK" alone.
        info_text = r.ft_info(TEST_INDEX).to_a.flatten.join(" ")
        assert_match(/HNSW/, info_text, "FT.INFO should report the HNSW algorithm")
        refute_match(/FLAT/, info_text, "an HNSW index should not report FLAT")
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # create index with a FLAT vector field via the builder API.
    def test_ft_create_builder_vector_flat
      ensure_redisearch_loaded

      with_db0 do
        result = r.ft_create(TEST_INDEX,
                             [Valkey::Search::VectorField.flat("embedding", dim: 128, metric: :l2)],
                             on: :hash, prefixes: ["doc:"])
        assert_equal "OK", result
        assert_includes r.ft_list, TEST_INDEX
        # Assert the schema the server actually stored, not just that creation
        # succeeded: "OK" plus index existence holds true for any schema, including
        # the wrong algorithm or a dropped DIM.
        info_text = r.ft_info(TEST_INDEX).to_a.flatten.join(" ")
        assert_match(/FLAT/, info_text, "FT.INFO should report the FLAT algorithm")
        assert_match(/\b128\b/, info_text, "FT.INFO should report the requested dimension")
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # create index with a tag field via the builder API.
    def test_ft_create_builder_tag
      ensure_redisearch_loaded

      with_db0 do
        result = r.ft_create(TEST_INDEX,
                             [Valkey::Search::TagField.new("category", separator: ",", case_sensitive: true)])
        assert_equal "OK", result
        assert_includes r.ft_list, TEST_INDEX
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # HASH data type + key prefixes: only prefixed keys are indexed.
    def test_ft_create_builder_prefix_only_indexes_matching_keys
      ensure_redisearch_loaded

      with_db0 do
        opts = Valkey::Search::CreateOptions.new(on: :hash, prefixes: ["doc:"])
        r.ft_create(TEST_INDEX, [Valkey::Search::TextField.new("title")], opts)

        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello world"])
        r.send_command(Valkey::RequestType::HSET, ["other:1", "title", "hello world"])
        sleep 0.1

        results = r.ft_search(TEST_INDEX, "hello")
        assert_instance_of Valkey::Search::SearchResult, results
        assert_equal 1, results.total_results, "only the doc:-prefixed key should be indexed"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # ------------------------------------------------------------------
    # Builder-API query integration coverage.
    #
    # Exercise the SearchOptions builder path of ft_search (returns a structured
    # Valkey::Search::SearchResult). Module-gated like the rest of this suite.
    # ------------------------------------------------------------------

    # basic text search returns fields + total via SearchResult.
    def test_ft_search_builder_basic_text
      ensure_redisearch_loaded

      with_db0 do
        r.ft_create(TEST_INDEX, [Valkey::Search::TextField.new("title")], on: :hash, prefixes: ["doc:"])
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello world"])
        sleep 0.1

        result = r.ft_search(TEST_INDEX, "hello", Valkey::Search::SearchOptions.new)
        assert_instance_of Valkey::Search::SearchResult, result
        assert_equal 1, result.total_results
        assert_equal "hello world", result.documents.first.fields["title"]
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # pagination via LIMIT returns only the requested page.
    def test_ft_search_builder_limit
      ensure_redisearch_loaded

      with_db0 do
        r.ft_create(TEST_INDEX, [Valkey::Search::TextField.new("title")], on: :hash, prefixes: ["doc:"])
        3.times { |i| r.send_command(Valkey::RequestType::HSET, ["doc:#{i}", "title", "hello"]) }
        sleep 0.1

        # LIMIT must truncate to exactly `count`, and total_results still reports
        # the full match count. Asserting equality (not <=) is deliberate: a
        # builder that drops or zeroes the count arg still satisfies `<= 2`.
        result = r.ft_search(TEST_INDEX, "hello", limit: { offset: 0, count: 2 })
        assert_equal 2, result.documents.length, "LIMIT 0 2 should return exactly two documents"
        assert_equal 3, result.total_results

        # A non-zero offset must select a different window of the same result set,
        # which pins the offset arg as well as the count arg.
        page1 = r.ft_search(TEST_INDEX, "hello", limit: { offset: 0, count: 1 })
        page2 = r.ft_search(TEST_INDEX, "hello", limit: { offset: 1, count: 1 })

        assert_equal 1, page1.documents.length, "LIMIT 0 1 should return exactly one document"
        assert_equal 1, page2.documents.length, "LIMIT 1 1 should return exactly one document"
        refute_equal page1.documents.first.key, page2.documents.first.key,
                     "offset 1 should return a different document than offset 0"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # field projection via RETURN limits returned fields.
    def test_ft_search_builder_return_fields
      ensure_redisearch_loaded

      with_db0 do
        r.ft_create(TEST_INDEX,
                    [Valkey::Search::TextField.new("title"), Valkey::Search::NumericField.new("price")],
                    on: :hash, prefixes: ["doc:"])
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello", "price", "10"])
        sleep 0.1

        result = r.ft_search(TEST_INDEX, "hello", return_fields: ["title"])
        doc = result.documents.first
        assert_equal "hello", doc.fields["title"]
        refute doc.fields.key?("price"), "price should be projected out"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # sorting by a sortable field returns results in order.
    def test_ft_search_builder_sort_by
      ensure_redisearch_loaded

      with_db0 do
        r.ft_create(TEST_INDEX,
                    [Valkey::Search::TextField.new("title"),
                     Valkey::Search::NumericField.new("price", sortable: true)],
                    on: :hash, prefixes: ["doc:"])
        # Seed in descending price order so the *unsorted* reply order is wrong.
        # With only two ascending-by-accident documents, `assert_equal prices.sort,
        # prices` can pass even when SORTBY is never emitted; seeding worst-case and
        # asserting the exact expected sequence removes that luck.
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello", "price", "30"])
        r.send_command(Valkey::RequestType::HSET, ["doc:2", "title", "hello", "price", "20"])
        r.send_command(Valkey::RequestType::HSET, ["doc:3", "title", "hello", "price", "10"])
        sleep 0.1

        result = r.ft_search(TEST_INDEX, "hello",
                             sort_by: "price", sort_order: :asc, return_fields: ["price"])
        prices = result.documents.map { |d| Integer(d.fields["price"]) }
        assert_equal [10, 20, 30], prices, "results should be ascending by price"

        # Descending must invert the sequence, which pins the direction token as
        # well as the SORTBY clause itself.
        desc = r.ft_search(TEST_INDEX, "hello",
                           sort_by: "price", sort_order: :desc, return_fields: ["price"])
        assert_equal [30, 20, 10], desc.documents.map { |d| Integer(d.fields["price"]) },
                     "results should be descending by price"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # KNN vector similarity search returns nearest neighbors.
    def test_ft_search_builder_vector_knn
      ensure_redisearch_loaded

      with_db0 do
        r.ft_create(TEST_INDEX,
                    [Valkey::Search::VectorField.flat("embedding", dim: 4, metric: :l2)],
                    on: :hash, prefixes: ["doc:"])
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "embedding", [1.0, 0.0, 0.0, 0.0].pack("f*")])
        r.send_command(Valkey::RequestType::HSET, ["doc:2", "embedding", [0.0, 1.0, 0.0, 0.0].pack("f*")])
        sleep 0.1

        query_vec = [1.0, 0.0, 0.0, 0.0].pack("f*")
        result = r.ft_search(TEST_INDEX, "*=>[KNN 2 @embedding $vec]",
                             params: { vec: query_vec }, dialect: 2)
        assert_instance_of Valkey::Search::SearchResult, result
        # KNN 2 over two indexed vectors must return both, and the nearest neighbour
        # must be doc:1 (identical to the query vector). Asserting order pins the
        # vector payload and PARAMS binding; a bare `>= 1` would pass on a garbled
        # query that happened to match one document.
        assert_equal 2, result.documents.length, "KNN 2 should return both indexed vectors"
        assert_equal "doc:1", result.documents.first.key,
                     "the vector identical to the query should rank first"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # NOCONTENT returns keys only (no field data).
    def test_ft_search_builder_no_content
      ensure_redisearch_loaded

      with_db0 do
        r.ft_create(TEST_INDEX, [Valkey::Search::TextField.new("title")], on: :hash, prefixes: ["doc:"])
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello"])
        sleep 0.1

        result = r.ft_search(TEST_INDEX, "hello", no_content: true)
        assert_equal "doc:1", result.documents.first.key
        assert_empty result.documents.first.fields

        # Contrast against the default reply: without NOCONTENT the server returns
        # the field payload.
        with_content = r.ft_search(TEST_INDEX, "hello")
        assert_equal({ "title" => "hello" }, with_content.documents.first.fields,
                     "without no_content the field payload should be present")

        # The parsed result alone cannot prove NOCONTENT reached the wire: the
        # parser is passed no_content: separately and discards the field payload
        # client-side, so a builder that never emits the token yields an identical
        # SearchResult. Assert the emitted args directly to pin the token itself.
        assert_includes Valkey::Search::SearchOptions.new(no_content: true).to_args, "NOCONTENT",
                        "no_content: true must emit the NOCONTENT token"
        refute_includes Valkey::Search::SearchOptions.new.to_args, "NOCONTENT",
                        "NOCONTENT must not be emitted by default"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # query dialect 2 is accepted.
    def test_ft_search_builder_dialect
      ensure_redisearch_loaded

      with_db0 do
        r.ft_create(TEST_INDEX, [Valkey::Search::TextField.new("title")], on: :hash, prefixes: ["doc:"])
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "hello"])
        sleep 0.1

        result = r.ft_search(TEST_INDEX, "hello", dialect: 2)
        assert_instance_of Valkey::Search::SearchResult, result
        assert_equal 1, result.total_results
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # ------------------------------------------------------------------
    # Builder-API aggregate integration coverage.
    #
    # Exercise the AggregateOptions / clause builder path of ft_aggregate against
    # live seeded data. ft_aggregate returns the raw Array reply (no structured
    # aggregate result type), so we assert on that reply shape. Module-gated like
    # the rest of this suite.
    # ------------------------------------------------------------------

    # Seed a small products dataset (category TAG + price NUMERIC) for aggregate
    # tests. Returns after a short delay to allow async indexing to settle.
    def seed_products_for_aggregate
      r.ft_create(TEST_INDEX,
                  [Valkey::Search::TagField.new("category"),
                   Valkey::Search::NumericField.new("price", sortable: true)],
                  on: :hash, prefixes: ["product:"])
      r.send_command(Valkey::RequestType::HSET, ["product:1", "category", "electronics", "price", "100"])
      r.send_command(Valkey::RequestType::HSET, ["product:2", "category", "electronics", "price", "200"])
      r.send_command(Valkey::RequestType::HSET, ["product:3", "category", "books", "price", "50"])
      r.send_command(Valkey::RequestType::HSET, ["product:4", "category", "books", "price", "30"])
      sleep 0.1
    end

    # GROUPBY (>=1 property) with COUNT and SUM reducers over live data.
    def test_ft_aggregate_builder_groupby_reducers
      ensure_redisearch_loaded

      with_db0 do
        seed_products_for_aggregate

        # LOAD is required for GROUPBY to see the field: without `LOAD 1 @category`
        # the attribute is not in the aggregate pipeline and the server silently
        # collapses every document into a single ungrouped row (count=4) instead of
        # erroring. Asserting the group count and the per-group breakdown is what
        # distinguishes real grouping from that collapse.
        results = r.ft_aggregate(TEST_INDEX, "@price:[0 +inf]",
                                 load: ["@category", "@price"],
                                 clauses: [
                                   Valkey::Search::GroupBy.new(
                                     ["@category"],
                                     reducers: [
                                       Valkey::Search::Reducer.count(as: "count"),
                                       Valkey::Search::Reducer.sum("@price", as: "total")
                                     ]
                                   )
                                 ], dialect: 2)
        # glide-core normalizes FT.AGGREGATE into an Array of Hash rows.
        rows = aggregate_rows(results)
        assert_equal 2, rows.length, "two seeded categories should group into two rows"
        assert(rows.all? { |h| h.key?("count") }, "COUNT reducer alias should be present")
        assert(rows.all? { |h| h.key?("total") }, "SUM reducer alias should be present")
        # COUNT reflects the four seeded, price-matching documents.
        assert_equal 4, rows.sum { |h| Integer(h["count"]) }, "COUNT should total the seeded docs"

        by_category = rows.to_h { |h| [h["category"], h] }
        assert_equal %w[books electronics], by_category.keys.sort,
                     "GROUPBY should key rows by the loaded category field"
        assert_equal 2, Integer(by_category["electronics"]["count"])
        assert_equal 300, Integer(by_category["electronics"]["total"]), "100 + 200"
        assert_equal 2, Integer(by_category["books"]["count"])
        assert_equal 80, Integer(by_category["books"]["total"]), "50 + 30"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # `"*"` is a valid FT.AGGREGATE query on this module version, matching every
    # document rather than raising. A prior comment in this file claimed the
    # opposite ("Valkey Search rejects the wildcard"); measured directly against
    # a live server, that claim does not hold, so this pins the actual behavior
    # instead of leaving an untested assumption in the code.
    def test_ft_aggregate_builder_wildcard_query_matches_all
      ensure_redisearch_loaded

      with_db0 do
        seed_products_for_aggregate

        wildcard = aggregate_rows(
          r.ft_aggregate(TEST_INDEX, "*",
                         load: ["@category"],
                         clauses: [
                           Valkey::Search::GroupBy.new(
                             ["@category"],
                             reducers: [Valkey::Search::Reducer.count(as: "count")]
                           )
                         ], dialect: 2)
        )
        filtered = aggregate_rows(
          r.ft_aggregate(TEST_INDEX, "@price:[0 +inf]",
                         load: ["@category"],
                         clauses: [
                           Valkey::Search::GroupBy.new(
                             ["@category"],
                             reducers: [Valkey::Search::Reducer.count(as: "count")]
                           )
                         ], dialect: 2)
        )
        as_hash = ->(rows) { rows.to_h { |h| [h["category"], Integer(h["count"])] } }
        assert_equal as_hash.call(filtered), as_hash.call(wildcard),
                     "\"*\" should match every document, identically to a filter matching all of them"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # SORTBY (with MAX) is accepted and windows the grouped output.
    def test_ft_aggregate_builder_sortby_max
      ensure_redisearch_loaded

      with_db0 do
        seed_products_for_aggregate

        # LOAD makes the group field visible, so this groups into two rows; MAX 1
        # then windows it to exactly one. Asserting equality rather than `<= 1`
        # matters because a dropped SORTBY/MAX would leave two rows, while `<= 1`
        # would also accept zero rows from a broken pipeline.
        results = r.ft_aggregate(TEST_INDEX, "@price:[0 +inf]",
                                 load: ["@category", "@price"],
                                 clauses: [
                                   Valkey::Search::GroupBy.new(
                                     ["@category"],
                                     reducers: [Valkey::Search::Reducer.sum("@price", as: "total")]
                                   ),
                                   Valkey::Search::SortBy.new({ "@total" => :desc }, max: 1)
                                 ], dialect: 2)
        rows = aggregate_rows(results)
        assert_equal 1, rows.length, "SORTBY MAX 1 should window output to one row"
        assert(rows.all? { |h| h.key?("total") }, "SUM reducer alias should survive SORTBY")
        # electronics totals 300 vs books' 80, so DESC ordering must surface electronics.
        assert_equal 300, Integer(rows.first["total"]),
                     "SORTBY @total DESC should surface the highest-total group first"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # FILTER is accepted and prunes rows that fail the predicate.
    def test_ft_aggregate_builder_filter
      ensure_redisearch_loaded

      with_db0 do
        seed_products_for_aggregate

        # With LOAD the groups carry real SUM totals (electronics 300, books 80), so
        # `@total > 100` keeps exactly electronics and `@total > 1000` drops both.
        # Distinguishing kept-count 1 from 2 proves FILTER evaluates the predicate,
        # rather than merely proving rows survived.
        kept = aggregate_rows(
          r.ft_aggregate(TEST_INDEX, "@price:[0 +inf]",
                         load: ["@category", "@price"],
                         clauses: [
                           Valkey::Search::GroupBy.new(
                             ["@category"], reducers: [Valkey::Search::Reducer.sum("@price", as: "total")]
                           ),
                           Valkey::Search::Filter.new("@total > 100")
                         ], dialect: 2)
        )
        dropped = aggregate_rows(
          r.ft_aggregate(TEST_INDEX, "@price:[0 +inf]",
                         load: ["@category", "@price"],
                         clauses: [
                           Valkey::Search::GroupBy.new(
                             ["@category"], reducers: [Valkey::Search::Reducer.sum("@price", as: "total")]
                           ),
                           Valkey::Search::Filter.new("@total > 1000")
                         ], dialect: 2)
        )
        assert_equal 1, kept.length, "FILTER @total > 100 should keep only the electronics group"
        assert_equal 300, Integer(kept.first["total"])
        assert_empty dropped, "FILTER @total > 1000 should drop all rows"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # APPLY adds a computed field to each row.
    def test_ft_aggregate_builder_apply
      ensure_redisearch_loaded

      with_db0 do
        seed_products_for_aggregate

        results = r.ft_aggregate(TEST_INDEX, "@price:[0 +inf]",
                                 load: ["@category", "@price"],
                                 clauses: [
                                   Valkey::Search::GroupBy.new(
                                     ["@category"],
                                     reducers: [Valkey::Search::Reducer.sum("@price", as: "total")]
                                   ),
                                   Valkey::Search::Apply.new("@total * 2", as: "double_total")
                                 ], dialect: 2)
        rows = aggregate_rows(results)
        assert_equal 2, rows.length, "APPLY should preserve both grouped rows"
        assert(rows.all? { |h| h.key?("double_total") }, "APPLY should add double_total to every row")
        # Assert the arithmetic, not just the alias: a no-op APPLY would still add
        # the key but leave the value equal to @total.
        rows.each do |h|
          assert_equal Integer(h["total"]) * 2, Integer(h["double_total"]),
                       "double_total should be twice total for #{h['category']}"
        end
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # LIMIT windows the pipeline output.
    def test_ft_aggregate_builder_limit
      ensure_redisearch_loaded

      with_db0 do
        seed_products_for_aggregate

        # The seed data has exactly two categories, so an unlimited GROUPBY returns
        # two rows (LOAD is required for the group field to be visible). Asserting
        # the unlimited count first, then exactly one row under LIMIT 0 1, proves the
        # clause actually truncated: a builder that drops the LIMIT clause entirely
        # would return two rows and fail here, whereas a bare `<= 1` assertion would
        # pass for any count including zero.
        unlimited = r.ft_aggregate(TEST_INDEX, "@price:[0 +inf]",
                                   load: ["@category"],
                                   clauses: [
                                     Valkey::Search::GroupBy.new(
                                       ["@category"],
                                       reducers: [Valkey::Search::Reducer.count(as: "count")]
                                     )
                                   ], dialect: 2)
        assert_equal 2, aggregate_rows(unlimited).length,
                     "two seeded categories should group into two rows without LIMIT"

        results = r.ft_aggregate(TEST_INDEX, "@price:[0 +inf]",
                                 load: ["@category"],
                                 clauses: [
                                   Valkey::Search::GroupBy.new(
                                     ["@category"],
                                     reducers: [Valkey::Search::Reducer.count(as: "count")]
                                   ),
                                   Valkey::Search::Limit.new(0, 1)
                                 ], dialect: 2)
        rows = aggregate_rows(results)
        assert_equal 1, rows.length, "LIMIT 0 1 should return exactly one row"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # ------------------------------------------------------------------
    # Builder-API info + lifecycle integration coverage.
    # ------------------------------------------------------------------

    # ft_info (plain and scoped) returns index metadata as a Hash.
    def test_ft_info_builder_metadata
      ensure_redisearch_loaded

      with_db0 do
        r.ft_create(TEST_INDEX,
                    [Valkey::Search::TextField.new("title"),
                     Valkey::Search::NumericField.new("price")],
                    on: :hash, prefixes: ["doc:"])

        info = r.ft_info(TEST_INDEX)
        assert_kind_of Hash, info
        name = info["index_name"] || info["index_name".upcase] || info[:index_name]
        assert_equal TEST_INDEX, name.to_s, "info should report the index name"

        # Scoped info (LOCAL) must be accepted on standalone (no-op scope).
        scoped = r.ft_info(TEST_INDEX, scope: :local)
        assert_kind_of Hash, scoped
        scoped_name = scoped["index_name"] || scoped["index_name".upcase] || scoped[:index_name]
        assert_equal TEST_INDEX, scoped_name.to_s, "scoped info should report the index name"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # ft_drop_index removes the index from ft_list; documents survive.
    def test_ft_drop_index_builder_preserves_documents
      ensure_redisearch_loaded

      with_db0 do
        r.ft_create(TEST_INDEX, [Valkey::Search::TextField.new("title")],
                    on: :hash, prefixes: ["doc:"])
        r.send_command(Valkey::RequestType::HSET, ["doc:1", "title", "keep me"])
        sleep 0.1

        assert_includes r.ft_list, TEST_INDEX

        result = r.ft_drop_index(TEST_INDEX)
        assert_equal "OK", result
        refute_includes r.ft_list, TEST_INDEX, "index should be gone after drop"

        # Docs survive (Valkey FT.DROPINDEX has no DD; keys preserved).
        value = r.send_command(Valkey::RequestType::HGET, ["doc:1", "title"])
        assert_equal "keep me", value, "document should survive FT.DROPINDEX"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    # ft_list includes a builder-created index.
    def test_ft_list_includes_builder_index
      ensure_redisearch_loaded

      with_db0 do
        r.ft_create(TEST_INDEX, [Valkey::Search::TextField.new("title")],
                    on: :hash, prefixes: ["doc:"])
        list = r.ft_list
        assert_kind_of Array, list
        assert_includes list, TEST_INDEX, "ft_list should include the builder-created index"
      end
    rescue Valkey::CommandError => e
      skip_if_redisearch_unavailable(e)
    end

    private

    # Normalize an FT.AGGREGATE reply into an Array of row Hashes. glide-core
    # normalizes the reply to an Array of Hashes already; tolerate the raw
    # `[count, [k, v, ...], ...]` shape too for robustness across engine builds.
    def aggregate_rows(results)
      return [] if results.nil?

      arr = Array(results)
      return [] if arr.empty?

      if arr.all?(Hash)
        arr
      else
        # Raw shape: drop the leading count, fold each [k, v, ...] pair-array to a Hash.
        arr[1..].to_a.map { |row| row.is_a?(Hash) ? row : Hash[*row] }
      end
    end

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

      # Try to load the search module. MODULE LOAD is sent via send_command
      # rather than a #module_load helper: the ModuleCommands mixin is not
      # included on Valkey, so calling r.module_load would raise NoMethodError
      # (not a CommandError) and escape the rescue below.
      begin
        r.send_command(Valkey::RequestType::MODULE_LOAD, [REDISEARCH_MODULE_PATH])
        sleep 0.2 # Give module time to initialize
      rescue Valkey::CommandError => e
        if e.message.include?("No such file") || e.message.include?("cannot open")
          skip("RediSearch module file not available at #{REDISEARCH_MODULE_PATH}")
        elsif e.message.include?("MODULE command not allowed")
          skip("MODULE commands not enabled")
        elsif e.message.include?("unknown command")
          skip("MODULE command not supported on this server version")
        elsif e.message.include?("Error loading the extension")
          skip("RediSearch module failed to load on this engine")
        else
          # Any other load failure means search is unavailable here — skip
          # rather than fail the whole suite on a non-module server.
          skip("RediSearch module could not be loaded: #{e.message}")
        end
      end
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
