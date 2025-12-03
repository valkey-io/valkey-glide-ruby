# frozen_string_literal: true

module Lint
  module StreamCommands
    def test_xadd
      # Add entry with auto-generated ID
      id1 = r.xadd("mystream", { "field1" => "value1", "field2" => "value2" })
      assert_match(/\d+-\d+/, id1)

      # Parse the first ID to ensure the second one is greater
      timestamp, _sequence = id1.split("-").map(&:to_i)
      # Use a timestamp that's definitely greater (add 1000ms to be safe)
      future_timestamp = timestamp + 1000
      id2 = r.xadd("mystream", { "field1" => "value1" }, id: "#{future_timestamp}-0")
      assert_equal "#{future_timestamp}-0", id2

      # Verify stream length
      assert_equal 2, r.xlen("mystream")

      r.del "mystream"
    end

    def test_xadd_with_options
      # Add with maxlen trimming (approximate trimming may keep a few more entries)
      r.xadd("mystream", { "field1" => "value1" }, maxlen: 3, approximate: true)
      r.xadd("mystream", { "field2" => "value2" }, maxlen: 3, approximate: true)
      r.xadd("mystream", { "field3" => "value3" }, maxlen: 3, approximate: true)
      r.xadd("mystream", { "field4" => "value4" }, maxlen: 3, approximate: true)
      # Approximate trimming may keep a few more entries, so check it's reasonable
      assert_operator r.xlen("mystream"), :<=, 5

      r.del "mystream"

      # Add with nomkstream option
      result = r.xadd("nonexistent", { "field1" => "value1" }, nomkstream: true)
      assert_nil result
      assert_equal 0, r.xlen("nonexistent")

      r.del "nonexistent"
    end

    def test_xdel
      id1 = r.xadd("mystream", { "field1" => "value1" })
      id2 = r.xadd("mystream", { "field2" => "value2" })
      id3 = r.xadd("mystream", { "field3" => "value3" })

      assert_equal 3, r.xlen("mystream")

      # Delete single entry
      assert_equal 1, r.xdel("mystream", id1)
      assert_equal 2, r.xlen("mystream")

      # Delete multiple entries
      assert_equal 2, r.xdel("mystream", id2, id3)
      assert_equal 0, r.xlen("mystream")

      r.del "mystream"
    end

    def test_xlen
      assert_equal 0, r.xlen("mystream")

      r.xadd("mystream", { "field1" => "value1" })
      assert_equal 1, r.xlen("mystream")

      r.xadd("mystream", { "field2" => "value2" })
      assert_equal 2, r.xlen("mystream")

      r.del "mystream"
    end

    def test_xrange
      # Clean up any existing stream first
      r.del "mystream"

      id1 = r.xadd("mystream", { "field1" => "value1" }, id: "1000-0")
      r.xadd("mystream", { "field2" => "value2" }, id: "2000-0")
      r.xadd("mystream", { "field3" => "value3" }, id: "3000-0")

      # Get all entries (redis-rb format: [id, [field, value, ...]])
      entries = r.xrange("mystream", "-", "+")
      assert_equal 3, entries.length
      assert_equal id1, entries[0][0]
      assert_kind_of Array, entries[0][1] # field-value array (redis-rb format)

      # Get entries with count
      entries = r.xrange("mystream", "-", "+", count: 2)
      assert_equal 2, entries.length

      # Get entries in specific range
      entries = r.xrange("mystream", "1000-0", "2000-0")
      assert_equal 2, entries.length

      r.del "mystream"
    end

    def test_xrevrange
      # Clean up any existing stream first
      r.del "mystream"

      r.xadd("mystream", { "field1" => "value1" }, id: "1000-0")
      r.xadd("mystream", { "field2" => "value2" }, id: "2000-0")
      id3 = r.xadd("mystream", { "field3" => "value3" }, id: "3000-0")

      # Get all entries in reverse (redis-rb format: [id, [field, value, ...]])
      entries = r.xrevrange("mystream")
      assert_equal 3, entries.length
      assert_equal id3, entries[0][0] # Last entry first
      assert_kind_of Array, entries[0][1] # field-value array (redis-rb format)

      # Get last entry
      entries = r.xrevrange("mystream", "+", "-", count: 1)
      assert_equal 1, entries.length
      assert_equal id3, entries[0][0]

      r.del "mystream"
    end

    def test_xtrim
      # Clean up any existing stream first
      r.del "mystream"

      # Add multiple entries
      10.times do |i|
        r.xadd("mystream", { "field" => "value#{i}" })
      end

      assert_equal 10, r.xlen("mystream")

      # Trim to maxlen (use exact trimming to ensure it works)
      removed = r.xtrim("mystream", 5, approximate: false)
      assert_operator removed, :>=, 0
      assert_equal 5, r.xlen("mystream")

      r.del "mystream"
    end

    def test_xread
      # Clean up any existing stream first
      r.del "mystream"

      # Add entries to stream
      r.xadd("mystream", { "field1" => "value1" })
      r.xadd("mystream", { "field2" => "value2" })

      # Read from beginning
      result = r.xread(["mystream"], ["0"])
      assert_kind_of Hash, result
      assert result.key?("mystream")
      assert_operator result["mystream"].length, :>=, 2
      # Verify entries are in redis-rb format: [id, [field, value, ...]]
      assert_kind_of Array, result["mystream"][0]
      assert_equal 2, result["mystream"][0].length
      assert_kind_of Array, result["mystream"][0][1]

      # Read with count
      result = r.xread(["mystream"], ["0"], count: 1)
      assert_operator result["mystream"].length, :<=, 1

      r.del "mystream"
    end

    def test_xreadgroup
      # Clean up any existing stream first
      r.del "mystream"

      # Create stream and add entries
      r.xadd("mystream", { "field1" => "value1" })
      r.xadd("mystream", { "field2" => "value2" })

      # Create consumer group
      r.xgroup_create("mystream", "mygroup", "0", mkstream: true)

      # Read from consumer group
      result = r.xreadgroup("mygroup", "consumer1", ["mystream"], [">"])
      # After HashifyStreams conversion, should be Hash format
      assert_kind_of Hash, result
      assert result.key?("mystream")
      # Entries are converted to [id, hash] format
      assert_operator result["mystream"].length, :>=, 2
      # Verify entries are in redis-rb format: [id, [field, value, ...]]
      assert_kind_of Array, result["mystream"][0]
      assert_equal 2, result["mystream"][0].length
      assert_kind_of Array, result["mystream"][0][1]

      r.del "mystream"
    end

    def test_xgroup_create
      # Create stream first
      r.xadd("mystream", { "field1" => "value1" })

      # Create group from beginning
      assert_equal "OK", r.xgroup_create("mystream", "mygroup", "0")

      # Create group with mkstream
      assert_equal "OK", r.xgroup_create("newstream", "mygroup2", "0", mkstream: true)
      assert_operator r.xlen("newstream"), :>=, 0

      r.del "mystream"
      r.del "newstream"
    end

    def test_xgroup_createconsumer
      r.xadd("mystream", { "field1" => "value1" })
      r.xgroup_create("mystream", "mygroup", "0")

      # Create consumer
      result = r.xgroup_createconsumer("mystream", "mygroup", "consumer1")
      assert_kind_of Integer, result

      r.del "mystream"
    end

    def test_xgroup_setid
      id1 = r.xadd("mystream", { "field1" => "value1" })
      r.xgroup_create("mystream", "mygroup", "0")

      # Set group ID
      assert_equal "OK", r.xgroup_setid("mystream", "mygroup", id1)

      r.del "mystream"
    end

    def test_xgroup_destroy
      r.xadd("mystream", { "field1" => "value1" })
      r.xgroup_create("mystream", "mygroup", "0")

      # Destroy group
      result = r.xgroup_destroy("mystream", "mygroup")
      assert_kind_of Integer, result

      r.del "mystream"
    end

    def test_xgroup_delconsumer
      r.xadd("mystream", { "field1" => "value1" })
      r.xgroup_create("mystream", "mygroup", "0")

      # Read some messages to create pending
      r.xreadgroup("mygroup", "consumer1", ["mystream"], [">"])

      # Delete consumer
      result = r.xgroup_delconsumer("mystream", "mygroup", "consumer1")
      assert_kind_of Integer, result

      r.del "mystream"
    end

    def test_xack
      id1 = r.xadd("mystream", { "field1" => "value1" })
      id2 = r.xadd("mystream", { "field2" => "value2" })
      r.xgroup_create("mystream", "mygroup", "0")

      # Read messages
      r.xreadgroup("mygroup", "consumer1", ["mystream"], [">"])

      # Acknowledge single message
      assert_equal 1, r.xack("mystream", "mygroup", id1)

      # Acknowledge multiple messages
      assert_equal 1, r.xack("mystream", "mygroup", id2)

      r.del "mystream"
    end

    def test_xpending
      # Clean up any existing stream first
      r.del "mystream"

      r.xadd("mystream", { "field1" => "value1" })
      r.xadd("mystream", { "field2" => "value2" })
      r.xgroup_create("mystream", "mygroup", "0")

      # Read messages (creates pending)
      r.xreadgroup("mygroup", "consumer1", ["mystream"], [">"])

      # Get pending summary (converted to Hash)
      pending = r.xpending("mystream", "mygroup")
      assert_kind_of Hash, pending
      assert pending.key?("size")
      assert_operator pending["size"], :>=, 2 # Should have at least 2 pending messages

      # Get detailed pending entries (converted to Array of Hashes)
      entries = r.xpending("mystream", "mygroup", "-", "+", 10)
      assert_kind_of Array, entries
      assert_operator entries.length, :>=, 2 # Should have at least 2 entries
      # Each entry should be a Hash with entry_id, consumer, elapsed, count
      entries.each do |entry|
        assert_kind_of Hash, entry
        assert entry.key?("entry_id")
        assert entry.key?("consumer")
        assert entry.key?("elapsed")
        assert entry.key?("count")
      end

      r.del "mystream"
    end

    def test_xclaim
      # Clean up any existing stream first
      r.del "mystream"

      id1 = r.xadd("mystream", { "field1" => "value1" })
      r.xgroup_create("mystream", "mygroup", "0")

      # Read message with consumer1
      r.xreadgroup("mygroup", "consumer1", ["mystream"], [">"])

      # Wait a bit for idle time
      sleep(0.1)

      # Claim message for consumer2 (redis-rb format: [id, [field, value, ...]])
      claimed = r.xclaim("mystream", "mygroup", "consumer2", 100, [id1])
      assert_kind_of Array, claimed
      assert_operator claimed.length, :>=, 1 # Should claim at least 1 message
      # Each entry should be [id, [field, value, ...]] format (redis-rb)
      claimed.each do |entry|
        assert_kind_of Array, entry
        assert_equal 2, entry.length
        assert_kind_of String, entry[0] # ID
        assert_kind_of Array, entry[1] # field-value array (redis-rb format)
      end

      r.del "mystream"
    end

    def test_xautoclaim
      # Clean up any existing stream first
      r.del "mystream"

      r.xadd("mystream", { "field1" => "value1" })
      r.xgroup_create("mystream", "mygroup", "0")

      # Read message with consumer1
      r.xreadgroup("mygroup", "consumer1", ["mystream"], [">"])

      # Wait a bit for idle time
      sleep(0.1)

      # Auto-claim for consumer2 (redis-rb format: Hash with 'next' and 'entries')
      result = r.xautoclaim("mystream", "mygroup", "consumer2", 100, "0-0")
      assert_kind_of Hash, result
      assert result.key?("next")
      assert result.key?("entries")
      assert_kind_of Array, result["entries"]
      # Verify entries are in redis-rb format: [id, [field, value, ...]]
      result["entries"].each do |entry|
        assert_kind_of Array, entry
        assert_equal 2, entry.length
        assert_kind_of String, entry[0] # ID
        assert_kind_of Array, entry[1] # field-value array (redis-rb format)
      end

      r.del "mystream"
    end

    def test_xinfo_stream
      # Clean up any existing stream first
      r.del "mystream"

      r.xadd("mystream", { "field1" => "value1" })
      r.xadd("mystream", { "field2" => "value2" })

      # Get basic stream info
      info = r.xinfo_stream("mystream")
      assert_kind_of Array, info
      # Info is returned as flat array of key-value pairs
      assert_operator info.length, :>, 0

      r.del "mystream"
    end

    def test_xinfo_groups
      # Clean up any existing stream first
      r.del "mystream"

      r.xadd("mystream", { "field1" => "value1" })
      r.xgroup_create("mystream", "mygroup", "0")

      # Get groups info
      groups = r.xinfo_groups("mystream")
      assert_kind_of Array, groups
      assert_operator groups.length, :>=, 1

      r.del "mystream"
    end

    def test_xinfo_consumers
      # Clean up any existing stream first
      r.del "mystream"

      r.xadd("mystream", { "field1" => "value1" })
      r.xgroup_create("mystream", "mygroup", "0")

      # Read message to create consumer
      r.xreadgroup("mygroup", "consumer1", ["mystream"], [">"])

      # Get consumers info
      consumers = r.xinfo_consumers("mystream", "mygroup")
      assert_kind_of Array, consumers
      assert_operator consumers.length, :>=, 1 # Should have at least 1 consumer

      r.del "mystream"
    end

    # TODO: Implement xsetid command after enabling in glide-core
    # def test_xsetid
    #   target_version "5.0" do
    #     # Clean up any existing stream first
    #     r.del "mystream"

    #     id1 = r.xadd("mystream", { "field1" => "value1" })

    #     # Set stream ID
    #     assert_equal "OK", r.xsetid("mystream", id1)

    #     r.del "mystream"
    #   end
    # end
  end
end
