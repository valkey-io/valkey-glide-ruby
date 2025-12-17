# frozen_string_literal: true

require "valkey/commands/string_commands"
require "valkey/commands/connection_commands"
require "valkey/commands/server_commands"
require "valkey/commands/generic_commands"
require "valkey/commands/bitmap_commands"
require "valkey/commands/list_commands"
require "valkey/commands/geo_commands"
require "valkey/commands/hyper_log_log_commands"
require "valkey/commands/sorted_set_commands"
require "valkey/commands/set_commands"
require "valkey/commands/scripting_commands"
require "valkey/commands/function_commands"
require "valkey/commands/module_commands"
require "valkey/commands/pubsub_commands"
require "valkey/commands/json_commands"
require "valkey/commands/cluster_commands"
require "valkey/commands/transaction_commands"
require "valkey/commands/vector_search_commands"
require "valkey/commands/stream_commands"
require "valkey/commands/hash_commands"

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
    include HyperLogLogCommands
    include SortedSetCommands
    include SetCommands
    include ScriptingCommands
    include FunctionCommands
    include ModuleCommands
    include PubSubCommands
    include JsonCommands
    include ClusterCommands
    include TransactionCommands
    include VectorSearchCommands
    include StreamCommands
    include HashCommands

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
