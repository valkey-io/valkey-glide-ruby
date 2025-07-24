# frozen_string_literal: true

class Valkey
  class Pipeline
    include Commands

    attr_reader :commands

    def initialize
      @commands = []
    end

    def send_command(command_type, command_args = [], &block)
      @commands << [command_type, command_args, block]
    end
  end
end
