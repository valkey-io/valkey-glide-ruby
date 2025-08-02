# frozen_string_literal: true

class Valkey
  # Valkey Utils module
  #
  # This module provides utility functions for transforming and processing
  # data structures commonly used in Valkey commands.
  #
  # It includes methods for converting values to boolean, hash, or float,
  # as well as methods for handling specific Valkey command responses.
  #
  module Utils
    Boolify = lambda { |value|
      value != 0 unless value.nil?
    }

    BoolifySet = lambda { |value|
      case value
      when "OK"
        true
      when nil
        false
      else
        value
      end
    }

    Hashify = lambda { |value|
      if value.respond_to?(:each_slice)
        value.each_slice(2).to_h
      else
        value
      end
    }

    Pairify = lambda { |value|
      if value.respond_to?(:each_slice)
        value.each_slice(2).to_a
      else
        value
      end
    }

    Floatify = lambda { |value|
      case value
      when "inf"
        Float::INFINITY
      when "-inf"
        -Float::INFINITY
      when String
        Float(value)
      else
        value
      end
    }

    FloatifyPair = lambda { |(first, score)|
      [first, Floatify.call(score)]
    }

    FloatifyPairs = lambda { |value|
      return value unless value.respond_to?(:each_slice)

      value.each_slice(2).map(&FloatifyPair)
    }

    HashifyInfo = lambda { |reply|
      lines = reply.split("\r\n").grep_v(/^(#|$)/)
      lines.map! { |line| line.split(':', 2) }
      lines.compact!
      lines.to_h
    }

    HashifyStreams = lambda { |reply|
      case reply
      when nil
        {}
      else
        reply.transform_values { |entries| HashifyStreamEntries.call(entries) }
      end
    }

    EMPTY_STREAM_RESPONSE = [nil].freeze
    private_constant :EMPTY_STREAM_RESPONSE

    HashifyStreamEntries = lambda { |reply|
      reply.compact.map do |entry_id, values|
        [entry_id, values&.each_slice(2)&.to_h]
      end
    }

    HashifyStreamAutoclaim = lambda { |reply|
      {
        'next' => reply[0],
        'entries' => reply[1].compact.map do |entry, values|
          [entry, values.each_slice(2)&.to_h]
        end
      }
    }

    HashifyStreamAutoclaimJustId = lambda { |reply|
      {
        'next' => reply[0],
        'entries' => reply[1]
      }
    }

    HashifyStreamPendings = lambda { |reply|
      {
        'size' => reply[0],
        'min_entry_id' => reply[1],
        'max_entry_id' => reply[2],
        'consumers' => reply[3].nil? ? {} : reply[3].to_h
      }
    }

    HashifyStreamPendingDetails = lambda { |reply|
      reply.map do |arr|
        {
          'entry_id' => arr[0],
          'consumer' => arr[1],
          'elapsed' => arr[2],
          'count' => arr[3]
        }
      end
    }

    HashifyClusterNodeInfo = lambda { |str|
      arr = str.split(' ')
      {
        'node_id' => arr[0],
        'ip_port' => arr[1],
        'flags' => arr[2].split(','),
        'master_node_id' => arr[3],
        'ping_sent' => arr[4],
        'pong_recv' => arr[5],
        'config_epoch' => arr[6],
        'link_state' => arr[7],
        'slots' => arr[8].nil? ? nil : Range.new(*arr[8].split('-'))
      }
    }

    HashifyClusterSlots = lambda { |reply|
      reply.map do |arr|
        first_slot, last_slot = arr[0..1]
        master = { 'ip' => arr[2][0], 'port' => arr[2][1], 'node_id' => arr[2][2] }
        replicas = arr[3..].map { |r| { 'ip' => r[0], 'port' => r[1], 'node_id' => r[2] } }
        {
          'start_slot' => first_slot,
          'end_slot' => last_slot,
          'master' => master,
          'replicas' => replicas
        }
      end
    }

    HashifyClusterNodes = lambda { |reply|
      reply.split(/[\r\n]+/).map { |str| HashifyClusterNodeInfo.call(str) }
    }

    HashifyClusterSlaves = lambda { |reply|
      reply.map { |str| HashifyClusterNodeInfo.call(str) }
    }

    Noop = ->(reply) { reply }
  end
end
