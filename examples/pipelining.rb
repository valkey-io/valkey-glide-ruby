# frozen_string_literal: true

# Pipeline example — batch commands in one round trip.
#
# Run: bundle exec ruby examples/pipelining.rb

require "valkey"

host = ENV.fetch("VALKEY_HOST", "127.0.0.1")
port = Integer(ENV.fetch("VALKEY_PORT", 6379))

client = Valkey.new(host: host, port: port)

client.del("pipe_counter")

results = client.pipelined do |pipe|
  pipe.set("pipe_key", "pipe_value")
  pipe.get("pipe_key")
  pipe.incr("pipe_counter")
  pipe.get("pipe_counter")
end

puts "Pipeline results:"
results.each_with_index { |r, i| puts "  [#{i}] #{r.inspect}" }

client.del("pipe_key", "pipe_counter")
client.close

puts "Done."
