# frozen_string_literal: true

module Helper
  module Client
    include Generic

    class << self
      def server_address
        if ENV["STANDALONE_ENDPOINTS"]
          parse_endpoint(ENV["STANDALONE_ENDPOINTS"])
        else
          { host: "127.0.0.1", port: PORT }
        end
      end

      private

      def parse_endpoint(endpoint_str)
        return { host: "127.0.0.1", port: PORT } if endpoint_str.nil? || endpoint_str.empty?

        parts = endpoint_str.strip.rpartition(":")
        host = parts[0]
        port_str = parts[2]
        { host: host, port: port_str.to_i }
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
