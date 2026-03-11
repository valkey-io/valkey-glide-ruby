# frozen_string_literal: true

class Valkey
  module PubSubCallback
    def pubsub_callback(_client_ptr, kind, msg_ptr, msg_len, chan_ptr, chan_len, pat_ptr, pat_len)
      puts "PubSub received kind=#{kind}, message=#{msg_ptr.read_string(msg_len)}" \
           ", channel=#{chan_ptr.read_string(chan_len)}, pattern=#{pat_ptr.read_string(pat_len)}"
    end
  end
end
