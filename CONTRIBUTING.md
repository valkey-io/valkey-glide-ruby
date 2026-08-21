# Contributing Guidelines

Thank you for your interest in contributing to Valkey GLIDE for Ruby. Whether it's a bug report, new feature, correction, or documentation, we value feedback from the community.

This document will go over some of the important things to know before making a contribution. For our guidelines, please take a look at the Valkey GLIDE [CONTRIBUTING.md](https://github.com/valkey-io/valkey-glide/blob/main/CONTRIBUTING.md).

## Raising an Issue

When raising an issue, please make use of our issue templates and ensure that it is not a duplicate.

## Creating a Pull Request

External pull request is not allowed without first creating an issue. This is to allow for discussions on the issue without bombarding the repo with pull requests. 

Exceptions are made for pull requests that are small in scope or contains simple changes, e.g fixing typos. However, any PR made without making an issue first risk 
being rejected.

Finally, keep your PR scope focused and small, preferably +-500 lines changes. This allow maintainers to review your PR in a timely manner. A large convoluted PR 
will be rejected and asked for a resubmit.

## Signed Commits and DCO

All commits require a DCO signoff and are cryptographically signed: `git commit -S -s -m "message"`. You should follow the Conventional Commits format: <type>(<scope>): <description>.

## AI-Assisted Development

If you use Cursor, Claude Code, or similar tools, agent context files are available:

- [AGENTS.md](./AGENTS.md)
- [CLAUDE.md](./CLAUDE.md)

## Code of Conduct

This project follows the [Amazon Open Source Code of Conduct](https://aws.github.io/code-of-conduct). See the [FAQ](https://aws.github.io/code-of-conduct-faq) or contact opensource-codeofconduct@amazon.com with questions.

## Security

See [SECURITY.md](https://github.com/valkey-io/.github/blob/main/SECURITY.md).

## Licensing

Contributions are licensed under the same terms as the project. See [LICENSE](./LICENSE). You will be asked to confirm licensing in your PR.
