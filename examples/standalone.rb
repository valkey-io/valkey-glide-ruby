# frozen_string_literal: true

# Basic standalone Valkey example.
#
# Run: bundle exec ruby examples/standalone.rb
# Requires Valkey/Redis on VALKEY_HOST:VALKEY_PORT (default 127.0.0.1:6379).

require "valkey"

host = ENV.fetch("VALKEY_HOST", "127.0.0.1")
port = Integer(ENV.fetch("VALKEY_PORT", 6379))

client = Valkey.new(host: host, port: port)

puts "PING: #{client.ping}"
puts "SET: #{client.set('hello', 'world')}"
puts "GET: #{client.get('hello')}"

client.del("hello")
client.close

puts "Done."
