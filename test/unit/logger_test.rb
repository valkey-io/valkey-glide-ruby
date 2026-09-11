# frozen_string_literal: true

# Unit tests for Valkey::Logger: level filtering, argument handling, and the LogResult
# error/null-pointer paths, including that every result is freed exactly once.
#
# The native logger is process-wide, so almost every test here stubs Bindings and hands
# back a LogResult it allocated itself. Bindings.free_log_result is stubbed alongside it,
# because the real one would hand a Ruby-allocated pointer to Rust's deallocator.
# TestLogger#test_native_logger_round_trip is the one test that calls the real bindings.

require "test_helper"

class TestLogger < Minitest::Test
  def setup
    super if defined?(super)
    @allocations = []
    @freed = []
    Valkey::Logger.reset!
  end

  def teardown
    Valkey::Logger.reset!
    @allocations.clear
    super if defined?(super)
  end

  def test_levels_are_ordered_from_most_to_least_severe
    assert_equal %i[error warn info debug trace off], Valkey::Logger::LEVELS.keys
    assert_equal [0, 1, 2, 3, 4, 5], Valkey::Logger::LEVELS.values
  end

  def test_default_level_before_configuration
    assert_equal :warn, Valkey::Logger.logger_level
    refute_predicate Valkey::Logger, :configured?
  end

  def test_init_records_the_level_the_native_logger_settled_on
    stub_bindings(logger_init: ->(*) { fake_log_result(level: :info) }) do
      Valkey::Logger.init(level: :info)
    end

    assert_equal :info, Valkey::Logger.logger_level
    assert_predicate Valkey::Logger, :configured?
    assert_equal 1, @freed.size
  end

  def test_init_without_a_level_passes_a_null_pointer
    calls = []

    stub_bindings(logger_init: recorder(calls) { fake_log_result(level: :warn) }) do
      Valkey::Logger.init
    end

    level_pointer, file_name = calls.fetch(0)

    assert_nil level_pointer
    assert_nil file_name
  end

  def test_init_passes_the_level_as_an_integer_pointer
    calls = []

    stub_bindings(logger_init: recorder(calls) { fake_log_result(level: :debug) }) do
      Valkey::Logger.init(level: :debug)
    end

    assert_equal 3, calls.fetch(0).fetch(0).read_int
  end

  def test_init_forwards_the_file_name
    calls = []

    stub_bindings(logger_init: recorder(calls) { fake_log_result(level: :warn) }) do
      Valkey::Logger.init(file_name: "my_app.log")
    end

    assert_equal "my_app.log", calls.fetch(0).fetch(1)
  end

  def test_init_accepts_a_level_given_as_a_string
    calls = []

    stub_bindings(logger_init: recorder(calls) { fake_log_result(level: :trace) }) do
      Valkey::Logger.init(level: "TRACE")
    end

    assert_equal 4, calls.fetch(0).fetch(0).read_int
  end

  def test_init_is_a_no_op_once_configured
    calls = []

    stub_bindings(logger_init: recorder(calls) { fake_log_result(level: :info) }) do
      Valkey::Logger.init(level: :info)
      Valkey::Logger.init(level: :trace)
    end

    assert_equal 1, calls.size
    assert_equal :info, Valkey::Logger.logger_level
  end

  def test_set_logger_config_reconfigures_an_already_configured_logger
    calls = []
    levels = %i[info trace]

    stub_bindings(logger_init: recorder(calls) { fake_log_result(level: levels.shift) }) do
      Valkey::Logger.init(level: :info)
      Valkey::Logger.set_logger_config(level: :trace)
    end

    assert_equal 2, calls.size
    assert_equal :trace, Valkey::Logger.logger_level
  end

  def test_init_raises_on_a_log_error_and_frees_the_result
    pointer = nil

    error = assert_raises Valkey::LoggerError do
      stub_bindings(logger_init: ->(*) { pointer = fake_log_result(error_message: "bad file name") }) do
        Valkey::Logger.init(file_name: "unwritable.log")
      end
    end

    assert_match(/Logger initialization failed: bad file name/, error.message)
    assert_equal [pointer], @freed
    refute_predicate Valkey::Logger, :configured?
  end

  def test_init_raises_on_a_null_result_pointer
    error = assert_raises Valkey::LoggerError do
      stub_bindings(logger_init: ->(*) { FFI::Pointer::NULL }) do
        Valkey::Logger.init
      end
    end

    assert_match(/null pointer/, error.message)
    assert_empty @freed
    refute_predicate Valkey::Logger, :configured?
  end

  def test_init_rejects_an_unknown_level
    error = assert_raises(ArgumentError) { Valkey::Logger.init(level: :verbose) }

    assert_match(/unknown log level: :verbose/, error.message)
    refute_predicate Valkey::Logger, :configured?
  end

  def test_init_rejects_an_empty_file_name
    assert_raises(ArgumentError) { Valkey::Logger.init(file_name: "") }
  end

  def test_init_rejects_a_non_string_file_name
    assert_raises(ArgumentError) { Valkey::Logger.init(file_name: :my_app) }
  end

  def test_log_configures_the_logger_on_first_use
    init_calls = []
    log_calls = []

    stub_bindings(
      logger_init: recorder(init_calls) { fake_log_result(level: :warn) },
      glide_log: recorder(log_calls) { fake_log_result }
    ) do
      Valkey::Logger.log(:warn, "MyApp", "first message")
    end

    assert_equal 1, init_calls.size
    assert_equal 1, log_calls.size
  end

  def test_log_forwards_the_level_identifier_and_message
    log_calls = configured_at(:info) do
      Valkey::Logger.log(:error, "MyApp", "something broke")
    end

    assert_equal [:error, "MyApp", "something broke"], log_calls.fetch(0)
  end

  def test_log_coerces_the_identifier_and_message_to_strings
    log_calls = configured_at(:info) do
      Valkey::Logger.log(:info, :MyApp, 42)
    end

    assert_equal [:info, "MyApp", "42"], log_calls.fetch(0)
  end

  def test_log_drops_messages_less_severe_than_the_current_level
    log_calls = configured_at(:warn) do
      Valkey::Logger.log(:info, "MyApp", "chatty")
      Valkey::Logger.log(:debug, "MyApp", "chattier")
    end

    assert_empty log_calls
  end

  def test_log_keeps_messages_at_or_above_the_current_level
    log_calls = configured_at(:warn) do
      Valkey::Logger.log(:warn, "MyApp", "at the level")
      Valkey::Logger.log(:error, "MyApp", "above the level")
    end

    assert_equal %i[warn error], log_calls.map(&:first)
  end

  def test_off_drops_every_level
    log_calls = configured_at(:off) do
      Valkey::Logger::LEVELS.each_key { |level| Valkey::Logger.log(level, "MyApp", "quiet") }
    end

    assert_empty log_calls
  end

  def test_trace_keeps_every_level
    log_calls = configured_at(:trace) do
      Valkey::Logger.log(:trace, "MyApp", "noisy")
      Valkey::Logger.log(:error, "MyApp", "noisy")
    end

    assert_equal 2, log_calls.size
  end

  def test_enabled_reflects_the_current_level
    stub_bindings(logger_init: ->(*) { fake_log_result(level: :info) }) { Valkey::Logger.init(level: :info) }

    assert Valkey::Logger.enabled?(:error)
    assert Valkey::Logger.enabled?(:info)
    refute Valkey::Logger.enabled?(:debug)
  end

  def test_enabled_is_false_for_every_level_when_off
    stub_bindings(logger_init: ->(*) { fake_log_result(level: :off) }) { Valkey::Logger.init(level: :off) }

    Valkey::Logger::LEVELS.each_key { |level| refute Valkey::Logger.enabled?(level), "#{level} should be disabled" }
  end

  def test_enabled_rejects_an_unknown_level
    assert_raises(ArgumentError) { Valkey::Logger.enabled?(:verbose) }
  end

  def test_log_rejects_an_unknown_level
    log_calls = configured_at(:trace) do
      assert_raises(ArgumentError) { Valkey::Logger.log(:verbose, "MyApp", "message") }
    end

    assert_empty log_calls
  end

  def test_log_appends_an_exception_with_its_backtrace
    caught = begin
      raise "kaboom"
    rescue RuntimeError => e
      e
    end

    log_calls = configured_at(:trace) do
      Valkey::Logger.log(:error, "MyApp", "write failed", error: caught)
    end

    message = log_calls.fetch(0).fetch(2)

    assert_match(/\Awrite failed: RuntimeError: kaboom\n/, message)
    assert_match(/logger_test\.rb/, message)
  end

  def test_log_appends_an_exception_without_a_backtrace
    log_calls = configured_at(:trace) do
      Valkey::Logger.log(:error, "MyApp", "write failed", error: RuntimeError.new("kaboom"))
    end

    assert_equal "write failed: RuntimeError: kaboom", log_calls.fetch(0).fetch(2)
  end

  def test_log_appends_a_non_exception_error_value
    log_calls = configured_at(:trace) do
      Valkey::Logger.log(:error, "MyApp", "write failed", error: "kaboom")
    end

    assert_equal "write failed: kaboom", log_calls.fetch(0).fetch(2)
  end

  def test_log_frees_the_result_on_success
    pointer = nil

    stub_bindings(
      logger_init: ->(*) { fake_log_result(level: :trace) },
      glide_log: ->(*) { pointer = fake_log_result }
    ) do
      Valkey::Logger.init(level: :trace)
      @freed.clear
      Valkey::Logger.log(:error, "MyApp", "message")
    end

    assert_equal [pointer], @freed
  end

  def test_log_reports_a_log_error_without_raising_and_frees_the_result
    pointer = nil

    _out, err = capture_io do
      stub_bindings(
        logger_init: ->(*) { fake_log_result(level: :trace) },
        glide_log: ->(*) { pointer = fake_log_result(error_message: "message contains invalid UTF-8") }
      ) do
        Valkey::Logger.init(level: :trace)
        @freed.clear
        Valkey::Logger.log(:error, "MyApp", "message")
      end
    end

    assert_match(/failed to log message: message contains invalid UTF-8/, err)
    assert_equal [pointer], @freed
  end

  def test_log_reports_a_null_result_pointer_without_raising
    _out, err = capture_io do
      stub_bindings(
        logger_init: ->(*) { fake_log_result(level: :trace) },
        glide_log: ->(*) { FFI::Pointer::NULL }
      ) do
        Valkey::Logger.init(level: :trace)
        @freed.clear
        Valkey::Logger.log(:error, "MyApp", "message")
      end
    end

    assert_match(/null pointer/, err)
    assert_empty @freed
  end

  # Exercises the real bindings against the real glide-core logger to verify the struct
  # layout, the enum encoding, and that both calls return a freeable result. Configures
  # the process-wide logger to :off so it stays quiet for the rest of the suite.
  def test_native_logger_round_trip
    Valkey::Logger.set_logger_config(level: :off)

    assert_equal :off, Valkey::Logger.logger_level

    result_pointer = Valkey::Bindings.glide_log(:error, "TestLogger", "round trip")

    refute_predicate result_pointer, :null?
    assert_predicate Valkey::Bindings::LogResult.new(result_pointer)[:log_error], :null?
  ensure
    Valkey::Bindings.free_log_result(result_pointer) if result_pointer
  end

  private

  # Allocates a LogResult that mimics what the native layer returns. Ruby owns this
  # memory, so tests that use it must also stub Bindings.free_log_result.
  def fake_log_result(error_message: nil, level: :off)
    pointer = FFI::MemoryPointer.new(Valkey::Bindings::LogResult.size)
    result = Valkey::Bindings::LogResult.new(pointer)
    error_pointer = error_message ? FFI::MemoryPointer.from_string(error_message) : FFI::Pointer::NULL
    result[:log_error] = error_pointer
    result[:level] = level
    @allocations.push(pointer, error_pointer)
    pointer
  end

  # A stub that records the arguments it was called with, then returns the block's value.
  def recorder(calls, &result)
    lambda do |*args|
      calls << args
      result.call
    end
  end

  # Applies the given Bindings stubs, plus a free_log_result stub that records what was
  # freed, then yields. Recursive so that adding a stub does not add a level of nesting.
  def stub_bindings(stubs, &block)
    all_stubs = stubs.merge(free_log_result: ->(pointer) { @freed << pointer })
    apply_stubs(all_stubs.to_a, &block)
  end

  def apply_stubs(stubs, &block)
    return block.call if stubs.empty?

    name, value = stubs.first
    Valkey::Bindings.stub(name, value) { apply_stubs(stubs.drop(1), &block) }
  end

  # Configures the logger at the given level with stubbed bindings, yields, and returns
  # the arguments of every glide_log call made inside the block.
  def configured_at(level)
    log_calls = []
    stub_bindings(
      logger_init: ->(*) { fake_log_result(level: level) },
      glide_log: recorder(log_calls) { fake_log_result }
    ) do
      Valkey::Logger.init(level: level)
      yield
    end
    log_calls
  end
end
