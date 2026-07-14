# frozen_string_literal: true

# TODO: the test depends on couple of command groups which are not implemented yet
#
module ValkeyTests
  module Scanning
    # def test_scan_basic
    #   r.debug :populate, 1000
    #
    #   cursor = 0
    #   all_keys = []
    #   loop do
    #     cursor, keys = r.scan cursor
    #     all_keys += keys
    #     break if cursor == "0"
    #   end
    #
    #   assert_equal 1000, all_keys.uniq.size
    # end
    #
    # def test_scan_count
    #   r.debug :populate, 1000
    #
    #   cursor = 0
    #   all_keys = []
    #   loop do
    #     cursor, keys = r.scan cursor, count: 5
    #     all_keys += keys
    #     break if cursor == "0"
    #   end
    #
    #   assert_equal 1000, all_keys.uniq.size
    # end
    #
    # def test_scan_match
    #   r.debug :populate, 1000
    #
    #   cursor = 0
    #   all_keys = []
    #   loop do
    #     cursor, keys = r.scan cursor, match: "key:1??"
    #     all_keys += keys
    #     break if cursor == "0"
    #   end
    #
    #   assert_equal 100, all_keys.uniq.size
    # end
  end
end
