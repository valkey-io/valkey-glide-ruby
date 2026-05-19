# frozen_string_literal: true

require "ffi"
require "json"
require "cgi"

require "valkey/version"
require "valkey/request_type"
require "valkey/response_type"
require "valkey/request_error_type"
require "valkey/bindings"
require "valkey/utils"
require "valkey/commands"
require "valkey/errors"
require "valkey/pubsub_callback"
require "valkey/pipeline"
require "valkey/opentelemetry"

class Valkey
  include Utils
  include Commands
  include PubSubCallback

  def pipelined(exception: true)
    pipeline = Pipeline.new

    yield pipeline

    return [] if pipeline.commands.empty?

    send_batch_commands(pipeline.commands, exception: exception)
  end

  def send_batch_commands(commands, exception: true)
    # WORKAROUND: The underlying Glide FFI backend has stability issues when
    # batching transactional commands like MULTI / EXEC / DISCARD. To avoid
    # native crashes we fall back to issuing those commands sequentially
    # instead of via `Bindings.batch`.
    tx_types = [RequestType::MULTI, RequestType::EXEC, RequestType::DISCARD]

    if commands.any? { |(command_type, _args, _block)| tx_types.include?(command_type) }
      results = []

      commands.each do |command_type, command_args, block|
        res = send_command(command_type, command_args)
        res = block.call(res) if block
        results << res
      end

      return results
    end

    cmds = []
    blocks = []
    buffers = [] # Keep references to prevent GC

    commands.each do |command_type, command_args, block|
      arg_ptrs, arg_lens = build_command_args(command_args)

      cmd = Bindings::CmdInfo.new
      cmd[:request_type] = command_type
      cmd[:args] = arg_ptrs
      cmd[:arg_count] = command_args.size
      cmd[:args_len] = arg_lens

      cmds << cmd
      blocks << block
      buffers << [arg_ptrs, arg_lens] # Prevent GC
    end

    # Create array of pointers to CmdInfo structs
    cmd_ptrs = FFI::MemoryPointer.new(:pointer, cmds.size)
    cmds.each_with_index do |cmd, i|
      cmd_ptrs[i].put_pointer(0, cmd.to_ptr)
    end

    batch_info = Bindings::BatchInfo.new
    batch_info[:cmd_count] = cmds.size
    batch_info[:cmds] = cmd_ptrs
    batch_info[:is_atomic] = false

    batch_options = Bindings::BatchOptionsInfo.new
    batch_options[:retry_server_error] = true
    batch_options[:retry_connection_error] = true
    batch_options[:has_timeout] = false
    batch_options[:timeout] = 0 # No timeout
    batch_options[:route_info] = FFI::Pointer::NULL

    # Create OpenTelemetry span for batch operation if sampling is enabled
    # TODO: add parent span propagation via create_batch_otel_span_with_parent
    # to support distributed tracing context (see Go client base_client.go for reference)
    span_ptr = 0
    if OpenTelemetry.should_sample?
      begin
        span_ptr = Bindings.create_batch_otel_span
      rescue StandardError => e
        warn "Failed to create OpenTelemetry batch span: #{e.message}"
        span_ptr = 0
      end
    end

    begin
      res = Bindings.batch(
        @connection,
        0,
        batch_info,
        exception,
        batch_options.to_ptr,
        span_ptr
      )

      results = convert_response(res)
    ensure
      # Always drop the span if one was created
      if span_ptr != 0
        begin
          Bindings.drop_otel_span(span_ptr)
        rescue StandardError => e
          warn "Failed to drop OpenTelemetry batch span: #{e.message}"
        end
      end
    end

    blocks.each_with_index do |block, i|
      results[i] = block.call(results[i]) if block
    end

    results
  end

  def build_command_args(command_args)
    # For empty arrays, pass NULL pointers as per Rust FFI contract
    # This matches Go's approach which successfully uses nil pointers
    return [FFI::Pointer::NULL, FFI::Pointer::NULL] if command_args.empty?

    arg_ptrs = FFI::MemoryPointer.new(:pointer, command_args.size)
    arg_lens = FFI::MemoryPointer.new(:ulong, command_args.size)
    buffers = []

    command_args.each_with_index do |arg, i|
      arg = arg.to_s # Ensure we convert to string

      buf = FFI::MemoryPointer.from_string(arg.to_s)
      buffers << buf # prevent garbage collection
      arg_ptrs.put_pointer(i * FFI::Pointer.size, buf)
      arg_lens.put_ulong(i * 8, arg.bytesize)
    end

    [arg_ptrs, arg_lens]
  end

  def convert_response(res, &block)
    result = Bindings::CommandResult.new(res)

    if result[:response].null?
      error = result[:command_error]

      case error[:command_error_type]
      when RequestErrorType::EXECABORT, RequestErrorType::UNSPECIFIED
        raise CommandError, error[:command_error_message]
      when RequestErrorType::TIMEOUT
        raise TimeoutError, error[:command_error_message]
      when RequestErrorType::DISCONNECT
        raise ConnectionError, error[:command_error_message]
      else
        raise "Unknown error type: #{error[:command_error_type]}"
      end
    end

    result = result[:response]

    convert_response = lambda { |response_item|
      # TODO: handle all types of responses
      case response_item[:response_type]
      when ResponseType::STRING
        response_item[:string_value].read_string(response_item[:string_value_len])
      when ResponseType::INT
        response_item[:int_value]
      when ResponseType::FLOAT
        response_item[:float_value]
      when ResponseType::BOOL
        response_item[:bool_value]
      when ResponseType::ARRAY
        ptr = response_item[:array_value]
        count = response_item[:array_value_len].to_i
        return [] if count.zero? || ptr.null?

        count.times.map do |i|
          item = Bindings::CommandResponse.new(ptr + (i * Bindings::CommandResponse.size))
          convert_response.call(item)
        end
      when ResponseType::MAP
        return nil if response_item[:array_value].null?

        ptr = response_item[:array_value]
        count = response_item[:array_value_len].to_i
        map = {}

        Array.new(count) do |i|
          item = Bindings::CommandResponse.new(ptr + (i * Bindings::CommandResponse.size))

          map_key = convert_response.call(Bindings::CommandResponse.new(item[:map_key]))
          map_value = convert_response.call(Bindings::CommandResponse.new(item[:map_value]))

          map[map_key] = map_value
        end

        # technically it has to return a Hash, but as of now we return just one pair
        map.to_a.flatten(1) # Flatten to get pairs
      when ResponseType::SETS
        ptr = response_item[:sets_value]
        count = response_item[:sets_value_len].to_i

        Array.new(count) do |i|
          item = Bindings::CommandResponse.new(ptr + (i * Bindings::CommandResponse.size))
          convert_response.call(item)
        end
      when ResponseType::NULL
        nil
      when ResponseType::OK
        "OK"
      when ResponseType::ERROR
        # For errors in arrays (like EXEC responses), return an error object
        # instead of raising. The error message is typically in string_value.
        error_msg = if response_item[:string_value].null?
                      "Unknown error"
                    else
                      response_item[:string_value].read_string(response_item[:string_value_len])
                    end
        CommandError.new(error_msg)
      else
        raise "Unsupported response type: #{response_item[:response_type]}"
      end
    }

    response = convert_response.call(result)

    if block_given?
      block.call(response)
    else
      response
    end
  end

  def send_command(command_type, command_args = [], &block)
    # Validate connection
    if @connection.nil?
      raise "Connection is nil"
    elsif @connection.null?
      raise "Connection pointer is null"
    elsif @connection.address.zero?
      raise "Connection address is 0"
    end

    channel = 0
    route = ""

    route_buf = FFI::MemoryPointer.from_string(route)

    # Handle empty command_args case
    if command_args.empty?
      arg_ptrs = FFI::MemoryPointer.new(:pointer, 1)
      arg_lens = FFI::MemoryPointer.new(:ulong, 1)
      arg_ptrs.put_pointer(0, FFI::MemoryPointer.new(1))
      arg_lens.put_ulong(0, 0)
    else
      arg_ptrs, arg_lens = build_command_args(command_args)
    end

    # Create OpenTelemetry span if sampling is enabled
    # TODO: add parent span propagation via create_otel_span_with_parent
    # to support distributed tracing context (see Go client base_client.go for reference)
    span_ptr = 0
    if OpenTelemetry.should_sample?
      begin
        span_ptr = Bindings.create_otel_span(command_type)
      rescue StandardError => e
        # Log error but continue execution - tracing is non-critical
        warn "Failed to create OpenTelemetry span: #{e.message}"
        span_ptr = 0
      end
    end

    begin
      res = Bindings.command(
        @connection,
        channel,
        command_type,
        command_args.size,
        arg_ptrs,
        arg_lens,
        route_buf,
        route.bytesize,
        span_ptr
      )

      result = convert_response(res, &block)
    ensure
      # Always drop the span if one was created, even if command fails
      if span_ptr != 0
        begin
          Bindings.drop_otel_span(span_ptr)
        rescue StandardError => e
          # Log but don't raise - span cleanup errors shouldn't break command execution
          warn "Failed to drop OpenTelemetry span: #{e.message}"
        end
      end
    end

    # Track queued commands during MULTI (except for MULTI, EXEC, DISCARD, WATCH, UNWATCH)
    if @in_multi && !@queued_commands.nil?
      tx_commands = [
        RequestType::MULTI, RequestType::EXEC, RequestType::DISCARD,
        RequestType::WATCH, RequestType::UNWATCH
      ]
      @queued_commands << [command_type, command_args.dup] if !tx_commands.include?(command_type) && result == "QUEUED"
    end

    result
  end

  def initialize(options = {})
    # Parse URL if provided
    if options[:url]
      url_options = Utils.parse_redis_url(options[:url])
      # Merge URL options, but explicit options take precedence
      options = url_options.merge(options.reject { |k, _v| k == :url })
    end

    # Extract connection parameters
    host = options[:host] || "127.0.0.1"
    port = options[:port] || 6379
    database_id = options[:db] || 0

    # Validate database ID
    raise ArgumentError, "Database ID must be non-negative, got: #{database_id}" if database_id.negative?

    nodes = options[:nodes] || [{ host: host, port: port }]

    # Validate nodes array
    raise ArgumentError, "Nodes array cannot be empty" if nodes.empty?

    # Build URI string
    # Use the first node for standalone mode, or first node for cluster discovery
    first_node = nodes.first
    raise ArgumentError, "First node cannot be nil" if first_node.nil?

    uri_host = first_node[:host]
    uri_port = first_node[:port]

    # Validate host and port
    raise ArgumentError, "Host cannot be nil" if uri_host.nil?
    raise ArgumentError, "Port cannot be nil" if uri_port.nil?
    raise ArgumentError, "Port must be a number" unless uri_port.is_a?(Integer)

    # Determine scheme based on TLS/SSL
    scheme = [true, "true"].include?(options[:ssl]) ? "rediss" : "redis"

    # Build URI with authentication if provided
    uri_parts = [scheme, "://"]

    # Add authentication to URI
    if options[:username] && options[:password]
      uri_parts << CGI.escape(options[:username])
      uri_parts << ":"
      uri_parts << CGI.escape(options[:password])
      uri_parts << "@"
    elsif options[:password]
      uri_parts << ":"
      uri_parts << CGI.escape(options[:password])
      uri_parts << "@"
    end

    uri_parts << uri_host
    uri_parts << ":"
    uri_parts << uri_port.to_s

    # Add database ID to URI if specified
    uri_parts << "/" << database_id.to_s if database_id.positive?

    uri_str = uri_parts.join

    # Build JSON options for additional configuration
    json_options = {}

    # Cluster mode
    json_options["cluster_mode_enabled"] = true if options[:cluster_mode]

    # Protocol
    json_options["protocol"] = case options[:protocol]
                               when :resp3, "resp3", 3
                                 "RESP3"
                               else
                                 "RESP2"
                               end

    # Timeouts
    request_timeout = options[:timeout] || 5.0

    # Validate timeout types
    raise ArgumentError, "Timeout must be a number, got: #{request_timeout.class}" unless request_timeout.is_a?(Numeric)
    raise ArgumentError, "Timeout must be positive, got: #{request_timeout}" if request_timeout <= 0

    json_options["request_timeout"] = (request_timeout * 1000).to_i

    if options[:connect_timeout]
      connect_timeout = options[:connect_timeout]
      unless connect_timeout.is_a?(Numeric)
        raise ArgumentError, "Connect timeout must be a number, got: #{connect_timeout.class}"
      end
      raise ArgumentError, "Connect timeout must be positive, got: #{connect_timeout}" if connect_timeout <= 0

      json_options["connection_timeout"] = (connect_timeout * 1000).to_i
    end

    # Client name
    json_options["client_name"] = options[:client_name] if options[:client_name]

    # TLS/SSL certificates
    root_certs = []
    if options[:ssl_params].is_a?(Hash)
      # ca_file - read CA certificate file (PEM or DER format)
      if options[:ssl_params][:ca_file]
        ca_file = options[:ssl_params][:ca_file]
        raise ArgumentError, "CA file does not exist: #{ca_file}" unless File.exist?(ca_file)
        raise ArgumentError, "CA file is not readable: #{ca_file}" unless File.readable?(ca_file)

        root_certs << File.binread(ca_file)
      end

      # cert - client certificate (file path or OpenSSL::X509::Certificate)
      if options[:ssl_params][:cert]
        cert_data = if options[:ssl_params][:cert].is_a?(String)
                      cert_file = options[:ssl_params][:cert]
                      raise ArgumentError, "Cert file does not exist: #{cert_file}" unless File.exist?(cert_file)
                      raise ArgumentError, "Cert file is not readable: #{cert_file}" unless File.readable?(cert_file)

                      File.binread(cert_file)
                    elsif options[:ssl_params][:cert].respond_to?(:to_pem)
                      options[:ssl_params][:cert].to_pem
                    elsif options[:ssl_params][:cert].respond_to?(:to_der)
                      options[:ssl_params][:cert].to_der
                    else
                      options[:ssl_params][:cert].to_s
                    end
        root_certs << cert_data
      end

      # key - client key (file path or OpenSSL::PKey)
      if options[:ssl_params][:key]
        key_data = if options[:ssl_params][:key].is_a?(String)
                     key_file = options[:ssl_params][:key]
                     raise ArgumentError, "Key file does not exist: #{key_file}" unless File.exist?(key_file)
                     raise ArgumentError, "Key file is not readable: #{key_file}" unless File.readable?(key_file)

                     File.binread(key_file)
                   elsif options[:ssl_params][:key].respond_to?(:to_pem)
                     options[:ssl_params][:key].to_pem
                   elsif options[:ssl_params][:key].respond_to?(:to_der)
                     options[:ssl_params][:key].to_der
                   else
                     options[:ssl_params][:key].to_s
                   end
        root_certs << key_data
      end

      # Additional root certificates from ca_path
      if options[:ssl_params][:ca_path]
        ca_path = options[:ssl_params][:ca_path]
        raise ArgumentError, "CA path does not exist: #{ca_path}" unless Dir.exist?(ca_path)

        Dir.glob(File.join(ca_path, "*.crt")).each do |cert_file|
          root_certs << File.binread(cert_file) if File.readable?(cert_file)
        end
        Dir.glob(File.join(ca_path, "*.pem")).each do |cert_file|
          root_certs << File.binread(cert_file) if File.readable?(cert_file)
        end
      end

      # Direct root_certs array support
      root_certs.concat(options[:ssl_params][:root_certs]) if options[:ssl_params][:root_certs].is_a?(Array)
    end

    json_options["root_certs"] = root_certs unless root_certs.empty?

    # Connection retry strategy
    if options[:reconnect_attempts] || options[:reconnect_delay] || options[:reconnect_delay_max]
      number_of_retries = options[:reconnect_attempts] || 1
      base_delay = options[:reconnect_delay] || 0.5
      max_delay = options[:reconnect_delay_max]

      # Validate reconnection parameters
      unless number_of_retries.is_a?(Integer)
        raise ArgumentError, "Reconnect attempts must be an integer, got: #{number_of_retries.class}"
      end

      if number_of_retries.negative?
        raise ArgumentError,
              "Reconnect attempts must be non-negative, got: #{number_of_retries}"
      end

      raise ArgumentError, "Reconnect delay must be a number, got: #{base_delay.class}" unless base_delay.is_a?(Numeric)
      raise ArgumentError, "Reconnect delay must be positive, got: #{base_delay}" unless base_delay.positive?

      if max_delay
        unless max_delay.is_a?(Numeric)
          raise ArgumentError, "Reconnect delay max must be a number, got: #{max_delay.class}"
        end
        raise ArgumentError, "Reconnect delay max must be positive, got: #{max_delay}" unless max_delay.positive?
      end

      exponent_base = 2

      if max_delay && base_delay.positive? && number_of_retries.positive?
        calculated_base = (max_delay / base_delay)**(1.0 / number_of_retries.to_f)
        exponent_base = [calculated_base.round, 2].max
      end

      factor_ms = (base_delay * 1000).to_i

      json_options["connection_retry_strategy"] = {
        "number_of_retries" => number_of_retries,
        "factor" => factor_ms,
        "exponent_base" => exponent_base,
        "jitter_percent" => 0
      }
    end

    # Convert JSON options to string (pass nil if empty)
    json_str = json_options.empty? ? nil : JSON.generate(json_options)

    # Create client using URI-based FFI function
    client_type = Bindings::ClientType.new
    client_type[:tag] = 1 # SyncClient

    response_ptr = Bindings.create_client_from_uri(
      uri_str,
      json_str,
      client_type,
      method(:pubsub_callback)
    )

    res = Bindings::ConnectionResponse.new(response_ptr)

    if res[:conn_ptr].null?
      error_message = res[:connection_error_message]
      Bindings.free_connection_response(response_ptr)
      raise CannotConnectError, error_message
    end

    @connection = res[:conn_ptr]
    Bindings.free_connection_response(response_ptr)

    # Track transactional state for `MULTI` / `EXEC` / `DISCARD` helpers.
    # This avoids Ruby warnings about uninitialised instance variables and
    # gives us a single source of truth for whether we're inside a TX.
    @in_multi = false
    # Track queued commands during MULTI for transaction isolation support
    @queued_commands = []
    # Track if we're inside a multi block (multi { ... }) vs direct multi calls
    @in_multi_block = false
  end

  def close
    return if @connection.nil? || @connection.null?

    Bindings.close_client(@connection)
    @connection = nil
  end

  alias disconnect! close

  # Retrieves client statistics including connection and compression metrics.
  #
  # This method returns detailed statistics about the client's operations,
  # tracked globally across all clients in the process.
  #
  # @return [Hash] a hash containing statistics with the following keys:
  #   - `:total_connections` [Integer] total number of connections opened to Valkey
  #   - `:total_clients` [Integer] total number of GLIDE clients
  #   - `:total_values_compressed` [Integer] total number of values compressed
  #   - `:total_values_decompressed` [Integer] total number of values decompressed
  #   - `:total_original_bytes` [Integer] total original bytes before compression
  #   - `:total_bytes_compressed` [Integer] total bytes after compression
  #   - `:total_bytes_decompressed` [Integer] total bytes after decompression
  #   - `:compression_skipped_count` [Integer] number of times compression was skipped
  #
  # @example Get client statistics
  #   client = Valkey.new(host: 'localhost', port: 6379)
  #   stats = client.statistics
  #   puts "Total connections: #{stats[:total_connections]}"
  #   puts "Total clients: #{stats[:total_clients]}"
  #   puts "Values compressed: #{stats[:total_values_compressed]}"
  #
  # @note Statistics are tracked globally and shared across all clients
  #
  # @return [Hash] statistics hash with integer values
  def statistics
    # Call FFI function to get statistics (returns by value)
    stats = Bindings.get_statistics

    # Convert to Ruby hash
    {
      total_connections: stats[:total_connections],
      total_clients: stats[:total_clients],
      total_values_compressed: stats[:total_values_compressed],
      total_values_decompressed: stats[:total_values_decompressed],
      total_original_bytes: stats[:total_original_bytes],
      total_bytes_compressed: stats[:total_bytes_compressed],
      total_bytes_decompressed: stats[:total_bytes_decompressed],
      compression_skipped_count: stats[:compression_skipped_count]
    }
  end
end
