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

class Valkey
  include Utils
  include Commands
  include PubSubCallback

  def pipelined(exception: true)
    pipeline = Pipeline.new

    yield pipeline

    return if pipeline.commands.empty?

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

    commands.each do |command_type, command_args, block|
      arg_ptrs, arg_lens = build_command_args(command_args)

      cmd = Bindings::CmdInfo.new
      cmd[:request_type] = command_type
      cmd[:args] = arg_ptrs
      cmd[:arg_count] = command_args.size
      cmd[:args_len] = arg_lens

      cmds << cmd
      blocks << block
    end

    batch_info = Bindings::BatchInfo.new
    batch_info[:cmd_count] = cmds.size
    batch_info[:cmds] = FFI::MemoryPointer.new(Bindings::CmdInfo, cmds.size)

    cmds.each_with_index do |cmd, i|
      batch_info[:cmds].put_pointer(i * Bindings::CmdInfo.size, cmd.to_ptr)
    end

    batch_options = Bindings::BatchOptionsInfo.new
    batch_options[:retry_server_error] = true
    batch_options[:retry_connection_error] = true
    batch_options[:has_timeout] = false
    batch_options[:timeout] = 0 # No timeout

    res = Bindings.batch(
      @connection, # Assuming @connection is set after create
      0,
      batch_info,
      exception,
      batch_options,
      0
    )

    results = convert_response(res)

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
          item = Bindings::CommandResponse.new(ptr + i * Bindings::CommandResponse.size)
          convert_response.call(item)
        end
      when ResponseType::MAP
        return nil if response_item[:array_value].null?

        ptr = response_item[:array_value]
        count = response_item[:array_value_len].to_i
        map = {}

        Array.new(count) do |i|
          item = Bindings::CommandResponse.new(ptr + i * Bindings::CommandResponse.size)

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
          item = Bindings::CommandResponse.new(ptr + i * Bindings::CommandResponse.size)
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

    res = Bindings.command(
      @connection,
      channel,
      command_type,
      command_args.size,
      arg_ptrs,
      arg_lens,
      route_buf,
      route.bytesize,
      0
    )

    result = convert_response(res, &block)

    # Track queued commands during MULTI (except for MULTI, EXEC, DISCARD, WATCH, UNWATCH)
    if @in_multi && !@queued_commands.nil?
      tx_commands = [RequestType::MULTI, RequestType::EXEC, RequestType::DISCARD, RequestType::WATCH, RequestType::UNWATCH]
      @queued_commands << [command_type, command_args.dup] if !tx_commands.include?(command_type) && result == "QUEUED"
    end

    result
  end

  def initialize(options = {})
    # Parse URL if provided (redis-rb compatibility)
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

    # Protocol defaults to RESP2 for stability with RediSearch commands
    # Users can explicitly set protocol: :resp3 if needed
    protocol = case options[:protocol]
               when :resp3, "resp3", 3
                 ConnectionRequest::ProtocolVersion::RESP3
               else
                 # Default to RESP2 for stability (RediSearch compatibility)
                 ConnectionRequest::ProtocolVersion::RESP2
               end

    # TLS/SSL support (redis-rb compatibility)
    tls_mode = if options[:ssl] == true || options[:ssl] == "true"
                 ConnectionRequest::TlsMode::SecureTls
               else
                 ConnectionRequest::TlsMode::NoTls
               end

    # SSL parameters (redis-rb compatibility)
    # Map ssl_params to protobuf root_certs
    # Note: root_certs in protobuf is `repeated bytes`, which accepts an array of byte strings
    root_certs = []
    if options[:ssl_params] && options[:ssl_params].is_a?(Hash)
      # ca_file - read CA certificate file (PEM or DER format)
      if options[:ssl_params][:ca_file]
        root_certs << File.binread(options[:ssl_params][:ca_file])
      end

      # cert - client certificate (can be file path or OpenSSL::X509::Certificate)
      if options[:ssl_params][:cert]
        cert_data = if options[:ssl_params][:cert].is_a?(String)
                      # Assume it's a file path
                      File.binread(options[:ssl_params][:cert])
                    elsif options[:ssl_params][:cert].respond_to?(:to_pem)
                      # OpenSSL::X509::Certificate object
                      options[:ssl_params][:cert].to_pem
                    elsif options[:ssl_params][:cert].respond_to?(:to_der)
                      # DER format
                      options[:ssl_params][:cert].to_der
                    else
                      # Fallback to string conversion
                      options[:ssl_params][:cert].to_s
                    end
        root_certs << cert_data
      end

      # key - client key (can be file path or OpenSSL::PKey)
      if options[:ssl_params][:key]
        key_data = if options[:ssl_params][:key].is_a?(String)
                     # Assume it's a file path
                     File.binread(options[:ssl_params][:key])
                   elsif options[:ssl_params][:key].respond_to?(:to_pem)
                     # OpenSSL::PKey object
                     options[:ssl_params][:key].to_pem
                   elsif options[:ssl_params][:key].respond_to?(:to_der)
                     # DER format
                     options[:ssl_params][:key].to_der
                   else
                     # Fallback to string conversion
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

      # Direct root_certs array support (array of byte strings)
      if options[:ssl_params][:root_certs] && options[:ssl_params][:root_certs].is_a?(Array)
        root_certs.concat(options[:ssl_params][:root_certs])
      end
    end

    # Authentication support (redis-rb compatibility)
    authentication_info = nil
    if options[:password] || options[:username]
      authentication_info = ConnectionRequest::AuthenticationInfo.new(
        password: options[:password] || "",
        username: options[:username] || ""
      )
    end

    # Database selection (redis-rb compatibility: db option)
    database_id = options[:db] || options[:database_id] || 0

    # Client name (redis-rb compatibility)
    client_name = options[:client_name] || options[:name] || ""

    # Timeout handling (redis-rb compatibility)
    # Keep existing behavior for request_timeout (may be in seconds or milliseconds depending on backend)
    # Use timeout, read_timeout, write_timeout, or default 3.0
    # Note: Protobuf uses single request_timeout for both read and write operations
    request_timeout = options[:timeout] || options[:read_timeout] || options[:write_timeout] || 3.0

    # Connection timeout (separate from request timeout)
    # Protobuf expects milliseconds for connection_timeout
    connection_timeout_ms = if options[:connect_timeout]
                              (options[:connect_timeout] * 1000).to_i
                            else
                              0 # Use default from backend
                            end

    # Connection retry strategy (redis-rb compatibility)
    # Map reconnect_attempts, reconnect_delay, reconnect_delay_max to protobuf connection_retry_strategy
    connection_retry_strategy = nil
    if options[:reconnect_attempts] || options[:reconnect_delay] || options[:reconnect_delay_max]
      # Default values matching redis-rb behavior
      number_of_retries = options[:reconnect_attempts] || 1
      base_delay = options[:reconnect_delay] || 0.5 # Base delay in seconds
      max_delay = options[:reconnect_delay_max]
      exponent_base = 2 # Exponential backoff base (default)
      jitter_percent = 0 # No jitter by default

      # Calculate exponent_base from reconnect_delay_max if provided
      # The formula is: delay = base_delay * (exponent_base ^ attempt)
      # We want the max delay to be reached at the last retry
      if max_delay && base_delay > 0 && number_of_retries > 0
        # Calculate exponent_base: max_delay = base_delay * (exponent_base ^ number_of_retries)
        # So: exponent_base = (max_delay / base_delay) ^ (1 / number_of_retries)
        calculated_base = (max_delay / base_delay) ** (1.0 / number_of_retries.to_f)
        exponent_base = [calculated_base.round, 2].max # At least 2 for exponential backoff
      end

      # Factor is the base delay in milliseconds
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
    request_params[:connection_timeout] = connection_timeout_ms if connection_timeout_ms > 0
    request_params[:database_id] = database_id if database_id > 0
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
end
