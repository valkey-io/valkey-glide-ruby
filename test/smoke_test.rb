# frozen_string_literal: true

##
# Smoke test for the packaged gem — validates that:
#   1. The gem loads and the FFI native library is found
#   2. The Valkey client class is available
#
# Used by the CD workflow (cd.yml) to verify the built gem artifact
# on each platform. Does NOT require a running server.
#
# Usage:
#   ruby test/smoke_test.rb

require "valkey"

puts "=== Valkey GLIDE Ruby Smoke Test ==="
puts "  Version: #{Valkey::VERSION}"

# Verify FFI bindings loaded (would raise LoadError/FFI::NotFoundError if native lib is missing)
raise "Bindings module not defined" unless defined?(Valkey::Bindings)

puts "  FFI bindings: OK"

# Verify client can be constructed with lazy_connect (no server needed)
client = Valkey.new(host: "127.0.0.1", port: 6379, lazy_connect: true)
raise "Client not a Valkey instance" unless client.is_a?(Valkey)

puts "  Client creation (lazy): OK"

client.close
puts "=== Smoke test passed ==="
