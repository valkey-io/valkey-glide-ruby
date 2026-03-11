# frozen_string_literal: true

require "ffi"
require "google/protobuf"

require "valkey/version"
require "valkey/request_type"
require "valkey/response_type"
require "valkey/request_error_type"
require "valkey/protobuf/command_request_pb"
require "valkey/protobuf/connection_request_pb"
require "valkey/protobuf/response_pb"
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

        Array.new(count) do |i|
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

    nodes = options[:nodes] || [{ host: host, port: port }]

    cluster_mode_enabled = options[:cluster_mode] || false

    # Protocol defaults to RESP2
    protocol = case options[:protocol]
               when :resp3, "resp3", 3
                 ConnectionRequest::ProtocolVersion::RESP3
               else
                 ConnectionRequest::ProtocolVersion::RESP2
               end

    # TLS/SSL support
    tls_mode = if [true, "true"].include?(options[:ssl])
                 ConnectionRequest::TlsMode::SecureTls
               else
                 ConnectionRequest::TlsMode::NoTls
               end

    # SSL parameters - map ssl_params to protobuf root_certs
    root_certs = []
    if options[:ssl_params].is_a?(Hash)
      # ca_file - read CA certificate file (PEM or DER format)
      root_certs << File.binread(options[:ssl_params][:ca_file]) if options[:ssl_params][:ca_file]

      # cert - client certificate (file path or OpenSSL::X509::Certificate)
      if options[:ssl_params][:cert]
        cert_data = if options[:ssl_params][:cert].is_a?(String)
                      File.binread(options[:ssl_params][:cert])
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
                     File.binread(options[:ssl_params][:key])
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
        Dir.glob(File.join(options[:ssl_params][:ca_path], "*.crt")).each do |cert_file|
          root_certs << File.binread(cert_file)
        end
        Dir.glob(File.join(options[:ssl_params][:ca_path], "*.pem")).each do |cert_file|
          root_certs << File.binread(cert_file)
        end
      end

      # Direct root_certs array support
      root_certs.concat(options[:ssl_params][:root_certs]) if options[:ssl_params][:root_certs].is_a?(Array)
    end

    # Authentication support
    authentication_info = nil
    if options[:password] || options[:username]
      authentication_info = ConnectionRequest::AuthenticationInfo.new(
        password: options[:password] || "",
        username: options[:username] || ""
      )
    end

    # Database selection
    database_id = options[:db] || 0

    # Client name
    client_name = options[:client_name] || ""

    # Timeout handling
    # :timeout sets the request timeout (for command execution)
    # :connect_timeout sets the connection establishment timeout
    # Default request timeout is 5.0 seconds
    request_timeout = options[:timeout] || 5.0

    # Connection timeout (milliseconds) - defaults to 0 (uses system default)
    connection_timeout_ms = if options[:connect_timeout]
                              (options[:connect_timeout] * 1000).to_i
                            else
                              0
                            end

    # Connection retry strategy
    connection_retry_strategy = nil
    if options[:reconnect_attempts] || options[:reconnect_delay] || options[:reconnect_delay_max]
      number_of_retries = options[:reconnect_attempts] || 1
      base_delay = options[:reconnect_delay] || 0.5
      max_delay = options[:reconnect_delay_max]
      exponent_base = 2
      jitter_percent = 0

      if max_delay && base_delay.positive? && number_of_retries.positive?
        calculated_base = (max_delay / base_delay)**(1.0 / number_of_retries.to_f)
        exponent_base = [calculated_base.round, 2].max
      end

      factor_ms = (base_delay * 1000).to_i

      connection_retry_strategy = ConnectionRequest::ConnectionRetryStrategy.new(
        number_of_retries: number_of_retries,
        factor: factor_ms,
        exponent_base: exponent_base,
        jitter_percent: jitter_percent
      )
    end

    # Build connection request
    request_params = {
      cluster_mode_enabled: cluster_mode_enabled,
      request_timeout: request_timeout,
      protocol: protocol,
      tls_mode: tls_mode,
      addresses: nodes.map { |node| ConnectionRequest::NodeAddress.new(host: node[:host], port: node[:port]) }
    }

    # Add optional fields only if they have values
    request_params[:connection_timeout] = connection_timeout_ms if connection_timeout_ms.positive?
    request_params[:database_id] = database_id if database_id.positive?
    request_params[:client_name] = client_name unless client_name.empty?
    request_params[:authentication_info] = authentication_info if authentication_info
    request_params[:root_certs] = root_certs unless root_certs.empty?
    request_params[:connection_retry_strategy] = connection_retry_strategy if connection_retry_strategy

    request = ConnectionRequest::ConnectionRequest.new(request_params)

    client_type = Bindings::ClientType.new
    client_type[:tag] = 1 # SyncClient

    request_str = ConnectionRequest::ConnectionRequest.encode(request)
    request_buf = FFI::MemoryPointer.new(:char, request_str.bytesize)
    request_buf.put_bytes(0, request_str)

    request_len = request_str.bytesize

    response_ptr = Bindings.create_client(
      request_buf,
      request_len,
      client_type,
      method(:pubsub_callback)
    )

    res = Bindings::ConnectionResponse.new(response_ptr)

    # Check if connection was successful
    if res[:conn_ptr].null?
      error_message = res[:connection_error_message]
      raise CannotConnectError, "Failed to connect to cluster: #{error_message}"
    end

    @connection = res[:conn_ptr]

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
