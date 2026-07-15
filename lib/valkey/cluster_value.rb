# frozen_string_literal: true

class Valkey
  # Wraps a cluster command response when an explicit `route:` was provided.
  #
  # When a route fans out to multiple nodes (e.g. Route.all_primaries),
  # the value is a Hash of "host:port" => result. When routed to a single
  # node (e.g. Route.random), it holds that single result.
  #
  # Only returned when an explicit `route:` is passed to a command.
  # Without `route:`, commands return their normal redis-rb-compatible value.
  #
  # @example Multi-node
  #   cv = client.dbsize(route: Valkey::Route.all_primaries)
  #   cv.multi_node?  #=> true
  #   cv.multi_value  #=> { "10.0.0.1:6379" => 120, "10.0.0.2:6379" => 98 }
  #
  # @example Single-node
  #   cv = client.ping(route: Valkey::Route.random)
  #   cv.single_node? #=> true
  #   cv.single_value #=> "PONG"
  class ClusterValue
    attr_reader :value

    # @param value [Object] the raw response (single value or Hash of per-node results)
    # @param multi_node [Boolean] whether the route fanned out to multiple nodes
    def initialize(value, multi_node:)
      @value = value
      @multi_node = multi_node
    end

    # @return [Object] the single-node result
    def single_value
      @value
    end

    # @return [Hash<String, Object>] per-node results keyed by "host:port"
    def multi_value
      @value
    end

    # @return [Boolean] true if the response came from multiple nodes
    def multi_node?
      @multi_node
    end

    # @return [Boolean] true if the response came from a single node
    def single_node?
      !@multi_node
    end
  end
end
