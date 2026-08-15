# frozen_string_literal: true

require "test_helper"

# Unit tests for Valkey::Route class.
# These do not require a running server — they test the Ruby layer only.
class TestRouteUnit < Minitest::Test
  def test_all_nodes_route
    route = Valkey::Route.all_nodes
    refute_nil route
  end

  def test_all_primaries_route
    route = Valkey::Route.all_primaries
    refute_nil route
  end

  def test_random_route
    route = Valkey::Route.random
    refute_nil route
  end

  def test_slot_id_route_primary
    route = Valkey::Route.slot_id(1234, :primary)
    refute_nil route
  end

  def test_slot_id_route_replica
    route = Valkey::Route.slot_id(5000, :replica)
    refute_nil route
  end

  def test_slot_key_route
    route = Valkey::Route.slot_key("mykey")
    refute_nil route
  end

  def test_slot_key_route_replica
    route = Valkey::Route.slot_key("mykey", :replica)
    refute_nil route
  end

  def test_by_address_route
    route = Valkey::Route.by_address("10.0.0.1", 6379)
    refute_nil route
  end
end
