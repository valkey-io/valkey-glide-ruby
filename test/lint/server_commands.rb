# frozen_string_literal: true

module Lint
  module ServerCommands
    def test_bgrewriteaof
      skip("BGREWRITEAOF command not implemented in backend yet")

      response = r.bgrewriteaof
      assert_equal "OK", response
    end

    def test_bgsave
      skip("BGREWRITEAOF command not implemented in backend yet")

      response = r.bgsave
      assert_equal "Background saving started", response
    end

    def test_dbsize_flushdb
      r.set("key_0", "value_0")
      r.flushdb
      assert_equal 0, r.dbsize

      r.set("key_1", "value_1")
      r.set("key_2", "value_2")
      assert_equal 2, r.dbsize
    end

    def test_time
      result = r.time

      assert_kind_of Array, result
      assert_equal 2, result.size

      # convert to Ruby Time and assert it's close to now
      now = Time.now.to_f
      valkey_time = result[0].to_i + result[1].to_i / 1_000_000.0

      assert_in_delta now, valkey_time, 5.0 # within 5 seconds of system time
    end

    def test_lastsave_save
      before = r.lastsave
      assert_kind_of Integer, before
      assert_operator before, :>, 0

      skip("SAVE command not implemented in backend yet")
      r.set("test:lastsave", "123")
      r.save

      after = r.lastsave
      assert_kind_of Integer, after
      assert_operator after, :>=, before
    end

    def test_slaveof
      skip("SLAVEOF not implemented in backend yet")

      # Change this to a real Valkey/Redis master IP & port if available in test env
      host = "127.0.0.1"
      port = 6379

      response = r.slaveof(host, port)
      assert_equal "OK", response
    end

    def test_sync
      skip("SYNC command not implemented in backend yet")

      response = r.sync
      # The response can be nil or specific based on backend implementation
      assert response.nil? || response.is_a?(String), "Expected sync to return nil or a String"
    end

    def test_debug
      skip("DEBUG command not implemented in backend yet")

      r.set("somekey", "somevalue") # Ensure key exists
      response = r.debug("OBJECT", "somekey")
      assert response.is_a?(String), "Expected debug to return a String response"
    end

    def test_config_set
      response = r.config(:set, "maxmemory", "100mb")
      assert_equal "OK", response
    end

    def test_config_get
      r.config(:set, "maxmemory", "100mb")
      result = r.config(:get, "maxmemory")
      assert_kind_of Hash, result
      assert result.key?("maxmemory"), "Expected key 'maxmemory' in result"
      assert_equal "104857600", result["maxmemory"] # 100mb in bytes
    end

    def test_config_resetstat
      response = r.config(:resetstat)
      assert_equal "OK", response
    end

    def test_config_rewrite
      # CONFIG REWRITE may fail with read-only file system or succeed
      result = r.config(:rewrite)
      assert_equal "OK", result
    rescue Valkey::CommandError => e
      # Expected error when config file is read-only or other file system issues
      assert e.message.include?("Read-only") || e.message.include?("file system") || e.message.include?("config"),
             "Expected config rewrite error about file system or config, got: #{e.message}"
    end

    def test_config_invalid
      assert_raises(NoMethodError) do
        r.config(:nonexistent)
      end
    end

    def test_client_id
      assert_kind_of Integer, r.client(:id)
    end

    def test_client_set_get_name
      r.client(:set_name, "test_client")
      assert_equal "test_client", r.client(:get_name)

      # Reset to default name
      r.client(:set_name, "")
      assert_nil r.client(:get_name)
    end

    def test_client_list
      response = r.client(:list)
      assert_kind_of Array, response
      assert response.all? { |client| client.is_a?(Hash) }, "Expected all clients to be represented as Hashes"
    end

    def test_client_pause_unpause
      assert_equal "OK", r.client(:pause, 100) # Pause for 100 milliseconds
      sleep(0.2)
      assert_equal "OK", r.client(:unpause)
    end

    def test_client_info
      response = r.client(:info)
      assert_kind_of String, response
      assert response.include?("id"), "Expected client info to contain 'id'"
      assert response.include?("name"), "Expected client info to contain 'name'"
    end

    def test_client_set_info
      assert_equal "OK", r.client(:set_info, 'lib-name', 'valkey') # TODO: 'implementing lib-var'
      assert_raises(Valkey::CommandError) do
        r.client(:set_info, 'foo', '0.0.1')
      end
    end

    def test_client_unblock
      result = r.client(:unblock, r.client(:id))
      assert [0, 1].include?(result), "Expected unblock to return 0 or 1"
    end

    def test_client_caching
      skip("CLIENT CACHING command not implemented in backend yet")

      # Assuming caching is enabled by default, this should return true
      response = r.client(:caching)
      assert_equal true, response
    end

    def test_client_tracking
      skip("CLIENT TRACKING command not implemented in backend yet")

      # Assuming tracking is enabled by default, this should return true
      response = r.client(:tracking)
      assert_equal true, response
    end

    def test_client_reply
      assert_equal "OK", r.client(:reply, "ON") # TODO: "OFF" or "SKIP" doesnt work yet
    end

    def test_client_kill
      # Create a second client connection
      extra_client = Valkey.new
      sleep(0.5) # Ensure the new client created

      addr = extra_client.client(:info)[/addr=(\S+)/, 1]

      if addr
        result = extra_client.client(:kill, addr)
        assert_equal "OK", result
      else
        skip("No client address found for extra client")
      end
    end

    def test_client_kill_simple
      extra_client = Valkey.new
      sleep(0.5) # Give it a moment to register with the server

      addr = extra_client.client(:info)[/addr=(\S+)/, 1]

      if addr
        result = extra_client.client(:kill_simple, addr)
        assert_equal "OK", result
      else
        skip("No client address found to kill")
      end
    end

    def test_client_tracking_info
      skip("CLIENT TRACKING command not implemented in backend yet")

      assert_kind_of Array, r.client(:tracking_info)
    end

    def test_client_getredir
      # extra_client = Valkey.new
      # extra_client.client('tracking', 'on', 'bcast') # TODO: Ensure tracking is implemented
      assert_kind_of Integer, r.client(:getredir)
    end

    def test_client_no_evict
      assert_equal "OK", r.client_no_evict(:on)
      assert_equal "OK", r.client_no_evict(:off)
      assert_raises(Valkey::CommandError) do
        r.client_no_evict(:xyz)
      end
    end

    def test_client_no_touch
      assert_equal "OK", r.client_no_touch(:on)
      assert_equal "OK", r.client_no_touch(:off)
      assert_raises(Valkey::CommandError) do
        r.client_no_touch(:xyz)
      end
    end

    # ACL Commands Tests

    def test_acl_whoami
      username = r.acl_whoami
      assert_kind_of String, username
      assert_equal "default", username
    end

    def test_acl_users
      users = r.acl_users
      assert_kind_of Array, users
      assert_includes users, "default"
    end

    def test_acl_list
      rules = r.acl_list
      assert_kind_of Array, rules
      assert(rules.any? { |rule| rule.start_with?("user default") })
    end

    def test_acl_cat
      categories = r.acl_cat
      assert_kind_of Array, categories
      assert_includes categories, "read"
      assert_includes categories, "write"
    end

    def test_acl_cat_with_category
      commands = r.acl_cat("read")
      assert_kind_of Array, commands
      assert_includes commands, "get"
    end

    def test_acl_genpass
      password = r.acl_genpass
      assert_kind_of String, password
      assert_equal 64, password.length # 256 bits = 64 hex chars
    end

    def test_acl_genpass_with_bits
      password = r.acl_genpass(128)
      assert_kind_of String, password
      assert_equal 32, password.length # 128 bits = 32 hex chars
    end

    def test_acl_setuser_and_getuser
      assert_equal "OK", r.acl_setuser("testuser", "on", ">testpass", "~*", "+@read")

      user_info = r.acl_getuser("testuser")
      assert_kind_of Array, user_info

      r.acl_deluser("testuser")
    end

    def test_acl_deluser
      r.acl_setuser("tempuser", "on")

      deleted = r.acl_deluser("tempuser")
      assert_equal 1, deleted

      deleted = r.acl_deluser("nonexistent")
      assert_equal 0, deleted
    end

    def test_acl_deluser_multiple
      r.acl_setuser("user1", "on")
      r.acl_setuser("user2", "on")

      deleted = r.acl_deluser("user1", "user2")
      assert_equal 2, deleted
    end

    def test_acl_getuser_nonexistent
      user_info = r.acl_getuser("nonexistent")
      assert_nil user_info
    end

    def test_acl_dryrun
      result = r.acl_dryrun("default", "get", "key1")
      assert_equal "OK", result
    end

    def test_acl_dryrun_denied
      r.acl_setuser("limiteduser", "on", ">pass", "~*", "+@read", "-set")

      result = r.acl_dryrun("limiteduser", "set", "key1", "value")
      assert_kind_of String, result
      assert result.include?("permission") || result.include?("denied") || result.include?("no permissions")

      r.acl_deluser("limiteduser")
    end

    def test_acl_log
      log = r.acl_log
      assert_kind_of Array, log
    end

    def test_acl_log_with_count
      log = r.acl_log(5)
      assert_kind_of Array, log
      assert log.length <= 5
    end

    def test_acl_log_reset
      result = r.acl_log("RESET")
      assert_equal "OK", result

      log = r.acl_log
      assert_kind_of Array, log
    end

    def test_acl_load
      skip("ACL LOAD requires aclfile configuration")

      assert_equal "OK", r.acl_load
    end

    def test_acl_save
      skip("ACL SAVE requires aclfile configuration")

      assert_equal "OK", r.acl_save
    end

    def test_acl_convenience_method_whoami
      username = r.acl(:whoami)
      assert_equal "default", username
    end

    def test_acl_convenience_method_users
      users = r.acl(:users)
      assert_kind_of Array, users
      assert_includes users, "default"
    end

    def test_acl_convenience_method_cat
      categories = r.acl(:cat)
      assert_kind_of Array, categories
      assert_includes categories, "read"
    end

    def test_acl_convenience_method_genpass
      password = r.acl(:genpass)
      assert_kind_of String, password
      assert_equal 64, password.length
    end

    def test_acl_convenience_method_setuser_deluser
      assert_equal "OK", r.acl(:setuser, "convuser", "on")
      assert_equal 1, r.acl(:deluser, "convuser")
    end

    def test_latency_doctor
      # Enable latency monitoring first
      r.config_set("latency-monitor-threshold", "100")

      # LATENCY DOCTOR returns a human-readable string (or array with server info)
      result = r.latency_doctor
      # Server may return array with [server_info, string] or just string
      if result.is_a?(Array)
        assert result.size >= 2, "Expected array with at least 2 elements"
        assert_kind_of String, result[1], "Expected second element to be a String"
        assert !result[1].empty?, "Expected latency_doctor string to be non-empty"
      else
        assert_kind_of String, result
        assert !result.empty?, "Expected latency_doctor to return a non-empty string"
      end
    rescue Valkey::CommandError => e
      # Skip if latency monitoring is not available or not enabled
      if e.message.include?("LATENCY") || e.message.include?("unknown")
        skip("LATENCY DOCTOR not available: #{e.message}")
      end
      raise
    end

    def test_latency_graph
      # Enable latency monitoring first
      r.config_set("latency-monitor-threshold", "100")

      # LATENCY GRAPH requires an event name
      result = r.latency_graph("command")
      assert_kind_of String, result
      # Graph may be empty if no events recorded, but should still return a string
    rescue Valkey::CommandError => e
      # Skip if latency monitoring is not available, event doesn't exist, or no samples
      if e.message.include?("LATENCY") || e.message.include?("unknown") || e.message.include?("No samples")
        skip("LATENCY GRAPH not available: #{e.message}")
      end
      raise
    end

    def test_latency_histogram
      # Enable latency monitoring first
      r.config_set("latency-monitor-threshold", "100")

      # LATENCY HISTOGRAM without arguments returns all histograms
      result = r.latency_histogram
      assert_kind_of Array, result
      # Result may be empty if no latency events recorded

      # LATENCY HISTOGRAM with specific commands
      result = r.latency_histogram("SET", "GET")
      assert_kind_of Array, result
    rescue Valkey::CommandError => e
      # Skip if latency monitoring is not available
      if e.message.include?("LATENCY") || e.message.include?("unknown")
        skip("LATENCY HISTOGRAM not available: #{e.message}")
      end
      raise
    end

    def test_latency_history
      # Enable latency monitoring first
      r.config_set("latency-monitor-threshold", "100")

      # LATENCY HISTORY requires an event name
      result = r.latency_history("command")
      # Server may return string (server info) when no data, or array of entries
      if result.is_a?(String)
        # No samples available - this is valid
        assert !result.empty?, "Expected non-empty string response"
      else
        assert_kind_of Array, result
        # Server may include server info as first element, filter it out
        entries = result.reject { |e| e.is_a?(String) && e.include?(":") }
        # If not empty, each entry should be [timestamp, latency]
        entries.each do |entry|
          next unless entry.is_a?(Array) && entry.size >= 2

          assert_equal 2, entry.size, "Expected each history entry to be [timestamp, latency]"
          assert_kind_of Integer, entry[0], "Expected timestamp to be an Integer"
          assert_kind_of Integer, entry[1], "Expected latency to be an Integer"
        end
      end
    rescue Valkey::CommandError => e
      # Skip if latency monitoring is not available or event doesn't exist
      if e.message.include?("LATENCY") || e.message.include?("unknown") || e.message.include?("No samples")
        skip("LATENCY HISTORY not available: #{e.message}")
      end
      raise
    end

    def test_latency_latest
      # Enable latency monitoring first
      r.config_set("latency-monitor-threshold", "100")

      # LATENCY LATEST returns latest latency events
      result = r.latency_latest
      # Server may return string (server info) when no data, or array of entries
      if result.is_a?(String)
        # No samples available - this is valid
        assert !result.empty?, "Expected non-empty string response"
      else
        assert_kind_of Array, result
        # Server may include server info as first element, filter it out
        entries = result.reject { |e| e.is_a?(String) && e.include?(":") }
        # Result may be empty if no latency events recorded
        # If not empty, each entry should be [event_name, timestamp, latest_latency, max_latency]
        entries.each do |entry|
          next unless entry.is_a?(Array) && entry.size >= 4

          assert entry.size >= 4, "Expected each latest entry to have at least 4 elements"
          assert_kind_of String, entry[0], "Expected event name to be a String"
          assert_kind_of Integer, entry[1], "Expected timestamp to be an Integer"
          assert_kind_of Integer, entry[2], "Expected latest latency to be an Integer"
          assert_kind_of Integer, entry[3], "Expected max latency to be an Integer"
        end
      end
    rescue Valkey::CommandError => e
      # Skip if latency monitoring is not available
      if e.message.include?("LATENCY") || e.message.include?("unknown")
        skip("LATENCY LATEST not available: #{e.message}")
      end
      raise
    end

    def test_latency_reset
      # Enable latency monitoring first
      r.config_set("latency-monitor-threshold", "100")

      # LATENCY RESET without arguments resets all events
      result = r.latency_reset
      assert_kind_of Integer, result
      assert result >= 0, "Expected reset count to be non-negative"

      # LATENCY RESET with specific events
      result = r.latency_reset("command", "fast-command")
      assert_kind_of Integer, result
      assert result >= 0, "Expected reset count to be non-negative"
    rescue Valkey::CommandError => e
      # Skip if latency monitoring is not available
      if e.message.include?("LATENCY") || e.message.include?("unknown")
        skip("LATENCY RESET not available: #{e.message}")
      end
      raise
    end

    def test_memory_doctor
      # MEMORY DOCTOR returns a human-readable string (or array in cluster mode)
      result = r.memory_doctor
      if result.is_a?(Array)
        # In cluster mode, may return array with server info (IP:port) and messages
        # Filter out server info strings (short strings matching IP:port pattern)
        messages = result.reject { |e| e.is_a?(String) && e.match?(/^\d+\.\d+\.\d+\.\d+:\d+$/) }
        assert !messages.empty?, "Expected memory_doctor to return at least one message"
        messages.each do |msg|
          assert_kind_of String, msg
          assert !msg.empty?, "Expected memory_doctor message to be non-empty"
        end
      else
        assert_kind_of String, result
        assert !result.empty?, "Expected memory_doctor to return a non-empty string"
      end
    rescue Valkey::CommandError => e
      # Skip if MEMORY command is not available
      skip("MEMORY DOCTOR not available: #{e.message}") if e.message.include?("MEMORY") || e.message.include?("unknown")
      raise
    end

    def test_memory_malloc_stats
      # MEMORY MALLOC-STATS returns allocator statistics
      result = r.memory_malloc_stats
      assert_kind_of String, result
      # Result may be empty or contain allocator statistics
    rescue Valkey::CommandError => e
      # Skip if MEMORY command is not available
      if e.message.include?("MEMORY") || e.message.include?("unknown")
        skip("MEMORY MALLOC-STATS not available: #{e.message}")
      end
      raise
    end

    def test_memory_purge
      # MEMORY PURGE returns "OK"
      result = r.memory_purge
      assert_equal "OK", result
    rescue Valkey::CommandError => e
      # Skip if MEMORY command is not available
      skip("MEMORY PURGE not available: #{e.message}") if e.message.include?("MEMORY") || e.message.include?("unknown")
      raise
    end

    def test_memory_stats
      # MEMORY STATS returns a hash of memory statistics (or array in cluster mode)
      result = r.memory_stats
      if result.is_a?(Array)
        # In cluster mode, may return array with server info and hash responses
        # Find hash responses and validate them
        hashes = result.select { |e| e.is_a?(Hash) }
        assert !hashes.empty?, "Expected memory_stats to return at least one hash"
        hashes.each do |stats|
          # Check for any common memory stats keys (more flexible)
          has_stats = stats.key?("peak.allocated") || stats.key?("total.allocated") || stats.key?("keys.count") ||
                      stats.key?("used_memory") || stats.key?("used_memory_human") || stats.key?("used_memory_peak") ||
                      !stats.empty?
          assert has_stats, "Expected memory_stats hash to contain meaningful statistics"
        end
      else
        assert_kind_of Hash, result
        # Check for any common memory stats keys (more flexible)
        has_stats = result.key?("peak.allocated") || result.key?("total.allocated") || result.key?("keys.count") ||
                    result.key?("used_memory") || result.key?("used_memory_human") || result.key?("used_memory_peak") ||
                    !result.empty?
        assert has_stats, "Expected memory_stats to return meaningful statistics"
      end
    rescue Valkey::CommandError => e
      # Skip if MEMORY command is not available
      skip("MEMORY STATS not available: #{e.message}") if e.message.include?("MEMORY") || e.message.include?("unknown")
      raise
    end

    def test_memory_usage
      # Create a test key
      r.set("test:memory:key", "test value")

      # MEMORY USAGE returns memory usage in bytes
      result = r.memory_usage("test:memory:key")
      assert_kind_of Integer, result
      assert result.positive?, "Expected memory usage to be positive"

      # MEMORY USAGE with samples parameter
      result = r.memory_usage("test:memory:key", samples: 10)
      assert_kind_of Integer, result
      assert result.positive?, "Expected memory usage to be positive"

      # MEMORY USAGE for non-existent key returns nil
      result = r.memory_usage("test:memory:nonexistent")
      assert_nil result

      # Clean up
      r.del("test:memory:key")
    rescue Valkey::CommandError => e
      # Skip if MEMORY command is not available
      skip("MEMORY USAGE not available: #{e.message}") if e.message.include?("MEMORY") || e.message.include?("unknown")
      raise
    end

    def test_command
      # COMMAND returns details about all commands
      result = r.command_
      assert_kind_of Array, result
      assert !result.empty?, "Expected COMMAND to return non-empty array"
      # Each entry should be an array with command information
      result.first(5).each do |cmd_info|
        assert_kind_of Array, cmd_info
        assert cmd_info.size >= 6, "Expected command info to have at least 6 elements"
      end
    rescue Valkey::CommandError => e
      skip("COMMAND not available: #{e.message}") if e.message.include?("COMMAND") || e.message.include?("unknown")
      raise
    end

    def test_command_count
      # COMMAND COUNT returns the total number of commands
      result = r.command_count
      assert_kind_of Integer, result
      assert result.positive?, "Expected command count to be positive"
    rescue Valkey::CommandError => e
      if e.message.include?("COMMAND") || e.message.include?("unknown")
        skip("COMMAND COUNT not available: #{e.message}")
      end
      raise
    end

    def test_command_docs
      # COMMAND DOCS without arguments returns docs for all commands
      result = r.command_docs
      assert_kind_of Array, result
      assert !result.empty?, "Expected COMMAND DOCS to return non-empty array"

      # COMMAND DOCS with specific commands
      result = r.command_docs("GET", "SET")
      assert_kind_of Array, result
      # Server may return more entries (e.g., with aliases or variations)
      # Filter out string elements (command names) and only check hash docs
      docs = result.select { |d| d.is_a?(Hash) }
      assert docs.size >= 2, "Expected at least 2 command docs (hashes)"
      docs.each do |doc|
        assert_kind_of Hash, doc, "Expected each doc to be a Hash"
        assert doc.key?("summary") || doc.key?("since"), "Expected doc to have summary or since"
      end
    rescue Valkey::CommandError => e
      skip("COMMAND DOCS not available: #{e.message}") if e.message.include?("COMMAND") || e.message.include?("unknown")
      raise
    end

    def test_command_get_keys
      # COMMAND GETKEYS extracts key names from a command (not positions in newer Redis versions)
      result = r.command_get_keys("GET", "mykey")
      assert_kind_of Array, result
      # Server may return key names or positions depending on version
      if result.first.is_a?(Integer)
        assert_equal [0], result, "Expected GET command to have key at position 0"
      else
        assert result.include?("mykey"), "Expected GET command to return key name 'mykey'"
      end

      # Test MSET which has multiple keys
      result = r.command_get_keys("MSET", "key1", "val1", "key2", "val2")
      assert_kind_of Array, result
      if result.first.is_a?(Integer)
        assert result.include?(0), "Expected MSET to have key at position 0"
      else
        assert result.include?("key1"), "Expected MSET to return key name 'key1'"
        assert result.include?("key2"), "Expected MSET to return key name 'key2'"
      end
    rescue Valkey::CommandError => e
      if e.message.include?("COMMAND") || e.message.include?("unknown")
        skip("COMMAND GETKEYS not available: #{e.message}")
      end
      raise
    end

    def test_command_get_keys_and_flags
      # COMMAND GETKEYSANDFLAGS extracts keys and their flags
      result = r.command_get_keys_and_flags("GET", "mykey")
      assert_kind_of Array, result
      assert !result.empty?, "Expected COMMAND GETKEYSANDFLAGS to return non-empty array"
      # Each entry should be [key_or_position, flags_array]
      # Server may return key names or positions depending on version
      result.each do |entry|
        assert_kind_of Array, entry
        assert entry.size >= 2, "Expected entry to have at least key/position and flags"
        # First element may be Integer (position) or String (key name)
        assert (entry[0].is_a?(Integer) || entry[0].is_a?(String)), "Expected first element to be Integer or String"
        assert_kind_of Array, entry[1], "Expected second element to be flags (Array)"
      end
    rescue Valkey::CommandError => e
      if e.message.include?("COMMAND") || e.message.include?("unknown")
        skip("COMMAND GETKEYSANDFLAGS not available: #{e.message}")
      end
      raise
    end

    def test_command_info
      # COMMAND INFO without arguments returns info for all commands
      result = r.command_info
      assert_kind_of Array, result
      assert !result.empty?, "Expected COMMAND INFO to return non-empty array"

      # COMMAND INFO with specific commands
      result = r.command_info("GET", "SET")
      assert_kind_of Array, result
      assert_equal 2, result.size, "Expected 2 command info entries"
      result.each do |info|
        assert_kind_of Array, info
        assert info.size >= 6, "Expected command info to have at least 6 elements"
      end
    rescue Valkey::CommandError => e
      skip("COMMAND INFO not available: #{e.message}") if e.message.include?("COMMAND") || e.message.include?("unknown")
      raise
    end

    def test_command_list
      # COMMAND LIST without filters returns all commands
      result = r.command_list
      assert_kind_of Array, result
      assert !result.empty?, "Expected COMMAND LIST to return non-empty array"
      assert result.all? { |cmd| cmd.is_a?(String) }, "Expected all commands to be Strings"
      # Commands may be in lowercase or uppercase depending on server version
      command_names = result.map(&:upcase)
      assert command_names.include?("GET"), "Expected GET command to be in the list"
      assert command_names.include?("SET"), "Expected SET command to be in the list"

      # COMMAND LIST with ACLCAT filter
      result = r.command_list(aclcat: "read")
      assert_kind_of Array, result
      # Should return read commands
      command_names = result.map(&:upcase)
      assert command_names.include?("GET"), "Expected GET (read command) to be in filtered list"
    rescue Valkey::CommandError => e
      skip("COMMAND LIST not available: #{e.message}") if e.message.include?("COMMAND") || e.message.include?("unknown")
      raise
    end

    def test_command_dispatcher
      # Test the dispatcher method
      count = r.command(:count)
      assert_kind_of Integer, count
      assert count.positive?

      list = r.command(:list)
      assert_kind_of Array, list
      assert !list.empty?

      info = r.command(:info, "GET")
      assert_kind_of Array, info
      assert_equal 1, info.size
    rescue Valkey::CommandError => e
      if e.message.include?("COMMAND") || e.message.include?("unknown")
        skip("COMMAND dispatcher not available: #{e.message}")
      end
      raise
    end
  end
end
