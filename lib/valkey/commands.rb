# frozen_string_literal: true

require "valkey/commands/string_commands"
require "valkey/commands/connection_commands"
require "valkey/commands/server_commands"
require "valkey/commands/generic_commands"
require "valkey/commands/bitmap_commands"
require "valkey/commands/list_commands"
require "valkey/commands/geo_commands"

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
    include ListCommands
    include GeoCommands

    # there are a few commands that are not implemented by design
    #
    # raises CommandError when called
    #
    %i[keys].each do |command|
      define_method command do |*_args|
        raise CommandError, "Unsupported command: #{command}"
      end
    end
  end
end
