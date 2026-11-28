# Migrating from redis-rb

In order to facilitate easy migration from Redis, Valkey GLIDE for Ruby generally follows the [redis-rb](https://github.com/redis/redis-rb) interface.

## Command differences

Some commands exist in both clients but differ in their arguments or return values.

- [DELEX](https://valkey.io/commands/delex):
  - Exactly one string comparison option (`ifeq` or `ifne`) is required. Valkey does not support `DELEX` with no comparison option. Use `DEL` instead.
  - No hash-digest comparison option (`ifdeq` or  `ifdne`) is accepted. Valkey does not support `DELEX` with hash-digest comparisons.
  - Returns boolean instead of integer for consistency with other methods.
