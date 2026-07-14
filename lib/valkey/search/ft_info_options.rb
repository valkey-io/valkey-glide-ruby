# frozen_string_literal: true

class Valkey
  module Search
    # Options for the FT.INFO command.
    #
    # Controls which nodes provide index information in cluster mode.
    #
    # @example Local scope (default)
    #   Valkey::Search::FtInfoOptions.new(scope: :local)
    #
    # @example Cluster-wide info
    #   Valkey::Search::FtInfoOptions.new(scope: :cluster)
    #
    # @see https://valkey.io/commands/ft.info/
    class FtInfoOptions
      # @return [Symbol, nil] info scope (:local, :primary, or :cluster)
      attr_reader :scope

      # @return [Symbol, nil] shard scope (:allshards or :someshards)
      attr_reader :shard_scope

      # @return [Symbol, nil] consistency mode (:consistent or :inconsistent)
      attr_reader :consistency

      # @param scope [Symbol, nil] which nodes provide info:
      #   - +:local+ — only the executing node (default)
      #   - +:primary+ — primary nodes of every shard (cluster only)
      #   - +:cluster+ — all nodes including replicas (cluster only)
      # @param shard_scope [Symbol, nil] :allshards or :someshards
      # @param consistency [Symbol, nil] :consistent or :inconsistent
      def initialize(scope: nil, shard_scope: nil, consistency: nil)
        @scope = scope
        @shard_scope = shard_scope
        @consistency = consistency
      end

      # Serialize into the argument array appended after the index name
      # in FT.INFO.
      #
      # @return [Array<String>]
      def to_args
        args = []
        args << @scope.to_s.upcase if @scope
        args << @shard_scope.to_s.upcase if @shard_scope
        args << @consistency.to_s.upcase if @consistency
        args
      end
    end
  end
end
