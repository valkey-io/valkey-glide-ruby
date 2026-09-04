# frozen_string_literal: true

module Helper
  class Version
    include Comparable

    # A fully-anchored dotted-numeric version with an optional pre-release
    # suffix: "8", "8.1", "8.1.0", "8.1.0-rc1", "8.1.0-alpha.2".
    #
    # Anchored at BOTH ends deliberately. With no \z, "8garbage" matched and gated
    # to RUN — a false PASS, which is worse than a skip because the test then
    # executes against a server whose version is unknown. The pre-release suffix
    # is admitted explicitly rather than by leaving the end open, so real-world
    # rc/alpha builds are accepted without also accepting arbitrary trailing text.
    PARSEABLE = /\A\d+(\.\d+)*(-[0-9A-Za-z.]+)?\z/

    # Versions at or below this are treated as unusable rather than merely old.
    # "0" and "0.0" are the sentinel values whose removal from the version helpers
    # this predicate exists to make permanent: they are indistinguishable from
    # "detection failed", so accepting them would silently reinstate the
    # skip-everything behaviour by another route.
    UNUSABLE_MAJOR = 0

    attr_reader :parts

    # True when +value+ is a usable, fully-parseable version string.
    #
    # Comparison is lenient by design: `initialize` stringifies anything and
    # `<=>` compares with #to_i, so a non-numeric part silently becomes 0 and an
    # unparseable string like "unstable" or "" sorts BELOW every real version.
    # That makes garbage the *winner* of a minimum and drags version gates down
    # instead of failing, so callers deriving a version from server data must
    # screen it through here first rather than trusting truthiness.
    def self.parseable?(value)
      return false if value.is_a?(Version)
      return false unless value.is_a?(String) && PARSEABLE.match?(value)

      # Reject 0.x: a zero major is the sentinel shape, not a real server version.
      value.split(".").first.to_i > UNUSABLE_MAJOR
    end

    def initialize(version)
      @parts = case version
               when Version
                 version.parts
               else
                 version.to_s.split(".")
               end
    end

    def <=>(other)
      other = Version.new(other)
      length = [parts.length, other.parts.length].max
      length.times do |i|
        a = parts[i]
        b = other.parts[i]

        return -1 if a.nil?
        return +1 if b.nil?
        return a.to_i <=> b.to_i if a != b
      end

      0
    end
  end
end
