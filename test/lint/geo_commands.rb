# frozen_string_literal: true

module Lint
  module GeoCommands
    def setup
      super
      added_items_count = r.geoadd("Sicily", 13.361389, 38.115556, "Palermo", 15.087269, 37.502669, "Catania")

      assert_equal 2, added_items_count
    end

    def test_geopos
      positions = r.geopos("Sicily", "Palermo", "Catania")
      assert_equal 2, positions.length

      expected = [[13.361389, 38.115556], [15.087269, 37.502669]]
      positions.each_with_index do |pos, i|
        pos.each_with_index do |coord, j|
          assert_in_delta expected[i][j], coord, 0.00001
        end
      end
    end

    def test_geohash
      geohash = r.geohash("Sicily", "Palermo")
      assert_equal ["sqc8b49rny0"], geohash

      geohashes = r.geohash("Sicily", "Palermo", "Catania")
      assert_equal %w[sqc8b49rny0 sqdtr74hyu0], geohashes
    end

    def test_geohash_with_nonexistant_location
      geohashes = r.geohash("Sicily", "Palermo", "Rome")
      assert_equal ["sqc8b49rny0", nil], geohashes
    end

    def test_geodist
      distination_in_meters = r.geodist("Sicily", "Palermo", "Catania")
      assert_equal 166_274.1516, distination_in_meters

      distination_in_feet = r.geodist("Sicily", "Palermo", "Catania", 'ft')
      assert_equal 545_518.8700, distination_in_feet
    end

    def test_geodist_with_nonexistant_location
      distination = r.geodist("Sicily", "Palermo", "Rome")
      assert_nil distination
    end
  end
end
