# frozen_string_literal: true

require "test_helper"

# Covers the FFI argument buffers built by Valkey#build_command_args, in
# particular that arg_lens is indexed by the platform's ulong width.
class TestBuildCommandArgs < Minitest::Test
  # Stands in for the arg_lens buffer so offsets can be checked against a
  # simulated ulong width that differs from the host's.
  class RecordingLengthBuffer
    attr_reader :writes

    def initialize
      @writes = []
    end

    def put_ulong(offset, value)
      @writes << [offset, value]
    end
  end

  def setup
    @client = Valkey.allocate
  end

  def test_lengths_are_written_at_ulong_stride
    args = ["a", "bb", "héllo", 42, :sym]
    _ptrs, lens, _buffers, flattened = build(args)
    ulong_size = FFI.type_size(:ulong)

    assert_equal args.size * ulong_size, lens.size
    flattened.each_with_index do |arg, index|
      assert_equal arg.to_s.bytesize, lens.get_ulong(index * ulong_size)
    end
  end

  def test_pointers_reference_argument_bytes
    args = %w[SET key value]
    ptrs, _lens, _buffers, _flattened = build(args)

    args.each_with_index do |arg, index|
      assert_equal arg, ptrs.get_pointer(index * FFI::Pointer.size).read_string(arg.bytesize)
    end
  end

  def test_lengths_stay_in_bounds_with_four_byte_ulong
    simulated_ulong_size = 4
    args = %w[one two three four]

    writes = with_simulated_ulong_size(simulated_ulong_size) { build(args)[1].writes }

    expected_offsets = Array.new(args.size) { |index| index * simulated_ulong_size }
    assert_equal expected_offsets, writes.map(&:first)
    assert_equal args.map(&:bytesize), writes.map(&:last)
    assert(writes.all? { |offset, _| offset + simulated_ulong_size <= args.size * simulated_ulong_size })
  end

  def test_empty_args_return_null_pointers
    ptrs, lens, buffers, flattened = build([])

    assert_predicate ptrs, :null?
    assert_predicate lens, :null?
    assert_empty buffers
    assert_empty flattened
  end

  def test_nested_args_are_flattened_before_lengths_are_written
    _ptrs, lens, _buffers, flattened = build(["key", %w[field value], { "other" => "x" }])
    ulong_size = FFI.type_size(:ulong)

    assert_equal %w[key field value other x], flattened
    assert_equal flattened.size * ulong_size, lens.size
    assert_equal 1, lens.get_ulong((flattened.size - 1) * ulong_size)
  end

  def test_unsupported_argument_type_raises
    assert_raises(TypeError) { build(["key", nil]) }
  end

  private

  def build(args)
    @client.send(:build_command_args, args)
  end

  def with_simulated_ulong_size(simulated_size, &block)
    recorder = RecordingLengthBuffer.new
    original_type_size = FFI.method(:type_size)
    original_new = FFI::MemoryPointer.method(:new)
    simulated_type_size = ->(type) { type == :ulong ? simulated_size : original_type_size.call(type) }
    simulated_new = ->(type, *rest) { type == :ulong ? recorder : original_new.call(type, *rest) }

    FFI.stub(:type_size, simulated_type_size) do
      FFI::MemoryPointer.stub(:new, simulated_new, &block)
    end
  end
end
