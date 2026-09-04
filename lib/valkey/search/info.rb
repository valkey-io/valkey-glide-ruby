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
      # @param scope [Symbol, nil] :local, :primary, or :cluster
      # @param shard_scope [Symbol, nil] :all_shards or :some_shards
      # @param consistency [Symbol, nil] :consistent or :inconsistent
      def initialize(scope: nil, shard_scope: nil, consistency: nil)
        @scope = scope.nil? ? nil : Search.lookup_token(Search::SCOPES, scope, "info scope")
        @shard_scope = shard_scope.nil? ? nil : Search.lookup_token(Search::SHARD_SCOPES, shard_scope, "shard scope")
        @consistency = consistency.nil? ? nil : Search.lookup_token(Search::CONSISTENCY, consistency, "consistency")
      end

      # @return [Array] FT.INFO option tokens (after `index`), in wire order
      def to_args
        args = []
        args << @scope unless @scope.nil?
        Search.append_cluster_flags(args, @shard_scope, @consistency)
        args
      end
    end
  end
end
