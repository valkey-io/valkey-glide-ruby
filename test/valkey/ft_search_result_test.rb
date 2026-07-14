# frozen_string_literal: true

require "test_helper"

class TestFtSearchResult < Minitest::Test
  # --- FtSearchDocument ---

  def test_document_key
    doc = Valkey::Search::FtSearchDocument.new("doc:1", { "title" => "hello" })
    assert_equal "doc:1", doc.key
  end

  def test_document_fields
    fields = { "title" => "hello", "price" => "9.99" }
    doc = Valkey::Search::FtSearchDocument.new("doc:1", fields)
    assert_equal fields, doc.fields
  end

  def test_document_bracket_accessor
    doc = Valkey::Search::FtSearchDocument.new("doc:1", { "title" => "hello" })
    assert_equal "hello", doc["title"]
    assert_nil doc["nonexistent"]
  end

  def test_document_sort_key
    doc = Valkey::Search::FtSearchDocument.new("doc:1", {}, sort_key: "9.99")
    assert_equal "9.99", doc.sort_key
  end

  def test_document_sort_key_nil_by_default
    doc = Valkey::Search::FtSearchDocument.new("doc:1", {})
    assert_nil doc.sort_key
  end

  def test_document_to_s
    doc = Valkey::Search::FtSearchDocument.new("doc:1", { "x" => "1" })
    assert_match(/FtSearchDocument/, doc.to_s)
    assert_match(/doc:1/, doc.to_s)
  end

  # --- FtSearchResult.from_raw ---

  def test_from_raw_nil
    result = Valkey::Search::FtSearchResult.from_raw(nil)
    assert_equal 0, result.total_results
    assert_equal [], result.documents
  end

  def test_from_raw_empty
    result = Valkey::Search::FtSearchResult.from_raw([])
    assert_equal 0, result.total_results
    assert_equal [], result.documents
  end

  def test_from_raw_count_only
    # When count-only mode is used, response is just [count]
    result = Valkey::Search::FtSearchResult.from_raw([5])
    assert_equal 5, result.total_results
    assert_equal [], result.documents
  end

  def test_from_raw_normal_response
    # glide-core normalized format: [count, {key => {field => value}}]
    raw = [2, { "doc:1" => { "title" => "hello" }, "doc:2" => { "title" => "world" } }]
    result = Valkey::Search::FtSearchResult.from_raw(raw)
    assert_equal 2, result.total_results
    assert_equal 2, result.documents.size
    assert_equal "doc:1", result.documents[0].key
    assert_equal "hello", result.documents[0]["title"]
    assert_equal "doc:2", result.documents[1].key
    assert_equal "world", result.documents[1]["title"]
  end

  def test_from_raw_multiple_fields
    raw = [1, { "doc:1" => { "title" => "hi", "price" => "5.0", "category" => "books" } }]
    result = Valkey::Search::FtSearchResult.from_raw(raw)
    assert_equal 1, result.total_results
    doc = result.documents.first
    assert_equal "hi", doc["title"]
    assert_equal "5.0", doc["price"]
    assert_equal "books", doc["category"]
  end

  def test_from_raw_empty_fields
    # NOCONTENT response: documents have empty field maps
    raw = [2, { "doc:1" => {}, "doc:2" => {} }]
    result = Valkey::Search::FtSearchResult.from_raw(raw)
    assert_equal 2, result.total_results
    assert_equal({}, result.documents[0].fields)
    assert_equal({}, result.documents[1].fields)
  end

  def test_from_raw_with_sortkeys
    # WITHSORTKEYS format: {key => [sort_key, {fields}]}
    raw = [2, {
      "doc:1" => ["9.99", { "title" => "cheap", "price" => "9.99" }],
      "doc:2" => ["19.99", { "title" => "pricey", "price" => "19.99" }]
    }]
    result = Valkey::Search::FtSearchResult.from_raw(raw, withsortkeys: true)
    assert_equal 2, result.total_results
    assert_equal "9.99", result.documents[0].sort_key
    assert_equal "cheap", result.documents[0]["title"]
    assert_equal "19.99", result.documents[1].sort_key
    assert_equal "pricey", result.documents[1]["title"]
  end

  def test_from_raw_with_sortkeys_nil_sort_key
    # When sort field is missing, sort_key is nil
    raw = [1, { "doc:1" => [nil, { "title" => "no price" }] }]
    result = Valkey::Search::FtSearchResult.from_raw(raw, withsortkeys: true)
    assert_nil result.documents[0].sort_key
    assert_equal "no price", result.documents[0]["title"]
  end

  def test_from_raw_count_string
    # glide-core might return count as string
    raw = ["3", { "doc:1" => { "x" => "1" } }]
    result = Valkey::Search::FtSearchResult.from_raw(raw)
    assert_equal 3, result.total_results
  end

  def test_from_raw_fields_as_array
    # Handle case where fields come as alternating array [key, val, key, val]
    raw = [1, { "doc:1" => ["title", "hello", "price", "5"] }]
    result = Valkey::Search::FtSearchResult.from_raw(raw)
    assert_equal "hello", result.documents[0]["title"]
    assert_equal "5", result.documents[0]["price"]
  end

  def test_from_raw_fields_nil
    # Handle nil field value gracefully
    raw = [1, { "doc:1" => nil }]
    result = Valkey::Search::FtSearchResult.from_raw(raw)
    assert_equal({}, result.documents[0].fields)
  end

  def test_result_to_s
    result = Valkey::Search::FtSearchResult.from_raw([3, { "a" => {} }])
    assert_match(/FtSearchResult/, result.to_s)
    assert_match(/total=3/, result.to_s)
    assert_match(/docs=1/, result.to_s)
  end
end
