# frozen_string_literal: true

require "test_helper"

module FtCursorTests
  def test_aggregate_typed_cursor_paged_to_exhaustion
    skip_unless_search_1_3!
    @client.ft_create(@index, [Valkey::Search::NumericField.new("n", sortable: true)], on: :hash, prefixes: [@prefix])
    (1..20).each { |i| @client.hset("#{@prefix}d#{i}", "n", i.to_s) }
    poll_until_indexed(@client, @index, 20)

    seen = Set.new
    total = 0
    page = @client.ft_aggregate(@index, "*", load: ["n"], with_cursor: Valkey::Search::WithCursor.new(count: 5))
    rows, cursor_id = page
    total += rows.length
    seen.merge(rows.map { |row| row["n"].to_i })
    pages_read = 1
    while cursor_id != 0
      rows, cursor_id = @client.ft_cursor_read(@index, cursor_id)
      total += rows.length
      seen.merge(rows.map { |row| row["n"].to_i })
      pages_read += 1
      raise "paging did not terminate" if pages_read > 10
    end
    assert_equal 20, total
    assert_equal Set.new(1..20), seen
  end

  def test_aggregate_typed_cursor_del_and_errors
    skip_unless_search_1_3!
    @client.ft_create(@index, [Valkey::Search::NumericField.new("n", sortable: true)], on: :hash, prefixes: [@prefix])
    (1..5).each { |i| @client.hset("#{@prefix}d#{i}", "n", i.to_s) }
    poll_until_indexed(@client, @index, 5)

    _rows, cursor_id = @client.ft_aggregate(@index, "*", load: ["n"],
                                                         with_cursor: Valkey::Search::WithCursor.new(count: 1))
    refute_equal 0, cursor_id

    assert_equal "OK", @client.ft_cursor_del(@index, cursor_id)

    err = assert_raises(Valkey::CommandError) { @client.ft_cursor_read(@index, cursor_id) }
    assert_match(/Cursor/, err.message)

    err2 = assert_raises(Valkey::CommandError) { @client.ft_cursor_read(@index, 999_999_999) }
    assert_match(/Cursor/, err2.message)
  end
end

class FtCursorStandaloneTest < Helper::SearchModuleStandaloneCase
  include FtCursorTests
end

class FtCursorClusterTest < Helper::SearchModuleClusterCase
  include FtCursorTests

  def test_cursor_commands_use_index_primary_with_prefer_replica_client
    skip_unless_search_1_3!
    @client.ft_create(@index, [Valkey::Search::NumericField.new("n", sortable: true)], on: :hash, prefixes: [@prefix])
    (1..20).each { |i| @client.hset("#{@prefix}d#{i}", "n", i.to_s) }
    poll_until_indexed(@client, @index, 20)

    prefer_replica = Valkey.new(cluster_mode: true, nodes: Helper::ModuleClient.cluster_addresses,
                                timeout: TIMEOUT, read_from: Valkey::ReadFrom::PREFER_REPLICA)
    begin
      rows, cursor_id = prefer_replica.ft_aggregate(@index, "*", load: ["n"],
                                                                 with_cursor: Valkey::Search::WithCursor.new(count: 5))
      seen = rows.map { |row| row["n"].to_i }
      pages_read = 1
      while cursor_id != 0
        rows, cursor_id = prefer_replica.ft_cursor_read(@index, cursor_id)
        seen.concat(rows.map { |row| row["n"].to_i })
        pages_read += 1
        raise "paging did not terminate" if pages_read > 10
      end
      assert_equal (1..20).to_a, seen.sort
      assert_equal 4, pages_read

      replicas = shard_for_key(cluster_shards, @index)[:replicas]
      assert_operator replicas.length, :>=, 1, "fixture bug: no replica found for the index's shard"

      _rows, open_cursor_id = prefer_replica.ft_aggregate(
        @index, "*", load: ["n"], with_cursor: Valkey::Search::WithCursor.new(count: 5)
      )
      replicas.each do |replica|
        direct = Valkey.new(host: replica["ip"], port: replica["port"].to_i, timeout: TIMEOUT)
        begin
          err = assert_raises(Valkey::CommandError) { direct.ft_cursor_read(@index, open_cursor_id) }
          assert_match(/Cursor/i, err.message)
        ensure
          direct.close
        end
      end
      assert_equal "OK", prefer_replica.ft_cursor_del(@index, open_cursor_id)
    ensure
      prefer_replica&.close
    end
  end
end
