# frozen_string_literal: true

module Helper
  module Cluster
    include Generic

    def init(valkey)
      valkey.flushdb
      valkey
    rescue Valkey::CannotConnectError
      puts <<-MSG
        Cannot connect to Valkey.

        Make sure Valkey Cluster Node is running on localhost, port #{PORT_CLUSTER_MODE}.
      MSG
      exit 1
    end

    # TODO: it has to come from the server
    def version
      '7.0'
    end

    private

    def _new_client(options = {})
      Valkey.new(options.merge(nodes: CLUSTER_NODES, timeout: TIMEOUT, cluster_mode: true))
    end
  end
end
