# frozen_string_literal: true

require "test_helper"

class TestClusterIamAuthentication < Minitest::Test
  include Helper::Cluster
  include ValkeyTests::IamAuthentication
end
