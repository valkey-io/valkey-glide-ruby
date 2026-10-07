# frozen_string_literal: true

class Valkey
  # AWS services supported for IAM authentication.
  module ServiceType
    # Amazon ElastiCache.
    ELASTICACHE = "ELASTICACHE"

    # Amazon MemoryDB.
    MEMORYDB = "MEMORYDB"
  end
end
