# frozen_string_literal: true

class Valkey
  module Glide
    # A connection's subscriptions
    #
    # @!attribute [rw] desired_subscriptions
    #   @return [Hash{Symbol => Array<String>}] the subscriptions the client
    #     asked for, keyed `:exact`, `:pattern` and `:sharded`. Standalone
    #     connections omit `:sharded`.
    # @!attribute [rw] actual_subscriptions
    #   @return [Hash{Symbol => Array<String>}] the subscriptions the server has
    #     confirmed, keyed the same way.
    #
    # @see https://valkey.io/docs/topics/pubsub/
    PubSubState = Struct.new(:desired_subscriptions, :actual_subscriptions)
  end
end
