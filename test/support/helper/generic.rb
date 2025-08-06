# frozen_string_literal: true

module Helper
  module Generic
    include Helper

    attr_reader :log, :valkey

    alias r valkey

    def run
      if respond_to?(:around)
        around { super }
      else
        super
      end
    end

    def silent
      verbose = $VERBOSE
      $VERBOSE = false

      begin
        yield
      ensure
        $VERBOSE = verbose
      end
    end

    def setup
      @valkey = init _new_client

      # Run GC to make sure orphaned connections are closed.
      GC.start
      super
    end

    def teardown
      valkey&.close
      super
    end

    def assert_in_range(range, value)
      assert range.include?(value), "expected #{value} to be in #{range.inspect}"
    end

    def target_version(target)
      if version < target
        skip("Requires Valkey > #{target}") if respond_to?(:skip)
      else
        yield
      end
    end

    def keys(pattern = "*")
      list = []

      loop do
        cursor, keys = r.scan(0, match: pattern, count: 100)
        list.concat(keys)
        break if cursor == "0"
      end

      list
    end

    def all_keys
      keys.sort
    end

    def with_db(index)
      r.select(index)
      yield
    end

    def omit_version(min_ver)
      skip("Requires Valkey > #{min_ver}") if version < min_ver
    end

    def version
      Version.new(valkey.info["valkey_version"])
    end

    def with_acl
      admin = _new_client
      admin.acl("SETUSER", "johndoe", "on",
                "+ping", "+select", "+command", "+cluster|slots", "+cluster|nodes", "+readonly",
                ">mysecret")
      yield("johndoe", "mysecret")
    ensure
      admin.acl("DELUSER", "johndoe")
      admin.close
    end

    def with_default_user_password
      admin = _new_client
      admin.acl("SETUSER", "default", ">mysecret")
      yield("default", "mysecret")
    ensure
      admin.acl("SETUSER", "default", "nopass")
      admin.close
    end

    def cluster_mode?
      # Check if we're running in cluster mode by examining the client configuration
      # or by checking if cluster_info returns cluster_state (ok or fail both indicate cluster mode)
      cluster_info = r.cluster_info
      # Both "ok" and "fail" indicate we're in cluster mode - "fail" just means degraded
      %w[ok fail].include?(cluster_info["cluster_state"])
    rescue Valkey::CommandError
      # If cluster commands are disabled, we're in standalone mode
      false
    end

    def skip_unless_cluster_mode
      skip("Test requires cluster mode") unless cluster_mode?
    end

    def skip_if_cluster_mode
      skip("Test not applicable in cluster mode") if cluster_mode?
    end

    # Enhanced helper for cluster command testing
    def assert_cluster_command_behavior(command_name, &_block)
      case cluster_command_category(command_name)
      when :cluster_only
        skip_unless_cluster_mode
      when :standalone_only
        skip_if_cluster_mode
      end
      # Run the block for all cases (including mode_dependent and universal)
      yield
    end

    private

    def cluster_command_category(command_name)
      # Categorize cluster commands based on their behavior
      cluster_only_commands = %i[
        cluster_failover cluster_meet cluster_setslot
        cluster_set_config_epoch cluster_addslots cluster_delslots
        cluster_addslotsrange cluster_delslotsrange cluster_bumpepoch
        cluster_flushslots cluster_replicate
      ]

      mode_dependent_commands = %i[
        cluster_nodes cluster_slots cluster_info cluster_replicas
        cluster_slaves cluster_count_failure_reports cluster_forget
        cluster_reset cluster_saveconfig
      ]

      universal_commands = %i[
        cluster_keyslot cluster_countkeysinslot cluster_getkeysinslot
        cluster_myid readonly readwrite
      ]

      if cluster_only_commands.include?(command_name)
        :cluster_only
      elsif mode_dependent_commands.include?(command_name)
        :mode_dependent
      elsif universal_commands.include?(command_name)
        :universal
      else
        :unknown
      end
    end
  end
end
