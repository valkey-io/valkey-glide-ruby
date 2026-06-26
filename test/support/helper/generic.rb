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
      # glide-core runs INFO (and CLIENT) during the connection handshake, so the
      # ACL user must be granted those even though the test only exercises PING/SET.
      # This mirrors the python reference grant (+ping +info +client +cluster ...);
      # +set is intentionally withheld so the disallowed-command test still fails.
      admin.acl("SETUSER", "johndoe", "on",
                "+ping", "+select", "+command", "+info", "+client",
                "+cluster|slots", "+cluster|nodes", "+readonly",
                ">mysecret")
      yield("johndoe", "mysecret")
    ensure
      begin
        admin&.acl("DELUSER", "johndoe")
      rescue Valkey::BaseError
        # best-effort restore; never let teardown cascade into other tests
      ensure
        admin&.close
      end
    end

    def with_default_user_password
      admin = _new_client
      admin.acl("SETUSER", "default", ">mysecret")
      yield("default", "mysecret")
    ensure
      begin
        admin&.acl("SETUSER", "default", "nopass")
      rescue Valkey::BaseError
        # best-effort restore; never let teardown cascade into other tests
      ensure
        admin&.close
      end
    end
  end
end
