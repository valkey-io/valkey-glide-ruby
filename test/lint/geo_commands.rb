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

    def test_geosearch_by_member_basic
      result = r.geosearch("Sicily", "FROMMEMBER", "Palermo", "BYRADIUS", 200, "km")
      assert_kind_of Array, result
      assert_includes result, "Palermo"
      assert_includes result, "Catania"
    end

    def test_geosearch_with_dist_coord
      result = r.geosearch("Sicily", "FROMMEMBER", "Palermo", "BYRADIUS", 200, "km", "WITHDIST", "WITHCOORD")

      result.each do |entry|
        # Check the structure: entry is [member_name, [distance, [lon, lat]]]
        member_name, (distance, coords) = entry

        # Assert member_name is a string
        assert_kind_of String, member_name

        # Assert distance is numeric and non-negative
        assert_kind_of Numeric, distance
        assert_operator distance, :>=, 0.0

        # Assert coordinates is an array with exactly 2 numeric elements
        assert_kind_of Array, coords
        assert_equal 2, coords.size
        coords.each { |coord| assert_kind_of Numeric, coord }
      end
    end

    def test_geosearch_sorted_and_limited
      result = r.geosearch("Sicily", "FROMMEMBER", "Palermo", "BYRADIUS", 200, "km", "ASC", "COUNT", 1)
      assert_equal 1, result.size
    end

    def test_geosearch_fromlonlat
      result = r.geosearch("Sicily", "FROMLONLAT", "13.361389", "38.115556", "BYRADIUS", 200, "km")
      assert_includes result, "Palermo"
    end

    def test_geosearch_box
      result = r.geosearch("Sicily", "FROMMEMBER", "Palermo", "BYBOX", 400, 400, "km")
      assert_includes result, "Palermo"
      assert_includes result, "Catania"
    end

    def test_geosearch_with_invalid_args
      assert_raises Valkey::CommandError do
        # Invalid clause name
        r.geosearch("Sicily", "InvalidClause", "Palermo", "BYRADIUS", 100, "km", "WITHDIST")
      end

      assert_raises Valkey::CommandError do
        # Invalid distance unit
        r.geosearch("Sicily", "FROMMEMBER", "Palermo", "BYRADIUS", 100, "InvalidDistance", "WITHDIST")
      end

      assert_raises Valkey::CommandError do
        # Invalid trailing keyword
        r.geosearch("Sicily", "FROMMEMBER", "Palermo", "BYRADIUS", 100, "km", "InvalidKeyword")
      end
    end

    def test_geosearchstore_saves_expected_items
      stored_count = r.geosearchstore(
        "nearby:palermo",
        "Sicily",
        "FROMMEMBER", "Palermo",
        "BYRADIUS", 200, "km",
        "ASC", "COUNT", 10
      )

      # We expect both "Palermo" and "Catania" to be within 200km radius
      assert_equal 2, stored_count
    end
  end
end
