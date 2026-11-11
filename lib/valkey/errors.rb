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

  # Raised on server side errors
  class CommandError < BaseError; end

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

  # Raised on client side errors
  class InvalidClientOptionError < BaseError; end

  class Resp3RequiredError < InvalidClientOptionError
    def initialize(protocol)
      super(format("Pub/Sub requires the RESP3 protocol. Found %p", protocol))
    end
  end

  class SubscriptionError < BaseError; end

  # Server error codes mapped to the same classes redis-rb raises through
  # redis-client's `CommandError::ERRORS` and `Redis::Client::ERROR_MAPPING`.
  # Authentication failures surface as {CannotConnectError}, and MASTERDOWN as
  # {ConnectionError}, exactly as in redis-rb.
  SERVER_ERROR_CLASSES = {
    "EXECABORT" => ExecAbortError,
    "WRONGPASS" => CannotConnectError,
    "NOPERM" => PermissionError,
    "READONLY" => ReadOnlyError,
    "MASTERDOWN" => ConnectionError,
    "WRONGTYPE" => WrongTypeError,
    "OOM" => OutOfMemoryError,
    "NOSCRIPT" => NoScriptError
  }.freeze

  # glide-core renders the server errors it knows as
  # `An error was signalled by the server: - <Kind>: <detail>`, where <Kind> is
  # the `ServerErrorKind` variant name (glide-core/redis-rs/redis/src/types.rs).
  # All other codes, such as WRONGTYPE, OOM and WRONGPASS, are extension errors
  # rendered as `<CODE>: <detail>`. Both are turned back into the server's own
  # `<CODE> <detail>` text, which is what redis-rb exposes as the message.
  GLIDE_ERROR_KIND_CODES = {
    "ResponseError" => "ERR",
    "ExecAbortError" => "EXECABORT",
    "BusyLoadingError" => "LOADING",
    "NoScriptError" => "NOSCRIPT",
    "Moved" => "MOVED",
    "Ask" => "ASK",
    "TryAgain" => "TRYAGAIN",
    "ClusterDown" => "CLUSTERDOWN",
    "CrossSlot" => "CROSSSLOT",
    "MasterDown" => "MASTERDOWN",
    "ReadOnly" => "READONLY",
    "NotBusy" => "NOTBUSY",
    "PermissionDenied" => "NOPERM"
  }.freeze

  # Marks an exception built from a server error reply, as opposed to one raised
  # for a transport failure. The two can share a class - MASTERDOWN and a dropped
  # connection both raise {ConnectionError} - so internal code can tell them apart.
  #
  # @api private
  module ServerReply; end

  # Builds the exception for a server error reply, picking the class from the
  # error code the same way redis-client does and using the server's original
  # error text as the message. Unknown codes yield `default`.
  #
  # @param [String] message the error message returned by the server
  # @param [Class] default the class used when the code is not recognised
  # @return [BaseError]
  # @api private
  def self.error_for(message, default: CommandError)
    message = normalize_server_error(message)
    SERVER_ERROR_CLASSES.fetch(server_error_code(message), default).new(message).extend(ServerReply)
  end

  # @api private
  def self.normalize_server_error(message)
    message = message.to_s.strip

    if (match = message.match(/\AAn error was signalled by the server:\s*-\s*(\w+)(?::\s*(.*))?\z/m)) &&
       (code = GLIDE_ERROR_KIND_CODES[match[1]])
      return [code, match[2]].compact.join(" ").strip
    end

    if (match = message.match(/\A([A-Z][A-Z0-9_]*): (.*)\z/m))
      return "#{match[1]} #{match[2]}".strip
    end

    message
  end

  # @api private
  def self.server_error_code(message)
    # Older servers nest the real error code inside script errors.
    if message.start_with?("ERR Error running script") && (match = message.match(/:\s-([A-Z]+) /))
      return match[1]
    end

    message.split(" ", 2).first.to_s
  end

  private_class_method :normalize_server_error, :server_error_code
  private_constant :SERVER_ERROR_CLASSES, :GLIDE_ERROR_KIND_CODES
end
