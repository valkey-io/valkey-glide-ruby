# frozen_string_literal: true

class Valkey
  module Glide
    # A connection's subscriptions
    #
    # @!attribute [rw] desired_subscriptions
    #   @return [Hash{Symbol => Array<String>}] the subscriptions the client asked for, keyed
    #     `:exact`, `:pattern` and `:sharded`. If empty, then the client has no desired
    #     subscriptions. Otherwise each mode maps to its channels, for example
    #     `{ exact: ["channel1"] }`. A targeted unsubscribe may leave `{ exact: [] }`, while
    #     unsubscribe-all removes `:exact`. Treat these states equivalently, for example with
    #     `desired_subscriptions.fetch(:exact, [])`.
    # @!attribute [rw] actual_subscriptions
    #   @return [Hash{Symbol => Array<String>}] the subscriptions the server has confirmed, keyed
    #     the same way. Each mode maps to its confirmed channels, for example
    #     `{ exact: ["channel1"], pattern: [] }`. Every supported mode is present, mapped to `[]`
    #     when it has no confirmed subscriptions: `:exact` and `:pattern` on standalone, plus
    #     `:sharded` in cluster mode.
    #
    # @see https://valkey.io/docs/topics/pubsub/
    PubSubState = Struct.new(:desired_subscriptions, :actual_subscriptions) do
      # Build a state from the raw `GET_SUBSCRIPTIONS` reply.
      #
      # glide-core answers this synthetic request locally rather than on the wire, always as a
      # labelled 4-element array, `["desired", {modes}, "actual", {modes}]`, whose mode maps are
      # keyed by the capitalized mode name (`"Exact"`, `"Pattern"`, `"Sharded"`).
      #
      # @param [Array] reply the raw reply
      # @return [PubSubState]
      # @raise [Valkey::CommandError] if the reply is not the expected labelled 4-element array
      def self.from_reply(reply)
        reject_reply(reply) unless reply.is_a?(Array) && reply.size == 4

        desired_label, desired, actual_label, actual = reply
        reject_reply(reply) unless desired_label == "desired" && actual_label == "actual"

        new(symbolize_modes(desired), symbolize_modes(actual))
      end

      def self.symbolize_modes(payload)
        Utils::Hashify.call(payload).to_h do |mode, channels|
          [mode.to_s.downcase.to_sym, Array(channels).map(&:to_s).uniq]
        end
      end
      private_class_method :symbolize_modes

      def self.reject_reply(reply)
        raise Valkey::CommandError,
              "Unexpected GET_SUBSCRIPTIONS response: expected " \
              "[\"desired\", {modes}, \"actual\", {modes}], got: #{reply.inspect}"
      end
      private_class_method :reject_reply
    end
  end
end
