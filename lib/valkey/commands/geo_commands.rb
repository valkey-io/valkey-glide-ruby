# frozen_string_literal: true

class Valkey
  module Commands
    # This module contains commands on geospatial operations.
    #
    # @see https://valkey.io/commands/#geo
    #
    module GeoCommands
      # Add one or more geospatial items (longitude, latitude, name) to a key.
      #
      # @example
      #   valkey.geoadd("locations", 13.361389, 38.115556, "Palermo", 15.087269, 37.502669, "Catania")
      #     # => Integer (number of elements added)
      #
      # @param [String] key the name of the key
      # @param [Array<String, Float>] members one or more longitude, latitude, and name triplets
      # @return [Integer] the number of elements added
      def geoadd(key, *members)
        send_command(RequestType::GEO_ADD, [key, *members])
      end

      # Retrieve the positions (longitude, latitude) of one or more elements.
      #
      # @example
      #   valkey.geopos("locations", "Palermo", "Catania")
      #     # => [[13.361389, 38.115556], [15.087269, 37.502669]]
      #
      # @param [String] key the name of the key
      # @param [Array<String>] members one or more member names to get positions for
      # @return [Array<Array<Float, Float>, nil>] list of positions or nil for missing members
      def geopos(key, *members)
        send_command(RequestType::GEO_POS, [key, *members])
      end

      # Returns geohash string representing position for specified members of the specified key.
      #
      # @param [String] key
      # @param [String, Array<String>] member one member or array of members
      # @return [Array<String, nil>] returns array containg geohash string if member is present, nil otherwise
      def geohash(key, *member)
        send_command(RequestType::GEO_HASH, [key, *member])
      end

      # Returns the distance between two members of a geospatial index
      #
      # @param [String] key
      # @param [Array<String>] members
      # @param ['m', 'km', 'mi', 'ft'] unit
      # @return [String, nil] returns distance in specified unit if both members present, nil otherwise.
      def geodist(key, member1, member2, unit = 'm')
        send_command(RequestType::GEO_DIST, [key, member1, member2, unit])
      end
    end
  end
end
