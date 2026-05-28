# frozen_string_literal: true

# Cluster mode example.
#
# Run: bundle exec ruby examples/cluster.rb
# Requires a 6-node cluster on 127.0.0.1:7000-7005 (see examples/README.md).

require "valkey"

base_port = Integer(ENV.fetch("VALKEY_CLUSTER_PORT", 7000))
host = ENV.fetch("VALKEY_HOST", "127.0.0.1")

nodes = 6.times.map { |i| { host: host, port: base_port + i } }

client = Valkey.new(nodes: nodes, cluster_mode: true)

puts "PING: #{client.ping}"
puts "SET: #{client.set('cluster_key', 'cluster_value')}"
puts "GET: #{client.get('cluster_key')}"

client.del("cluster_key")
client.close

puts "Done."
