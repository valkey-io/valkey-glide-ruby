# frozen_string_literal: true

module Helper
  module Client
    include Generic

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
      Valkey.new(options.merge(port: PORT, timeout: TIMEOUT))
    end
  end
end
