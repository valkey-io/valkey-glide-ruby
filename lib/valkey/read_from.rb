# frozen_string_literal: true

class Valkey
  #
  # this module defines constants for the `read_from:` connection option.
  # Each constant is the canonical GLIDE string for that read-routing strategy,
  # matching the RequestType/ResponseType constant modules' convention in this
  # gem. Ruby symbols (`:prefer_replica`) and the exact-match strings
  # (`"PreferReplica"`) are still accepted directly by `Valkey.new` -- these
  # constants are purely an additional, IDE-completion-friendly way to write
  # the same values, not a new validation mechanism.
  #
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
