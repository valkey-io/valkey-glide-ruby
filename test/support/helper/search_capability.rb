# frozen_string_literal: true

module Helper
  module SearchCapability
    class ModuleNotLoadedError < StandardError; end

    def self.inkeys_probe_error?(msg)
      msg.include?("Unexpected") && msg.include?("INKEYS")
    end

    def self.probe_search_1_3_capability(client)
      probe_index = "__glide_rb_search_1_3_probe_#{SecureRandom.hex}"
      begin
        client.send_command(Valkey::RequestType::CUSTOM_COMMAND,
                            ["FT.CREATE", probe_index, "SCHEMA", "title", "TEXT"])
      rescue Valkey::CommandError => e
        raise ModuleNotLoadedError,
              "search 1.3 capability probe could not create a test index " \
              "(is the search module loaded at all?): #{e.message}"
      end
      begin
        client.send_command(Valkey::RequestType::CUSTOM_COMMAND,
                            ["FT.SEARCH", probe_index, "*", "INKEYS", "0"])
        true
      rescue Valkey::CommandError => e
        return false if inkeys_probe_error?(e.message)

        raise "search 1.3 capability probe got an unexpected error: #{e.message}"
      ensure
        drop_probe_index(client, probe_index)
      end
    end

    def self.drop_probe_index(client, probe_index, retried: false)
      client.send_command(Valkey::RequestType::CUSTOM_COMMAND, ["FT.DROPINDEX", probe_index])
    rescue Valkey::CommandError
      raise if retried

      drop_probe_index(client, probe_index, retried: true)
    end

    def self.parse_emulate_release_level(config_get_raw)
      pairs =
        case config_get_raw
        when Hash then config_get_raw
        when Array
          config_get_raw.each_slice(2).select { |pair| pair.length == 2 }.to_h
        else return nil
        end
      pairs.each do |key, value|
        decoded_key = key.is_a?(String) ? key : key.to_s
        return value.is_a?(String) ? value : value.to_s if decoded_key == "search.emulate-release"
      end
      nil
    end

    def self.emulate_release_level(client)
      raw = client.send_command(Valkey::RequestType::CONFIG_GET, ["search.emulate-release"])
      parse_emulate_release_level(raw)
    end
  end
end
