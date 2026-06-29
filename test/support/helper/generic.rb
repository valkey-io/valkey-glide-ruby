# frozen_string_literal: true

module Helper
  module Generic
    include Helper

    attr_reader :log, :valkey

    alias r valkey

    # Credentials used by the auth helpers (with_acl / with_default_user_password).
    AUTH_TEST_PASSWORD = "mysecret"
    ACL_TEST_USERNAME = "johndoe"

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
      admin.acl("SETUSER", ACL_TEST_USERNAME, "on",
                "+ping", "+select", "+command", "+info", "+client",
                "+cluster|slots", "+cluster|nodes", "+readonly",
                ">#{AUTH_TEST_PASSWORD}")
      yield(ACL_TEST_USERNAME, AUTH_TEST_PASSWORD)
    ensure
      admin&.close
      delete_acl_user(ACL_TEST_USERNAME)
    end

    # Remove the ACL test user. Mirrors restore_default_user_nopass: run the
    # cleanup from a fresh privileged (default / no-password) connection rather
    # than as `johndoe` (which lacks +acl) or via a possibly-stale `admin`.
    def delete_acl_user(username)
      client = _new_client
      client.acl("DELUSER", username)
    rescue Valkey::BaseError => e
      warn "[auth-helper] could not delete ACL user `#{username}`: #{e.class}: #{e.message}"
    ensure
      client&.close
    end

    def with_default_user_password
      client = _new_client
      client.acl("SETUSER", "default", ">#{AUTH_TEST_PASSWORD}")
      yield("default", AUTH_TEST_PASSWORD)
    ensure
      client&.close
      restore_default_user_nopass
    end

    def restore_default_user_nopass
      client = _new_client(password: AUTH_TEST_PASSWORD)
      client.acl("SETUSER", "default", "nopass")
    rescue Valkey::BaseError => e
      warn "[auth-helper] could not reset `default` user to nopass: #{e.class}: #{e.message}"
    ensure
      client&.close
    end
  end
end
