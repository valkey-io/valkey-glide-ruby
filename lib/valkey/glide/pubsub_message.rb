# frozen_string_literal: true

class Valkey
  # GLIDE-specific public types, returned by APIs that have no redis-rb
  # equivalent. Internal members carry `@api private`.
  module Glide
    # A message delivered on a subscribed channel.
    #
    # @!attribute [rw] message
    #   @return [String] the published payload. Binary safe: embedded NUL bytes
    #     are preserved.
    # @!attribute [rw] channel
    #   @return [String] the channel the message was published to. For a
    #     pattern subscription this is the concrete channel that matched, not
    #     the pattern.
    # @!attribute [rw] pattern
    #   @return [String, nil] the pattern the subscription matched on, set only
    #     when the push was a `PMESSAGE`; `nil` for exact and sharded pushes.
    #
    # @see https://valkey.io/docs/topics/pubsub/
    PubSubMessage = Struct.new(:message, :channel, :pattern)
  end
end
