# frozen_string_literal: true

class Valkey
  # A Pub/Sub message delivered on a subscribed channel.
  #
  # @!attribute [r] message
  #   @return [String] the published payload. Binary safe: embedded NUL bytes
  #     are preserved.
  # @!attribute [r] channel
  #   @return [String] the channel the message was published to. For a
  #     pattern subscription this is the concrete channel that matched, not
  #     the pattern.
  # @!attribute [r] pattern
  #   @return [String, nil] the pattern the subscription matched on, set only
  #     when the push was a `PMESSAGE`; `nil` for exact and sharded pushes.
  #
  # @see https://valkey.io/docs/topics/pubsub/
  class PubSubMessage
    attr_reader :message, :channel, :pattern

    # @param [String] message the published payload
    # @param [String] channel the channel the message was published to
    # @param [String, nil] pattern the matched pattern for a `PMESSAGE`
    def initialize(message:, channel:, pattern: nil)
      @message = message
      @channel = channel
      @pattern = pattern
    end
  end
end
