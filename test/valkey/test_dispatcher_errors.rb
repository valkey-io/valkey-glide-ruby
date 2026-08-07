# frozen_string_literal: true

# Shared tests for the unknown-subcommand dispatcher path:
# `script`, `client`, and `cluster` all build a method name from the
# subcommand and previously leaked `NoMethodError: undefined method
# '<family>_<garbage>'` when the mapping missed. They now raise
# `ArgumentError` with a "unknown <FAMILY> subcommand" message.
module ValkeyTests
  module DispatcherErrors
    def test_script_unknown_subcommand_raises_argument_error
      # BB-3-004
      error = assert_raises(ArgumentError) { r.script(:garbage) }
      assert_match(/unknown SCRIPT subcommand/i, error.message)
    end

    def test_client_unknown_subcommand_raises_argument_error
      # BB-4-005
      error = assert_raises(ArgumentError) { r.client(:garbage) }
      assert_match(/unknown CLIENT subcommand/i, error.message)
    end

    def test_client_getname_and_setname_parity
      # BB-4-005: redis-rb-style :getname / :setname must resolve to the
      # underscored methods (client_get_name / client_set_name).
      assert_equal "OK", r.client(:setname, "dispatcher_test")
      assert_equal "dispatcher_test", r.client(:getname)

      # Snake-case form still works.
      assert_equal "OK", r.client(:set_name, "dispatcher_test_2")
      assert_equal "dispatcher_test_2", r.client(:get_name)
    end

    def test_cluster_unknown_subcommand_raises_argument_error
      # BB-4-006
      error = assert_raises(ArgumentError) { r.cluster(:garbage) }
      assert_match(/unknown CLUSTER subcommand/i, error.message)
    end
  end
end
