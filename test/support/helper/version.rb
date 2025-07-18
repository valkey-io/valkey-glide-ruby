# frozen_string_literal: true

module Helper
  class Version
    include Comparable

    attr_reader :parts

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
