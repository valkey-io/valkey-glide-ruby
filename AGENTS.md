# AGENTS.md

Valkey GLIDE for Ruby (`valkey-rb`): official Ruby client for Valkey, wrapping the Rust glide-core via FFI with a synchronous redis-rb-compatible API.

## SDD skill

This project uses Spec-Driven Development (SDD). If you have access to the SDD skill, load it before taking any action on this project — it governs how to read, write, and maintain all project documentation. If the skill is unavailable, read the files in `sdd/` directly.

## Documentation

Project documentation lives in the `sdd/` directory.

### If you are exploring this project

Read these files first:
- `sdd/PRODUCT.md` — What this project is and why it exists
- `sdd/TDD.md` — Behavioral contract (test rubrics in Given/When/Then format)

### If you are contributing to this project

Read all of the above, plus:
- `sdd/POLICY.md` — Development rules, build process, and constraints you must follow
- `sdd/TECH.md` — Technical architecture, dependencies, and module responsibilities

### Detailed reference (read when relevant)

- `DEVELOPER.md` — Full developer setup guide (building from source, running tests, CI details)
- `CONTRIBUTING.md` — PR process, DCO signoff, commit conventions
- `CLAUDE.md` — Claude-specific workflow constraints
- `README.md` — User-facing getting started and examples

## Quick build/test reference

```bash
bin/setup                           # bundle install
bundle exec rubocop                 # lint
bundle exec rake test:standalone    # needs Valkey on :6379
bundle exec rake test:cluster       # needs cluster on :7000-7005
```

## Key constraints (see sdd/POLICY.md for full list)

- Synchronous only — no async patterns
- All FFI args are strings — type conversion happens in Ruby
- redis-rb API compatibility is a design goal
- RequestType constants must match glide-core enum
- DCO signoff required on all commits
