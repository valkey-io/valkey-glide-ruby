# frozen_string_literal: true

class Valkey
  # Represents a cluster routing directive. Passed as `route:` to commands
  # that support explicit cluster routing (no-key commands like DBSIZE, INFO,
  # PING, FLUSHALL, FUNCTION_*, etc.).
  #
  # When `route:` is provided the command response type depends on the route:
  # single-node routes return the value directly, multi-node routes return a
  # Hash of `"host:port" => value`.
  #
  # @example
  #   client.dbsize(route: Valkey::Route.all_primaries)
  #   client.ping(route: Valkey::Route.random)
  #   client.info(route: Valkey::Route.all_nodes)
  #
  # @see https://valkey.io/topics/cluster-spec
  class Route
    # RouteType enum values (mirrors glide-ffi RouteType C enum)
    ROUTE_ALL_NODES     = 0
    ROUTE_ALL_PRIMARIES = 1
    ROUTE_RANDOM        = 2
    ROUTE_SLOT_ID       = 3
    ROUTE_SLOT_KEY      = 4
    ROUTE_BY_ADDRESS    = 5

    # SlotType enum values (mirrors glide-ffi SlotType C enum)
    SLOT_PRIMARY = 0
    SLOT_REPLICA = 1

    attr_reader :multi_node
    alias multi_node? multi_node

    # Route to all nodes (primaries + replicas).
    # @note Don't use with write commands — they could be routed to replicas and fail.
    # @return [Route]
    def self.all_nodes
      new(ROUTE_ALL_NODES, multi_node: true)
    end

    # Route to all primary nodes.
    # @return [Route]
    def self.all_primaries
      new(ROUTE_ALL_PRIMARIES, multi_node: true)
    end

    # Route to a random node.
    # @note Don't use with write commands — they could be randomly routed to a replica and fail.
    # @return [Route]
    def self.random
      new(ROUTE_RANDOM, multi_node: false)
    end

    # Route to a specific slot by ID.
    # @param slot_id [Integer] slot number (0–16383)
    # @param slot_type [Symbol] :primary or :replica
    # @return [Route]
    def self.slot_id(slot_id, slot_type = :primary)
      route = new(ROUTE_SLOT_ID, multi_node: false)
      route.instance_variable_set(:@slot_id, slot_id.to_i)
      route.instance_variable_set(:@slot_type, slot_type == :replica ? SLOT_REPLICA : SLOT_PRIMARY)
      route
    end

    # Route to the node owning a specific key's slot.
    # @param key [String] the key whose slot determines routing
    # @param slot_type [Symbol] :primary or :replica
    # @return [Route]
    def self.slot_key(key, slot_type = :primary)
      route = new(ROUTE_SLOT_KEY, multi_node: false)
      route.instance_variable_set(:@slot_key, key.to_s)
      route.instance_variable_set(:@slot_type, slot_type == :replica ? SLOT_REPLICA : SLOT_PRIMARY)
      route
    end

    # Route to a specific node by address.
    # @param host [String] hostname or IP
    # @param port [Integer] port number
    # @return [Route]
    def self.by_address(host, port)
      route = new(ROUTE_BY_ADDRESS, multi_node: false)
      route.instance_variable_set(:@hostname, host.to_s)
      route.instance_variable_set(:@port, port.to_i)
      route
    end

    # Build the FFI RouteInfo struct for passing to command_with_route_info.
    #
    # Returns both the struct and any pinned memory buffers that must remain
    # alive until the FFI call completes.
    #
    # @return [Array(Bindings::RouteInfo, Array)] the struct and pinned buffers
    def to_ffi
      info = Bindings::RouteInfo.new
      info[:route_type] = @route_type
      info[:slot_id] = @slot_id || 0
      info[:slot_type] = @slot_type || SLOT_PRIMARY
      info[:port] = @port || 0

      pinned = [] # prevent GC of string buffers during FFI call
      info[:slot_key] = pin_string(@slot_key, pinned)
      info[:hostname] = pin_string(@hostname, pinned)

      [info, pinned]
    end

    private

    # Pin a string into an FFI pointer (or NULL if nil), appending the buffer
    # to +pinned+ so it is not garbage-collected before the FFI call completes.
    def pin_string(str, pinned)
      return FFI::Pointer::NULL unless str

      buf = FFI::MemoryPointer.from_string(str)
      pinned << buf
      buf
    end

    def initialize(route_type, multi_node:)
      @route_type = route_type
      @multi_node = multi_node
    end
  end
end
