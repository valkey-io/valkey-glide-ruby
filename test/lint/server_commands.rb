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
  end
end
