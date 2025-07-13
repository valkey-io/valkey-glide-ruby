# frozen_string_literal: true

require 'valkey'

valkey = Valkey.new

valkey.set("foo", "bar")
puts valkey.get("foo")
