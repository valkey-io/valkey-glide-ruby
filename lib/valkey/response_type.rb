# frozen_string_literal: true

class Valkey
  #
  # this module defines constants for response types used in Valkey.
  # Each constant represents a specific type of response that can be received from the server.
  #
  module ResponseType
    NULL = 0
    INT = 1
    FLOAT = 2
    BOOL = 3
    STRING = 4
    ARRAY = 5
    MAP = 6
    SETS = 7
    OK = 8
    ERROR = 9
  end
end
