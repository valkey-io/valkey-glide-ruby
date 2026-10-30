# frozen_string_literal: true

class Valkey
  module Glide
    # A connection's subscriptions
    #
    # @!attribute [r] desired_subscriptions
    #   @return [Hash{Symbol => Array<String>}] the subscriptions the client asked for, keyed
    #     `:exact`, `:pattern` and `:sharded`. If empty, then the client has no desired
    #     subscriptions. Otherwise each mode maps to its channels, for example
    #     `{ exact: ["channel1"] }`. A targeted unsubscribe may leave `{ exact: [] }`, while
    #     unsubscribe-all removes `:exact`. Treat these states equivalently, for example with
    #     `desired_subscriptions.fetch(:exact, [])`.
    # @!attribute [r] actual_subscriptions
    #   @return [Hash{Symbol => Array<String>}] the subscriptions the server has confirmed, keyed
    #     the same way. Each mode maps to its confirmed channels, for example
    #     `{ exact: ["channel1"], pattern: [] }`. Every supported mode is present, mapped to `[]`
    #     when it has no confirmed subscriptions: `:exact` and `:pattern` on standalone, plus
    #     `:sharded` in cluster mode.
    #
    # @see https://valkey.io/docs/topics/pubsub/
    class PubSubState
      attr_reader :desired_subscriptions, :actual_subscriptions

      # @param [Hash{Symbol => Array<String>}] desired_subscriptions
      # @param [Hash{Symbol => Array<String>}] actual_subscriptions
      def initialize(desired_subscriptions:, actual_subscriptions:)
        @desired_subscriptions = desired_subscriptions
        @actual_subscriptions = actual_subscriptions
      end

      # Build a state from the raw `GET_SUBSCRIPTIONS` reply.
      #
      # @example Cluster client subscribed to one exact channel
      #   reply = [
      #     "desired", { "Exact" => ["news"] },
      #     "actual",  { "Exact" => ["news"], "Pattern" => [], "Sharded" => [] }
      #   ]
      #   state = PubSubState.from_reply(reply)
      #   state.desired_subscriptions # => { exact: ["news"] }
      #   state.actual_subscriptions  # => { exact: ["news"], pattern: [], sharded: [] }
      #
      # @param [Array] reply the raw reply
      # @return [PubSubState]
      # @raise [Valkey::CommandError] if the reply is not the expected labelled 4-element array
      def self.from_reply(reply)
        reject_reply(reply) unless reply.is_a?(Array) && reply.size == 4

        desired_label, desired, actual_label, actual = reply
        reject_reply(reply) unless desired_label == "desired" && actual_label == "actual"

        new(desired_subscriptions: symbolize_modes(desired), actual_subscriptions: symbolize_modes(actual))
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
