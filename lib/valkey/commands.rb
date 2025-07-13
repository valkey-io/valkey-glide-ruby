# frozen_string_literal: true

require "valkey/commands/string_commands"
require "valkey/commands/connection_commands"
require "valkey/commands/server_commands"
require "valkey/commands/generic_commands"
require "valkey/commands/bitmap_commands"

class Valkey
  # Valkey commands module
  #
  # This module includes various command modules that provide methods
  # for interacting with a Valkey server. Each command module corresponds to a
  # specific set of commands that can be executed against the Valkey server.
  #
  # The commands are organized into groups based on their functionality,
  # such as string operations, connection management, server information,
  # key management, and bitmap operations.
  #
  # @see https://valkey.io/commands/ Valkey Commands Documentation
  #
  module Commands
    include StringCommands
    include ConnectionCommands
    include ServerCommands
    include GenericCommands
    include BitmapCommands

    # # Commands returning 1 for true and 0 for false may be executed in a pipeline
    # # where the method call will return nil. Propagate the nil instead of falsely
    # # returning false.
    # Boolify = lambda { |value|
    #   value != 0 unless value.nil?
    # }
    #
    # BoolifySet = lambda { |value|
    #   case value
    #   when "OK"
    #     true
    #   when nil
    #     false
    #   else
    #     value
    #   end
    # }
    HashifyInfo = lambda { |reply|
      lines = reply.split("\r\n").grep_v(/^(#|$)/)
      lines.map! { |line| line.split(':', 2) }
      lines.compact!
      lines.to_h
    }
  end
end
