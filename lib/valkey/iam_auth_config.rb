# frozen_string_literal: true

class Valkey
  # Configuration for AWS IAM authentication.
  #
  # GLIDE Core resolves AWS credentials, validates the configuration, and
  # refreshes tokens automatically. When no interval is provided, Core uses
  # 300 seconds; explicit intervals must be within `1...43_200`.
  class IamAuthConfig
    # @return [String] ElastiCache replication group or MemoryDB cluster name
    attr_reader :cluster_name

    # @return [String] one of the {ServiceType} constants
    attr_reader :service

    # @return [String] AWS region containing the cluster
    attr_reader :region

    # @return [Integer, nil] token refresh interval, or `nil` for Core's default
    attr_reader :refresh_interval_seconds

    # Creates IAM authentication configuration.
    #
    # @param cluster_name [String] ElastiCache replication group or MemoryDB cluster name
    # @param service [String] one of the {ServiceType} constants
    # @param region [String] AWS region containing the cluster
    # @param refresh_interval_seconds [Integer, nil] token refresh interval in seconds;
    #   `nil` uses Core's 300-second default
    def initialize(cluster_name:, service:, region:, refresh_interval_seconds: nil)
      @cluster_name = cluster_name
      @service = service
      @region = region
      @refresh_interval_seconds = refresh_interval_seconds
    end
  end
end
