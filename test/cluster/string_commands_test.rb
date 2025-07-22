# frozen_string_literal: true

require "test_helper"

class TestStringCommandsOnClusters < Minitest::Test
  include Helper::Cluster
  include Lint::StringCommands

  # TODO: info returns string
  # def test_set_and_get
  #   expect(valkey.info).to be_a Hash
  # end
end
