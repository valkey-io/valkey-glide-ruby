# Contributing Guidelines

Thank you for your interest in contributing to Valkey GLIDE for Ruby (`valkey-rb`). Whether it's a bug report, new feature, correction, or documentation, we value feedback from the community.

Please read this document before submitting issues or pull requests.

## Reporting Bugs and Feature Requests

Use the [GitHub issue tracker](https://github.com/valkey-io/valkey-glide-ruby/issues) for bugs, feature requests, and questions.

Before creating a new issue:

1. Search [existing issues](https://github.com/valkey-io/valkey-glide-ruby/issues) to avoid duplicates.
2. Include Ruby version, OS/architecture, `valkey-rb` version, and Valkey/Redis server version.
3. For connection problems, note standalone vs cluster and whether TLS is enabled.
4. Provide a minimal reproduction script when possible.

For issues that affect the shared Rust core or other language clients, consider opening an issue in [valkey-glide](https://github.com/valkey-io/valkey-glide/issues) as well.

## Contributing via Pull Requests

1. Work against the latest `main` branch.
2. Check [open](https://github.com/valkey-io/valkey-glide-ruby/pulls) and recently merged PRs for duplicates.
3. For large changes (new command families, FFI updates, API breaks), open an issue first to discuss scope.

### Pull request steps

1. Fork [valkey-glide-ruby](https://github.com/valkey-io/valkey-glide-ruby).
2. Make focused changes; avoid unrelated formatting drive-by edits.
3. Run local checks (see [DEVELOPER.md](./DEVELOPER.md)):
   ```bash
   bundle exec rubocop
   bundle exec rake test:standalone    # standalone — requires Valkey on :6379
   bundle exec rake test:cluster   # if cluster-related — requires nodes :7000–:7005
   ```
4. Commit with **DCO sign-off** and **conventional commits**:
   ```bash
   git commit -s -m "feat(ruby): add EXAMPLE command"
   ```
   Configure automatic signoff: `git config --global format.signOff true`

5. Open a PR and respond to CI feedback (RuboCop + test matrix in `.github/workflows/CI.yml`).

GitHub guides: [fork a repo](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo), [create a pull request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-a-pull-request).

### Commit message format

```
<type>(<scope>): <description>
```

| Type | Use for |
|------|---------|
| `feat` | New feature or command |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `test` | Tests only |
| `refactor` | Code change without behavior change |
| `chore` | Tooling, CI, deps |

**Scope:** `ruby` or a command area (e.g. `ruby-pubsub`).

### Developer Certificate of Origin (DCO)

All commits must include:

```
Signed-off-by: Your Name <your.email@example.com>
```

By signing off, you agree to the [Developer Certificate of Origin](https://developercertificate.org/).

## Adding or Updating Commands

1. Confirm the command exists in [glide-core `request_type.rs`](https://github.com/valkey-io/valkey-glide/blob/main/glide-core/src/request_type.rs).
2. Add or verify `RequestType` in `lib/valkey/request_type.rb`.
3. Implement in the appropriate `lib/valkey/commands/*.rb` module.
4. Add tests under `test/valkey/` and lint coverage in `test/lint/` when matching redis-rb behavior.
5. Update the [command implementation wiki](https://github.com/valkey-io/valkey-glide-ruby/wiki/The-implementation-status-of-the-Valkey-commands).

See [DEVELOPER.md](./DEVELOPER.md) for full details.

## Updating the Native FFI Library

Changes that require a new `libglide_ffi` build:

1. Build from [valkey-glide/ffi](https://github.com/valkey-io/valkey-glide/tree/main/ffi) at a compatible release tag.
2. Copy `libglide_ffi.so` or `libglide_ffi.dylib` into `lib/valkey/`.
3. Document the valkey-glide version in the PR description.
4. Test on the target platform (Linux x86_64/aarch64, macOS Intel/Apple Silicon).

## AI-Assisted Development

If you use Cursor, Claude Code, or similar tools, read:

- [AGENTS.md](./AGENTS.md) — build, test, and quality checklist
- [CLAUDE.md](./CLAUDE.md) — workflow constraints for this repository

## Code of Conduct

This project follows the [Amazon Open Source Code of Conduct](https://aws.github.io/code-of-conduct). See the [FAQ](https://aws.github.io/code-of-conduct-faq) or contact opensource-codeofconduct@amazon.com with questions.

## Security

Report security vulnerabilities via [valkey-glide SECURITY.md](https://github.com/valkey-io/valkey-glide/blob/main/SECURITY.md).

## Licensing

Contributions are licensed under the same terms as the project. See [LICENSE](./LICENSE). You will be asked to confirm licensing in your PR.

## Community

Join Valkey Slack: [Join Valkey Slack](https://join.slack.com/t/valkey-oss-developer/shared_invite/zt-2nxs51chx-EB9hu9Qdch3GMfRcztTSkQ).

Broader GLIDE contributing process: [valkey-glide CONTRIBUTING.md](https://github.com/valkey-io/valkey-glide/blob/main/CONTRIBUTING.md).
