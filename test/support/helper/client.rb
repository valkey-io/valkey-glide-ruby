# frozen_string_literal: true

module Helper
  module Client
    include Generic

    @test_server = nil

    class << self
      attr_accessor :test_server

      def server_address
        if ENV["STANDALONE_ENDPOINTS"]
          parse_endpoint(ENV["STANDALONE_ENDPOINTS"])
        elsif test_server
          test_server.addresses.first
        else
          { host: "127.0.0.1", port: PORT }
        end
      end

      def start_server
        return if test_server || ENV["STANDALONE_ENDPOINTS"]

        @test_server = Valkey::TestCluster.new(
          cluster_mode: false,
          tls: ENV["STANDALONE_TLS"] == "true",
          replica_count: 0,
          load_module: parse_module_paths(ENV["STANDALONE_MODULES"])
        )
      end

      def stop_server
        test_server&.close
        @test_server = nil
      end

      private

      def parse_endpoint(endpoint_str)
        return { host: "127.0.0.1", port: PORT } if endpoint_str.nil? || endpoint_str.empty?

        parts = endpoint_str.strip.rpartition(":")
        host = parts[0]
        port_str = parts[2]
        { host: host, port: port_str.to_i }
      end

      def parse_module_paths(modules_str)
        return nil if modules_str.nil? || modules_str.empty?

        modules_str.split(",").map(&:strip)
      end
    end

    def init(valkey)
      valkey.select 14
      valkey.flushdb
      valkey.select 15
      valkey.flushdb
      valkey
    rescue Valkey::CannotConnectError
      puts <<-MSG
        Cannot connect to Valkey.

        Make sure Valkey is running on localhost, port #{PORT}.
        This testing suite connects to the database 15.
      MSG
      exit 1
    end

    def cluster_mode?
      false
    end

    private

    def _new_client(options = {})
      address = Helper::Client.server_address
      Valkey.new(options.merge(host: address[:host], port: address[:port], timeout: TIMEOUT))
    end
  end
end
