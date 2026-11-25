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

  # Server error codes mapped to the classes redis-rb raises through
  # redis-client's `CommandError::ERRORS` and `Redis::Client::ERROR_MAPPING`.
  # EXECABORT is deliberate: redis-client has no entry for it and raises a plain
  # `CommandError`, so {ExecAbortError} is a subclass of what redis-rb raises.
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

  GLIDE_PREFIX_PATTERN = /\AAn error was signalled by the server:\s*/
  GLIDE_KIND_PATTERN = /\AAn error was signalled by the server:\s*-\s*(\w+)(?::\s*(.*))?\z/m
  EXTENSION_PATTERN = /\A([A-Za-z][A-Za-z0-9_]*): (.*)\z/m

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
  def self.make_server_reply_error(message, default: CommandError)
    message = normalize_server_error(message)
    SERVER_ERROR_CLASSES.fetch(server_error_code(message), default).new(message).extend(ServerReply)
  end

  # Restores the server's `CODE detail` text from glide-core's rendering.
  #
  # Temporary: this can go once glide-core exposes the server error code, see
  # https://github.com/valkey-io/valkey-glide/issues/7309.
  #
  # @api private
  def self.normalize_server_error(message)
    message = message.to_s.strip

    if (match = message.match(GLIDE_KIND_PATTERN)) && (code = GLIDE_ERROR_KIND_CODES[match[1]])
      # Cluster pipelines repeat glide-core's prefix inside the detail.
      detail = match[2].to_s.sub(GLIDE_PREFIX_PATTERN, "")
      return [code, detail].reject(&:empty?).join(" ")
    end

    # Extension codes may be mixed case (valkey-search's `Invalid: ...`), so only
    # glide-core's own `...Error` names are left alone.
    if (match = message.match(EXTENSION_PATTERN)) && !match[1].end_with?("Error")
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
  private_constant :SERVER_ERROR_CLASSES, :GLIDE_ERROR_KIND_CODES, :GLIDE_PREFIX_PATTERN,
                   :GLIDE_KIND_PATTERN, :EXTENSION_PATTERN
end
