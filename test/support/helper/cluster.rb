# frozen_string_literal: true

module Helper
  module Cluster
    include Generic

    @test_cluster = nil

    class << self
      attr_accessor :test_cluster

      def cluster_addresses
        if ENV["CLUSTER_ENDPOINTS"]
          parse_endpoints(ENV["CLUSTER_ENDPOINTS"])
        elsif test_cluster
          test_cluster.addresses
        else
          start_cluster
          test_cluster.addresses
        end
      end

      def start_cluster
        return if test_cluster

        @test_cluster = Valkey::TestCluster.new(
          cluster_mode: true,
          tls: ENV["CLUSTER_TLS"] == "true",
          load_module: parse_module_paths(ENV.fetch("CLUSTER_MODULES", nil))
        )
      end

      def stop_cluster
        test_cluster&.close
        @test_cluster = nil
      end

      private

      def parse_endpoints(endpoints_str)
        return [] if endpoints_str.nil? || endpoints_str.empty?

        endpoints_str.split(",").map do |endpoint|
          parts = endpoint.strip.rpartition(":")
          host = parts[0]
          port_str = parts[2]
          { host: host, port: port_str.to_i }
        end
      end

      def parse_module_paths(modules_str)
        return nil if modules_str.nil? || modules_str.empty?

        modules_str.split(",").map(&:strip)
      end
    end

    def init(valkey)
      valkey.flushdb
      valkey
    rescue Valkey::CannotConnectError
      puts <<-MSG
        Cannot connect to Valkey.

        Make sure Valkey Cluster Node is running on localhost, port #{PORT_CLUSTER_MODE}.
      MSG
      exit 1
    rescue Valkey::CommandError => e
      # In cluster mode, flushdb might hit a read-only replica
      # This is acceptable during test setup
      raise unless e.message.include?("ReadOnly") || e.message.include?("read only replica")

      valkey
    end

    # Query actual server version from the cluster.
    #
    # Detection failure raises rather than degrading to a sentinel. A sentinel
    # version ("0.0") makes every `omit_version` gate skip, and a skipped test is
    # indistinguishable from a passing one in the suite output — so an
    # undetectable version silently destroys test signal instead of reporting a
    # problem. Failing loudly is the only way that surfaces.
    def version
      info = valkey.info
      ver = extract_version_from_info(info)
      unless Version.parseable?(ver)
        raise "Could not determine a usable server version from INFO " \
              "(got: #{ver.inspect} from #{info.class})"
      end

      Version.new(ver)
    end

    def cluster_mode?
      true
    end

    private

    # Extracts a server version from an INFO reply.
    #
    # A cluster INFO fans out, so the reply may be a per-node Hash
    # ({ "host:port" => { ... } }) or an Array of node replies rather than a flat
    # field hash. Every node is searched, not just the first — an arbitrary node
    # may legitimately lack the version keys, and stopping at it reports "no
    # version found" for a cluster that has one.
    #
    # When nodes disagree, the MINIMUM version is returned: version gates exist
    # to skip tests the weakest node cannot satisfy, so the conservative bound is
    # the correct one and it makes the gate deterministic regardless of hash
    # ordering.
    def extract_version_from_info(info)
      case info
      when Hash
        info["valkey_version"] || info["redis_version"] ||
          min_version(info.values)
      when Array
        min_version(info)
      when String
        # Anchor to the start of a line so an unrelated field that merely ends in
        # "valkey_version" (e.g. "other_valkey_version:9.9.9") cannot be latched.
        ::Regexp.last_match(1) if info =~ /^(?:valkey|redis)_version:(\S+)/
      end
    end

    # Smallest usable version found across node replies, or nil when none report
    # one.
    #
    # Unparseable values are DISCARDED, not ranked. Version comparison treats a
    # non-numeric part as 0, so an empty or garbage string sorts below every real
    # version and would otherwise be elected as the minimum — letting a single bad
    # node silence version-gated tests for the whole cluster. Discarding means a
    # cluster with one bad node and one good node still reports the good version,
    # and a cluster where every node is unusable yields nil, which `version`
    # turns into a loud failure.
    def min_version(entries)
      Array(entries)
        .filter_map { |entry| extract_version_from_info(entry) }
        .select { |ver| Version.parseable?(ver) }
        .min_by { |ver| Version.new(ver) }
    end

    def _new_client(options = {})
      addresses = Helper::Cluster.cluster_addresses
      nodes = addresses.empty? ? CLUSTER_NODES : addresses
      Valkey.new(options.merge(nodes: nodes, timeout: TIMEOUT, cluster_mode: true))
    end
  end
end
