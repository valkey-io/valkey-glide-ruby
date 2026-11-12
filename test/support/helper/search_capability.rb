# frozen_string_literal: true

module Helper
  # Classifies whether the connected valkey-search module supports 1.3
  # features, and reads its active `search.emulate-release` compatibility
  # level, against a real server rather than the vendored RediSearch .so
  # test/support/ uses elsewhere. No module-test harness against a real
  # valkey-search module existed in this repo before this port. Mirrors
  # Python's `requires_search_1_3` capability probe and
  # `emulate_release_level` fixture from #7335 (`python/tests/conftest.py`).
  module SearchCapability
    # Raised when the probe cannot even create a test index — the search
    # module appears entirely absent. Never silently treated as "pre-1.3".
    class ModuleNotLoadedError < StandardError; end

    # Pure classification function, independent of any server round-trip:
    # true if +msg+ matches the pre-1.3.0 "Unexpected argument `INKEYS`"
    # rejection (raw or GLIDE-reformatted spelling — GLIDE's RequestError
    # splits the server's error text on its first word as if it were an
    # error code, so "Unexpected argument `INKEYS`" surfaces client-side as
    # "Unexpected: argument `INKEYS`"). false otherwise — which does not
    # mean "definitely 1.3+"; the caller still has to distinguish "no
    # error at all" (1.3+) from "a different error" (unexpected, should
    # raise loudly).
    #
    # @param msg [String]
    # @return [Boolean]
    def self.inkeys_probe_error?(msg)
      msg.include?("Unexpected") && msg.include?("INKEYS")
    end

    # Probes the connected search module for 1.3 capability using a real
    # command with a fake argument, not a version-string compare: a
    # version string can be present and still not answer whether the
    # specific capability a test needs is actually live. INKEYS is the
    # marker because it is new in 1.3.0-rc1 and is parsed by the module's
    # generic keyword-dispatch machinery, so a module that doesn't
    # understand it rejects it with that parser's generic unknown-argument
    # error rather than silently ignoring it.
    #
    # The probe targets a real (throwaway) index rather than a nonexistent
    # one — a nonexistent index raises its own "Index ... not found" error
    # before option parsing is even reached, on both pre-1.3 and 1.3+
    # modules identically, masking the signal entirely.
    #
    # @param client [Valkey] a connected client
    # @return [Boolean] true if the module is 1.3-capable
    # @raise [ModuleNotLoadedError] if the module appears entirely absent
    #   (FT.CREATE itself fails) — a hard, loud failure rather than a
    #   silent skip
    # @raise [RuntimeError] on any other unexpected error from the probe
    #   itself (a wire-syntax regression, etc.) — not the pre-1.3-vs-1.3
    #   signal this probe exists to detect
    def self.probe_1_3_capability(client)
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
        # The capability gate cleans up loudly: a failed drop retries once,
        # then raises, matching the port rules' "capability probe cleans
        # up loudly" requirement. It never swallows the error.
        drop_probe_index(client, probe_index)
      end
    end

    # @api private
    def self.drop_probe_index(client, probe_index, retried: false)
      client.send_command(Valkey::RequestType::CUSTOM_COMMAND, ["FT.DROPINDEX", probe_index])
    rescue Valkey::CommandError
      raise if retried

      drop_probe_index(client, probe_index, retried: true)
    end

    # Pulls the value out of a `CONFIG GET search.emulate-release` reply.
    # Accepts a Hash (GLIDE's own CONFIG GET shape) or a flat Array/pair
    # list, for safety. Returns nil — rather than raising — when the key
    # is absent, the reply is empty, or the reply is some other shape
    # entirely; the caller decides whether nil means "pre-1.3" or
    # "unparseable reply from a 1.3-capable module".
    #
    # @param config_get_raw [Hash, Array, Object]
    # @return [String, nil]
    def self.parse_emulate_release_level(config_get_raw)
      pairs =
        case config_get_raw
        when Hash then config_get_raw
        when Array
          # Python's zip() truncates to the shorter of the two zipped
          # sequences, which for zip(flat[0::2], flat[1::2]) on an
          # odd-length list means the dangling trailing key is dropped
          # entirely, never paired with a value. Mirror that by discarding
          # any slice that isn't a full pair, rather than raising (bare
          # each_slice(2).to_h raises on a leftover singleton) or inventing
          # a value Python's reply shape never produces.
          config_get_raw.each_slice(2).select { |pair| pair.length == 2 }.to_h
        else return nil
        end
      pairs.each do |key, value|
        decoded_key = key.is_a?(String) ? key : key.to_s
        return value.is_a?(String) ? value : value.to_s if decoded_key == "search.emulate-release"
      end
      nil
    end

    # The connected module's active `search.emulate-release` level (e.g.
    # "1.0.0" at the module's own default, "1.3.0" when explicitly
    # raised), read via `CONFIG GET search.emulate-release`.
    #
    # `probe_1_3_capability` answers "is this binary 1.3-capable at all",
    # not "is the 1.3 RediSearch-compatible behavior actually active right
    # now" — those are different questions, because `search.emulate-release`
    # defaults to the module's current major (1.0.0) regardless of binary
    # version. A 1.3-capable module left at that default still runs the
    # legacy branch of every `VALKEY_SEARCH_COMPATIBILITY_FIX` gate. Tests
    # that assert the *corrected* 1.3 behavior need this to know which
    # branch is actually live, in addition to a 1.3-capability check.
    #
    # @param client [Valkey] a connected client (must already be confirmed
    #   1.3-capable via {probe_1_3_capability} — a pre-1.3 module has no
    #   `search.emulate-release` key at all, which this method cannot
    #   distinguish from a misread of a 1.3-capable module's reply)
    # @return [String, nil] the level, or nil if the module is pre-1.3
    #   (no such config key exists)
    def self.emulate_release_level(client)
      raw = client.send_command(Valkey::RequestType::CONFIG_GET, ["search.emulate-release"])
      parse_emulate_release_level(raw)
    end
  end
end
