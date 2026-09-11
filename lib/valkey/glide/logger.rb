# frozen_string_literal: true

class Valkey
  # Logging that goes through the logger built into the Valkey GLIDE core, so that
  # application logs and the driver's own internal logs land in the same place, in the
  # same format, under the same level filter.
  #
  # The logger is process-wide and can be configured in two ways:
  #
  # 1. {init} configures it only if it has not been configured yet.
  # 2. {set_logger_config} always replaces the current configuration, which means new
  #    logs are no longer written alongside the logs emitted before the call.
  #
  # If neither is called, the first {log} call configures a logger with the GLIDE core
  # defaults (level `:warn`, console output).
  #
  # @example Log to the console at :info and above
  #   Valkey::Logger.init(level: :info)
  #   Valkey::Logger.log(:info, "MyApp", "connected to Valkey")
  #
  # @example Log to hourly-rotated files instead of the console
  #   Valkey::Logger.init(level: :debug, file_name: "my_app.log")
  #
  # @example Attach an exception to a message
  #   Valkey::Logger.log(:error, "MyApp", "write failed", error: caught_exception)
  #
  # @example Turn logging off completely
  #   Valkey::Logger.set_logger_config(level: :off)
  module Logger
    # Severity levels, ordered from most to least severe. The integer values mirror
    # glide-core's `Level` enum.
    LEVELS = {
      error: 0,
      warn: 1,
      info: 2,
      debug: 3,
      trace: 4,
      off: 5
    }.freeze

    # The level the GLIDE core falls back to when none is given.
    DEFAULT_LEVEL = :warn

    @configured = false
    @logger_level = DEFAULT_LEVEL
    @mutex = Mutex.new

    class << self
      # The level the logger is currently filtering at. Messages less severe than this
      # are dropped before they reach the native layer.
      #
      # @return [Symbol] one of the keys of {LEVELS}
      attr_reader :logger_level

      # Configure the logger if it has not been configured yet. Use this when there is no
      # intention of replacing an existing configuration; use {set_logger_config} to
      # override one.
      #
      # @param level [Symbol, String, nil] one of `:error`, `:warn`, `:info`, `:debug`,
      #   `:trace`, `:off`. When nil, the GLIDE core default ({DEFAULT_LEVEL}) is used.
      #   Pass `:off` to disable logging completely.
      # @param file_name [String, nil] when given, logs are written to hourly-rotated
      #   files postfixed with this name. When nil, logs are written to the console.
      #
      # @raise [ArgumentError] if level is not a known level, or file_name is not a
      #   non-empty String
      # @raise [Valkey::LoggerError] if the native logger could not be initialized
      #
      # @return [void]
      def init(level: nil, file_name: nil)
        @mutex.synchronize { configure(level, file_name) unless @configured }
      end

      # Replace the current logger configuration. Logs emitted after this call are not
      # written alongside the logs emitted before it.
      #
      # @param level [Symbol, String, nil] see {init}
      # @param file_name [String, nil] see {init}
      #
      # @raise [ArgumentError] if level is not a known level, or file_name is not a
      #   non-empty String
      # @raise [Valkey::LoggerError] if the native logger could not be initialized
      #
      # @return [void]
      def set_logger_config(level: nil, file_name: nil)
        @mutex.synchronize { configure(level, file_name) }
      end

      # Whether the logger has been configured, either explicitly through {init} /
      # {set_logger_config} or implicitly by the first {log} call.
      #
      # @return [Boolean]
      def configured?
        @configured
      end

      # Log a message, unless the current logger level filters it out. Configures the
      # logger with the GLIDE core defaults first if it has not been configured yet.
      #
      # A message that the native layer rejects (for instance, one that is not valid
      # UTF-8) is reported on stderr rather than raised: a failed log must never break
      # the code path that emitted it.
      #
      # @param level [Symbol, String] the severity of this message, see {init}
      # @param identifier [String] gives the message its context, such as the emitting
      #   component
      # @param message [String] the message to log
      # @param error [Exception, nil] an exception to append to the message, with its
      #   backtrace when it has one
      #
      # @raise [ArgumentError] if level is not a known level
      #
      # @return [void]
      def log(level, identifier, message, error: nil)
        level = normalize_level(level)
        init unless @configured
        return unless enabled?(level)

        message = "#{message}: #{format_error(error)}" if error
        send_log(level, identifier.to_s, message.to_s)
      end

      # Whether a message of the given level would currently be logged. Useful to skip
      # building an expensive message that would be dropped anyway.
      #
      # @param level [Symbol, String] see {init}
      #
      # @raise [ArgumentError] if level is not a known level
      #
      # @return [Boolean]
      def enabled?(level)
        level = normalize_level(level)
        # `:off` sorts below every real level, so comparing against it would let
        # everything through. Treat it as "nothing is enabled" instead.
        return false if @logger_level == :off

        LEVELS.fetch(level) <= LEVELS.fetch(@logger_level)
      end

      # Forget the configuration recorded on the Ruby side, so the next {log} or {init}
      # reconfigures the native logger. Does not reset the native logger itself.
      #
      # @api private
      def reset!
        @configured = false
        @logger_level = DEFAULT_LEVEL
      end

      private

      def configure(level, file_name)
        validate_file_name!(file_name)
        level_pointer = build_level_pointer(level)

        result_pointer = Bindings.logger_init(level_pointer, file_name)
        raise LoggerError, "Logger initialization returned a null pointer" if result_pointer.null?

        @logger_level = consume_init_result(result_pointer)
        @configured = true
      end

      def consume_init_result(result_pointer)
        result = Bindings::LogResult.new(result_pointer)
        error_message = read_log_error(result)
        raise LoggerError, "Logger initialization failed: #{error_message}" if error_message

        result[:level]
      ensure
        Bindings.free_log_result(result_pointer)
      end

      def send_log(level, identifier, message)
        result_pointer = Bindings.glide_log(level, identifier, message)
        if result_pointer.null?
          warn "Valkey::Logger: glide_log returned a null pointer"
          return
        end

        error_message = read_log_error(Bindings::LogResult.new(result_pointer))
        warn "Valkey::Logger: failed to log message: #{error_message}" if error_message
      ensure
        Bindings.free_log_result(result_pointer) if result_pointer && !result_pointer.null?
      end

      def read_log_error(result)
        error_pointer = result[:log_error]
        return nil if error_pointer.null?

        error_pointer.read_string
      end

      def build_level_pointer(level)
        return nil if level.nil?

        pointer = FFI::MemoryPointer.new(:int, 1)
        pointer.write_int(LEVELS.fetch(normalize_level(level)))
        pointer
      end

      def normalize_level(level)
        symbol = level.to_s.downcase.to_sym
        return symbol if LEVELS.key?(symbol)

        raise ArgumentError, "unknown log level: #{level.inspect} (expected one of #{LEVELS.keys.join(', ')})"
      end

      def validate_file_name!(file_name)
        return if file_name.nil?
        return if file_name.is_a?(String) && !file_name.empty?

        raise ArgumentError, "file_name must be a non-empty String or nil, got: #{file_name.inspect}"
      end

      def format_error(error)
        return error.to_s unless error.is_a?(Exception)

        backtrace = error.backtrace
        return "#{error.class}: #{error.message}" if backtrace.nil? || backtrace.empty?

        "#{error.class}: #{error.message}\n#{backtrace.join("\n")}"
      end
    end
  end
end
