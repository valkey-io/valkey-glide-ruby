# frozen_string_literal: true

class Valkey
  # Structured builder API for Valkey Search (FT.*) commands.
  module Search
    # Sort orders shared by FT.SEARCH SORTBY and FT.AGGREGATE SORTBY.
    SORT_ORDERS = { asc: "ASC", desc: "DESC" }.freeze
    # Cluster shard-scope flags shared by SEARCH/AGGREGATE/INFO.
    SHARD_SCOPES = { all_shards: "ALLSHARDS", some_shards: "SOMESHARDS" }.freeze
    # Cluster consistency flags shared by SEARCH/AGGREGATE/INFO.
    CONSISTENCY = { consistent: "CONSISTENT", inconsistent: "INCONSISTENT" }.freeze
    # Query dialects accepted by Valkey-native search (only DIALECT 2).
    DIALECTS = [2].freeze

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

    # Validate a DIALECT value against the Valkey-native supported set.
    #
    # @param dialect [Integer, nil] requested dialect (nil emits nothing)
    # @return [Integer, nil] the validated dialect
    # @raise [ArgumentError] when the dialect is unsupported
    def self.normalize_dialect(dialect)
      return nil if dialect.nil?
      return dialect if DIALECTS.include?(dialect)

      raise ArgumentError, "unsupported dialect #{dialect.inspect}; Valkey-native search supports #{DIALECTS.inspect}"
    end

    # Flatten a PARAMS hash to its `PARAMS <nargs> <k> <v>...` token run, or [] when
    # empty/nil. Keys are stringified; values pass through (coerced at the FFI
    # boundary).
    #
    # @param params [Hash, nil]
    # @return [Array] the PARAMS token run (empty when there are no params)
    def self.params_tokens(params)
      return [] if params.nil? || params.empty?

      flat = params.flat_map { |k, v| [k.to_s, v] }
      ["PARAMS", flat.length, *flat]
    end

    # Append pre-validated trailing cluster flag tokens (shard scope, then
    # consistency) to args, skipping nils. Callers validate/convert via
    # {lookup_token} at construction time so a bad value fails fast.
    #
    # @param args [Array] the token array being built (mutated in place)
    # @param shard_scope_token [String, nil] the wire token (e.g. "ALLSHARDS")
    # @param consistency_token [String, nil] the wire token (e.g. "CONSISTENT")
    # @return [Array] args
    def self.append_cluster_flags(args, shard_scope_token, consistency_token)
      args << shard_scope_token unless shard_scope_token.nil?
      args << consistency_token unless consistency_token.nil?
      args
    end
  end
end

require "valkey/search/fields"
require "valkey/search/create_options"
require "valkey/search/query"
require "valkey/search/aggregate"
require "valkey/search/info"
