# frozen_string_literal: true

require "ffi"
require "json"
require "uri"

require "valkey/version"
require "valkey/request_type"
require "valkey/response_type"
require "valkey/read_from"
require "valkey/request_error_type"
require "valkey/bindings"
require "valkey/utils"
require "valkey/commands"
require "valkey/errors"
require "valkey/future"
require "valkey/pubsub_callback"
require "valkey/pipeline"
require "valkey/opentelemetry"
require "valkey/route"

class Valkey
  include Utils
  include Commands
  include PubSubCallback

  def pipelined(exception: true)
    pipeline = Pipeline.new

    begin
      yield pipeline

      return [] if pipeline.commands.empty?

      results = send_batch_commands(pipeline.commands, exception: exception)
      pipeline.resolve_futures!(results)
      results
    rescue StandardError
      pipeline.abort_futures!
      raise
    end
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

    # Determine scheme based on truthy TLS/SSL.
    scheme = options[:ssl] ? "rediss" : "redis"

    # Build URI with authentication if provided
    uri_parts = [scheme, "://"]

    # Add authentication to URI. Use RFC 3986 percent-encoding rather than
    # form-encoding (`CGI.escape`) so a space in the password becomes `%20`,
    # not `+`. The FFI layer decodes userinfo per RFC 3986
    # (`percent_encoding::percent_decode`), which does NOT treat `+` as a
    # space — using CGI.escape would silently corrupt any password containing
    # a literal space. See valkey-glide/issues/6659.
    #
    # We pass an explicit `unsafe` regex — anything outside RFC 3986 §2.3
    # "unreserved" (`ALPHA / DIGIT / - . _ ~`) plus the RFC 2396 "mark" chars
    # (`! ~ * ' ( )`) — because `URI::RFC2396_PARSER.escape`'s default set
    # leaves `/` and `?` raw in userinfo, which the Rust `url` crate on the
    # FFI side then rejects with "Invalid connection URI". Encoding more is
    # always safe because the FFI decodes uniformly.
    userinfo_unsafe = /[^\-_.!~*'()a-zA-Z0-9]/
    if options[:username] && options[:password]
      uri_parts << URI::RFC2396_PARSER.escape(options[:username], userinfo_unsafe)
      uri_parts << ":"
      uri_parts << URI::RFC2396_PARSER.escape(options[:password], userinfo_unsafe)
      uri_parts << "@"
    elsif options[:password]
      uri_parts << ":"
      uri_parts << URI::RFC2396_PARSER.escape(options[:password], userinfo_unsafe)
      uri_parts << "@"
    end

    # Wrap IPv6 literals in brackets so the host/port separator is unambiguous.
    uri_parts << (uri_host.include?(":") ? "[#{uri_host}]" : uri_host)
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

    # Client name (user-configurable)
    json_options["client_name"] = options[:client_name] if options[:client_name]

    # read_from parsing.
    json_options["read_from"] = options[:read_from] if options[:read_from]

    # client_az
    json_options["client_az"] = options[:client_az] if options[:client_az]

    unless json_options["client_az"]
      case json_options["read_from"]
      when ReadFrom::AZ_AFFINITY
        raise ArgumentError, "client_az must be set when read_from is AZAffinity"
      when ReadFrom::AZ_AFFINITY_REPLICAS_AND_PRIMARY
        raise ArgumentError, "client_az must be set when read_from is AZAffinityReplicasAndPrimary"
      end
    end

    if options.key?(:inflight_requests_limit)
      json_options["inflight_requests_limit"] = options[:inflight_requests_limit]
    end

    json_options["lazy_connect"] = options[:lazy_connect] if options.key?(:lazy_connect)

    json_options["periodic_checks"] = build_periodic_checks(options[:periodic_checks]) if options.key?(:periodic_checks)

    # TLS/SSL certificates
    root_certs = []
    if options[:ssl_params].is_a?(Hash)
      # ca_file - CA certificate file path
      root_certs << read_ssl_value(options[:ssl_params][:ca_file], "CA") if options[:ssl_params][:ca_file]

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

      # cert - file path or OpenSSL::X509::Certificate
      json_options["client_cert"] = read_ssl_value(options[:ssl_params][:cert], "Cert") if options[:ssl_params][:cert]

      # key - file path or OpenSSL::PKey
      json_options["client_key"] = read_ssl_value(options[:ssl_params][:key], "Key") if options[:ssl_params][:key]

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
    # Serializes `close` so two threads cannot both capture the handle and
    # double-decrement its Arc refcount (issue #212). We use `Mutex#try_lock`
    # in `close`, not `#synchronize`, so trap-context callers still work:
    # only `#lock`/`#synchronize` raise ThreadError from a trap, `#try_lock`
    # returns false and moves on.
    @close_lock = Mutex.new
    Bindings.free_connection_response(response_ptr)

    # Store cluster mode flag for response handling (MAP returns Hash in cluster, Array in standalone)
    @cluster_mode = options[:cluster_mode] ? true : false

    # Returns GLIDE Core map as a flattened-map array
    # Ex: { "key1" => "value1", "key2" => "value2" } becomes ["key1", "value1", "key2", "value2"]
    # Compatibility for redis-rb 4.x
    @flatten_map = options[:flatten_map] ? true : false

    # Track transactional state for `MULTI` / `EXEC` / `DISCARD` helpers.
    # This avoids Ruby warnings about uninitialised instance variables and
    # gives us a single source of truth for whether we're inside a TX.
    @in_multi = false
    # Track queued commands during MULTI for transaction isolation support
    @queued_commands = []
    # Track if we're inside a multi block (multi { ... }) vs direct multi calls
    @in_multi_block = false
  end

  # Closes the client and frees the native connection. Idempotent and
  # thread-safe: `@close_lock.try_lock` lets exactly one caller free the
  # handle, while every other concurrent `close` (and every subsequent one)
  # is a no-op. Without this, two threads could both read `@connection`
  # before either nulled it, both call `close_client`, and double-decrement
  # the Arc refcount - which is UB per Rust (issue #212).
  #
  # `try_lock` (not `synchronize`) is deliberate: `Mutex#synchronize` /
  # `#lock` raise ThreadError from a trap context, but `#try_lock` does not.
  # That keeps the standard `Signal.trap("TERM") { client.close }` shutdown
  # idiom working - the trap either wins the lock and closes, or another
  # thread has already closed and it silently returns.
  #
  # In-flight commands are safe: every glide-ffi command entry point does
  # `Arc::increment_strong_count` on the handle before using it, and
  # `close_client` only decrements, so the native ClientAdapter outlives any
  # request still executing and is dropped once the last one finishes.
  # Verified with 12 concurrent blocking calls held open across a `close`.
  def close
    return unless @close_lock&.try_lock

    begin
      conn = @connection
      @connection = nil

      Bindings.close_client(conn) unless conn.nil? || conn.null?
    ensure
      @close_lock.unlock
    end
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
  #   stats = client.get_statistics
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

  alias get_statistics statistics

  # Sends a single low-level command to the server, converting the response to
  # a Ruby value. This is the primitive every command method in
  # `lib/valkey/commands/*.rb` is built on. Public (rather than private) because
  # some test helpers (e.g. `test/lint/vector_search_commands.rb`,
  # `test/valkey/connection_lifecycle_test.rb`) call it directly with an
  # explicit receiver to issue commands with no dedicated wrapper method yet
  # (e.g. `DEBUG SLEEP`, raw `HSET` in vector search fixtures).
  def send_command(command_type, command_args = [], route: nil, &block)
    conn = connection!

    channel = 0

    # Handle empty command_args case
    if command_args.empty?
      arg_ptrs = FFI::MemoryPointer.new(:pointer, 1)
      arg_lens = FFI::MemoryPointer.new(:ulong, 1)
      arg_ptrs.put_pointer(0, FFI::MemoryPointer.new(1))
      arg_lens.put_ulong(0, 0)
      _buffers = [] # nothing to keep alive
      flattened_args = command_args
    else
      arg_ptrs, arg_lens, _buffers, flattened_args = build_command_args(command_args)
    end

    # Create OpenTelemetry span if sampling is enabled, as a child of the app's current
    # span context when a parent_span_context_provider is registered (see Valkey::OpenTelemetry).
    span_ptr = 0
    if OpenTelemetry.should_sample?
      begin
        parent_ctx = OpenTelemetry.parent_span_context
        span_ptr = if parent_ctx
                     Bindings.create_otel_span_with_trace_context(
                       command_type, parent_ctx[:trace_id], parent_ctx[:span_id],
                       parent_ctx[:trace_flags], parent_ctx[:tracestate]
                     )
                   else
                     Bindings.create_otel_span(command_type)
                   end
      rescue StandardError => e
        # Log error but continue execution - tracing is non-critical
        warn "Failed to create OpenTelemetry span: #{e.message}"
        span_ptr = 0
      end
    end

    begin
      if route
        # Use command_with_route_info when an explicit route is provided.
        route_info, _pinned_bufs = route.to_ffi
        res = Bindings.command_with_route_info(
          conn,
          channel,
          command_type,
          flattened_args.size,
          arg_ptrs,
          arg_lens,
          route_info.to_ptr,
          FFI::Pointer::NULL, # response_buf (NULL = normal response path)
          0,                  # response_buf_len
          span_ptr
        )
      else
        # Use legacy command() for unrouted calls to preserve existing behavior.
        route_str = ""
        route_buf = FFI::MemoryPointer.from_string(route_str)
        res = Bindings.command(
          conn,
          channel,
          command_type,
          flattened_args.size,
          arg_ptrs,
          arg_lens,
          route_buf,
          route_str.bytesize,
          span_ptr
        )
      end

      result = convert_response(res, &block)
    ensure
      # Free the native CommandResult (arena + response + error) to prevent memory leak
      Bindings.free_command_result(res) if res && !res.null?

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
      if !tx_commands.include?(command_type) && result == "QUEUED"
        @queued_commands << [command_type, command_args.dup, block]
      end
    end

    result
  end

  private

  # Returns the live native client handle, raising if the client has been
  # closed.
  def connection!
    conn = @connection
    raise ConnectionError, "the client is closed" if conn.nil? || conn.null?

    conn
  end

  # Read an SSL value
  # Accepts a file path (String), an OpenSSL object (#to_pem / #to_der), or a fallback #to_s.
  def read_ssl_value(value, label)
    if value.is_a?(String)
      raise ArgumentError, "#{label} file does not exist: #{value}" unless File.exist?(value)
      raise ArgumentError, "#{label} file is not readable: #{value}" unless File.readable?(value)

      File.binread(value)
    # Duck-typing check
    elsif value.respond_to?(:to_pem)
      value.to_pem
    elsif value.respond_to?(:to_der)
      value.to_der
    else
      value.to_s
    end
  end

  def send_batch_commands(commands, exception: true, is_atomic: false)
    # WORKAROUND: The underlying Glide FFI backend has stability issues when
    # batching LITERAL MULTI / EXEC / DISCARD commands (e.g. a `pipelined` block
    # that manually calls `pipeline.multi`/`pipeline.exec`). To avoid native
    # crashes we fall back to issuing those commands sequentially instead of via
    # `Bindings.batch`. This never applies to a real `is_atomic: true` batch
    # (see `multi`'s block form) - that path never contains literal MULTI/EXEC
    # commands, since the server-side transaction wrapping is handled by GLIDE
    # itself based on the `is_atomic` flag, not by commands in the list.
    unless is_atomic
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
    end

    # Checked before allocating any FFI memory below, so a closed client fails fast.
    conn = connection!

    cmds = []
    blocks = []
    buffers = [] # Keep references to prevent GC

    commands.each do |command_type, command_args, block|
      arg_ptrs, arg_lens, arg_bufs, flattened_args = build_command_args(command_args)

      cmd = Bindings::CmdInfo.new
      cmd[:request_type] = command_type
      cmd[:args] = arg_ptrs
      cmd[:arg_count] = flattened_args.size
      cmd[:args_len] = arg_lens

      cmds << cmd
      blocks << block
      buffers << [arg_ptrs, arg_lens, arg_bufs] # Prevent GC
    end

    # Create array of pointers to CmdInfo structs
    cmd_ptrs = FFI::MemoryPointer.new(:pointer, cmds.size)
    cmds.each_with_index do |cmd, i|
      cmd_ptrs[i].put_pointer(0, cmd.to_ptr)
    end

    batch_info = Bindings::BatchInfo.new
    batch_info[:cmd_count] = cmds.size
    batch_info[:cmds] = cmd_ptrs
    batch_info[:is_atomic] = is_atomic

    batch_options = Bindings::BatchOptionsInfo.new
    batch_options[:retry_server_error] = true
    batch_options[:retry_connection_error] = true
    batch_options[:has_timeout] = false
    batch_options[:timeout] = 0 # No timeout
    batch_options[:route_info] = FFI::Pointer::NULL

    # Create OpenTelemetry span for batch operation if sampling is enabled, as a child of
    # the app's current span context when a parent_span_context_provider is registered.
    span_ptr = 0
    if OpenTelemetry.should_sample?
      begin
        parent_ctx = OpenTelemetry.parent_span_context
        span_ptr = if parent_ctx
                     Bindings.create_batch_otel_span_with_trace_context(
                       parent_ctx[:trace_id], parent_ctx[:span_id], parent_ctx[:trace_flags], parent_ctx[:tracestate]
                     )
                   else
                     Bindings.create_batch_otel_span
                   end
      rescue StandardError => e
        warn "Failed to create OpenTelemetry batch span: #{e.message}"
        span_ptr = 0
      end
    end

    begin
      res = Bindings.batch(
        conn,
        0,
        batch_info,
        exception,
        batch_options.to_ptr,
        span_ptr
      )

      results = convert_response(res)
    ensure
      # Free the native CommandResult (arena + response + error) to prevent memory leak
      Bindings.free_command_result(res) if res && !res.null?

      # Always drop the span if one was created
      if span_ptr != 0
        begin
          Bindings.drop_otel_span(span_ptr)
        rescue StandardError => e
          warn "Failed to drop OpenTelemetry batch span: #{e.message}"
        end
      end
    end

    # An inline error slot (see the ResponseType::ERROR case in
    # convert_response above) must be left alone here - e.g. Utils::Boolify
    # would otherwise silently coerce a CommandError object to `true`
    # (`value != 0` is true for any non-numeric object), hiding the error.
    blocks.each_with_index do |block, i|
      results[i] = block.call(results[i]) if block && !results[i].is_a?(CommandError)
    end

    results
  end

  # Builds the `periodic_checks` extra_options_json value. Accepts
  # `{ manual_interval: { duration_in_sec: N } }` or `{ disabled: true/false }`
  # (symbol or string keys). Only checks shape (Hash present, manual_interval
  # is a Hash) to avoid a NoMethodError -- the core validates values.
  def build_periodic_checks(periodic_checks)
    unless periodic_checks.is_a?(Hash)
      raise ArgumentError, "periodic_checks must be a Hash, got: #{periodic_checks.class}"
    end

    if periodic_checks.key?(:disabled) || periodic_checks.key?("disabled")
      disabled = periodic_checks.key?(:disabled) ? periodic_checks[:disabled] : periodic_checks["disabled"]
      return { "disabled" => disabled }
    end

    manual_interval = periodic_checks[:manual_interval] || periodic_checks["manual_interval"]
    raise ArgumentError, "periodic_checks must contain :manual_interval or :disabled" unless manual_interval.is_a?(Hash)

    duration_in_sec = manual_interval[:duration_in_sec] || manual_interval["duration_in_sec"]

    { "manual_interval" => { "duration_in_sec" => duration_in_sec } }
  end

  # Builds the FFI arg_ptrs/arg_lens/buffers for command_args, flattening nested
  # Array/Hash elements first (mirroring redis-client's CommandBuilder#generate)
  # so callers like hset(key, [field, value]) serialize correctly instead of
  # collapsing into one garbled Array#to_s/Hash#to_s string. Returns the
  # flattened command_args too - callers must size arg_count off this returned
  # array, not their original pre-flatten one, or arg_count goes out of sync
  # with arg_ptrs/arg_lens. Each element's type is checked against the same
  # allow-list redis-client's CommandBuilder#generate uses (String, Symbol,
  # Integer, Float) - anything else, including nil, raises TypeError instead
  # of being silently coerced via #to_s (e.g. nil.to_s => "").
  def build_command_args(command_args)
    # Flatten nested Arrays/Hashes to match redis-client's behavior.
    command_args = command_args.flat_map { |el| el.is_a?(Hash) ? el.flatten : el }

    # For empty arrays, pass NULL pointers as per Rust FFI contract
    # This matches Go's approach which successfully uses nil pointers
    return [FFI::Pointer::NULL, FFI::Pointer::NULL, [], []] if command_args.empty?

    arg_ptrs = FFI::MemoryPointer.new(:pointer, command_args.size)
    arg_lens = FFI::MemoryPointer.new(:ulong, command_args.size)
    buffers = []

    command_args.each_with_index do |arg, i|
      arg = case arg
            when String, Symbol, Integer, Float
              arg.to_s
            else
              raise TypeError, "Unsupported command argument type: #{arg.class}"
            end

      buf = FFI::MemoryPointer.from_string(arg)
      buffers << buf # prevent garbage collection
      arg_ptrs.put_pointer(i * FFI::Pointer.size, buf)
      arg_lens.put_ulong(i * 8, arg.bytesize)
    end

    [arg_ptrs, arg_lens, buffers, command_args]
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

        @flatten_map ? map.to_a.flatten(1) : map
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

    # Don't run the caller's converter (e.g. Utils::Boolify) over the MULTI-queued
    # "QUEUED" sentinel - send_command's own `result == "QUEUED"` check (used to
    # track queued commands) needs to see the literal string, not e.g. `true`.
    if block_given? && response != "QUEUED"
      block.call(response)
    else
      response
    end
  end
end
