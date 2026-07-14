# Examples

Runnable examples for Valkey GLIDE Ruby. Requires a Valkey or Redis OSS server unless noted.

## Prerequisites

From the repository root:

```bash
bin/setup
```

Run examples with the gem loaded from `lib/`:

```bash
bundle exec ruby examples/standalone.rb
```

Or:

```bash
RUBYOPT="-I$(pwd)/lib" ruby examples/standalone.rb
```

## Examples

| File | Description | Server |
|------|-------------|--------|
| [standalone.rb](./standalone.rb) | Basic connect, SET, GET | Standalone `:6379` |
| [cluster.rb](./cluster.rb) | Cluster connect, SET, GET | Cluster `:7000`–`:7005` |
| [pipelining.rb](./pipelining.rb) | Non-atomic pipeline | Standalone `:6379` |
| [opentelemetry.rb](./opentelemetry.rb) | OTel file exporter + traced commands | Standalone `:6379` |
| [statistics.rb](./statistics.rb) | Client statistics | Standalone `:6379` |

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `VALKEY_HOST` | `127.0.0.1` | Server host |
| `VALKEY_PORT` | `6379` | Standalone port |
| `VALKEY_CLUSTER_PORT` | `7000` | First cluster node port |

## Standalone with Docker

```bash
docker run -d --name valkey -p 6379:6379 valkey/valkey:8
bundle exec ruby examples/standalone.rb
```

## Cluster with Docker

```bash
docker run -d -p 7000-7005:7000-7005 grokzen/redis-cluster:7.0.15
bundle exec ruby examples/cluster.rb
```
