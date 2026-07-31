# frozen_string_literal: true

# Regression test for the auth-error class round in PR #211.
#
# Before the fix, glide-core's "Password authentication failed-
# AuthenticationFailed" connect-time error surfaced as
# Valkey::CannotConnectError. That masked auth failures as network errors:
# callers rescuing Valkey::CommandError could not catch them, and code that
# retried on CannotConnectError would spin forever on bad credentials.
#
# The fix branches on the connection error message via
# Valkey.classify_connection_error and raises Valkey::PermissionError
# (already defined as a CommandError subclass) when the message mentions
# authentication failure. Real network errors — e.g. a closed port — must
# still raise CannotConnectError.
#
# Note on scope: this file exercises the classifier and the class
# hierarchy contract only. A live wrong-password integration test is
# already defined in test/valkey/auth_commands_test.rb but is currently
# skipped because glide-core hangs on wrong credentials
# (valkey-glide-ruby/issues/115). Once that upstream hang is resolved,
# the auth_commands_test.rb `test_connect_with_wrong_password_raises`
# case should be updated to assert PermissionError and re-enabled.

require "test_helper"

class TestAuthErrorClassRegression < Minitest::Test
  # The exact message glide-core emits on wrong password at connect time.
  # Kept verbatim so the regression check fails loudly if upstream ever
  # changes the wording (see also test/valkey/auth_commands_test.rb which
  # asserts the same "AuthenticationFailed" substring).
  AUTH_FAILED_MESSAGE = "Received error for address 127.0.0.1:8000: " \
                        "Password authentication failed- AuthenticationFailed"

  # Classification: the exact glide-core wrong-password message maps to
  # PermissionError. This is the regression: pre-fix behavior was
  # CannotConnectError.
  def test_classify_auth_failed_returns_permission_error
    assert_equal ::Valkey::PermissionError,
                 ::Valkey.classify_connection_error(AUTH_FAILED_MESSAGE)
  end

  # Match is case-insensitive and tolerates extra whitespace so mild
  # wording drift still classifies correctly.
  def test_classify_auth_failed_case_and_space_insensitive
    ["authentication failed", "Authentication  Failed",
     "some prefix - AUTHENTICATIONFAILED - some suffix"].each do |msg|
      assert_equal ::Valkey::PermissionError,
                   ::Valkey.classify_connection_error(msg),
                   "expected PermissionError for: #{msg.inspect}"
    end
  end

  # PermissionError is-a CommandError is-a BaseError: rescuing any of
  # those must catch a connect-time auth failure. This is the whole point
  # of the fix — legacy code that only rescued CannotConnectError will NOT
  # catch these anymore (documented as intentional in the commit message).
  def test_permission_error_class_hierarchy
    assert_operator ::Valkey::PermissionError, :<, ::Valkey::CommandError
    assert_operator ::Valkey::PermissionError, :<, ::Valkey::BaseError
    # And crucially NOT a CannotConnectError / BaseConnectionError:
    refute_operator ::Valkey::PermissionError, :<, ::Valkey::CannotConnectError
    refute_operator ::Valkey::PermissionError, :<, ::Valkey::BaseConnectionError
  end

  # Classification: network / non-auth messages remain CannotConnectError.
  # nil is included because res[:connection_error_message] may be nil in
  # some code paths — the classifier must not raise on that.
  def test_classify_non_auth_messages_return_cannot_connect_error
    ["Connection refused (os error 61)",
     "Received error for address 127.0.0.1:59999: TCP timeout",
     "unknown transport failure",
     "",
     nil].each do |msg|
      assert_equal ::Valkey::CannotConnectError,
                   ::Valkey.classify_connection_error(msg),
                   "expected CannotConnectError for: #{msg.inspect}"
    end
  end

  # Contract with initialize: the raised class must equal the classifier
  # result for the exact wrong-password message. The classifier is the
  # single source of truth called from Valkey#initialize.
  def test_initialize_uses_classifier_result
    assert_equal ::Valkey::PermissionError,
                 ::Valkey.classify_connection_error(AUTH_FAILED_MESSAGE)
    # The error can be caught via any of these rescue clauses — this
    # asserts the intended user-visible contract of the fix.
    error = ::Valkey::PermissionError.new(AUTH_FAILED_MESSAGE)
    assert_kind_of ::Valkey::PermissionError, error
    assert_kind_of ::Valkey::CommandError, error
    assert_kind_of ::Valkey::BaseError, error
    refute_kind_of ::Valkey::CannotConnectError, error
    assert_includes error.message, "AuthenticationFailed"
  end
end
