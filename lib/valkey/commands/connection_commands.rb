# frozen_string_literal: true

class Valkey
  module Commands
    # This module contains commands related to connection management.
    #
    # @see https://valkey.io/commands/#connection
    #
    module ConnectionCommands
      # Authenticate to the server.
      #
      # @param [Array<String>] args includes both username and password
      #   or only password
      # @return [String] `OK`
      def auth(*args)
        send_command(RequestType::AUTH, args)
      end

      # Ping the server.
      #
      # @param [optional, String] message
      # @return [String] `PONG`
      def ping(message = nil)
        send_command(RequestType::PING, [message].compact)
      end

      # Echo the given string.
      #
      # @param [String] value
      # @return [String]
      def echo(value)
        send_command(RequestType::ECHO, [value])
      end

      # Change the selected database for the current connection.
      #
      # @param [Integer] db zero-based index of the DB to use (0 to 15)
      # @return [String] `OK`
      def select(db)
        send_command(RequestType::SELECT, [db])
      end

      # Close the connection.
      #
      # @return [String] `OK`
      def quit
        # TODO: Implement a proper quit command
        # synchronize do |client|
        #   client.call_v([:quit])
        # rescue ConnectionError
        # ensure
        #   client.close
        # end
      end
    end
  end
end
