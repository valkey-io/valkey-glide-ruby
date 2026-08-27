# frozen_string_literal: true

class Valkey
  module Search
    # Options for FT.INFO. Valkey-native FT.INFO adds a scope (LOCAL / PRIMARY /
    # CLUSTER) plus the shared cluster flags (shard scope, consistency) on top of
    # the plain `FT.INFO <index>` form. Mirrors the Java FTInfoOptions surface,
    # adapted to Ruby idiom.
    #
    # @example
    #   Valkey::Search::InfoOptions.new(scope: :cluster, consistency: :consistent)
    #
    # @see https://redis.io/commands/ft.info/
    class InfoOptions
      SCOPES       = { local: "LOCAL", primary: "PRIMARY", cluster: "CLUSTER" }.freeze
      SHARD_SCOPES = SearchOptions::SHARD_SCOPES
      CONSISTENCY  = SearchOptions::CONSISTENCY

      # @param scope [Symbol, nil] :local, :primary, or :cluster
      # @param shard_scope [Symbol, nil] :all_shards or :some_shards
      # @param consistency [Symbol, nil] :consistent or :inconsistent
      def initialize(scope: nil, shard_scope: nil, consistency: nil)
        @scope = scope.nil? ? nil : Search.lookup_token(SCOPES, scope, "info scope")
        @shard_scope = shard_scope.nil? ? nil : Search.lookup_token(SHARD_SCOPES, shard_scope, "shard scope")
        @consistency = consistency.nil? ? nil : Search.lookup_token(CONSISTENCY, consistency, "consistency")
      end

      # @return [Array] FT.INFO option tokens (after `index`), in wire order
      def to_args
        args = []
        args << @scope unless @scope.nil?
        args << @shard_scope unless @shard_scope.nil?
        args << @consistency unless @consistency.nil?
        args
      end
    end
  end
end
