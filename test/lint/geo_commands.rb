# frozen_string_literal: true

module Lint
  module GeoCommands
    def test_geoadd_and_geopos
      r.geoadd("geo_key", 13.361389, 38.115556, "Palermo")
      r.geoadd("geo_key", 15.087269, 37.502669, "Catania")

      positions = r.geopos("geo_key", "Palermo", "Catania")

      expected = [[13.361389, 38.115556], [15.087269, 37.502669]]

      assert_equal 2, positions.length
      positions.each_with_index do |pos, i|
        pos.each_with_index do |coord, j|
          assert_in_delta expected[i][j], coord, 0.00001
        end
      end
    end
  end
end
