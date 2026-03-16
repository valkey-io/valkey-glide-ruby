# Valkey

A Ruby client library for [Valkey][valkey-home] built with [Valkey Glide Core][valkey-glide-home] that tries to provide a drop in replacement for redis-rb.

## Features

- **High Performance**: Built on Valkey GLIDE Core (Rust-based) for optimal performance
- **OpenTelemetry Integration**: Built-in distributed tracing support
- **Client Statistics**: Real-time monitoring of connections and commands
- **Drop-in Replacement**: Compatible with redis-rb API

## Getting started

#### Building Ruby GLIDE from Source

> **Note**: An updated Ruby gem with the latest FFI library will be released to simplify deployment. This build-from-source approach is a temporary workaround until the official gem is updated.

The public Ruby gem contains an outdated FFI library that crashes in cluster mode. Please build from source instead:

```bash
# 1. Install dependencies
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
brew install protobuf  # macOS
# sudo apt-get install protobuf-compiler  # Ubuntu

# 2. Build glide-core v2.3.0-rc7
git clone https://github.com/valkey-io/valkey-glide.git
cd valkey-glide && git checkout v2.3.0-rc7
cd ffi && cargo build --release

# 3. Get Ruby source and replace FFI library
git clone https://github.com/valkey-io/valkey-glide-ruby.git
cp ../valkey-glide/ffi/target/release/libglide_ffi.so valkey-glide-ruby/lib/valkey/
```

**Integration Options:**

**Option 1: Direct Load Path (Recommended for Development)**
```ruby
# At the top of your application (before requiring valkey)
$LOAD_PATH.unshift('/path/to/valkey-glide-ruby/lib')
require 'valkey'

# Now use normally - cluster mode works perfectly
client = Valkey.new(
  nodes: [
    { host: 'node1.example.com', port: 6379 },
    { host: 'node2.example.com', port: 6379 }
  ],
  cluster_mode: true
)
```

**Option 2: Environment Variable**
```bash
# Set environment variable
export RUBYLIB="/path/to/valkey-glide-ruby/lib:$RUBYLIB"

# Or in your shell profile (.bashrc, .zshrc)
echo 'export RUBYLIB="/path/to/valkey-glide-ruby/lib:$RUBYLIB"' >> ~/.bashrc
```

```ruby
# In your Ruby application
require 'valkey'  # Uses source-built version automatically
```

**Option 3: Bundler with Local Path**
```ruby
# Gemfile
gem 'valkey', path: '/path/to/valkey-glide-ruby'

# Or for specific environments
group :production do
  gem 'valkey', path: '/path/to/valkey-glide-ruby'
end

group :development, :test do
  gem 'valkey'  # Use public gem for standalone mode
end
```

```bash
bundle install
```

**Option 4: Docker Integration**
```dockerfile
FROM ruby:3.2-slim

# Build process (as shown above)
RUN git clone https://github.com/valkey-io/valkey-glide.git /glide
WORKDIR /glide
RUN git checkout v2.3.0-rc7
WORKDIR /glide/ffi
RUN cargo build --release

RUN git clone https://github.com/valkey-io/valkey-glide-ruby.git /ruby-glide
RUN cp /glide/ffi/target/release/libglide_ffi.so /ruby-glide/lib/valkey/

# Set up application
WORKDIR /app
COPY Gemfile* ./
ENV RUBYLIB="/ruby-glide/lib:$RUBYLIB"
RUN bundle install

COPY . .
CMD ["ruby", "app.rb"]
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

