# frozen_string_literal: true

class Valkey
  module Commands
    module HyperLogLogCommands
      # Add one or more members to a HyperLogLog structure.
      #
      # @param [String] key
      # @param [String, Array<String>] member one member, or array of members
      # @return [Boolean] true if at least 1 HyperLogLog internal register was altered. false otherwise.
      #
      # @see https://valkey.io/commands/pfadd/
      def pfadd(key, member)
        args = [key]

        if member.is_a?(Array)
          args += member
        else
          args << member
        end

        send_command(RequestType::PFADD, args, &Utils::Boolify)
      end

      # Get the approximate cardinality of members added to HyperLogLog structure.
      #
      # If called with multiple keys, returns the approximate cardinality of the
      # union of the HyperLogLogs contained in the keys.
      #
      # @param [String, Array<String>] keys
      # @return [Integer]
      #
      # @see https://valkey.io/commands/pfcount
      def pfcount(*keys)
        send_command(RequestType::PFCOUNT, keys.flatten(1))
      end

      # Merge multiple HyperLogLog values into an unique value that will approximate the cardinality of the union of
      # the observed Sets of the source HyperLogLog structures.
      #
      # @param [String] dest_key destination key
      # @param [String, Array<String>] source_key source key, or array of keys
      # @return [Boolean]
      #
      # @see https://valkey.io/commands/pfmerge
      def pfmerge(dest_key, *source_key)
        send_command(RequestType::PFMERGE, [dest_key, *source_key], &Utils::BoolifySet)
      end
    end
  end
end
