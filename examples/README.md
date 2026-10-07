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
| [cluster.rb](./cluster.rb) | Cluster connect, SET, GET | Cluster `:7000`-`:7005` |
| [iam_authentication.rb](./iam_authentication.rb) | AWS IAM authentication and manual token refresh | ElastiCache or MemoryDB |
| [pipelining.rb](./pipelining.rb) | Non-atomic pipeline | Standalone `:6379` |
| [opentelemetry.rb](./opentelemetry.rb) | OTel file exporter + traced commands | Standalone `:6379` |
| [statistics.rb](./statistics.rb) | Client statistics | Standalone `:6379` |

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `VALKEY_HOST` | `127.0.0.1` | Server host |
| `VALKEY_PORT` | `6379` | Standalone port |
| `VALKEY_CLUSTER_PORT` | `7000` | First cluster node port |

### IAM authentication

Prerequisites:

- An IAM-enabled ElastiCache or MemoryDB endpoint.
- AWS credentials available through the standard AWS credential chain.
- Network and TLS access to the endpoint.

```bash
VALKEY_HOST=clustercfg.my-cache.amazonaws.com \
VALKEY_IAM_USERNAME=iam-user \
VALKEY_IAM_CLUSTER_NAME=my-cache \
AWS_REGION=us-east-1 \
bundle exec ruby examples/iam_authentication.rb
```

Set `VALKEY_CLUSTER_MODE=true` for a cluster client. The example accepts:

| Variable | Default | Purpose |
|----------|---------|---------|
| `VALKEY_HOST` | Required | ElastiCache or MemoryDB endpoint |
| `VALKEY_PORT` | `6379` | Endpoint port |
| `VALKEY_CLUSTER_MODE` | `false` | Enable cluster mode when `true` |
| `VALKEY_IAM_USERNAME` | Required | IAM-enabled Valkey user |
| `VALKEY_IAM_CLUSTER_NAME` | Required | ElastiCache replication group or MemoryDB cluster name |
| `VALKEY_IAM_SERVICE` | `ELASTICACHE` | `ELASTICACHE` or `MEMORYDB` |
| `AWS_REGION` | Required | AWS region containing the endpoint |
| `VALKEY_IAM_REFRESH_INTERVAL_SECONDS` | Core default | Optional token refresh interval |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` | AWS credential chain | Optional environment-based AWS credentials |

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
