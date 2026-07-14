# frozen_string_literal: true

# Behavioral authentication tests for valkey-glide-ruby.
#
# Unlike uri_connection_test.rb (which connects to a no-auth server and rescues
# away every failure), these tests actually toggle auth at runtime via the
# Helper::Generic `with_default_user_password` / `with_acl` block helpers and
# assert the concrete success/failure behavior.
#
# Note:
# - Credentials are created and torn down per-test.
# - ACL rules are defined per node th inside the block helpers.
module ValkeyTests
  module AuthCommands
    WRONG_CREDENTIALS_HANG_SKIP =
      "Disabled: wrong-credentials tests as it is causing suites to hang. See valkey-glide-ruby/issues/115"

    # =========================================================
    # Default user -- connect-time
    # =========================================================

    # should connect and respond to PING when given the correct default-user password
    def test_connect_with_correct_password_succeeds
      with_default_user_password do |_user, password|
        client = _new_client(password: password)
        assert_equal "PONG", client.ping
        client.close
      end
    end

    # should refuse to connect when the default-user password is wrong
    def test_connect_with_wrong_password_raises
      skip(WRONG_CREDENTIALS_HANG_SKIP)
      with_default_user_password do |_user, _password|
        error = assert_raises(::Valkey::CannotConnectError) do
          _new_client(password: "wrongpass", connect_timeout: 1.0, reconnect_attempts: 0)
        end
        # glide-core surfaces a wrong password at connect-time as
        # "Password authentication failed- AuthenticationFailed" (not the raw
        # server WRONGPASS, which only appears via the runtime AUTH command).
        assert_includes error.message, "AuthenticationFailed"
      end
    end

    # should refuse to connect when no credentials are supplied to a password-protected server
    def test_connect_without_password_raises
      with_default_user_password do |_user, _password|
        error = assert_raises(::Valkey::CannotConnectError) do
          _new_client(connect_timeout: 1.0, reconnect_attempts: 0)
        end
        assert_includes error.message, "NOAUTH"
      end
    end

    # should refuse to connect when given an empty password against a password-protected server
    def test_connect_with_empty_password_against_auth_server_raises
      with_default_user_password do |_user, _password|
        error = assert_raises(::Valkey::CannotConnectError) do
          _new_client(password: "", connect_timeout: 1.0, reconnect_attempts: 0)
        end
        # An empty password is currently treated as "no credentials", so the
        # server returns NOAUTH (same as the missing-password case). This
        # empty-vs-missing behavior is implementation-defined and could change.
        assert_includes error.message, "NOAUTH"
      end
    end

    # =========================================================
    # ACL user -- connect-time (skipped in cluster mode)
    # =========================================================

    # should connect and respond to PING when given valid ACL user credentials
    def test_connect_with_acl_user_credentials_succeeds
      skip("ACL auth tests only run on standalone mode") if cluster_mode?
      with_acl do |username, password|
        # Built directly, not via init: johndoe lacks +flushdb.
        client = _new_client(username: username, password: password)
        assert_equal "PONG", client.ping
        client.close
      end
    end

    # should refuse to connect when the ACL user's password is wrong
    def test_connect_with_acl_user_wrong_password_raises
      skip("ACL auth tests only run on standalone mode") if cluster_mode?
      skip(WRONG_CREDENTIALS_HANG_SKIP)
      with_acl do |username, _password|
        error = assert_raises(::Valkey::CannotConnectError) do
          _new_client(username: username, password: "wrong",
                      connect_timeout: 1.0, reconnect_attempts: 0)
        end
        assert_includes error.message, "AuthenticationFailed"
      end
    end

    # should refuse to connect when the username does not exist
    def test_connect_with_acl_user_unknown_username_raises
      skip("ACL auth tests only run on standalone mode") if cluster_mode?
      skip(WRONG_CREDENTIALS_HANG_SKIP)
      with_acl do |_username, password|
        error = assert_raises(::Valkey::CannotConnectError) do
          _new_client(username: "nobody", password: password,
                      connect_timeout: 1.0, reconnect_attempts: 0)
        end
        # An unknown username surfaces the same connect-time auth failure as a
        # wrong password (the server does not distinguish the two to clients).
        assert_includes error.message, "AuthenticationFailed"
      end
    end

    # should raise when an ACL user runs a command outside its permissions
    # The FFI maps the permission error to Valkey::CommandError. glide-core
    # translates the server's NOPERM into a "PermissionDenied" message, so we
    # assert the class and that distinctive token.
    def test_acl_user_disallowed_command_raises
      skip("ACL auth tests only run on standalone mode") if cluster_mode?
      with_acl do |username, password|
        # Built directly, not via init: johndoe lacks +flushdb (and +set).
        client = _new_client(username: username, password: password)
        begin
          error = assert_raises(::Valkey::CommandError) do
            client.set("k", "v")
          end
          assert_includes error.message, "PermissionDenied"
        ensure
          client.close
        end
      end
    end

    # should return OK when AUTH is called with the correct password
    def test_auth_command_with_correct_password
      with_default_user_password do |_user, password|
        client = _new_client(password: password)
        assert_equal "OK", client.auth(password)
        client.close
      end
    end

    # should raise when AUTH is called with the wrong password
    def test_auth_command_with_wrong_password_raises
      with_default_user_password do |_user, password|
        client = _new_client(password: password)
        begin
          error = assert_raises(::Valkey::CommandError) do
            client.auth("wrongpass")
          end
          # The runtime AUTH command surfaces the raw server WRONGPASS reply
          # (unlike connect-time failures, which report AuthenticationFailed).
          assert_includes error.message, "WRONGPASS"
        ensure
          client.close
        end
      end
    end

    # should return OK when AUTH is called with a valid username and password
    def test_auth_command_with_username_and_password
      skip("ACL auth tests only run on standalone mode") if cluster_mode?
      with_acl do |username, password|
        client = _new_client(username: username, password: password)
        begin
          # This switches the live connection to the limited johndoe user;
          # don't run privileged commands on this client afterward.
          assert_equal "OK", client.auth(username, password)
        ensure
          client.close
        end
      end
    end
  end
end
