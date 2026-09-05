# frozen_string_literal: true

class Valkey
  class BaseError < StandardError; end

  class ProtocolError < BaseError
    def initialize(reply_type)
      super(<<-MESSAGE.gsub(/(?:^|\n)\s*/, " "))
        Got '#{reply_type}' as initial reply byte.
        If you're in a forking environment, such as Unicorn, you need to
        connect to Valkey after forking.
      MESSAGE
    end
  end

  class CommandError < BaseError; end

  # Raised when EXEC aborts a transaction before any queued command ran
  # (e.g. a queued command had a syntax/arity error) - distinct from a
  # plain CommandError so callers know nothing was applied.
  class ExecAbortError < CommandError; end

  class PermissionError < CommandError; end

  class WrongTypeError < CommandError; end

  class OutOfMemoryError < CommandError; end

  class NoScriptError < CommandError; end

  class BaseConnectionError < BaseError; end

  class CannotConnectError < BaseConnectionError; end

  class ConnectionError < BaseConnectionError; end

  class TimeoutError < BaseConnectionError; end

  # Raised when the connection was inherited by a child process.
  #
  # A native client handle cannot survive `fork()`: the Rust runtimes and
  # background threads behind it exist only in the parent. Create a new client
  # in the child rather than reusing the inherited one.
  class InheritedError < BaseConnectionError; end

  class ReadOnlyError < BaseConnectionError; end

  class InvalidClientOptionError < BaseError; end

  class SubscriptionError < BaseError; end
end
