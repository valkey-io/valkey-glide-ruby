# frozen_string_literal: true

require "securerandom"

# Pub/Sub reconciliation integration tests.
module ValkeyTests
  module PubSub
    PUBSUB_RECONCILIATION_INTERVAL_MS = 500
    PUBSUB_RECONCILIATION_METRIC_TIMEOUT_SECONDS = 3.0
    PUBSUB_RECONCILIATION_SUBSCRIBE_TIMEOUT_MS = 2000
    PUBSUB_RECONCILIATION_POLL_INTERVAL_SECONDS = 0.02

    def test_sync_subscription_metrics_repeated_reconciliation_failures_with_subscription_method_lazy
      assert_subscription_metrics_repeated_reconciliation_failures(:lazy)
    end

    def test_sync_subscription_metrics_repeated_reconciliation_failures_with_subscription_method_blocking
      assert_subscription_metrics_repeated_reconciliation_failures(:blocking)
    end

    private

    def assert_subscription_metrics_repeated_reconciliation_failures(subscription_method)
      token = "#{Process.pid}-#{SecureRandom.hex(6)}"
      channels = [
        "channel1-repeated-failures-#{token}",
        "channel2-repeated-failures-#{token}"
      ]
      username = "mock-test-user-repeated-#{token}"
      password = "password-repeated-#{SecureRandom.hex(8)}"
      admin = nil
      listener = nil

      begin
        admin = _new_client
        reconciliation_routed_call(
          admin,
          ["ACL", "SETUSER", username, "ON", ">#{password}", "~*", "resetchannels", "+@all", "-@pubsub"]
        )

        listener = _new_client(
          protocol: :resp3,
          pubsub_reconciliation_interval_ms: PUBSUB_RECONCILIATION_INTERVAL_MS
        )
        reconciliation_routed_call(listener, ["AUTH", username, password])

        initial_out_of_sync = listener.get_statistics.fetch(:subscription_out_of_sync_count, 0).to_i

        channels.each do |channel|
          subscribe_without_pubsub_permission(listener, channel, subscription_method)
        end

        out_of_sync_count = wait_for_out_of_sync_count(
          listener,
          initial_out_of_sync + 2,
          timeout: PUBSUB_RECONCILIATION_METRIC_TIMEOUT_SECONDS
        )
        assert_operator out_of_sync_count, :>=, initial_out_of_sync + 2,
                        "Expected at least 2 out-of-sync events, got " \
                        "#{out_of_sync_count - initial_out_of_sync}"
      ensure
        delete_reconciliation_acl_user(admin, username)

        begin
          admin&.close
        ensure
          listener&.close
        end
      end
    end

    def subscribe_without_pubsub_permission(listener, channel, subscription_method)
      if subscription_method == :blocking
        begin
          listener.subscribe(channel, timeout_ms: PUBSUB_RECONCILIATION_SUBSCRIBE_TIMEOUT_MS)
        rescue Valkey::TimeoutError
          nil
        end
      else
        listener.subscribe_lazy(channel)
      end
    end

    def reconciliation_routed_call(client, command)
      return client.call_v(command, route: Valkey::Route.all_nodes) if cluster_mode?

      client.call_v(command)
    end

    def wait_for_out_of_sync_count(client, minimum, timeout:)
      deadline = reconciliation_monotonic_now + timeout
      observed = client.get_statistics.fetch(:subscription_out_of_sync_count, 0).to_i

      while observed < minimum && reconciliation_monotonic_now < deadline
        sleep PUBSUB_RECONCILIATION_POLL_INTERVAL_SECONDS
        observed = client.get_statistics.fetch(:subscription_out_of_sync_count, 0).to_i
      end

      observed
    end

    def reconciliation_monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def delete_reconciliation_acl_user(admin, username)
      return unless admin

      reconciliation_routed_call(admin, ["ACL", "DELUSER", username])
    rescue Valkey::BaseError => e
      warn "Failed to delete Pub/Sub ACL test user #{username}: #{e.message}"
    end
  end
end
