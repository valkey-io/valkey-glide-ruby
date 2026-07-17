# frozen_string_literal: true

class Valkey
  module Bindings
    extend FFI::Library

    # Detect whether the current Linux system uses musl libc (e.g., Alpine Linux).
    # Uses a three-check cascade — any single match is sufficient.
    def self.musl_libc?
      return false unless FFI::Platform::OS == "linux"

      # Check 1: RUBY_PLATFORM contains 'musl' (e.g., Alpine-built Ruby)
      return true if RUBY_PLATFORM.include?("musl")

      # Check 2: /etc/alpine-release exists (Alpine Linux indicator)
      return true if File.exist?("/etc/alpine-release")

      # Check 3: RbConfig target_os contains 'musl'
      return true if RbConfig::CONFIG["target_os"].to_s.include?("musl")

      false
    end

    # Determine platform-specific library extension and directory name
    def self.platform_info
      os = if FFI::Platform.mac?
             "darwin"
           elsif FFI::Platform.windows?
             "windows"
           else
             "linux"
           end

      # Detect architecture
      arch = case RbConfig::CONFIG["host_cpu"]
             when /x86_64|amd64/i
               "x86_64"
             when /aarch64|arm64/i
               "aarch64"
             when /i[3-6]86/i
               "x86"
             else
               RbConfig::CONFIG["host_cpu"]
             end

      lib_ext = case os
                when "darwin"
                  "dylib"
                when "windows"
                  "dll"
                else
                  "so"
                end

      # Platform directory name matches Rust target triple convention
      platform_dir = case os
                     when "darwin"
                       "#{arch}-apple-darwin"
                     when "linux"
                       musl_libc? ? "#{arch}-unknown-linux-musl" : "#{arch}-unknown-linux-gnu"
                     when "windows"
                       "#{arch}-pc-windows-msvc"
                     end

      { os: os, arch: arch, lib_ext: lib_ext, platform_dir: platform_dir }
    end

    platform = platform_info
    lib_ext = platform[:lib_ext]
    platform_dir = platform[:platform_dir]

    # Look for the native library in the following locations (in order):
    # 1. valkey-glide submodule build output (development/source builds)
    # 2. Platform-specific bundled library in lib/valkey/native/{platform}/ (for gem distribution)
    # 3. Legacy bundled library in lib/valkey (fallback for old gem structure)
    lib_paths = [
      # Submodule build output (release) - from lib/valkey/ go up 2 levels to repo root
      File.expand_path("../../valkey-glide/ffi/target/release/libglide_ffi.#{lib_ext}", __dir__),
      # Submodule build output (debug)
      File.expand_path("../../valkey-glide/ffi/target/debug/libglide_ffi.#{lib_ext}", __dir__),
      # Platform-specific bundled library (for gem distribution)
      File.expand_path("./native/#{platform_dir}/libglide_ffi.#{lib_ext}", __dir__),
      # Legacy bundled library (fallback)
      File.expand_path("./libglide_ffi.#{lib_ext}", __dir__)
    ]

    lib_path = lib_paths.find { |path| File.exist?(path) }

    unless lib_path
      raise LoadError, <<~ERROR
        Could not find libglide_ffi native library for platform: #{platform_dir}

        Searched in:
        #{lib_paths.map { |p| "  - #{p}" }.join("\n")}

        To build from source:
          1. Initialize the submodule: git submodule update --init --recursive
          2. Build the FFI library: cd valkey-glide/ffi && cargo build --release

        Detected platform: OS=#{platform[:os]}, Arch=#{platform[:arch]}
      ERROR
    end

    ffi_lib lib_path

    class ClientType < FFI::Struct
      layout(
        :tag, :uint # 0 = AsyncClient, 1 = SyncClient
      )
    end

    class ConnectionResponse < FFI::Struct
      layout(
        :conn_ptr, :pointer, # *const c_void
        :connection_error_message, :string # *const c_char (null-terminated C string)
      )
    end

    class CommandError < FFI::Struct
      layout(
        :command_error_message, :string,
        :command_error_type, :int # Assuming RequestErrorType is repr(C) enum
      )
    end

    # Mirrors Rust's `RouteType` enum (valkey-glide/ffi/src/lib.rs)
    RouteType = enum(
      :all_nodes, 0,
      :all_primaries,
      :random,
      :slot_id,
      :slot_key,
      :by_address
    )

    # Mirrors Rust's `SlotType` enum (a mirror of `SlotAddr`)
    SlotType = enum(
      :primary, 0,
      :replica
    )

    class RouteInfo < FFI::Struct
      layout(
        :route_type, RouteType,
        :slot_id, :int32,        # slot number (for SlotId route)
        :slot_key, :pointer,     # *const c_char (for SlotKey route; NULL otherwise)
        :slot_type, SlotType,
        :hostname, :pointer,     # *const c_char (for ByAddress route; NULL otherwise)
        :port, :int32            # port number (for ByAddress route)
      )
    end

    class BatchOptionsInfo < FFI::Struct
      layout(
        :retry_server_error, :bool,
        :retry_connection_error, :bool,
        :has_timeout, :bool,
        :timeout, :uint, # Assuming u32 is represented as uint in C
        :route_info, :pointer # *const RouteInfo
      )
    end

    class CmdInfo < FFI::Struct
      layout(
        :request_type, :int,  # Assuming RequestType is repr(C) enum
        :args, :pointer,      # *const *const u8 (pointer to array of pointers to args)
        :arg_count, :ulong,   # usize (number of arguments)
        :args_len, :pointer   # *const usize (pointer to array of argument lengths)
      )
    end

    class ScriptHashBuffer < FFI::Struct
      layout(
        :ptr, :pointer,  # *mut u8 (pointer to the script hash)
        :len, :ulong,    # usize (length of the script hash)
        :capacity, :ulong # usize (capacity of the buffer)
      )
    end

    class BatchInfo < FFI::Struct
      layout(
        :cmd_count, :ulong,  # usize
        :cmds, :pointer,     # *const *const CmdInfo
        :is_atomic, :bool    # bool
      )
    end

    class CommandResponse < FFI::Struct
      layout(
        :response_type, :int,         # Assuming ResponseType is repr(C) enum
        :int_value, :int64,
        :float_value, :double,
        :bool_value, :bool,
        :string_value, :pointer,      # points to C string
        :string_value_len, :long,
        :array_value, :pointer,       # points to CommandResponse array
        :array_value_len, :long,
        :map_key, :pointer,           # CommandResponse*
        :map_value, :pointer,         # CommandResponse*
        :sets_value, :pointer,        # CommandResponse*
        :sets_value_len, :long,
        :arena_ptr, :pointer          # *mut c_void - arena allocator pointer
      )
    end

    callback :success_callback, %i[ulong pointer], :void
    callback :failure_callback, %i[ulong string int], :void

    class AsyncClientData < FFI::Struct
      layout(
        :success_callback, :success_callback,
        :failure_callback, :failure_callback
      )
    end

    class ClientData < FFI::Union
      layout(
        :async_client, AsyncClientData
      )
    end

    class CommandResult < FFI::Struct
      layout(
        :response, CommandResponse.by_ref,
        :command_error, CommandError.by_ref,
        :arena, :pointer # *mut ResponseArena
      )
    end

    callback :pubsub_callback, [
      :ulong, # client_ptr
      :int,             # kind (PushKind enum)
      :pointer, :long,  # message + length
      :pointer, :long,  # channel + length
      :pointer, :long   # pattern + length
    ], :void

    attach_function :create_client, [
      :pointer,        # *const u8 (connection_request_bytes)
      :ulong,          # usize (connection_request_len)
      ClientType.by_ref, # *const ClientType
      :pubsub_callback # callback
    ], :pointer        # *const ConnectionResponse

    attach_function :create_client_from_uri, [
      :string,         # *const c_char (uri_str)
      :string,         # *const c_char (extra_options_json)
      ClientType.by_ref, # *const ClientType
      :pubsub_callback # callback
    ], :pointer        # *const ConnectionResponse

    attach_function :free_connection_response, [
      :pointer # *mut ConnectionResponse
    ], :void

    attach_function :free_command_result, [
      :pointer # *mut CommandResult
    ], :void

    attach_function :free_script_hash_buffer, [
      :pointer # *mut ScriptHashBuffer
    ], :void

    attach_function :drop_script, [
      :pointer, # *mut u8 (hash bytes)
      :ulong    # usize (hash length)
    ], :pointer # returns *mut c_char (null on success, error string on failure)

    attach_function :free_drop_script_error, [
      :pointer # *mut c_char (error from drop_script)
    ], :void

    attach_function :close_client, [
      :pointer # client_adapter_ptr
    ], :void

    attach_function :command, [
      :pointer,     # client_adapter_ptr
      :ulong,       # request_id
      :int,         # command_type
      :ulong,       # arg_count
      :pointer,     # args (pointer to usize[])
      :pointer,     # args_len (pointer to c_ulong[])
      :pointer,     # route_bytes
      :ulong,       # route_bytes_len
      :ulong        # span_ptr (u64)
    ], :pointer, blocking: true # returns *mut CommandResult, releases GVL during I/O

    attach_function :command_with_route_info, [
      :pointer,     # client_adapter_ptr
      :ulong,       # request_id
      :int,         # command_type (RequestType)
      :ulong,       # arg_count
      :pointer,     # args (pointer to usize[])
      :pointer,     # args_len (pointer to c_ulong[])
      :pointer,     # route_info (*const RouteInfo, or NULL for no route)
      :pointer,     # response_buf (NULL = normal response path)
      :ulong,       # response_buf_len (0 if response_buf is NULL)
      :ulong        # span_ptr (u64)
    ], :pointer, blocking: true # returns *mut CommandResult, releases GVL during I/O

    attach_function :batch, [
      :pointer,        # client_ptr
      :ulong,          # callback_index
      BatchInfo.by_ref, # *const BatchInfo
      :bool,           # raise_on_error
      :pointer,        # *const BatchOptionsInfo
      :ulong           # span_ptr (u64)
    ], :pointer, blocking: true # returns *mut CommandResult, releases GVL during I/O

    attach_function :store_script, [
      :pointer, # *const u8 (script_bytes)
      :ulong # usize (script_len)
    ], :pointer # returns *mut ScriptHashBuffer

    attach_function :invoke_script, [
      :pointer,        # client_ptr
      :ulong,          # request_id
      :pointer,        # hash (pointer to C string)
      :ulong,          # keys_count (number of keys)
      :pointer,        # keys (pointer to usize[])
      :pointer,        # keys_len (pointer to c_ulong[])
      :ulong,          # args_count (number of args)
      :pointer,        # args (pointer to usize[])
      :pointer,        # args_len (pointer to c_ulong[])
      :pointer,        # route_bytes (pointer to u8)
      :ulong,          # route_bytes_len (usize)
      :uint64          # span_ptr (OpenTelemetry span pointer)
    ], :pointer, blocking: true # returns *mut CommandResult, releases GVL during I/O

    # OpenTelemetry structures
    class OpenTelemetryTracesConfig < FFI::Struct
      layout(
        :endpoint, :pointer,              # const char* (trace collector endpoint)
        :has_sample_percentage, :bool,    # whether sample_percentage is set
        :sample_percentage, :uint32       # sampling percentage (0-100)
      )
    end

    class OpenTelemetryMetricsConfig < FFI::Struct
      layout(
        :endpoint, :pointer               # const char* (metrics collector endpoint)
      )
    end

    class OpenTelemetryConfig < FFI::Struct
      layout(
        :traces, :pointer,                # OpenTelemetryTracesConfig*
        :metrics, :pointer,               # OpenTelemetryMetricsConfig*
        :has_flush_interval_ms, :bool,    # whether flush_interval_ms is set
        :flush_interval_ms, :int64        # flush interval in milliseconds
      )
    end

    # Statistics structure
    class Statistics < FFI::Struct
      layout(
        :total_connections, :ulong,
        :total_clients, :ulong,
        :total_values_compressed, :ulong,
        :total_values_decompressed, :ulong,
        :total_original_bytes, :ulong,
        :total_bytes_compressed, :ulong,
        :total_bytes_decompressed, :ulong,
        :compression_skipped_count, :ulong,
        :subscription_out_of_sync_count, :ulong,
        :subscription_last_sync_timestamp, :ulong
      )
    end

    # OpenTelemetry functions
    attach_function :init_open_telemetry, [
      OpenTelemetryConfig.by_ref # OpenTelemetry configuration
    ], :pointer # returns error string or NULL on success

    attach_function :free_c_string, [
      :pointer # C string to free
    ], :void

    attach_function :create_otel_span, [
      :int # request_type (RequestType enum value)
    ], :uint64 # returns span pointer (u64) or 0 on failure

    attach_function :create_batch_otel_span, [], :uint64 # returns span pointer (u64) or 0 on failure

    attach_function :create_otel_span_with_trace_context, [
      :int,    # request_type (RequestType enum value)
      :string, # trace_id (32-char lowercase hex, or nil for an independent span)
      :string, # span_id (16-char lowercase hex, or nil for an independent span)
      :uint8,  # trace_flags
      :string  # trace_state (W3C tracestate header, or nil)
    ], :uint64 # returns span pointer (u64); falls back to an independent span on invalid context

    attach_function :create_batch_otel_span_with_trace_context, [
      :string, # trace_id (32-char lowercase hex, or nil for an independent span)
      :string, # span_id (16-char lowercase hex, or nil for an independent span)
      :uint8,  # trace_flags
      :string  # trace_state (W3C tracestate header, or nil)
    ], :uint64 # returns span pointer (u64); falls back to an independent batch span on invalid context

    attach_function :drop_otel_span, [
      :uint64 # span_ptr to close
    ], :void

    # Statistics function
    attach_function :get_statistics, [], Statistics.by_value # returns statistics by value
  end
end
