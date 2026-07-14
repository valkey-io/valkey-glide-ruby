# frozen_string_literal: true

module Helper
  module Cluster
    include Generic

    @test_cluster = nil

    class << self
      attr_accessor :test_cluster

      def cluster_addresses
        if ENV["CLUSTER_ENDPOINTS"]
          parse_endpoints(ENV["CLUSTER_ENDPOINTS"])
        elsif test_cluster
          test_cluster.addresses
        else
          start_cluster
          test_cluster.addresses
        end
      end

      def start_cluster
        return if test_cluster

        @test_cluster = Valkey::TestCluster.new(
          cluster_mode: true,
          tls: ENV["CLUSTER_TLS"] == "true",
          load_module: parse_module_paths(ENV.fetch("CLUSTER_MODULES", nil))
        )
      end

      def stop_cluster
        test_cluster&.close
        @test_cluster = nil
      end

      private

      def parse_endpoints(endpoints_str)
        return [] if endpoints_str.nil? || endpoints_str.empty?

        endpoints_str.split(",").map do |endpoint|
          parts = endpoint.strip.rpartition(":")
          host = parts[0]
          port_str = parts[2]
          { host: host, port: port_str.to_i }
        end
      end

      def parse_module_paths(modules_str)
        return nil if modules_str.nil? || modules_str.empty?

        modules_str.split(",").map(&:strip)
      end
    end

    def init(valkey)
      valkey.flushdb
      valkey
    rescue Valkey::CannotConnectError
      puts <<-MSG
        Cannot connect to Valkey.

        Make sure Valkey Cluster Node is running on localhost, port #{PORT_CLUSTER_MODE}.
      MSG
      exit 1
    rescue Valkey::CommandError => e
      # In cluster mode, flushdb might hit a read-only replica
      # This is acceptable during test setup
      raise unless e.message.include?("ReadOnly") || e.message.include?("read only replica")

      valkey
    end

    # Query actual server version from the cluster. Falls back to "0.0" if
    # detection fails so that version-gated tests skip rather than error.
    def version
      info = valkey.info
      ver = extract_version_from_info(info)
      Version.new(ver || "0.0")
    rescue StandardError
      Version.new("0.0")
    end

    def cluster_mode?
      true
    end

    private

    def extract_version_from_info(info)
      case info
      when Hash
        info["valkey_version"] || info["redis_version"]
      when Array
        # Could be array of node responses; try first element
        first = info.first
        extract_version_from_info(first)
      when String
        # Raw INFO string — parse valkey_version or redis_version
        ::Regexp.last_match(1) if info =~ /(?:valkey|redis)_version:(\S+)/
      end
    end

    def _new_client(options = {})
      addresses = Helper::Cluster.cluster_addresses
      nodes = addresses.empty? ? CLUSTER_NODES : addresses
      Valkey.new(options.merge(nodes: nodes, timeout: TIMEOUT, cluster_mode: true))
    end
  end
end
