# frozen_string_literal: true

require "uri"

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
      return value if value.is_a?(TrueClass) || value.is_a?(FalseClass)

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
      if value.is_a?(Hash)
        value
      elsif value.respond_to?(:each_slice)
        if value.first.is_a?(Array)
          value.to_h
        else
          value.each_slice(2).to_h
        end
      else
        value
      end
    }

    Pairify = lambda { |value|
      if value.respond_to?(:each_slice)
        if value.first.is_a?(Array)
          value
        else
          value.each_slice(2).to_a
        end
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

      if value.first.is_a?(Array)
        value.map(&FloatifyPair)
      else
        value.each_slice(2).map(&FloatifyPair)
      end
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
      return [] if reply.nil?

      # In cluster mode, MAP responses come as Hash: {id => [fields], ...}
      if reply.is_a?(Hash)
        return reply.map { |entry_id, values| [entry_id, values.is_a?(Array) ? values.flatten : []] }
      end

      return [] if !reply.is_a?(Array) || reply.empty?

      # Reply format: [[entry_id, [field1, value1, field2, value2, ...]], ...]
      # Match redis-rb: return flat arrays [["id", ["field", "value", ...]], ...]
      # Check if first element is a pair [entry_id, values_array]
      first_elem = reply.first
      if first_elem.is_a?(Array) && first_elem.length == 2
        # Already in pair format: [[entry_id, [fields...]], ...]
        reply.compact.map do |entry_id, values|
          # Return flat array format like redis-rb, not hash
          values_array = if values.nil?
                           []
                         elsif values.is_a?(Array)
                           values
                         else
                           []
                         end
          [entry_id, values_array]
        end
      else
        # Flat array format: [entry_id1, [field1, value1, ...], entry_id2, [field2, value2, ...], ...]
        reply.compact.each_slice(2).map do |entry_id, values|
          # Return flat array format like redis-rb, not hash
          values_array = if values.nil?
                           []
                         elsif values.is_a?(Array)
                           values
                         else
                           []
                         end
          [entry_id, values_array]
        end
      end
    }

    HashifyStreamAutoclaim = lambda { |reply|
      {
        'next' => reply[0],
        'entries' => if reply[1].nil?
                       []
                     elsif reply[1].is_a?(Array)
                       # Reply[1] is already an array of entries: [[id, [field, value, ...]], ...]
                       # Use HashifyStreamEntries to convert them properly
                       HashifyStreamEntries.call(reply[1])
                     else
                       []
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
      arr = str.split
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

    # Parse a Valkey/Redis connection URL.
    #
    # Accepted schemes: redis, rediss, valkey, valkeys. TLS is enabled for the
    # `rediss` and `valkeys` variants. Matches the URI format documented for
    # valkey-cli (`valkey://user:password@host:port/dbnum`).
    #
    # @param [String] url Connection URL to parse
    # @return [Hash] Parsed options with keys :host, :port, :ssl,
    #   and optionally :username, :password, :db. Returns {} for nil / "".
    # @raise [ArgumentError] if the URL is malformed, has an unsupported
    #   scheme, is missing a host, or has a non-integer db path.
    # @example
    #   parse_redis_url('redis://:secret@localhost:6379/15')
    #   # => { host: 'localhost', port: 6379, password: 'secret', db: 15, ssl: false }
    #
    #   parse_redis_url('valkeys://user:secret@localhost:6380/0')
    #   # => { host: 'localhost', port: 6380, username: 'user', password: 'secret', db: 0, ssl: true }
    ALLOWED_URL_SCHEMES = %w[redis rediss valkey valkeys].freeze
    TLS_URL_SCHEMES = %w[rediss valkeys].freeze
    private_constant :ALLOWED_URL_SCHEMES, :TLS_URL_SCHEMES

    def self.parse_redis_url(url)
      return {} unless url.is_a?(String) && !url.empty?

      # Redact userinfo before it ends up in error messages, logs, or trackers.
      # The regex greedily consumes up to the LAST `@` after `://`, so passwords
      # containing `/` or `@` are still fully redacted (RFC 3986 allows both in
      # percent-decoded form; either can appear raw in a user-supplied URL).
      redacted = url.sub(%r{(\A[^:]+://).*@}, '\1[REDACTED]@').inspect

      uri = begin
        URI.parse(url)
      rescue URI::InvalidURIError
        raise ArgumentError, "Invalid Valkey URL #{redacted}: URI could not be parsed"
      end

      unless ALLOWED_URL_SCHEMES.include?(uri.scheme)
        raise ArgumentError,
              "Invalid Valkey URL #{redacted}: scheme must be one of " \
              "#{ALLOWED_URL_SCHEMES.join(', ')}, got #{uri.scheme.inspect}"
      end

      host = uri.hostname
      raise ArgumentError, "Invalid Valkey URL #{redacted}: missing host" if host.to_s.empty?

      result = {
        host: host,
        port: uri.port || 6379,
        ssl: TLS_URL_SCHEMES.include?(uri.scheme)
      }

      db_segment = uri.path.to_s.delete_prefix('/')
      unless db_segment.empty?
        unless db_segment.match?(/\A\d+\z/)
          raise ArgumentError, "Invalid Valkey URL #{redacted}: database must be a non-negative integer"
        end

        result[:db] = db_segment.to_i
      end

      result[:username] = uri.user if uri.user && !uri.user.empty?
      result[:password] = uri.password if uri.password && !uri.password.empty?

      result
    end
  end
end
