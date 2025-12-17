# frozen_string_literal: true

class Valkey
  class Pipeline
    include Commands

    attr_reader :commands

    def initialize
      @commands = []
      # Keep transactional state consistent with the main client so that
      # helpers like `multi`/`exec` can safely consult `@in_multi`.
      @in_multi = false
    end

    def send_command(command_type, command_args = [], &block)
      @commands << [command_type, command_args, block]
    end
  end
end
