# frozen_string_literal: true

require "test_helper"

class TestSearchFields < Minitest::Test
  # --- TextField ---

  def test_text_field_basic
    field = Valkey::Search::TextField.new("title")
    assert_equal ["title", "TEXT"], field.to_args
  end

  def test_text_field_with_alias
    field = Valkey::Search::TextField.new("title", field_alias: "t")
    assert_equal ["title", "AS", "t", "TEXT"], field.to_args
  end

  def test_text_field_sortable
    field = Valkey::Search::TextField.new("title", sortable: true)
    assert_equal ["title", "TEXT", "SORTABLE"], field.to_args
  end

  def test_text_field_nostem
    field = Valkey::Search::TextField.new("title", nostem: true)
    assert_equal ["title", "TEXT", "NOSTEM"], field.to_args
  end

  def test_text_field_weight
    field = Valkey::Search::TextField.new("title", weight: 2.0)
    assert_equal ["title", "TEXT", "WEIGHT", "2.0"], field.to_args
  end

  def test_text_field_withsuffixtrie
    field = Valkey::Search::TextField.new("title", withsuffixtrie: true)
    assert_equal ["title", "TEXT", "WITHSUFFIXTRIE"], field.to_args
  end

  def test_text_field_nosuffixtrie
    field = Valkey::Search::TextField.new("title", nosuffixtrie: true)
    assert_equal ["title", "TEXT", "NOSUFFIXTRIE"], field.to_args
  end

  def test_text_field_all_options
    field = Valkey::Search::TextField.new("title",
                                         field_alias: "t", nostem: true,
                                         weight: 5.0, withsuffixtrie: true, sortable: true)
    expected = ["title", "AS", "t", "TEXT", "NOSTEM", "WEIGHT", "5.0", "WITHSUFFIXTRIE", "SORTABLE"]
    assert_equal expected, field.to_args
  end

  # --- NumericField ---

  def test_numeric_field_basic
    field = Valkey::Search::NumericField.new("price")
    assert_equal ["price", "NUMERIC"], field.to_args
  end

  def test_numeric_field_with_alias
    field = Valkey::Search::NumericField.new("price", field_alias: "p")
    assert_equal ["price", "AS", "p", "NUMERIC"], field.to_args
  end

  def test_numeric_field_sortable
    field = Valkey::Search::NumericField.new("price", sortable: true)
    assert_equal ["price", "NUMERIC", "SORTABLE"], field.to_args
  end

  # --- TagField ---

  def test_tag_field_basic
    field = Valkey::Search::TagField.new("category")
    assert_equal ["category", "TAG"], field.to_args
  end

  def test_tag_field_with_alias
    field = Valkey::Search::TagField.new("category", field_alias: "cat")
    assert_equal ["category", "AS", "cat", "TAG"], field.to_args
  end

  def test_tag_field_separator
    field = Valkey::Search::TagField.new("tags", separator: ";")
    assert_equal ["tags", "TAG", "SEPARATOR", ";"], field.to_args
  end

  def test_tag_field_case_sensitive
    field = Valkey::Search::TagField.new("category", case_sensitive: true)
    assert_equal ["category", "TAG", "CASESENSITIVE"], field.to_args
  end

  def test_tag_field_sortable
    field = Valkey::Search::TagField.new("category", sortable: true)
    assert_equal ["category", "TAG", "SORTABLE"], field.to_args
  end

  def test_tag_field_all_options
    field = Valkey::Search::TagField.new("tags",
                                        field_alias: "t", separator: "|",
                                        case_sensitive: true, sortable: true)
    expected = ["tags", "AS", "t", "TAG", "SEPARATOR", "|", "CASESENSITIVE", "SORTABLE"]
    assert_equal expected, field.to_args
  end

  # --- VectorFieldFlat ---

  def test_vector_field_flat_basic
    field = Valkey::Search::VectorFieldFlat.new("embedding",
                                               dim: 128, distance_metric: :cosine)
    expected = ["embedding", "VECTOR", "FLAT", "6",
                "TYPE", "FLOAT32", "DIM", "128", "DISTANCE_METRIC", "COSINE"]
    assert_equal expected, field.to_args
  end

  def test_vector_field_flat_with_alias
    field = Valkey::Search::VectorFieldFlat.new("embedding",
                                               dim: 128, distance_metric: :l2,
                                               field_alias: "vec")
    expected = ["embedding", "AS", "vec", "VECTOR", "FLAT", "6",
                "TYPE", "FLOAT32", "DIM", "128", "DISTANCE_METRIC", "L2"]
    assert_equal expected, field.to_args
  end

  def test_vector_field_flat_float64
    field = Valkey::Search::VectorFieldFlat.new("embedding",
                                               dim: 256, distance_metric: :ip,
                                               type: :float64)
    expected = ["embedding", "VECTOR", "FLAT", "6",
                "TYPE", "FLOAT64", "DIM", "256", "DISTANCE_METRIC", "IP"]
    assert_equal expected, field.to_args
  end

  def test_vector_field_flat_with_initial_cap
    field = Valkey::Search::VectorFieldFlat.new("embedding",
                                               dim: 128, distance_metric: :cosine,
                                               initial_cap: 1000)
    expected = ["embedding", "VECTOR", "FLAT", "8",
                "TYPE", "FLOAT32", "DIM", "128", "DISTANCE_METRIC", "COSINE",
                "INITIAL_CAP", "1000"]
    assert_equal expected, field.to_args
  end

  def test_vector_field_flat_string_params
    # Verify symbols and strings both work for distance_metric/type
    field = Valkey::Search::VectorFieldFlat.new("embedding",
                                               dim: 64, distance_metric: "cosine",
                                               type: "float32")
    expected = ["embedding", "VECTOR", "FLAT", "6",
                "TYPE", "FLOAT32", "DIM", "64", "DISTANCE_METRIC", "COSINE"]
    assert_equal expected, field.to_args
  end

  # --- VectorFieldHnsw ---

  def test_vector_field_hnsw_basic
    field = Valkey::Search::VectorFieldHnsw.new("embedding",
                                               dim: 768, distance_metric: :cosine)
    expected = ["embedding", "VECTOR", "HNSW", "6",
                "TYPE", "FLOAT32", "DIM", "768", "DISTANCE_METRIC", "COSINE"]
    assert_equal expected, field.to_args
  end

  def test_vector_field_hnsw_with_m
    field = Valkey::Search::VectorFieldHnsw.new("embedding",
                                               dim: 768, distance_metric: :cosine,
                                               m: 16)
    expected = ["embedding", "VECTOR", "HNSW", "8",
                "TYPE", "FLOAT32", "DIM", "768", "DISTANCE_METRIC", "COSINE",
                "M", "16"]
    assert_equal expected, field.to_args
  end

  def test_vector_field_hnsw_with_ef_construction
    field = Valkey::Search::VectorFieldHnsw.new("embedding",
                                               dim: 768, distance_metric: :cosine,
                                               ef_construction: 200)
    expected = ["embedding", "VECTOR", "HNSW", "8",
                "TYPE", "FLOAT32", "DIM", "768", "DISTANCE_METRIC", "COSINE",
                "EF_CONSTRUCTION", "200"]
    assert_equal expected, field.to_args
  end

  def test_vector_field_hnsw_with_ef_runtime
    field = Valkey::Search::VectorFieldHnsw.new("embedding",
                                               dim: 768, distance_metric: :cosine,
                                               ef_runtime: 10)
    expected = ["embedding", "VECTOR", "HNSW", "8",
                "TYPE", "FLOAT32", "DIM", "768", "DISTANCE_METRIC", "COSINE",
                "EF_RUNTIME", "10"]
    assert_equal expected, field.to_args
  end

  def test_vector_field_hnsw_all_options
    field = Valkey::Search::VectorFieldHnsw.new("embedding",
                                               dim: 768, distance_metric: :l2,
                                               type: :float32, field_alias: "vec",
                                               initial_cap: 5000, m: 32,
                                               ef_construction: 400, ef_runtime: 20)
    expected = ["embedding", "AS", "vec", "VECTOR", "HNSW", "14",
                "TYPE", "FLOAT32", "DIM", "768", "DISTANCE_METRIC", "L2",
                "INITIAL_CAP", "5000", "M", "32",
                "EF_CONSTRUCTION", "400", "EF_RUNTIME", "20"]
    assert_equal expected, field.to_args
  end

  # --- Base Field ---

  def test_base_field_raises_not_implemented
    field = Valkey::Search::Field.new("test")
    assert_raises(NotImplementedError) { field.to_args }
  end
end
