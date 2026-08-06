# frozen_string_literal: true

class Valkey
  # Internal holder for the native Pub/Sub push callback.
  # Pub/Sub API is not yet ready.
  #
  # @api private
  # @note EXPERIMENTAL: part of the unfinished Pub/Sub surface; not covered by
  #   semantic versioning.
  module PubSubCallback
    private

    # Invoked by libglide_ffi on an incoming Pub/Sub push message.
    #
    # @api private
    # @note EXPERIMENTAL: signature is dictated by the FFI callback contract and
    #   may change when full Pub/Sub support lands.
    def pubsub_callback(_client_ptr, kind, msg_ptr, msg_len, chan_ptr, chan_len, pat_ptr, pat_len)
      puts "PubSub received kind=#{kind}, message=#{msg_ptr.read_string(msg_len)}" \
           ", channel=#{chan_ptr.read_string(chan_len)}, pattern=#{pat_ptr.read_string(pat_len)}"
    end
  end
end
