# Testing guidelines

This document is the authoritative testing reference for the Valkey GLIDE Ruby client. Follow these guidelines when developing new tests to keep them consistent, maintainable, and resilient to unrelated changes.

## Overall guidelines

- Avoid magic numbers. Use named variables, especially when a number has a unit.

## Test naming and organization

- Group tests by the feature they test.
- Within each group, order positive tests first, followed by negative tests and edge cases.
- Start with `test_<command_or_feature>`, which contains the basic positive-case assertions. Follow it with separate negative and edge-case tests.
- Use the format `test_<command_or_feature>_<condition_or_context>`.

Example:

```ruby
def test_get
  # Assert the basic positive case.
end

def test_get_not_found
  # Assert a simple negative case.
end

def test_get_nil
  # Assert an edge case.
end

def test_delifeq
end

def test_delifeq_not_matching
end

def test_delifeq_binary_value
end
```

## Test coverage

- Unit and integration tests have different purposes and cover different parts of the client.
- Each assertion must verify behavior owned by the layer under test.
- Tests must cover behavior owned by the Ruby client, not validation owned by Valkey or GLIDE Core. For example, do not test that Valkey rejects `SET` with both `XX` and `IFNE`; Ruby only forwards those options.

### Unit tests

- Unit tests cover Ruby-owned behavior, including request construction and data conversion before values reach Core.
- Each new component or API should have its own unit tests.
- Tests must assert only the component's properties and behavior.
- Tests should not cover Core or server behavior.
- Mocking and stubbing are allowed but should remain simple. If a test requires extensive mocking, consider skipping it and flagging the gap for human review.

#### [Command Unit Tests](/test/unit/commands/string_commands_test.rb)

> [!NOTE]
> These guidelines are a work in progress.

Command unit tests check that each command method sends the correct arguments to glide-core and returns its response.

What they test:

- Request type and command syntax (e.g. `DELEX IFEQ comparison-value`).
- Conversion of Ruby values to arguments (e.g. `value.to_s` or `Integer(expiry)`).
- That replies from `send_command` are returned and errors are raised unchanged.

What they do not test:

- Validation performed by glide-core or Valkey.
- Whether the server accepts a command.
- Reply conversion done by glide-core (e.g. Boolean replies).

In general, command unit tests should cover test cases for each argument:

| Argument type    | Behavior                                                        | Test cases                                             |
| ---------------- | --------------------------------------------------------------- | ------------------------------------------------------ |
| Key              | Not converted – passed directly.                                | Text string, binary string                             |
| String           | Converted with `to_s`.                                          | Text string, binary string, non-string                 |
| Integer          | Converted with `Integer()`.                                     | Integer, numeric string                                |
| Optional boolean | Added if `true` and omitted if `false` or `nil`.                | `true`, `false`, `nil`                                 |
| Optional string  | Added if non-`nil` and omitted if `nil`. Converted with `to_s`. | Text string, binary string, non-string, `false`, `nil` |
| Optional integer | Omitted if `nil`. Converted with `Integer()`.                   | Integer, numeric string, `nil`                         |

In addition, command unit tests should also verify that:

- Errors raised by glide-core or the server are propagated to the caller.
- If several options are specified, they are sent in the correct order, even if they are passed in a different order.

Structure:

- Use one test method per command, named `test_<command>`, in alphabetical order.
- If the command has many options, group them into paragraphs for readability.
- Use shared constants and helper methods to reduce duplication and improve readability.

### Integration tests

- Integration tests exercise the Ruby client from a user's point of view and verify public API contracts against a server.
- Negative tests must cover documented errors that are specific for that API; Generic errors like ACL and connections are not needed.
- Tests should assert return values and publicly observable state.
- They should not assert the Ruby client's private state. Unit tests own that behavior.
- Integration tests should use the Ruby client as an application would.
- Assertions must follow the public API documentation.
