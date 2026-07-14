# frozen_string_literal: true

# Client statistics example.
#
# Run: bundle exec ruby examples/statistics.rb

require "valkey"

host = ENV.fetch("VALKEY_HOST", "127.0.0.1")
port = Integer(ENV.fetch("VALKEY_PORT", 6379))

client = Valkey.new(host: host, port: port)
client.set("stats_demo", "1")
client.get("stats_demo")

stats = client.get_statistics

puts "Client statistics:"
stats.each { |k, v| puts "  #{k}: #{v}" }

client.del("stats_demo")
client.close

puts "Done."
