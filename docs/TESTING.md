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

### Unit tests

- Unit tests cover Ruby-owned behavior, including request construction and data conversion before values reach Core.
- Each new component or API should have its own unit tests.
- Tests must assert only the component's properties and behavior.
- Tests should not cover Core or server behavior.
- Mocking and stubbing are allowed but should remain simple. If a test requires extensive mocking, consider skipping it and flagging the gap for human review.

### Integration tests

- Integration tests exercise the Ruby client from a user's point of view and verify public API contracts against a server.
- Negative tests must cover documented errors that are specific for that API; Generic errors like ACL and connections are not needed.
- Tests should assert return values and publicly observable state.
- They should not assert the Ruby client's private state. Unit tests own that behavior.
- Integration tests should use the Ruby client as an application would.
- Assertions must follow the public API documentation.
