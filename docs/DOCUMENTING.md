# Documentation Guidelines

This document is the authoritative documentation reference for Valkey GLIDE Ruby client. Follow these guidelines to ensure consistent documentation across the board.

## API Documentations

All public API must be documented following YARD's [Getting Started Guide](https://rubydoc.info/gems/yard/file/docs/GettingStarted.md). Specific rules are defined in [`.yard-lint.yml`](./.yard-lint.yml), and we use `yard-lint` as our linter. It requires Ruby 3.3+.

```bash
bundle exec rake lint:yard
```

The linter checks only the public class and module source files listed in `YARD_PUBLIC_API_FILES` in the `Rakefile`. Keep that explicit allowlist current when adding or moving public APIs; do not add internal implementation files. The linter validates existing docstrings but does not require documentation on methods that have none.

Before opening a pull request, run the documentation linter with Ruby 3.3 or newer

Writing guidelines:

- Format parameter descriptions as `@param [Type] name - description`. Omit the separator when no description is needed.
- Use `@return [void]` when a method has no meaningful return value.
- Add `@raise` for errors that callers are expected to handle, not all possible errors.
- Add `@since` with the minimum Valkey version.
- Add `@see` with link to `https://valkey.io/commands` for commands.
- Use YARD tags instead of handwritten `Parameters` or `Returns` sections.
