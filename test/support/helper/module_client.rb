# frozen_string_literal: true

module Helper
  module ModuleClient
    class << self
      def standalone_address
        parse_endpoint(ENV.fetch("MODULES_STANDALONE_ENDPOINT", nil))
      end

      def cluster_addresses
        raw = ENV.fetch("MODULES_CLUSTER_ENDPOINTS", nil)
        return [] if raw.nil? || raw.empty?

        raw.split(",").map { |endpoint| parse_endpoint(endpoint) }
      end

      private

      def parse_endpoint(endpoint_str)
        if endpoint_str.nil? || endpoint_str.empty?
          raise "MODULES_STANDALONE_ENDPOINT/MODULES_CLUSTER_ENDPOINTS not set — run via " \
                "utils/run-modules-ci-locally.sh"
        end

        host, _, port = endpoint_str.strip.rpartition(":")
        { host: host, port: port.to_i }
      end
    end

    def modules_standalone_client(**options)
      address = Helper::ModuleClient.standalone_address
      Valkey.new(options.merge(host: address[:host], port: address[:port], timeout: TIMEOUT))
    end

    def modules_cluster_client(**options)
      nodes = Helper::ModuleClient.cluster_addresses
      Valkey.new(options.merge(cluster_mode: true, nodes: nodes, timeout: TIMEOUT))
    end
  end
end
