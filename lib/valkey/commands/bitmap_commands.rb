# frozen_string_literal: true

class Valkey
  module Commands
    # this module contains commands related to BITMAP data type.
    #
    # @see https://valkey.io/commands/#bitmap
    #
    module BitmapCommands
      # Sets or clears the bit at offset in the string value stored at key.
      #
      # @param [String] key
      # @param [Integer] offset bit offset
      # @param [Integer] value bit value `0` or `1`
      # @return [Integer] the original bit value stored at `offset`
      def setbit(key, offset, value)
        send_command(RequestType::SET_BIT, [key, offset, value])
      end

      # Returns the bit value at offset in the string value stored at key.
      #
      # @param [String] key
      # @param [Integer] offset bit offset
      # @return [Integer] `0` or `1`
      def getbit(key, offset)
        send_command(RequestType::GET_BIT, [key, offset])
      end

      # Count the number of set bits in a range of the string value stored at key.
      #
      # @param [String] key
      # @param [Integer] start start index
      # @param [Integer] stop stop index
      # @param [String, Symbol] scale the scale of the offset range
      #     e.g. 'BYTE' - interpreted as a range of bytes, 'BIT' - interpreted as a range of bits
      # @return [Integer] the number of bits set to 1
      def bitcount(key, start = 0, stop = -1, scale: nil)
        args = [key, start, stop]
        args << scale if scale
        send_command(RequestType::BIT_COUNT, args)
      end

      # Perform a bitwise operation between strings and store the resulting string in a key.
      #
      # @param [String] operation e.g. `and`, `or`, `xor`, `not`
      # @param [String] destkey destination key
      # @param [String, Array<String>] keys one or more source keys to perform `operation`
      # @return [Integer] the length of the string stored in `destkey`
      def bitop(operation, destkey, *keys)
        keys.flatten!(1)
        args = [operation, destkey]
        args.concat(keys)

        send_command(RequestType::BIT_OP, args)
      end

      def bitfield(key, *args)
        send_command(RequestType::BIT_FIELD, [key] + args.map(&:to_s))
      end

      def bitfield_ro(key, *args)
        send_command(RequestType::BIT_FIELD_READ_ONLY, [key] + args.map(&:to_s))
      end

      # Return the position of the first bit set to 1 or 0 in a string.
      #
      # @param [String] key
      # @param [Integer] bit whether to look for the first 1 or 0 bit
      # @param [Integer] start start index
      # @param [Integer] stop stop index
      # @param [String, Symbol] scale the scale of the offset range
      #     e.g. 'BYTE' - interpreted as a range of bytes, 'BIT' - interpreted as a range of bits
      # @return [Integer] the position of the first 1/0 bit.
      #                  -1 if looking for 1 and it is not found or start and stop are given.
      def bitpos(key, bit, start = nil, stop = nil, scale: nil)
        raise(ArgumentError, 'stop parameter specified without start parameter') if stop && !start

        args = [key, bit]
        args << start if start
        args << stop if stop
        args << scale if scale
        send_command(RequestType::BIT_POS, args)
      end
    end
  end
end
