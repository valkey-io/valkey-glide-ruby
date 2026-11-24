# frozen_string_literal: true

module Helper
  module SearchModule
    include Helper::ModuleClient

    def search_module_setup(client)
      @capable = Helper::SearchCapability.probe_search_1_3_capability(client)
      @level = @capable ? Helper::SearchCapability.emulate_release_level(client) : nil
      hashtag = SecureRandom.hex(6)
      @index = "{#{hashtag}}idx"
      @prefix = "{#{hashtag}}doc:"
    end

    def search_module_teardown
      @client&.send_command(Valkey::RequestType::CUSTOM_COMMAND, ["FT.DROPINDEX", @index])
    rescue Valkey::CommandError
      nil
    ensure
      @client&.close
    end

    # Skips unless the search module supports the valkey-search 1.3 features.
    def skip_unless_search_1_3!
      skip "search module is pre-1.3 (search.emulate-release unavailable); 1.3 tests skip on this build" unless @capable
    end

    def legacy_level?
      skip_unless_search_1_3!
      @level.nil? || Helper::Version.new(@level) < Helper::Version.new("1.3.0")
    end

    def poll_until_indexed(client, index, expected_count, timeout_secs: 10)
      deadline = Time.now + timeout_secs
      last_count = -1
      loop do
        info = client.ft_info(index)
        info = Valkey::Utils::Hashify.call(info) if info.is_a?(Array)
        raise "poll_until_indexed: FT.INFO reply for #{index} has no num_docs" unless info.key?("num_docs")

        last_count = info["num_docs"].to_i
        return if last_count >= expected_count
        if Time.now > deadline
          raise "poll_until_indexed: #{index} did not reach #{expected_count} docs within #{timeout_secs}s " \
                "(last seen: #{last_count})"
        end

        sleep 0.1
      end
    end

    def create_basic_index(client, index, prefix)
      client.ft_create(
        index,
        [Valkey::Search::TextField.new("title", sortable: true), Valkey::Search::NumericField.new("price")],
        on: :hash, prefixes: [prefix]
      )
    end

    def create_vector_index(client, index, prefix)
      client.ft_create(
        index,
        [
          Valkey::Search::TextField.new("title"),
          Valkey::Search::NumericField.new("price"),
          Valkey::Search::VectorField.flat("vec", dim: 4, metric: :l2)
        ],
        on: :hash, prefixes: [prefix]
      )
    end

    def create_hybrid_index(client, index, prefix)
      client.ft_create(
        index,
        [
          Valkey::Search::TextField.new("title"),
          Valkey::Search::VectorField.flat("vec", dim: 2, metric: :l2)
        ],
        on: :hash, prefixes: [prefix]
      )
      client.hset("#{prefix}text_winner", "title", "hello world", "vec", [1000.0, 1000.0].pack("f*"))
      client.hset("#{prefix}vector_winner", "title", "goodbye", "vec", [10.0, 10.0].pack("f*"))
      poll_until_indexed(client, index, 2)
    end
  end

  class SearchModuleStandaloneCase < Minitest::Test
    include SearchModule

    def setup
      @client = modules_standalone_client
      search_module_setup(@client)
    end

    def teardown
      search_module_teardown
    end
  end

  class SearchModuleClusterCase < Minitest::Test
    include SearchModule

    def setup
      skip "no cluster module endpoints configured" if Helper::ModuleClient.cluster_addresses.empty?
      @client = modules_cluster_client
      search_module_setup(@client)
    end

    def teardown
      search_module_teardown
    end

    def cluster_shards
      reply = @client.send_command(Valkey::RequestType::CUSTOM_COMMAND, %w[CLUSTER SHARDS])
      reply.map do |shard|
        shard_hash = Valkey::Utils::Hashify.call(shard)
        nodes = Array(shard_hash["nodes"]).map { |node| Valkey::Utils::Hashify.call(node) }
        {
          slot_ranges: shard_hash["slots"].each_slice(2).to_a,
          primary: nodes.find { |node| node["role"] == "master" },
          replicas: nodes.select { |node| node["role"] == "replica" }
        }
      end
    end

    def shard_for_key(shards, key)
      slot = @client.send_command(Valkey::RequestType::CUSTOM_COMMAND, ["CLUSTER", "KEYSLOT", key])
      shards.find { |shard| shard[:slot_ranges].any? { |lo, hi| slot.between?(lo, hi) } } ||
        raise("no shard owns slot #{slot} for #{key}")
    end
  end
end
