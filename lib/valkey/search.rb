# frozen_string_literal: true

class Valkey
  # Structured builder API for Valkey Search (FT.*) commands.
  module Search
    # Look up a symbol/string against a wire-token map, raising a uniform
    # ArgumentError on an unknown value. Shared by the enum-like option
    # validations (data type, distance metric, shard scope, consistency).
    #
    # @param map [Hash{Symbol=>String}] valid values mapped to wire tokens
    # @param value [Symbol, String] the caller-supplied value (case-insensitive)
    # @param label [String] human label for the error message
    # @return [String] the wire token
    # @raise [ArgumentError] when value is not a key of map
    def self.lookup_token(map, value, label)
      map.fetch(value.to_s.downcase.to_sym) do
        raise ArgumentError, "unknown #{label} #{value.inspect}; expected one of #{map.keys.inspect}"
      end
    end
  end
end

require "valkey/search/fields"
require "valkey/search/create_options"
