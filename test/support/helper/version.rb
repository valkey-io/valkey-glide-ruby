# frozen_string_literal: true

module Helper
  class Version
    include Comparable

    # Dotted-numeric with an optional pre-release suffix: "8", "8.1", "8.1.0-rc1".
    # Anchored at both ends, so "8garbage" is not accepted as version 8.
    PARSEABLE = /\A\d+(\.\d+)*(-[0-9A-Za-z.]+)?\z/

    # A zero major means version detection failed, not a genuinely old server.
    UNUSABLE_MAJOR = 0

    attr_reader :parts

    # True when +value+ is a usable, fully-parseable version String; false for a
    # Version instance. Screening matters because `<=>` scores a non-numeric part as
    # 0, so garbage sorts below every real version and would win a minimum.
    def self.parseable?(value)
      return false if value.is_a?(Version)
      return false unless value.is_a?(String) && PARSEABLE.match?(value)

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
