# Valkey

A Ruby client library for [Valkey][valkey-home] built with [Valkey Glide Core][valkey-glide-home] that tries to provide a drop in replacement for redis-rb.

## Features

- **High Performance**: Built on Valkey GLIDE Core (Rust-based) for optimal performance
- **OpenTelemetry Integration**: Built-in distributed tracing support
- **Client Statistics**: Real-time monitoring of connections and commands
- **Drop-in Replacement**: Compatible with redis-rb API

## Getting started

Install with:

```
$ gem install valkey
```

You can connect to Valkey by instantiating the `Valkey` class:

```ruby
require "valkey"

valkey = Valkey.new

valkey.set("mykey", "hello world")
# => "OK"

valkey.get("mykey")
# => "hello world"
```

## OpenTelemetry and Monitoring

The Valkey client includes built-in support for OpenTelemetry distributed tracing and client statistics monitoring.

### OpenTelemetry Tracing

Enable automatic tracing of all Valkey operations:

```ruby
require 'valkey'
require 'opentelemetry/sdk'

# Configure OpenTelemetry
OpenTelemetry::SDK.configure do |c|
  c.service_name = 'my-app'
end

# Create client with tracing enabled
client = Valkey.new(
  host: 'localhost',
  port: 6379,
  tracing: true
)

# All commands are automatically traced
client.set('key', 'value')
client.get('key')
```

### Client Statistics

Monitor connection and command metrics in real-time:

```ruby
client = Valkey.new

# Execute some operations
client.set('key1', 'value1')
client.get('key1')

# Get statistics
stats = client.get_statistics

puts "Active connections: #{stats[:connection_stats][:active_connections]}"
puts "Total commands: #{stats[:command_stats][:total_commands]}"
puts "Success rate: #{
  (stats[:command_stats][:successful_commands].to_f / 
   stats[:command_stats][:total_commands] * 100).round(2)
}%"
```

For detailed documentation, see [OPENTELEMETRY_GUIDE.md](OPENTELEMETRY_GUIDE.md) and [opentelemetry_example.rb](opentelemetry_example.rb).

## Documentation

Checkout [the implementation status of the Valkey commands][commands-implementation-progress].


[valkey-home]: https://valkey.io
[valkey-glide-home]: https://github.com/valkey-io/valkey-glide
[commands-implementation-progress]: https://github.com/valkey-io/valkey-glide-ruby/wiki/The-implementation-status-of-the-Valkey-commands

