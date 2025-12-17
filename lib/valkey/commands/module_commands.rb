# frozen_string_literal: true

class Valkey
  module Commands
    # This module contains commands related to Valkey Modules.
    #
    # @see https://valkey.io/commands/#module
    #
    module ModuleCommands
      # List all loaded modules.
      #
      # @example List all modules
      #   valkey.module_list
      #     # => [{"name" => "mymodule", "ver" => 1, ...}]
      #
      # @return [Array<Hash>] array of module information
      #
      # @see https://valkey.io/commands/module-list/
      def module_list
        send_command(RequestType::MODULE_LIST)
      end

      # Load a module.
      #
      # @example Load a module
      #   valkey.module_load("/path/to/mymodule.so")
      #     # => "OK"
      # @example Load a module with arguments
      #   valkey.module_load("/path/to/mymodule.so", "arg1", "arg2")
      #     # => "OK"
      #
      # @param [String] path the path to the module file
      # @param [Array<String>] args optional arguments to pass to the module
      # @return [String] "OK"
      #
      # @see https://valkey.io/commands/module-load/
      def module_load(path, *args)
        command_args = [path] + args
        send_command(RequestType::MODULE_LOAD, command_args)
      end

      # Unload a module.
      #
      # @example Unload a module
      #   valkey.module_unload("mymodule")
      #     # => "OK"
      #
      # @param [String] name the module name to unload
      # @return [String] "OK"
      #
      # @see https://valkey.io/commands/module-unload/
      def module_unload(name)
        send_command(RequestType::MODULE_UNLOAD, [name])
      end

      # Load a module with extended options.
      #
      # @example Load a module with CONFIG option
      #   valkey.module_loadex("/path/to/mymodule.so", configs: {"param1" => "value1"})
      #     # => "OK"
      # @example Load a module with ARGS option
      #   valkey.module_loadex("/path/to/mymodule.so", args: ["arg1", "arg2"])
      #     # => "OK"
      # @example Load a module with both CONFIG and ARGS
      #   valkey.module_loadex("/path/to/mymodule.so", configs: {"param1" => "value1"}, args: ["arg1"])
      #     # => "OK"
      #
      # @param [String] path the path to the module file
      # @param [Hash] configs configuration parameters as key-value pairs
      # @param [Array<String>] args optional arguments to pass to the module
      # @return [String] "OK"
      #
      # @see https://valkey.io/commands/module-loadex/
      def module_loadex(path, configs: {}, args: [])
        command_args = [path]

        unless configs.empty?
          command_args << "CONFIG"
          configs.each do |key, value|
            command_args << key.to_s
            command_args << value.to_s
          end
        end

        unless args.empty?
          command_args << "ARGS"
          command_args.concat(args)
        end

        send_command(RequestType::MODULE_LOAD_EX, command_args)
      end

      # Control module registry (convenience method).
      #
      # @example List all modules
      #   valkey.module(:list)
      #     # => [...]
      # @example Load a module
      #   valkey.module(:load, "/path/to/mymodule.so")
      #     # => "OK"
      # @example Unload a module
      #   valkey.module(:unload, "mymodule")
      #     # => "OK"
      # @example Load a module with extended options
      #   valkey.module(:loadex, "/path/to/mymodule.so", configs: {"param1" => "value1"})
      #     # => "OK"
      #
      # @param [String, Symbol] subcommand the subcommand (list, load, unload, loadex)
      # @param [Array] args arguments for the subcommand
      # @param [Hash] options options for the subcommand
      # @return [Object] depends on subcommand
      def module(subcommand, *args, **options)
        subcommand = subcommand.to_s.downcase

        if args.empty? && options.empty?
          send("module_#{subcommand}")
        elsif options.empty?
          send("module_#{subcommand}", *args)
        else
          send("module_#{subcommand}", *args, **options)
        end
      end
    end
  end
end
