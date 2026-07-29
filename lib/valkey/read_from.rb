# frozen_string_literal: true

class Valkey
  #
  # This module defines constants for the `read_from:` connection option values.
  module ReadFrom
    PRIMARY = "Primary"
    PREFER_REPLICA = "PreferReplica"
    AZ_AFFINITY = "AZAffinity"
    AZ_AFFINITY_REPLICAS_AND_PRIMARY = "AZAffinityReplicasAndPrimary"

    # "LowestLatency" is a valid GLIDE value but not yet usable via the vendored
    # native library (panics in ConnectionRequest::from, see types.rs) -- not
    # defined as a constant here since it can't work today, though passing the
    # raw string through directly is still forwarded to the core unchanged.
  end
end
