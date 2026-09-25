# frozen_string_literal: true

require "English"
require "securerandom"

# Pub/Sub subscription and message-delivery combination tests.
module ValkeyTests
  module PubSub
    SUBSCRIPTION_METHODS = %i[config lazy blocking].freeze
    MESSAGE_READ_METHODS = %i[blocking_get polling_try_get callback].freeze
    MATRIX_SUBSCRIPTION_MODES = %i[exact pattern sharded].freeze
    MATRIX_BULK_MESSAGE_WAIT_SECONDS = 10.0
    MATRIX_NO_MESSAGE_WAIT_SECONDS = 3.0
    MATRIX_RECONNECT_PUBLISH_ATTEMPTS = 5
    MATRIX_RECONNECT_POLL_SECONDS = 3.0
    MATRIX_RECONNECT_POLL_INTERVAL_SECONDS = 0.1

    def self.parameterized_test(name, topologies:, **parameters, &test_body)
      parameter_names = parameters.keys

      parameters.values.first.product(*parameters.values.drop(1)).each do |values|
        parameter_suffix = parameter_names.zip(values).map { |key, value| "#{key}_#{value}" }.join("_and_")

        define_method(:"#{name}_with_#{parameter_suffix}") do
          topology = cluster_mode? ? :cluster : :standalone
          skip "#{name} does not apply to #{topology}" unless topologies.include?(topology)

          instance_exec(*values, &test_body)
        end
      end
    end
    private_class_method :parameterized_test

    parameterized_test(
      :test_sync_pubsub_exact_happy_path,
      topologies: %i[standalone cluster],
      method: MESSAGE_READ_METHODS,
      subscription_method: SUBSCRIPTION_METHODS
    ) do |method, subscription_method|
      assert_exact_pubsub_matrix_case(subscription_method, method)
    end

    parameterized_test(
      :test_sync_pubsub_exact_happy_path_coexistence,
      topologies: %i[standalone cluster],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |subscription_method|
      assert_exact_pubsub_coexistence_matrix_case(subscription_method)
    end

    # PySync parameterized tests retained because Ruby coverage is missing or partial.
    # cluster_mode is omitted because topology is supplied by suite inclusion.
    parameterized_test(
      :test_sync_pubsub_exact_happy_path_many_channels,
      topologies: %i[standalone cluster],
      method: MESSAGE_READ_METHODS,
      subscription_method: SUBSCRIPTION_METHODS
    ) do |method, subscription_method|
      assert_exact_pubsub_many_channels_matrix_case(subscription_method, method)
    end

    parameterized_test(
      :test_sync_pubsub_exact_happy_path_many_channels_co_existence,
      topologies: %i[standalone cluster],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |subscription_method|
      assert_exact_pubsub_many_channels_coexistence_matrix_case(subscription_method)
    end

    parameterized_test(
      :test_sync_sharded_pubsub,
      topologies: %i[cluster],
      method: MESSAGE_READ_METHODS,
      subscription_method: SUBSCRIPTION_METHODS
    ) do |method, subscription_method|
      assert_sharded_pubsub_matrix_case(subscription_method, method)
    end

    parameterized_test(
      :test_sync_sharded_pubsub_co_existence,
      topologies: %i[cluster],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |subscription_method|
      skip_unless_sharded_pubsub
      assert_sharded_pubsub_coexistence_matrix_case(subscription_method)
    end

    parameterized_test(
      :test_sync_sharded_pubsub_many_channels,
      topologies: %i[cluster],
      subscription_method: SUBSCRIPTION_METHODS,
      method: MESSAGE_READ_METHODS
    ) do |subscription_method, method|
      assert_sharded_pubsub_many_channels_matrix_case(subscription_method, method)
    end

    parameterized_test(
      :test_sync_pubsub_pattern,
      topologies: %i[standalone cluster],
      method: MESSAGE_READ_METHODS,
      subscription_method: SUBSCRIPTION_METHODS
    ) do |method, subscription_method|
      assert_pattern_pubsub_messages_matrix_case(subscription_method, method, message_count: 2)
    end

    parameterized_test(
      :test_sync_pubsub_pattern_co_existence,
      topologies: %i[standalone cluster],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |subscription_method|
      assert_pattern_pubsub_coexistence_matrix_case(subscription_method)
    end

    parameterized_test(
      :test_sync_pubsub_pattern_many_channels,
      topologies: %i[standalone cluster],
      method: MESSAGE_READ_METHODS,
      subscription_method: SUBSCRIPTION_METHODS
    ) do |method, subscription_method|
      assert_pattern_pubsub_many_channels_matrix_case(subscription_method, method)
    end

    parameterized_test(
      :test_sync_pubsub_combined_exact_and_pattern_one_client,
      topologies: %i[standalone cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |method, subscription_method|
      assert_combined_exact_and_pattern_one_client_matrix_case(subscription_method, method)
    end

    parameterized_test(
      :test_sync_pubsub_combined_exact_and_pattern_multiple_clients,
      topologies: %i[standalone cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |method, subscription_method|
      assert_combined_exact_and_pattern_multiple_clients_matrix_case(subscription_method, method)
    end

    parameterized_test(
      :test_sync_pubsub_combined_exact_pattern_and_sharded_one_client,
      topologies: %i[cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |method, subscription_method|
      assert_combined_exact_pattern_sharded_one_client_matrix_case(subscription_method, method)
    end

    parameterized_test(
      :test_sync_pubsub_combined_exact_pattern_and_sharded_multi_client,
      topologies: %i[cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |method, subscription_method|
      skip_unless_sharded_pubsub
      assert_combined_exact_pattern_sharded_multi_client_matrix_case(subscription_method, method)
    end

    parameterized_test(
      :test_sync_pubsub_combined_different_channels_with_same_name,
      topologies: %i[cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |method, subscription_method|
      assert_combined_different_channels_with_same_name_matrix_case(subscription_method, method)
    end

    parameterized_test(
      :test_sync_pubsub_two_publishing_clients_same_name,
      topologies: %i[standalone cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |method, subscription_method|
      assert_two_publishing_clients_same_name_matrix_case(subscription_method, method)
    end

    parameterized_test(
      :test_sync_pubsub_three_publishing_clients_same_name_with_sharded,
      topologies: %i[cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |method, subscription_method|
      assert_three_publishing_clients_same_name_with_sharded_matrix_case(subscription_method, method)
    end

    parameterized_test(
      :test_sync_pubsub_exact_max_size_message_callback,
      topologies: %i[standalone cluster],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |subscription_method|
      assert_exact_max_size_message_callback_matrix_case(subscription_method)
    end

    parameterized_test(
      :test_sync_pubsub_sharded_large_size_message_callback,
      topologies: %i[cluster],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |subscription_method|
      assert_sharded_large_size_message_callback_matrix_case(subscription_method)
    end

    parameterized_test(
      :test_sync_unsubscribe_exact_channel,
      topologies: %i[standalone cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: %i[lazy blocking]
    ) do |method, subscription_method|
      assert_unsubscribe_exact_channel_matrix_case(method, subscription_method)
    end

    parameterized_test(
      :test_sync_lazy_client_multiple_subscription_types,
      topologies: %i[standalone cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |method, subscription_method|
      assert_lazy_client_multiple_subscription_types_matrix_case(method, subscription_method)
    end

    parameterized_test(
      :test_sync_punsubscribe_pattern,
      topologies: %i[standalone cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: %i[lazy blocking]
    ) do |method, subscription_method|
      assert_punsubscribe_pattern_matrix_case(method, subscription_method)
    end

    parameterized_test(
      :test_sync_sunsubscribe_sharded_channel,
      topologies: %i[cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: %i[lazy blocking]
    ) do |method, subscription_method|
      assert_sunsubscribe_sharded_channel_matrix_case(method, subscription_method)
    end

    parameterized_test(
      :test_sync_unsubscribe_all_subscription_types,
      topologies: %i[standalone cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: %i[lazy blocking]
    ) do |method, subscription_method|
      assert_unsubscribe_all_subscription_types_matrix_case(subscription_method, method)
    end

    parameterized_test(
      :test_sync_pubsub_exact_happy_path_custom_command,
      topologies: %i[standalone cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: %i[lazy blocking]
    ) do |method, subscription_method|
      assert_exact_pubsub_custom_command_matrix_case(subscription_method, method)
    end

    parameterized_test(
      :test_sync_resubscribe_after_connection_kill_exact_channels,
      topologies: %i[standalone cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: %i[config lazy blocking]
    ) do |method, subscription_method|
      assert_resubscribe_exact_after_connection_kill_matrix_case(method, subscription_method)
    end

    parameterized_test(
      :test_sync_resubscribe_after_connection_kill_patterns,
      topologies: %i[standalone cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: %i[config lazy blocking]
    ) do |method, subscription_method|
      assert_resubscribe_pattern_after_connection_kill_matrix_case(method, subscription_method)
    end

    parameterized_test(
      :test_sync_ssubscribe_channels_different_slots,
      topologies: %i[cluster],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |subscription_method|
      assert_ssubscribe_channels_different_slots_matrix_case(subscription_method)
    end

    parameterized_test(
      :test_sync_sunsubscribe_channels_different_slots,
      topologies: %i[cluster],
      subscription_method: %i[lazy blocking]
    ) do |subscription_method|
      assert_sunsubscribe_channels_different_slots_matrix_case(subscription_method)
    end

    parameterized_test(
      :test_sync_resubscribe_after_connection_kill_sharded,
      topologies: %i[cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |method, subscription_method|
      assert_resubscribe_sharded_after_connection_kill_matrix_case(method, subscription_method)
    end

    parameterized_test(
      :test_sync_resubscribe_after_connection_kill_many_exact_channels,
      topologies: %i[standalone cluster],
      method: %i[blocking_get polling_try_get callback],
      subscription_method: SUBSCRIPTION_METHODS
    ) do |method, subscription_method|
      assert_resubscribe_many_exact_channels_after_connection_kill_matrix_case(method, subscription_method)
    end

    private

    def assert_exact_pubsub_matrix_case(subscription_method, read_method)
      channel = unique_channel("matrix-#{subscription_method}-#{read_method}")
      payload = "message-#{subscription_method}-#{read_method}"
      callback_messages = []
      callback = ->(message, _context) { callback_messages << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        channels: [channel],
        callback: callback
      ) do |subscriber, publisher|
        receiver_count = publisher.publish(payload, channel)
        assert_equal 1, receiver_count if cluster_mode?

        received = matrix_get_message_by_method(read_method, subscriber, callback_messages)

        assert_equal payload, received.message
        assert_equal channel, received.channel
        assert_nil received.pattern

        matrix_check_no_messages_left(read_method, subscriber, callback_messages, 1)
      end
    end

    def assert_exact_pubsub_custom_command_matrix_case(subscription_method, read_method)
      channel = unique_channel("matrix-custom-command-#{read_method}-#{subscription_method}")
      payload = "test_exact_message_custom"
      callback_messages = []
      callback = ->(message, context) { context << message } if read_method == :callback
      context = callback_messages if callback

      with_matrix_bare_pubsub_client(callback: callback, context: context) do |subscriber|
        subscribe_command = if subscription_method == :lazy
                              ["SUBSCRIBE", channel]
                            else
                              ["SUBSCRIBE_BLOCKING", channel, "5000"]
                            end
        assert_nil subscriber.call_v(subscribe_command)
        matrix_wait_for_subscription_state_if_needed(
          subscriber,
          subscription_method,
          { exact: [channel] }
        )

        r.publish(payload, channel)
        received = matrix_get_message_by_method(read_method, subscriber, callback_messages)

        assert_equal payload, received.message
        assert_equal channel, received.channel
        assert_nil received.pattern
        matrix_check_no_messages_left(read_method, subscriber, callback_messages, 1)

        unsubscribe_command = if subscription_method == :lazy
                                ["UNSUBSCRIBE", channel]
                              else
                                ["UNSUBSCRIBE_BLOCKING", channel, "5000"]
                              end
        assert_nil subscriber.call_v(unsubscribe_command)
      end
    end

    def assert_resubscribe_exact_after_connection_kill_matrix_case(read_method, subscription_method)
      channel = unique_channel("matrix-reconnect-exact-#{subscription_method}-#{read_method}")
      callback_messages = []
      callback = ->(message, context) { context << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        channels: [channel],
        callback: callback,
        context: callback ? callback_messages : nil,
        state_timeout: 3.0
      ) do |subscriber, publisher|
        publisher.publish("message_before_kill", channel)
        message_before = matrix_get_message_by_method(read_method, subscriber, callback_messages, 0)
        assert_equal "message_before_kill", message_before.message
        assert_equal channel, message_before.channel

        matrix_kill_connections_tolerant(publisher)
        matrix_wait_for_actual_subscription(
          subscriber,
          :exact,
          channel,
          timeout: cluster_mode? ? 15.0 : 5.0
        )

        message_after = matrix_publish_after_reconnection(
          publisher,
          "message_after_kill",
          channel,
          subscriber,
          read_method,
          callback_messages,
          1
        )
        refute_nil message_after,
                   "no message received after #{MATRIX_RECONNECT_PUBLISH_ATTEMPTS} post-reconnection publishes"
        assert_equal "message_after_kill", message_after.message
        assert_equal channel, message_after.channel

        matrix_check_no_messages_left(
          read_method,
          subscriber,
          callback_messages,
          2,
          wait_seconds: MATRIX_RECONNECT_POLL_SECONDS
        )
      end
    end

    def assert_resubscribe_pattern_after_connection_kill_matrix_case(read_method, subscription_method)
      pattern_root = unique_channel("matrix-reconnect-pattern-#{subscription_method}-#{read_method}")
      pattern = "#{pattern_root}-*"
      channel = "#{pattern_root}-news"
      callback_messages = []
      callback = ->(message, context) { context << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        patterns: [pattern],
        callback: callback,
        context: callback ? callback_messages : nil,
        state_timeout: 3.0
      ) do |subscriber, publisher|
        publisher.publish("message_before_kill", channel)
        message_before = matrix_get_message_by_method(read_method, subscriber, callback_messages, 0)
        assert_equal "message_before_kill", message_before.message
        assert_equal channel, message_before.channel
        assert_equal pattern, message_before.pattern

        matrix_kill_connections_tolerant(publisher)
        matrix_wait_for_actual_subscription(
          subscriber,
          :pattern,
          pattern,
          timeout: cluster_mode? ? 15.0 : 5.0
        )

        message_after = matrix_publish_after_reconnection(
          publisher,
          "message_after_kill",
          channel,
          subscriber,
          read_method,
          callback_messages,
          1
        )
        refute_nil message_after,
                   "no message received after #{MATRIX_RECONNECT_PUBLISH_ATTEMPTS} post-reconnection publishes"
        assert_equal "message_after_kill", message_after.message
        assert_equal channel, message_after.channel
        assert_equal pattern, message_after.pattern

        matrix_check_no_messages_left(
          read_method,
          subscriber,
          callback_messages,
          2,
          wait_seconds: MATRIX_RECONNECT_POLL_SECONDS
        )
      end
    end

    def assert_resubscribe_sharded_after_connection_kill_matrix_case(read_method, subscription_method)
      skip_unless_sharded_pubsub

      channel = unique_channel("{matrix-reconnect-sharded-#{subscription_method}-#{read_method}}")
      callback_messages = []
      callback = ->(message, context) { context << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        sharded: [channel],
        callback: callback,
        context: callback ? callback_messages : nil,
        state_timeout: 3.0
      ) do |subscriber, publisher|
        publisher.publish("message_before_kill", channel, sharded: true)
        message_before = matrix_get_message_by_method(read_method, subscriber, callback_messages, 0)
        assert_equal "message_before_kill", message_before.message
        assert_equal channel, message_before.channel

        matrix_kill_connections_tolerant(publisher)
        matrix_wait_for_actual_subscription(subscriber, :sharded, channel, timeout: 15.0)

        publisher.publish("message_after_kill", channel, sharded: true)
        message_after = matrix_get_message_by_method(read_method, subscriber, callback_messages, 1)
        assert_equal "message_after_kill", message_after.message
        assert_equal channel, message_after.channel

        matrix_check_no_messages_left(
          read_method,
          subscriber,
          callback_messages,
          2,
          wait_seconds: MATRIX_RECONNECT_POLL_SECONDS
        )
      ensure
        subscriber.sunsubscribe(channel, timeout_ms: 5000) if subscription_method == :config
      end
    end

    def assert_resubscribe_many_exact_channels_after_connection_kill_matrix_case(read_method, subscription_method)
      case_token = SecureRandom.hex(8)
      payload = "message_after_kill"
      expected_messages = (0...256).to_h do |index|
        ["{reconnect_exact_#{index}}channel_#{case_token}", payload]
      end
      callback_messages = []
      callback = ->(message, context) { context << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        channels: expected_messages.keys,
        callback: callback,
        context: callback ? callback_messages : nil,
        state_timeout: 3.0
      ) do |subscriber, publisher|
        matrix_kill_connections_tolerant(publisher)
        matrix_wait_for_actual_subscriptions(
          subscriber,
          :exact,
          expected_messages.keys,
          timeout: cluster_mode? ? 15.0 : 5.0
        )

        expected_messages.each_key { |channel| publisher.publish(payload, channel) }

        received_messages = matrix_collect_messages_by_method(
          read_method,
          subscriber,
          callback_messages,
          expected_messages.length,
          timeout: MATRIX_BULK_MESSAGE_WAIT_SECONDS
        )
        remaining_messages = expected_messages.dup

        received_messages.each do |received|
          channel = received.channel.to_s

          assert remaining_messages.key?(channel),
                 "unexpected or duplicate Pub/Sub channel: #{channel.inspect}"
          assert_equal remaining_messages.fetch(channel), received.message
          assert_nil received.pattern
          remaining_messages.delete(channel)
        end

        assert_empty remaining_messages, "not all restored exact channels received messages"
        matrix_check_no_messages_left(
          read_method,
          subscriber,
          callback_messages,
          expected_messages.length,
          wait_seconds: MATRIX_RECONNECT_POLL_SECONDS
        )
      end
    end

    def assert_exact_pubsub_coexistence_matrix_case(subscription_method)
      channel = unique_channel("matrix-coexistence-#{subscription_method}")
      payloads = %w[test_exact_message_1 test_exact_message_2]

      with_matrix_pubsub_clients(subscription_method, channels: [channel]) do |subscriber, publisher|
        payloads.each do |payload|
          receiver_count = publisher.publish(payload, channel)
          assert_equal 1, receiver_count if cluster_mode?
        end

        blocking_message = matrix_blocking_get(subscriber)
        polling_message = wait_for_message(subscriber)

        refute_nil polling_message
        [blocking_message, polling_message].each do |received|
          assert_includes payloads, received.message
          assert_equal channel, received.channel
          assert_nil received.pattern
        end
        refute_equal blocking_message.message, polling_message.message

        no_message_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + MATRIX_NO_MESSAGE_WAIT_SECONDS
        matrix_assert_blocking_get_waits(subscriber, deadline: no_message_deadline)
        assert_nil subscriber.try_get_pubsub_message
      end
    end

    def assert_unsubscribe_exact_channel_matrix_case(read_method, unsubscribe_method)
      channel = unique_channel("matrix-unsubscribe-#{unsubscribe_method}-#{read_method}")
      callback_messages = []
      callback = ->(message, _context) { callback_messages << message } if read_method == :callback

      with_matrix_pubsub_clients(:config, channels: [channel], callback: callback) do |subscriber, publisher|
        assert_includes matrix_actual_subscriptions(subscriber, :exact), channel

        publisher.publish("exact_message_1", channel)
        received = matrix_get_message_by_method(read_method, subscriber, callback_messages)
        assert_equal "exact_message_1", received.message

        matrix_unsubscribe_by_method(
          subscriber,
          unsubscribe_method,
          { exact: [channel] },
          timeout_ms: 5000
        )
        matrix_wait_for_subscription_state_if_needed(
          subscriber,
          unsubscribe_method,
          { exact: [] }
        )
        refute_includes matrix_actual_subscriptions(subscriber, :exact), channel

        publisher.publish("exact_message_2", channel)
        matrix_assert_no_delivery(read_method, subscriber, callback_messages, 1)
      end
    end

    def assert_punsubscribe_pattern_matrix_case(read_method, unsubscribe_method)
      pattern_root = unique_channel("matrix-punsubscribe-#{unsubscribe_method}-#{read_method}")
      pattern = "#{pattern_root}.*"
      channel = "#{pattern_root}.sports"
      callback_messages = []
      callback = ->(message, _context) { callback_messages << message } if read_method == :callback

      with_matrix_pubsub_clients(:config, patterns: [pattern], callback: callback) do |subscriber, publisher|
        assert_includes matrix_actual_subscriptions(subscriber, :pattern), pattern

        publisher.publish("message_before_unsub", channel)
        received = matrix_get_message_by_method(read_method, subscriber, callback_messages)
        assert_equal "message_before_unsub", received.message

        matrix_unsubscribe_by_method(
          subscriber,
          unsubscribe_method,
          { pattern: [pattern] },
          timeout_ms: 5000
        )
        matrix_wait_for_subscription_state_if_needed(
          subscriber,
          unsubscribe_method,
          { pattern: [] }
        )
        refute_includes matrix_actual_subscriptions(subscriber, :pattern), pattern

        publisher.publish("message_after_unsub", channel)
        matrix_assert_no_delivery(read_method, subscriber, callback_messages, 1)
      ensure
        subscriber.punsubscribe(pattern, timeout_ms: 5000)
      end
    end

    def assert_sunsubscribe_sharded_channel_matrix_case(read_method, unsubscribe_method)
      skip_unless_sharded_pubsub

      channel = unique_channel("matrix-sunsubscribe-#{unsubscribe_method}-#{read_method}")
      callback_messages = []
      callback = ->(message, _context) { callback_messages << message } if read_method == :callback

      with_matrix_pubsub_clients(:config, sharded: [channel], callback: callback) do |subscriber, publisher|
        assert_includes matrix_actual_subscriptions(subscriber, :sharded), channel

        publisher.publish("message_before_unsub", channel, sharded: true)
        received = matrix_get_message_by_method(read_method, subscriber, callback_messages)
        assert_equal "message_before_unsub", received.message

        matrix_unsubscribe_by_method(
          subscriber,
          unsubscribe_method,
          { sharded: [channel] },
          timeout_ms: 5000
        )
        matrix_wait_for_subscription_state_if_needed(
          subscriber,
          unsubscribe_method,
          { sharded: [] }
        )
        refute_includes matrix_actual_subscriptions(subscriber, :sharded), channel

        publisher.publish("message_after_unsub", channel, sharded: true)
        matrix_assert_no_delivery(read_method, subscriber, callback_messages, 1)
      ensure
        subscriber.sunsubscribe(channel, timeout_ms: 5000)
      end
    end

    def assert_unsubscribe_all_subscription_types_matrix_case(unsubscribe_method, read_method)
      supports_sharded = matrix_supports_sharded_pubsub?
      channel_root = unique_channel("matrix-unsubscribe-all-#{unsubscribe_method}-#{read_method}")
      exact_channel = "#{channel_root}-exact"
      pattern = "#{channel_root}-pattern-*"
      sharded_channel = "#{channel_root}-sharded" if supports_sharded
      callback_messages = []
      callback = ->(message, context) { context << message } if read_method == :callback
      subscriptions = matrix_subscription_sets(
        channels: [exact_channel],
        patterns: [pattern],
        sharded: sharded_channel ? [sharded_channel] : []
      )

      with_matrix_pubsub_clients(
        :config,
        channels: [exact_channel],
        patterns: [pattern],
        sharded: sharded_channel ? [sharded_channel] : [],
        callback: callback,
        context: callback ? callback_messages : nil
      ) do |subscriber, _publisher|
        modes = subscriptions.keys
        matrix_unsubscribe_all_by_method(
          subscriber,
          unsubscribe_method,
          modes,
          timeout_ms: 5000
        )

        empty_subscriptions = modes.to_h { |mode| [mode, []] }
        matrix_wait_for_subscription_state_if_needed(
          subscriber,
          unsubscribe_method,
          empty_subscriptions,
          timeout: 3.0
        )

        desired_subscriptions = subscriber.get_subscriptions.desired_subscriptions
        assert_empty desired_subscriptions.fetch(:exact, [])
        assert_empty desired_subscriptions.fetch(:pattern, [])
        assert_empty desired_subscriptions.fetch(:sharded, []) if supports_sharded
      end
    end

    def assert_lazy_client_multiple_subscription_types_matrix_case(read_method, subscription_method)
      channel_root = unique_channel("matrix-lazy-multi-#{subscription_method}-#{read_method}")
      exact_channel = "#{channel_root}-exact"
      pattern = "#{channel_root}-pattern-*"
      pattern_channel = "#{channel_root}-pattern-match"
      sharded_channel = "#{channel_root}-sharded" if matrix_supports_sharded_pubsub?
      callback_messages = []
      callback = ->(message, _context) { callback_messages << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        channels: [exact_channel],
        patterns: [pattern],
        sharded: sharded_channel ? [sharded_channel] : [],
        callback: callback,
        client_options: { lazy_connect: true },
        subscription_timeout_ms: 10_000
      ) do |subscriber, publisher|
        publisher.publish("msg1", exact_channel)
        publisher.publish("msg2", pattern_channel)
        publisher.publish("msg3", sharded_channel, sharded: true) if sharded_channel

        expected_count = sharded_channel ? 3 : 2
        if read_method == :callback
          callback_count = matrix_wait_for_callback_count(callback_messages, expected_count)
          refute_nil callback_count, "callback received fewer than #{expected_count} Pub/Sub messages"
          assert_operator callback_messages.length, :>=, expected_count
        else
          expected_count.times do
            refute_nil matrix_get_message_by_method(read_method, subscriber, callback_messages)
          end
        end
      ensure
        next unless subscription_method == :config

        subscriber.unsubscribe(exact_channel, timeout_ms: 10_000)
        subscriber.punsubscribe(pattern, timeout_ms: 10_000)
        subscriber.sunsubscribe(sharded_channel, timeout_ms: 10_000) if sharded_channel
      end
    end

    def assert_exact_max_size_message_callback_matrix_case(subscription_method)
      channel = unique_channel("matrix-max-size-callback-#{subscription_method}")
      payload = "0" * (12 * 1024 * 1024)
      callback_messages = []
      callback = ->(message, context) { context << message }

      with_matrix_pubsub_clients(
        subscription_method,
        channels: [channel],
        callback: callback,
        context: callback_messages,
        client_timeout: 10.0,
        fresh_publisher: true,
        subscription_timeout_ms: 10_000
      ) do |_subscriber, publisher|
        receiver_count = publisher.publish(payload, channel)
        assert_equal 1, receiver_count if cluster_mode?

        received_count = matrix_wait_for_callback_count(callback_messages, 1, timeout: 30.0)
        refute_nil received_count, "callback received no maximum-size Pub/Sub message"
        assert_equal 1, callback_messages.length

        received = callback_messages.first
        assert payload == received.message, "callback Pub/Sub payload did not match the 12 MiB published payload"
        assert_equal channel, received.channel
        assert_nil received.pattern
      end
    end

    def assert_sharded_large_size_message_callback_matrix_case(subscription_method)
      skip_unless_sharded_pubsub

      channel = SecureRandom.alphanumeric(10)
      payload = "0" * (12 * 1024 * 1024)
      callback_messages = []
      callback_notifications = Queue.new
      callback = lambda do |message, context|
        context << message
        callback_notifications << true
      end

      with_matrix_pubsub_clients(
        subscription_method,
        sharded: [channel],
        callback: callback,
        context: callback_messages,
        client_timeout: 10.0,
        subscription_timeout_ms: 10_000,
        state_timeout: 10.0
      ) do |_subscriber, publisher|
        assert_equal 1, publisher.publish(payload, channel, sharded: true)

        notification = matrix_pop_callback_notification(callback_notifications, timeout: 45.0)
        refute_nil notification, "callback received no large sharded Pub/Sub message"
        assert_equal 1, callback_messages.length

        received = callback_messages.first
        assert payload == received.message, "callback sharded Pub/Sub payload did not match the 12 MiB payload"
        assert_equal payload.bytesize, received.message.bytesize
        assert_equal channel, received.channel
        assert_nil received.pattern

        assert_nil matrix_pop_callback_notification(
          callback_notifications,
          timeout: MATRIX_NO_MESSAGE_WAIT_SECONDS
        ), "callback received an unexpected extra sharded Pub/Sub message"
        assert_equal 1, callback_messages.length
      end
    end

    def assert_exact_pubsub_many_channels_matrix_case(subscription_method, read_method)
      channels_and_messages = matrix_channel_message_map(
        256,
        channel_prefix: "{same-shard}matrix-many-#{subscription_method}-#{read_method}"
      )
      callback_messages = []
      callback = ->(message, _context) { callback_messages << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        channels: channels_and_messages.keys,
        callback: callback
      ) do |subscriber, publisher|
        channels_and_messages.each do |channel, payload|
          receiver_count = publisher.publish(payload, channel)
          assert_equal 1, receiver_count if cluster_mode?
        end

        received_messages = matrix_collect_messages_by_method(
          read_method,
          subscriber,
          callback_messages,
          channels_and_messages.length,
          timeout: MATRIX_BULK_MESSAGE_WAIT_SECONDS
        )
        remaining_channels_and_messages = channels_and_messages.dup

        received_messages.each do |received|
          assert remaining_channels_and_messages.key?(received.channel),
                 "unexpected or duplicate Pub/Sub channel: #{received.channel.inspect}"
          assert_equal remaining_channels_and_messages.fetch(received.channel), received.message
          assert_nil received.pattern
          remaining_channels_and_messages.delete(received.channel)
        end

        assert_empty remaining_channels_and_messages
        matrix_check_no_messages_left(
          read_method,
          subscriber,
          callback_messages,
          channels_and_messages.length
        )
      end
    end

    def assert_exact_pubsub_many_channels_coexistence_matrix_case(subscription_method)
      channels_and_messages = matrix_random_channel_message_map(
        256,
        channel_prefix: "{same-shard}",
        channel_suffix_length: 10,
        payload_length: 5
      )

      with_matrix_pubsub_clients(
        subscription_method,
        channels: channels_and_messages.keys
      ) do |subscriber, publisher|
        channels_and_messages.each do |channel, payload|
          receiver_count = publisher.publish(payload, channel)
          assert_equal 1, receiver_count if cluster_mode?
        end

        read_method_for_index = lambda do |index|
          index.even? ? :polling_try_get : :blocking_get
        end
        received_messages = matrix_collect_messages_by_method(
          read_method_for_index,
          subscriber,
          [],
          channels_and_messages.length,
          timeout: MATRIX_BULK_MESSAGE_WAIT_SECONDS
        )
        remaining_channels_and_messages = channels_and_messages.dup

        received_messages.each do |received|
          channel = received.channel.to_s

          assert remaining_channels_and_messages.key?(channel),
                 "unexpected or duplicate Pub/Sub channel: #{channel.inspect}"
          assert_equal remaining_channels_and_messages.fetch(channel), received.message
          assert_nil received.pattern
          remaining_channels_and_messages.delete(channel)
        end

        assert_equal({}, remaining_channels_and_messages)
        no_message_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + MATRIX_NO_MESSAGE_WAIT_SECONDS
        matrix_assert_blocking_get_waits(subscriber, deadline: no_message_deadline)
        assert_nil subscriber.try_get_pubsub_message
      end
    end

    def assert_sharded_pubsub_matrix_case(subscription_method, read_method)
      skip_unless_sharded_pubsub

      channel = SecureRandom.alphanumeric(10)
      payload = SecureRandom.alphanumeric(5)
      callback_messages = []
      callback = ->(message, context) { context << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        sharded: [channel],
        callback: callback,
        context: callback ? callback_messages : nil
      ) do |subscriber, publisher|
        receiver_count = publisher.publish(payload, channel, sharded: true)
        assert_equal 1, receiver_count

        received = matrix_get_message_by_method(read_method, subscriber, callback_messages)

        assert_equal payload, received.message
        assert_equal channel, received.channel
        assert_nil received.pattern

        matrix_check_no_messages_left(read_method, subscriber, callback_messages, 1)
      ensure
        subscriber.sunsubscribe(channel, timeout_ms: 5000) if subscription_method == :config
      end
    end

    def assert_sharded_pubsub_coexistence_matrix_case(subscription_method)
      channel = SecureRandom.alphanumeric(10)
      payloads = [SecureRandom.alphanumeric(5), SecureRandom.alphanumeric(7)]

      with_matrix_pubsub_clients(subscription_method, sharded: [channel]) do |subscriber, publisher|
        payloads.each do |payload|
          assert_equal 1, publisher.publish(payload, channel, sharded: true)
        end

        blocking_message = matrix_blocking_get(subscriber)
        polling_message = matrix_polling_get(
          subscriber,
          failure_message: "second coexisting sharded Pub/Sub message did not arrive"
        )

        refute_nil polling_message
        [blocking_message, polling_message].each do |received|
          assert_includes payloads, received.message
          assert_equal channel, received.channel
          assert_nil received.pattern
        end
        refute_equal blocking_message.message, polling_message.message

        no_message_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + MATRIX_NO_MESSAGE_WAIT_SECONDS
        matrix_assert_blocking_get_waits(subscriber, deadline: no_message_deadline)
        assert_nil subscriber.try_get_pubsub_message
      ensure
        subscriber.sunsubscribe(channel, timeout_ms: 5000) if subscription_method == :config
      end
    end

    def assert_sharded_pubsub_many_channels_matrix_case(subscription_method, read_method)
      skip_unless_sharded_pubsub

      channels_and_messages = matrix_random_channel_message_map(
        256,
        channel_prefix: "{same-shard}",
        channel_suffix_length: 10,
        payload_length: 5
      )
      callback_messages = []
      callback = ->(message, context) { context << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        sharded: channels_and_messages.keys,
        callback: callback,
        context: callback ? callback_messages : nil
      ) do |subscriber, publisher|
        channels_and_messages.each do |channel, payload|
          assert_equal 1, publisher.publish(payload, channel, sharded: true)
        end

        received_messages = matrix_collect_messages_by_method(
          read_method,
          subscriber,
          callback_messages,
          channels_and_messages.length,
          timeout: MATRIX_BULK_MESSAGE_WAIT_SECONDS
        )
        remaining_channels_and_messages = channels_and_messages.dup

        received_messages.each do |received|
          channel = received.channel.to_s

          assert remaining_channels_and_messages.key?(channel),
                 "unexpected or duplicate sharded Pub/Sub channel: #{channel.inspect}"
          assert_equal remaining_channels_and_messages.fetch(channel), received.message
          assert_nil received.pattern
          remaining_channels_and_messages.delete(channel)
        end

        assert_equal({}, remaining_channels_and_messages)
        matrix_check_no_messages_left(
          read_method,
          subscriber,
          callback_messages,
          channels_and_messages.length
        )
      ensure
        subscriber.sunsubscribe(*channels_and_messages.keys, timeout_ms: 5000) if subscription_method == :config
      end
    end

    def assert_ssubscribe_channels_different_slots_matrix_case(subscription_method)
      skip_unless_sharded_pubsub

      suffix = SecureRandom.hex(8)
      channels = [
        "{slot1}channel_a-#{suffix}",
        "{slot2}channel_b-#{suffix}",
        "{slot3}channel_c-#{suffix}",
        "{slot1}channel_d-#{suffix}",
        "{slot4}channel_e-#{suffix}"
      ]
      expected_messages = channels.to_h { |channel| [channel, "msg_#{channel}"] }

      with_matrix_pubsub_clients(subscription_method, sharded: channels, state_timeout: 3.0) do |subscriber, publisher|
        expected_messages.each do |channel, message|
          publisher.publish(message, channel, sharded: true)
        end

        received_messages = {}
        channels.length.times do
          received = matrix_get_message_by_method(
            :polling_try_get,
            subscriber,
            [],
            timeout: 5.0
          )
          received_messages[received.channel.to_s] = received.message
        end

        assert_equal expected_messages, received_messages
      ensure
        channels.each { |channel| subscriber.sunsubscribe(channel, timeout_ms: 5000) } if subscription_method == :config
      end
    end

    def assert_sunsubscribe_channels_different_slots_matrix_case(subscription_method)
      skip_unless_sharded_pubsub

      suffix = SecureRandom.hex(8)
      channels = [
        "{slotA}unsub_channel_1-#{suffix}",
        "{slotB}unsub_channel_2-#{suffix}",
        "{slotC}unsub_channel_3-#{suffix}",
        "{slotA}unsub_channel_4-#{suffix}"
      ]
      sharded_subscriptions = { sharded: channels }

      with_matrix_pubsub_clients(:config, sharded: channels, state_timeout: 3.0) do |subscriber, publisher|
        state = subscriber.get_subscriptions
        matrix_assert_subscription_sets(sharded_subscriptions, state.desired_subscriptions)
        matrix_assert_subscription_sets(sharded_subscriptions, state.actual_subscriptions)

        matrix_unsubscribe_by_method(subscriber, subscription_method, sharded_subscriptions)
        matrix_wait_for_subscription_state_if_needed(
          subscriber,
          subscription_method,
          { sharded: [] },
          timeout: 3.0
        )

        state = subscriber.get_subscriptions
        matrix_assert_subscription_sets({ sharded: [] }, state.desired_subscriptions)
        matrix_assert_subscription_sets({ sharded: [] }, state.actual_subscriptions)

        channels.each do |channel|
          publisher.publish("test_message", channel, sharded: true)
        end
        matrix_assert_no_delivery(:polling_try_get, subscriber, [], 0)
      end
    end

    def assert_pattern_pubsub_matrix_case(subscription_method, read_method)
      assert_pattern_pubsub_messages_matrix_case(subscription_method, read_method, message_count: 2)
    end

    def assert_pattern_pubsub_many_channels_matrix_case(subscription_method, read_method)
      assert_pattern_pubsub_messages_matrix_case(
        subscription_method,
        read_method,
        message_count: 256,
        timeout: MATRIX_BULK_MESSAGE_WAIT_SECONDS
      )
    end

    def assert_pattern_pubsub_messages_matrix_case(subscription_method, read_method, message_count:, timeout: nil)
      pattern_prefix = "{channel}:matrix-pattern-#{SecureRandom.hex(8)}:"
      pattern = "#{pattern_prefix}*"
      channels_and_messages = matrix_random_channel_message_map(
        message_count,
        channel_prefix: pattern_prefix,
        channel_suffix_length: 10,
        payload_length: 5
      )
      callback_messages = []
      callback = ->(message, context) { context << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        patterns: [pattern],
        callback: callback,
        context: callback ? callback_messages : nil
      ) do |subscriber, publisher|
        channels_and_messages.each do |channel, payload|
          receiver_count = publisher.publish(payload, channel)
          assert_equal 1, receiver_count if cluster_mode?
        end

        matrix_assert_pattern_messages(
          read_method,
          subscriber,
          callback_messages,
          channels_and_messages,
          pattern,
          timeout: timeout
        )
        matrix_check_no_messages_left(
          read_method,
          subscriber,
          callback_messages,
          channels_and_messages.length
        )
      ensure
        subscriber.punsubscribe(pattern, timeout_ms: 5000) if subscription_method == :config
      end
    end

    def matrix_assert_pattern_messages(
      read_method,
      subscriber,
      callback_messages,
      channels_and_messages,
      pattern,
      timeout:
    )
      received_messages = if timeout
                            matrix_collect_messages_by_method(
                              read_method,
                              subscriber,
                              callback_messages,
                              channels_and_messages.length,
                              timeout: timeout
                            )
                          else
                            Array.new(channels_and_messages.length) do |index|
                              matrix_get_message_by_method(
                                read_method,
                                subscriber,
                                callback_messages,
                                index
                              )
                            end
                          end
      remaining_channels_and_messages = channels_and_messages.dup

      received_messages.each do |received|
        channel = received.channel.to_s

        assert remaining_channels_and_messages.key?(channel),
               "unexpected or duplicate pattern Pub/Sub channel: #{channel.inspect}"
        assert_equal remaining_channels_and_messages.fetch(channel), received.message
        assert_equal pattern, received.pattern
        remaining_channels_and_messages.delete(channel)
      end

      assert_equal({}, remaining_channels_and_messages)
    end

    def assert_pattern_pubsub_coexistence_matrix_case(subscription_method)
      pattern_root = "{channel}:matrix-pattern-coexistence-#{SecureRandom.hex(8)}"
      pattern = "#{pattern_root}:*"
      channels_and_messages = {
        "#{pattern_root}:0" => SecureRandom.alphanumeric(5),
        "#{pattern_root}:1" => SecureRandom.alphanumeric(5)
      }

      with_matrix_pubsub_clients(subscription_method, patterns: [pattern]) do |subscriber, publisher|
        channels_and_messages.each do |channel, payload|
          receiver_count = publisher.publish(payload, channel)
          assert_equal 1, receiver_count if cluster_mode?
        end

        remaining_channels_and_messages = channels_and_messages.dup
        %i[polling_try_get blocking_get].each do |read_method|
          received = matrix_get_message_by_method(read_method, subscriber, [])
          channel = received.channel.to_s

          assert remaining_channels_and_messages.key?(channel),
                 "unexpected or duplicate pattern Pub/Sub channel: #{channel.inspect}"
          assert_equal remaining_channels_and_messages.fetch(channel), received.message
          assert_equal pattern, received.pattern
          remaining_channels_and_messages.delete(channel)
        end

        assert_equal({}, remaining_channels_and_messages)
        no_message_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + MATRIX_NO_MESSAGE_WAIT_SECONDS
        matrix_assert_blocking_get_waits(subscriber, deadline: no_message_deadline)
        assert_nil subscriber.try_get_pubsub_message
      ensure
        subscriber.punsubscribe(pattern, timeout_ms: 5000) if subscription_method == :config
      end
    end

    def assert_combined_exact_and_pattern_one_client_matrix_case(subscription_method, read_method)
      case_token = SecureRandom.hex(8)
      exact_channels_and_messages = (0...256).to_h do |index|
        ["{channel}:#{case_token}:exact_#{index}", "exact_message_#{index}"]
      end
      pattern_root = "{pattern}:#{case_token}"
      pattern = "#{pattern_root}:*"
      pattern_channels_and_messages = (0...256).to_h do |index|
        ["#{pattern_root}:match_#{index}", "pattern_message_#{index}"]
      end
      all_channels_and_messages = exact_channels_and_messages.merge(pattern_channels_and_messages)
      callback_messages = []
      callback = ->(message, _context) { callback_messages << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        channels: exact_channels_and_messages.keys,
        patterns: [pattern],
        callback: callback,
        always_poll_subscription_state: true
      ) do |subscriber, publisher|
        all_channels_and_messages.each do |channel, payload|
          receiver_count = publisher.publish(payload, channel)
          assert_equal 1, receiver_count if cluster_mode?
        end

        received_messages = matrix_collect_messages_by_method(
          read_method,
          subscriber,
          callback_messages,
          all_channels_and_messages.length,
          timeout: MATRIX_BULK_MESSAGE_WAIT_SECONDS
        )
        remaining_channels_and_messages = all_channels_and_messages.dup

        received_messages.each do |received|
          channel = received.channel.to_s
          expected_pattern = pattern_channels_and_messages.key?(channel) ? pattern : nil

          assert remaining_channels_and_messages.key?(channel),
                 "unexpected or duplicate Pub/Sub channel: #{channel.inspect}"
          assert_equal remaining_channels_and_messages.fetch(channel), received.message
          expected_pattern ? assert_equal(expected_pattern, received.pattern) : assert_nil(received.pattern)
          remaining_channels_and_messages.delete(channel)
        end

        assert_empty remaining_channels_and_messages
        matrix_check_no_messages_left(
          read_method,
          subscriber,
          callback_messages,
          all_channels_and_messages.length
        )
      end
    end

    def assert_combined_exact_and_pattern_multiple_clients_matrix_case(subscription_method, read_method)
      case_token = SecureRandom.hex(8)
      exact_channels_and_messages = (0...256).to_h do |index|
        ["{channel}:#{case_token}:exact_#{index}", "exact_message_#{index}"]
      end
      pattern_root = "{pattern}:#{case_token}"
      pattern = "#{pattern_root}:*"
      pattern_channels_and_messages = (0...256).to_h do |index|
        ["#{pattern_root}:match_#{index}", "pattern_message_#{index}"]
      end
      exact_callback_messages = []
      pattern_callback_messages = []
      exact_callback = ->(message, context) { context << message } if read_method == :callback
      pattern_callback = ->(message, context) { context << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        channels: exact_channels_and_messages.keys,
        callback: exact_callback,
        context: exact_callback ? exact_callback_messages : nil
      ) do |exact_subscriber, publisher|
        with_matrix_pubsub_clients(
          subscription_method,
          patterns: [pattern],
          callback: pattern_callback,
          context: pattern_callback ? pattern_callback_messages : nil
        ) do |pattern_subscriber, _inner_publisher|
          matrix_publish_combined_channels_once(
            publisher,
            exact_channels_and_messages,
            pattern_channels_and_messages
          )
          exact_listener = [
            read_method,
            exact_subscriber,
            exact_callback_messages,
            exact_channels_and_messages,
            nil
          ]
          pattern_listener = [
            read_method,
            pattern_subscriber,
            pattern_callback_messages,
            pattern_channels_and_messages,
            pattern
          ]
          matrix_assert_combined_multiple_client_delivery(exact_listener, pattern_listener)
        end
      end
    end

    def assert_combined_exact_pattern_sharded_one_client_matrix_case(subscription_method, read_method)
      skip_unless_sharded_pubsub

      case_token = SecureRandom.hex(8)
      exact_channels_and_messages = (0...256).to_h do |index|
        ["{exact-#{case_token}}:channel_#{index}", "exact_message_#{index}"]
      end
      pattern_root = "{pattern-#{case_token}}"
      pattern = "#{pattern_root}:*"
      pattern_channels_and_messages = (0...256).to_h do |index|
        ["#{pattern_root}:match_#{index}", "pattern_message_#{index}"]
      end
      sharded_channels_and_messages = (0...256).to_h do |index|
        ["{sharded-#{case_token}}:channel_#{index}", "sharded_message_#{index}"]
      end
      all_channels_and_messages = exact_channels_and_messages
                                  .merge(pattern_channels_and_messages)
                                  .merge(sharded_channels_and_messages)
      callback_messages = []
      callback = ->(message, _context) { callback_messages << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        channels: exact_channels_and_messages.keys,
        patterns: [pattern],
        sharded: sharded_channels_and_messages.keys,
        callback: callback,
        cleanup_config_subscriptions: true
      ) do |subscriber, publisher|
        matrix_publish_combined_channels_once(
          publisher,
          exact_channels_and_messages,
          pattern_channels_and_messages
        )
        sharded_channels_and_messages.each do |channel, payload|
          assert_equal 1, publisher.publish(payload, channel, sharded: true)
        end

        received_messages = matrix_collect_messages_by_method(
          read_method,
          subscriber,
          callback_messages,
          all_channels_and_messages.length,
          timeout: MATRIX_BULK_MESSAGE_WAIT_SECONDS
        )
        remaining_channels_and_messages = all_channels_and_messages.dup

        received_messages.each do |received|
          channel = received.channel.to_s
          expected_pattern = pattern_channels_and_messages.key?(channel) ? pattern : nil

          assert remaining_channels_and_messages.key?(channel),
                 "unexpected or duplicate Pub/Sub channel: #{channel.inspect}"
          assert_equal remaining_channels_and_messages.fetch(channel), received.message
          expected_pattern ? assert_equal(expected_pattern, received.pattern) : assert_nil(received.pattern)
          remaining_channels_and_messages.delete(channel)
        end

        assert_empty remaining_channels_and_messages
        matrix_check_no_messages_left(
          read_method,
          subscriber,
          callback_messages,
          all_channels_and_messages.length
        )
      end
    end

    def assert_combined_exact_pattern_sharded_multi_client_matrix_case(subscription_method, read_method)
      case_token = SecureRandom.hex(8)
      exact_root = "{channel-#{case_token}}"
      exact_channels_and_messages = (0...256).to_h do |index|
        ["#{exact_root}:exact:#{index}", "exact_msg_#{index}"]
      end
      pattern_root = "{pattern-#{case_token}}"
      pattern = "#{pattern_root}:*"
      pattern_channels_and_messages = (0...256).to_h do |index|
        ["#{pattern_root}:test:#{index}", "pattern_msg_#{index}"]
      end
      sharded_root = "{same-shard-#{case_token}}"
      sharded_channels_and_messages = (0...256).to_h do |index|
        ["#{sharded_root}:#{index}:sharded", "sharded_msg_#{index}"]
      end
      exact_callback_messages = []
      pattern_callback_messages = []
      sharded_callback_messages = []
      callback = ->(message, context) { context << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        channels: exact_channels_and_messages.keys,
        callback: callback,
        context: callback ? exact_callback_messages : nil,
        cleanup_config_subscriptions: true
      ) do |exact_subscriber, publisher|
        with_matrix_pubsub_clients(
          subscription_method,
          patterns: [pattern],
          callback: callback,
          context: callback ? pattern_callback_messages : nil,
          cleanup_config_subscriptions: true
        ) do |pattern_subscriber, _pattern_publisher|
          with_matrix_pubsub_clients(
            subscription_method,
            sharded: sharded_channels_and_messages.keys,
            callback: callback,
            context: callback ? sharded_callback_messages : nil,
            cleanup_config_subscriptions: true
          ) do |sharded_subscriber, _sharded_publisher|
            matrix_assert_combined_three_listener_delivery(
              read_method,
              publisher,
              exact: [exact_subscriber, exact_callback_messages, exact_channels_and_messages, nil],
              pattern: [pattern_subscriber, pattern_callback_messages, pattern_channels_and_messages, pattern],
              sharded: [sharded_subscriber, sharded_callback_messages, sharded_channels_and_messages, nil]
            )
          end
        end
      end
    end

    def assert_combined_different_channels_with_same_name_matrix_case(subscription_method, read_method)
      skip_unless_sharded_pubsub

      channel = unique_channel("{same-name}")
      payloads = {
        exact: "exact_message",
        pattern: "pattern_message",
        sharded: "sharded_message"
      }
      exact_callback_messages = []
      pattern_callback_messages = []
      sharded_callback_messages = []
      callback = ->(message, context) { context << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        channels: [channel],
        callback: callback,
        context: callback ? exact_callback_messages : nil
      ) do |exact_subscriber, publisher|
        with_matrix_pubsub_clients(
          subscription_method,
          patterns: [channel],
          callback: callback,
          context: callback ? pattern_callback_messages : nil
        ) do |pattern_subscriber, _pattern_publisher|
          with_matrix_pubsub_clients(
            subscription_method,
            sharded: [channel],
            callback: callback,
            context: callback ? sharded_callback_messages : nil
          ) do |sharded_subscriber, _sharded_publisher|
            listeners = {
              exact: [exact_subscriber, exact_callback_messages],
              pattern: [pattern_subscriber, pattern_callback_messages],
              sharded: [sharded_subscriber, sharded_callback_messages]
            }
            matrix_assert_same_name_delivery(
              read_method,
              publisher,
              channel,
              payloads,
              listeners
            )
          end
        end
      end
    end

    def assert_two_publishing_clients_same_name_matrix_case(subscription_method, read_method)
      channel = unique_channel("same-name")
      ascii_letters = [*("A".."Z"), *("a".."z")]
      payloads = [10, 7].map do |length|
        Array.new(length) { ascii_letters.fetch(SecureRandom.random_number(ascii_letters.length)) }.join
      end
      exact_callback_messages = []
      pattern_callback_messages = []
      callback = ->(message, context) { context << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        channels: [channel],
        callback: callback,
        context: callback ? exact_callback_messages : nil
      ) do |exact_subscriber, _exact_publisher|
        with_matrix_pubsub_clients(
          subscription_method,
          patterns: [channel],
          callback: callback,
          context: callback ? pattern_callback_messages : nil
        ) do |pattern_subscriber, _pattern_publisher|
          payloads.each do |payload|
            receiver_count = pattern_subscriber.publish(payload, channel)
            assert_equal 2, receiver_count if cluster_mode?
          end

          matrix_assert_same_name_ordinary_messages(
            read_method,
            exact_subscriber,
            exact_callback_messages,
            channel,
            payloads,
            expected_pattern: nil
          )
          matrix_assert_same_name_ordinary_messages(
            read_method,
            pattern_subscriber,
            pattern_callback_messages,
            channel,
            payloads,
            expected_pattern: channel
          )

          matrix_check_no_messages_left_for_listeners(
            [
              [read_method, pattern_subscriber, pattern_callback_messages, 2],
              [read_method, exact_subscriber, exact_callback_messages, 2]
            ]
          )
        end
      end
    end

    def assert_three_publishing_clients_same_name_with_sharded_matrix_case(subscription_method, read_method)
      skip_unless_sharded_pubsub

      case_token = SecureRandom.hex(8)
      channel = "{same-name-#{case_token}}:channel"
      payloads = {
        exact: "exact-message-#{case_token}",
        pattern: "pattern-message-#{case_token}",
        sharded: "sharded-message-#{case_token}"
      }
      exact_callback_messages = []
      pattern_callback_messages = []
      sharded_callback_messages = []
      callback = ->(message, context) { context << message } if read_method == :callback

      with_matrix_pubsub_clients(
        subscription_method,
        channels: [channel],
        callback: callback,
        context: callback ? exact_callback_messages : nil,
        always_poll_subscription_state: true
      ) do |exact_subscriber, _exact_publisher|
        with_matrix_pubsub_clients(
          subscription_method,
          patterns: [channel],
          callback: callback,
          context: callback ? pattern_callback_messages : nil,
          always_poll_subscription_state: true
        ) do |pattern_subscriber, _pattern_publisher|
          with_matrix_pubsub_clients(
            subscription_method,
            sharded: [channel],
            callback: callback,
            context: callback ? sharded_callback_messages : nil,
            always_poll_subscription_state: true
          ) do |sharded_subscriber, _sharded_publisher|
            listeners = {
              exact: [exact_subscriber, exact_callback_messages],
              pattern: [pattern_subscriber, pattern_callback_messages],
              sharded: [sharded_subscriber, sharded_callback_messages]
            }
            matrix_assert_three_publisher_same_name_delivery(
              read_method,
              channel,
              payloads,
              listeners
            )
          end
        end
      end
    end

    def matrix_assert_three_publisher_same_name_delivery(read_method, channel, payloads, listeners)
      exact_subscriber, exact_callback_messages = listeners.fetch(:exact)
      pattern_subscriber, pattern_callback_messages = listeners.fetch(:pattern)
      sharded_subscriber, sharded_callback_messages = listeners.fetch(:sharded)

      assert_equal 2, pattern_subscriber.publish(payloads.fetch(:exact), channel)
      assert_equal 2, sharded_subscriber.publish(payloads.fetch(:pattern), channel)
      assert_equal 1, exact_subscriber.publish(payloads.fetch(:sharded), channel, sharded: true)

      ordinary_payloads = payloads.values_at(:exact, :pattern)
      matrix_assert_same_name_ordinary_messages(
        read_method,
        exact_subscriber,
        exact_callback_messages,
        channel,
        ordinary_payloads,
        expected_pattern: nil
      )
      matrix_assert_same_name_ordinary_messages(
        read_method,
        pattern_subscriber,
        pattern_callback_messages,
        channel,
        ordinary_payloads,
        expected_pattern: channel
      )

      sharded_message = matrix_get_message_by_method(read_method, sharded_subscriber, sharded_callback_messages)
      assert_equal payloads.fetch(:sharded), sharded_message.message
      assert_equal channel, sharded_message.channel
      assert_nil sharded_message.pattern

      matrix_check_no_messages_left_for_listeners(
        [
          [read_method, pattern_subscriber, pattern_callback_messages, 2],
          [read_method, exact_subscriber, exact_callback_messages, 2],
          [read_method, sharded_subscriber, sharded_callback_messages, 1]
        ]
      )
    end

    def matrix_assert_same_name_delivery(read_method, publisher, channel, payloads, listeners)
      assert_equal 2, publisher.publish(payloads.fetch(:exact), channel)
      assert_equal 2, publisher.publish(payloads.fetch(:pattern), channel)
      assert_equal 1, publisher.publish(payloads.fetch(:sharded), channel, sharded: true)

      exact_subscriber, exact_callback_messages = listeners.fetch(:exact)
      pattern_subscriber, pattern_callback_messages = listeners.fetch(:pattern)
      sharded_subscriber, sharded_callback_messages = listeners.fetch(:sharded)
      ordinary_payloads = payloads.values_at(:exact, :pattern)

      matrix_assert_same_name_ordinary_messages(
        read_method,
        exact_subscriber,
        exact_callback_messages,
        channel,
        ordinary_payloads,
        expected_pattern: nil
      )
      matrix_assert_same_name_ordinary_messages(
        read_method,
        pattern_subscriber,
        pattern_callback_messages,
        channel,
        ordinary_payloads,
        expected_pattern: channel
      )

      sharded_message = matrix_get_message_by_method(read_method, sharded_subscriber, sharded_callback_messages)
      assert_equal payloads.fetch(:sharded), sharded_message.message
      assert_equal channel, sharded_message.channel
      assert_nil sharded_message.pattern

      matrix_check_no_messages_left_for_listeners(
        [
          [read_method, exact_subscriber, exact_callback_messages, 2],
          [read_method, pattern_subscriber, pattern_callback_messages, 2],
          [read_method, sharded_subscriber, sharded_callback_messages, 1]
        ]
      )
    end

    def matrix_assert_same_name_ordinary_messages(
      read_method,
      subscriber,
      callback_messages,
      channel,
      expected_payloads,
      expected_pattern:
    )
      first = matrix_get_message_by_method(read_method, subscriber, callback_messages, 0)
      second = matrix_get_message_by_method(read_method, subscriber, callback_messages, 1)

      refute_equal first.message, second.message
      assert_includes expected_payloads, second.message
      assert_includes expected_payloads, first.message
      assert_equal channel, first.channel
      assert_equal channel, second.channel

      if expected_pattern
        assert_equal expected_pattern, first.pattern
        assert_equal expected_pattern, second.pattern
      else
        assert_nil first.pattern
        assert_nil second.pattern
      end
    end

    def matrix_assert_combined_three_listener_delivery(
      read_method,
      publisher,
      exact:,
      pattern:,
      sharded:
    )
      matrix_publish_combined_channels_once(
        publisher,
        exact.fetch(2),
        pattern.fetch(2)
      )
      sharded.fetch(2).each do |channel, payload|
        assert_equal 1, publisher.publish(payload, channel, sharded: true)
      end

      listeners = [exact, pattern, sharded]
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + MATRIX_BULK_MESSAGE_WAIT_SECONDS
      listeners.each do |listener|
        subscriber, callback_messages, channels_and_messages, expected_pattern = listener
        matrix_assert_combined_listener_messages(
          read_method,
          subscriber,
          callback_messages,
          channels_and_messages,
          expected_pattern,
          deadline: deadline
        )
      end

      matrix_check_combined_three_listeners_empty(read_method, listeners)
    end

    def matrix_check_combined_three_listeners_empty(read_method, listeners)
      listener_checks = listeners.map do |subscriber, callback_messages, channels_and_messages, _expected_pattern|
        [read_method, subscriber, callback_messages, channels_and_messages.length]
      end

      matrix_check_no_messages_left_for_listeners(listener_checks)
    end

    def matrix_publish_combined_channels_once(publisher, *channel_message_maps)
      channel_message_maps.each do |channels_and_messages|
        channels_and_messages.each do |channel, payload|
          receiver_count = publisher.publish(payload, channel)
          assert_equal 1, receiver_count if cluster_mode?
        end
      end
    end

    def matrix_assert_combined_multiple_client_delivery(exact_listener, pattern_listener)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + MATRIX_BULK_MESSAGE_WAIT_SECONDS
      matrix_assert_combined_listener_messages(*exact_listener, deadline: deadline)
      matrix_assert_combined_listener_messages(*pattern_listener, deadline: deadline)

      listener_checks = [exact_listener, pattern_listener].map do |read_method, subscriber, callback_messages, messages,
                                                                    _pattern|
        [read_method, subscriber, callback_messages, messages.length]
      end

      matrix_check_no_messages_left_for_listeners(listener_checks)
    end

    def matrix_assert_combined_listener_messages(
      read_method,
      subscriber,
      callback_messages,
      channels_and_messages,
      expected_pattern,
      deadline:
    )
      remaining_channels_and_messages = channels_and_messages.dup
      received_messages = matrix_collect_messages_by_method(
        read_method,
        subscriber,
        callback_messages,
        channels_and_messages.length,
        deadline: deadline
      )

      received_messages.each do |received|
        channel = received.channel.to_s

        assert remaining_channels_and_messages.key?(channel),
               "unexpected or duplicate Pub/Sub channel: #{channel.inspect}"
        assert_equal remaining_channels_and_messages.fetch(channel), received.message
        expected_pattern ? assert_equal(expected_pattern, received.pattern) : assert_nil(received.pattern)
        remaining_channels_and_messages.delete(channel)
      end

      assert_empty remaining_channels_and_messages
    end

    def with_matrix_pubsub_clients(
      subscription_method,
      channels: [],
      patterns: [],
      sharded: [],
      callback: nil,
      context: nil,
      client_options: {},
      client_timeout: nil,
      fresh_publisher: false,
      subscription_timeout_ms: 5000,
      state_timeout: MESSAGE_WAIT_SECONDS,
      always_poll_subscription_state: false,
      cleanup_config_subscriptions: false
    )
      subscriptions = matrix_subscription_sets(channels: channels, patterns: patterns, sharded: sharded)
      pubsub = {}
      pubsub[:subscriptions] = subscriptions if subscription_method == :config && subscriptions.any?
      pubsub[:callback] = callback if callback
      pubsub[:context] = context if context

      options = { protocol: :resp3 }.merge(client_options)
      options[:pubsub] = pubsub unless pubsub.empty?
      subscriber = matrix_new_client(options, timeout: client_timeout)
      publisher = matrix_new_client({}, timeout: client_timeout) if fresh_publisher

      matrix_subscribe_by_method(
        subscriber,
        subscription_method,
        subscriptions,
        timeout_ms: subscription_timeout_ms
      )
      matrix_wait_for_subscription_state_if_needed(
        subscriber,
        subscription_method,
        subscriptions,
        timeout: state_timeout,
        always_poll: always_poll_subscription_state
      )

      yield subscriber, publisher || r
    ensure
      original_error = $ERROR_INFO

      begin
        if cleanup_config_subscriptions && subscription_method == :config && subscriber
          matrix_cleanup_config_subscriptions(subscriber, subscriptions)
        end
      rescue StandardError => e
        raise e unless original_error

        warn "Failed to clean up config Pub/Sub subscriptions: #{e.message}"
      ensure
        begin
          subscriber&.close
        ensure
          publisher&.close
        end
      end
    end

    def with_matrix_bare_pubsub_client(callback: nil, context: nil, client_options: {})
      pubsub = {}
      pubsub[:callback] = callback if callback
      pubsub[:context] = context if context
      options = { protocol: :resp3 }.merge(client_options)
      options[:pubsub] = pubsub unless pubsub.empty?
      subscriber = _new_client(options)

      yield subscriber
    ensure
      subscriber&.close
    end

    def matrix_subscription_sets(channels: [], patterns: [], sharded: [])
      {
        exact: channels,
        pattern: patterns,
        sharded: sharded
      }.reject { |_mode, values| values.empty? }
    end

    def matrix_new_client(options, timeout:)
      return _new_client(options) unless timeout

      timeout_options = options.merge(timeout: timeout, connect_timeout: timeout)
      if cluster_mode?
        addresses = Helper::Cluster.cluster_addresses
        nodes = addresses.empty? ? CLUSTER_NODES : addresses
        Valkey.new(timeout_options.merge(nodes: nodes, cluster_mode: true))
      else
        address = Helper::Client.server_address
        Valkey.new(timeout_options.merge(host: address[:host], port: address[:port]))
      end
    end

    def matrix_subscribe_by_method(subscriber, subscription_method, subscriptions, timeout_ms: 5000)
      case subscription_method
      when :config
        # Config subscriptions are established at client creation.
        nil
      when :lazy
        matrix_each_subscription_mode(subscriptions) do |mode, values|
          subscriber.public_send(matrix_subscription_command(mode, :subscribe, :lazy), *values)
        end
      when :blocking
        matrix_each_subscription_mode(subscriptions) do |mode, values|
          subscriber.public_send(
            matrix_subscription_command(mode, :subscribe, :blocking),
            *values,
            timeout_ms: timeout_ms
          )
        end
      else
        raise ArgumentError, "unknown subscription method: #{subscription_method}"
      end
    end

    def matrix_unsubscribe_by_method(subscriber, subscription_method, subscriptions, timeout_ms: 5000)
      case subscription_method
      when :lazy
        matrix_each_subscription_mode(subscriptions) do |mode, values|
          subscriber.public_send(matrix_subscription_command(mode, :unsubscribe, :lazy), *values)
        end
      when :blocking
        matrix_each_subscription_mode(subscriptions) do |mode, values|
          subscriber.public_send(
            matrix_subscription_command(mode, :unsubscribe, :blocking),
            *values,
            timeout_ms: timeout_ms
          )
        end
      else
        raise ArgumentError, "unknown unsubscription method: #{subscription_method}"
      end
    end

    def matrix_cleanup_config_subscriptions(subscriber, subscriptions)
      matrix_each_subscription_mode(subscriptions) do |mode, values|
        command = matrix_subscription_command(mode, :unsubscribe, :blocking)
        subscriber.public_send(command, *values, timeout_ms: 5000)
      end
    end

    def matrix_unsubscribe_all_by_method(subscriber, subscription_method, modes, timeout_ms:)
      MATRIX_SUBSCRIPTION_MODES.each do |mode|
        next unless modes.include?(mode)

        command = matrix_subscription_command(mode, :unsubscribe, subscription_method)
        if subscription_method == :blocking
          subscriber.public_send(command, timeout_ms: timeout_ms)
        else
          subscriber.public_send(command)
        end
      end
    end

    def matrix_subscription_command(mode, operation, timing)
      commands = {
        exact: {
          subscribe: { lazy: :subscribe_lazy, blocking: :subscribe },
          unsubscribe: { lazy: :unsubscribe_lazy, blocking: :unsubscribe }
        },
        pattern: {
          subscribe: { lazy: :psubscribe_lazy, blocking: :psubscribe },
          unsubscribe: { lazy: :punsubscribe_lazy, blocking: :punsubscribe }
        },
        sharded: {
          subscribe: { lazy: :ssubscribe_lazy, blocking: :ssubscribe },
          unsubscribe: { lazy: :sunsubscribe_lazy, blocking: :sunsubscribe }
        }
      }

      commands.fetch(mode).fetch(operation).fetch(timing)
    end

    def matrix_each_subscription_mode(subscriptions)
      MATRIX_SUBSCRIPTION_MODES.each do |mode|
        values = subscriptions.fetch(mode, [])
        yield mode, values unless values.empty?
      end
    end

    def matrix_wait_for_subscription_state_if_needed(
      subscriber,
      subscription_method,
      expected_subscriptions,
      timeout: MESSAGE_WAIT_SECONDS,
      always_poll: false,
      state: :actual
    )
      expected = matrix_normalize_subscription_sets(expected_subscriptions)
      if subscription_method == :lazy || always_poll
        observed = wait_until(timeout: timeout) do
          current = matrix_subscription_state(subscriber, state)
          current if matrix_subscription_sets_match?(current, expected)
        end

        refute_nil observed, "subscription state did not reach #{expected.inspect}"
        matrix_assert_subscription_sets(expected, observed)
      else
        matrix_assert_subscription_sets(expected, matrix_subscription_state(subscriber, state))
      end
    end

    def matrix_actual_subscriptions(subscriber, mode)
      subscriber.get_subscriptions.actual_subscriptions.fetch(mode, [])
    end

    def matrix_desired_subscriptions(subscriber, mode)
      subscriber.get_subscriptions.desired_subscriptions.fetch(mode, [])
    end

    def matrix_subscription_state(subscriber, state)
      subscriber.get_subscriptions.public_send(:"#{state}_subscriptions")
    end

    def matrix_kill_connections_tolerant(publisher)
      route = Valkey::Route.all_nodes if cluster_mode?
      publisher.call_v(%w[CLIENT KILL SKIPME yes], route: route)
    rescue Valkey::TimeoutError
      nil
    end

    def matrix_wait_for_actual_subscription(subscriber, mode, expected, timeout:)
      observed = wait_until(timeout: timeout) do
        subscriptions = matrix_actual_subscriptions(subscriber, mode)
        subscriptions if subscriptions.include?(expected)
      end

      refute_nil observed, "#{mode} subscription was not restored; last state: " \
                           "#{matrix_actual_subscriptions(subscriber, mode).inspect}"
      assert_includes observed, expected
    end

    def matrix_wait_for_actual_subscriptions(subscriber, mode, expected, timeout:)
      observed = wait_until(timeout: timeout) do
        subscriptions = matrix_actual_subscriptions(subscriber, mode)
        subscriptions if (expected - subscriptions).empty?
      end

      if observed.nil?
        actual = matrix_actual_subscriptions(subscriber, mode)
        flunk("#{mode} subscriptions were not restored; missing: #{(expected - actual).inspect}; " \
              "last state: #{actual.inspect}")
      end

      assert_empty expected - observed
    end

    def matrix_publish_after_reconnection(
      publisher,
      payload,
      channel,
      subscriber,
      read_method,
      callback_messages,
      callback_index
    )
      MATRIX_RECONNECT_PUBLISH_ATTEMPTS.times do
        publisher.publish(payload, channel)
        deadline = monotonic_now + MATRIX_RECONNECT_POLL_SECONDS

        loop do
          message = if read_method == :callback
                      callback_messages[callback_index]
                    else
                      subscriber.try_get_pubsub_message
                    end
          return message if message
          break if monotonic_now >= deadline

          sleep MATRIX_RECONNECT_POLL_INTERVAL_SECONDS
        end
      end

      nil
    end

    def matrix_normalize_subscription_sets(subscriptions)
      return { exact: subscriptions } unless subscriptions.is_a?(Hash)

      subscriptions
    end

    def matrix_subscription_sets_match?(actual, expected)
      expected.all? { |mode, values| actual.fetch(mode, []).sort == values.sort }
    end

    def matrix_assert_subscription_sets(expected, actual)
      expected.each do |mode, values|
        assert_equal values.sort, actual.fetch(mode, []).sort
      end
    end

    def matrix_get_message_by_method(
      read_method,
      subscriber,
      callback_messages,
      callback_index = 0,
      timeout: nil,
      failure_message: nil
    )
      timeout ||= MESSAGE_WAIT_SECONDS

      case read_method
      when :callback
        wait_until(timeout: timeout) { callback_messages[callback_index] } ||
          flunk(failure_message || "callback received no Pub/Sub message at index #{callback_index}")
      when :blocking_get
        matrix_blocking_get(subscriber, timeout: timeout, failure_message: failure_message)
      when :polling_try_get
        wait_for_message(subscriber, timeout: timeout) ||
          flunk(failure_message || "polling read received no Pub/Sub message")
      else
        raise ArgumentError, "unknown message read method: #{read_method}"
      end
    end

    def matrix_collect_messages_by_method(
      read_method,
      subscriber,
      callback_messages,
      expected_count,
      timeout: nil,
      deadline: nil
    )
      deadline ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      deadline_description = timeout ? "the #{timeout}-second case deadline" : "the shared case deadline"

      if read_method == :callback
        remaining_timeout = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        flunk("callback received only 0 of #{expected_count} Pub/Sub messages before the case deadline") unless
          remaining_timeout.positive?

        callback_count = wait_until(timeout: remaining_timeout) do
          callback_messages.length if callback_messages.length >= expected_count
        end
        unless callback_count
          flunk(
            "callback received only #{callback_messages.length} of #{expected_count} Pub/Sub messages " \
            "before #{deadline_description}"
          )
        end

        Array.new(expected_count) { |index| callback_messages.fetch(index) }
      else
        Array.new(expected_count) do |index|
          current_read_method = read_method.respond_to?(:call) ? read_method.call(index) : read_method
          remaining_timeout = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          failure_message = "#{current_read_method} received only #{index} of #{expected_count} Pub/Sub messages " \
                            "before #{deadline_description}"
          flunk(failure_message) unless remaining_timeout.positive?

          matrix_get_message_by_method(
            current_read_method,
            subscriber,
            callback_messages,
            index,
            timeout: remaining_timeout,
            failure_message: failure_message
          )
        end
      end
    end

    def matrix_blocking_get(subscriber, timeout: MESSAGE_WAIT_SECONDS, failure_message: nil)
      reader = Thread.new { subscriber.get_pubsub_message }

      flunk(failure_message || "blocking read received no Pub/Sub message") unless reader.join(timeout)

      reader.value
    ensure
      matrix_cleanup_reader_thread(reader, original_error: $ERROR_INFO)
    end

    def matrix_polling_get(
      subscriber,
      timeout: MESSAGE_WAIT_SECONDS,
      failure_message: "polling read received no message"
    )
      wait_for_message(subscriber, timeout: timeout) || flunk(failure_message)
    end

    def matrix_wait_for_callback_count(callback_messages, expected_count, timeout: MESSAGE_WAIT_SECONDS)
      wait_until(timeout: timeout) { callback_messages.length if callback_messages.length >= expected_count }
    end

    def matrix_pop_callback_notification(callback_notifications, timeout:)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      reader = Thread.new { callback_notifications.pop }

      remaining_timeout = [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max
      reader.value if reader.join(remaining_timeout)
    ensure
      matrix_cleanup_reader_thread(reader, original_error: $ERROR_INFO)
    end

    def matrix_check_no_messages_left(
      read_method,
      subscriber,
      callback_messages,
      expected_callback_count,
      wait_seconds: MATRIX_NO_MESSAGE_WAIT_SECONDS,
      deadline: nil
    )
      deadline ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait_seconds

      case read_method
      when :callback
        assert_equal expected_callback_count, callback_messages.length
      when :blocking_get
        matrix_assert_blocking_get_waits(subscriber, deadline: deadline)
      when :polling_try_get
        assert_nil subscriber.try_get_pubsub_message
      else
        raise ArgumentError, "unknown message read method: #{read_method}"
      end
    end

    def matrix_check_no_messages_left_for_listeners(
      listeners,
      wait_seconds: MATRIX_NO_MESSAGE_WAIT_SECONDS
    )
      blocking_readers = []
      barrier_mutex = Mutex.new
      barrier_condition = ConditionVariable.new
      ready_reader_count = 0
      release_readers = false

      listeners.each do |read_method, subscriber, _callback_messages, _expected_callback_count|
        next unless read_method == :blocking_get

        reader = Thread.new do
          barrier_mutex.synchronize do
            ready_reader_count += 1
            barrier_condition.broadcast
            barrier_condition.wait(barrier_mutex) until release_readers
          end

          begin
            Timeout.timeout(wait_seconds) { [:returned, subscriber.get_pubsub_message] }
          rescue Timeout::Error
            [:timed_out]
          rescue Exception => e # rubocop:disable Lint/RescueException
            [:error, e]
          end
        end
        reader.report_on_exception = false
        blocking_readers << reader
      end

      unless blocking_readers.empty?
        setup_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait_seconds

        barrier_mutex.synchronize do
          until ready_reader_count == blocking_readers.length
            remaining_timeout = setup_deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            flunk "timed out waiting for blocking readers to become ready" unless remaining_timeout.positive?

            barrier_condition.wait(barrier_mutex, remaining_timeout)
          end

          release_readers = true
          barrier_condition.broadcast
        end
      end

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait_seconds

      listeners.each do |read_method, subscriber, callback_messages, expected_callback_count|
        next if read_method == :blocking_get

        matrix_check_no_messages_left(
          read_method,
          subscriber,
          callback_messages,
          expected_callback_count,
          deadline: deadline
        )
      end

      reader_failures = []
      reader_wait_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait_seconds + 1.0

      blocking_readers.each_with_index do |reader, index|
        remaining_timeout = [reader_wait_deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max
        joined_within_deadline = reader.join(remaining_timeout)

        unless joined_within_deadline
          begin
            reader.kill if reader.alive?
          rescue StandardError => e
            reader_failures << "blocking reader #{index} cleanup failed with #{e.class}: #{e.message}"
          ensure
            begin
              reader.join
            rescue StandardError => e
              reader_failures << "blocking reader #{index} cleanup failed with #{e.class}: #{e.message}"
            end
          end
        end

        result = reader.value
        if !joined_within_deadline && result.nil?
          reader_failures << "blocking reader #{index} did not finish its #{wait_seconds}-second observation"
          next
        end

        outcome, detail = result
        case outcome
        when :timed_out
          next
        when :returned
          reader_failures << "blocking reader #{index} unexpectedly returned #{detail.inspect}"
        when :error
          reader_failures << "blocking reader #{index} failed with #{detail.class}: #{detail.message}"
        else
          reader_failures << "blocking reader #{index} produced unexpected result #{result.inspect}"
        end
      end

      flunk reader_failures.join("\n") unless reader_failures.empty?
    ensure
      original_error = $ERROR_INFO
      cleanup_error = nil

      blocking_readers&.each do |reader|
        matrix_cleanup_reader_thread(reader, original_error: original_error)
      rescue StandardError => e
        cleanup_error ||= e
      end

      raise cleanup_error if cleanup_error && !original_error
    end

    def matrix_assert_no_delivery(
      read_method,
      subscriber,
      callback_messages,
      expected_callback_count,
      timeout: UNSUB_WAIT_TIME
    )
      case read_method
      when :callback
        extra = wait_until(timeout: timeout) do
          callback_messages.length if callback_messages.length > expected_callback_count
        end
        assert_nil extra
        assert_equal expected_callback_count, callback_messages.length
      when :blocking_get
        matrix_assert_blocking_get_waits(subscriber, wait_seconds: timeout)
      when :polling_try_get
        assert_nil wait_for_message(subscriber, timeout: timeout)
      else
        raise ArgumentError, "unknown message read method: #{read_method}"
      end
    end

    def matrix_assert_blocking_get_waits(
      subscriber,
      wait_seconds: MATRIX_NO_MESSAGE_WAIT_SECONDS,
      deadline: nil
    )
      deadline ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait_seconds
      reader = Thread.new { subscriber.get_pubsub_message }

      remaining_timeout = [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max
      refute reader.join(remaining_timeout), "blocking read returned with no Pub/Sub message queued"
    ensure
      matrix_cleanup_reader_thread(reader, original_error: $ERROR_INFO)
    end

    def matrix_cleanup_reader_thread(reader, original_error:)
      return unless reader

      cleanup_error = nil

      begin
        reader.kill if reader.alive?
      rescue StandardError => e
        cleanup_error = e
      ensure
        begin
          reader.join
        rescue StandardError => e
          cleanup_error ||= e
        end
      end

      raise cleanup_error if cleanup_error && !original_error
    end

    def matrix_channel_message_map(count, channel_prefix:, payload_prefix: "message")
      Array.new(count).to_h do |index|
        channel = unique_channel("#{channel_prefix}-#{index}")
        [channel, "#{payload_prefix}-#{index}-#{SecureRandom.hex(3)}"]
      end
    end

    def matrix_random_channel_message_map(count, channel_prefix:, channel_suffix_length:, payload_length:)
      channels_and_messages = {}

      while channels_and_messages.length < count
        channel = "#{channel_prefix}#{SecureRandom.alphanumeric(channel_suffix_length)}"
        channels_and_messages[channel] ||= SecureRandom.alphanumeric(payload_length)
      end

      channels_and_messages
    end

    def matrix_supports_sharded_pubsub?
      cluster_mode? && version >= "7.0"
    end
  end
end
