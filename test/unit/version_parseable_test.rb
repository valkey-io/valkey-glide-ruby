# frozen_string_literal: true

require "test_helper"

# Unit tests for `Helper::Version.parseable?`.
class TestVersionParseableUnit < Minitest::Test
  ACCEPTED = [
    "8",
    "8.1",
    "8.1.0",
    "7.2",
    "9.1.1",
    "10.0.0",
    "8.1.0-rc1",
    "8.1.0-alpha.2"
  ].freeze

  REJECTED = [
    "", # a valueless INFO line yields this via HashifyInfo
    "unstable",
    "0",
    "0.0",
    "00",
    "0garbage",
    "7.1garbage",
    "8garbage",
    "8.1.0.",
    "8.1.0-",
    "-1.0",
    "v8.1.0",
    " 8.1.0",
    "8.1.0 "
  ].freeze

  ACCEPTED.each_with_index do |value, index|
    define_method(:"test_accepts_#{index}_#{value.gsub(/\W/, '_')}") do
      assert Helper::Version.parseable?(value), "expected #{value.inspect} to be usable"
    end
  end

  # Indexed: `gsub(/\W/, "_")` collides for "8.1.0." / "8.1.0-" / "8.1.0 ",
  # and `define_method` would silently overwrite.
  REJECTED.each_with_index do |value, index|
    define_method(:"test_rejects_#{index}_#{value.empty? ? 'empty_string' : value.gsub(/\W/, '_')}") do
      refute Helper::Version.parseable?(value), "expected #{value.inspect} to be rejected"
    end
  end

  # Guards the generator: value-derived naming or a duplicate entry silently shrinks the table.
  def test_every_table_entry_generates_a_distinct_test
    accepted = self.class.instance_methods.grep(/\Atest_accepts_/)
    rejected = self.class.instance_methods.grep(/\Atest_rejects_\d+_/)

    assert_equal ACCEPTED.size, accepted.size,
                 "ACCEPTED table has #{ACCEPTED.size} entries but generated #{accepted.size} tests"
    assert_equal REJECTED.size, rejected.size,
                 "REJECTED table has #{REJECTED.size} entries but generated #{rejected.size} tests"
  end

  def test_rejects_nil
    refute Helper::Version.parseable?(nil)
  end

  def test_rejects_non_string_types
    [42, 8.1, :'8.1.0', [], {}, true].each do |value|
      refute Helper::Version.parseable?(value), "expected #{value.inspect} to be rejected"
    end
  end

  def test_rejects_a_version_instance
    # Callers screen raw strings from INFO; accepting a Version here would let a
    # pre-wrapped sentinel through the same hole.
    refute Helper::Version.parseable?(Helper::Version.new("8.1.0"))
  end

  def test_nothing_accepted_sorts_at_or_below_the_old_sentinel
    ACCEPTED.each do |value|
      assert Helper::Version.new(value) > Helper::Version.new("0.0"),
             "#{value.inspect} must sort above the old \"0.0\" sentinel"
    end
  end

  # Pins a known quirk: a pre-release compares EQUAL to its GA version.
  def test_prerelease_compares_equal_to_its_ga_version
    assert_equal 0, Helper::Version.new("8.1.0-rc1") <=> Helper::Version.new("8.1.0")
  end
end
