# frozen_string_literal: true

# Unit tests for Valkey::OpenTelemetry's resource_attributes support. Pure unit tests: no
# connection, no real native OTel init, no server needed - Bindings.init_open_telemetry is stubbed.

require "test_helper"

class TestOpenTelemetryResourceAttributes < Minitest::Test
  def setup
    super if defined?(super)
    @original_otel_resource_attributes = ENV.fetch("OTEL_RESOURCE_ATTRIBUTES", nil)
  end

  def teardown
    if @original_otel_resource_attributes.nil?
      ENV.delete("OTEL_RESOURCE_ATTRIBUTES")
    else
      ENV["OTEL_RESOURCE_ATTRIBUTES"] = @original_otel_resource_attributes
    end
    super if defined?(super)
  end

  def test_build_resource_attributes_env_includes_auto_detected_process_attributes
    value = ::Valkey::OpenTelemetry.send(:build_resource_attributes_env, nil)

    assert_match(/process\.pid=#{Process.pid}/, value)
    assert_match(/process\.command=#{Regexp.escape($PROGRAM_NAME)}/, value)
    assert_match(/process\.runtime\.name=#{Regexp.escape(RUBY_ENGINE)}/, value)
    assert_match(/process\.runtime\.version=#{Regexp.escape(RUBY_VERSION)}/, value)
    assert_match(/process\.runtime\.description=#{Regexp.escape(RUBY_DESCRIPTION)}/, value)
  end

  def test_build_resource_attributes_env_merges_caller_supplied_attributes
    value = ::Valkey::OpenTelemetry.send(:build_resource_attributes_env, { "host.name" => "web-1" })

    assert_match(/host\.name=web-1/, value)
    assert_match(/process\.pid=#{Process.pid}/, value)
  end

  def test_caller_supplied_attributes_win_over_auto_detected_on_key_collision
    value = ::Valkey::OpenTelemetry.send(:build_resource_attributes_env, { "process.pid" => "overridden" })

    assert_match(/process\.pid=overridden/, value)
    refute_match(/process\.pid=#{Process.pid}\b/, value)
  end

  def test_existing_otel_resource_attributes_is_preserved
    ENV["OTEL_RESOURCE_ATTRIBUTES"] = "k8s.pod.name=my-pod,k8s.namespace.name=default"

    value = ::Valkey::OpenTelemetry.send(:build_resource_attributes_env, nil)

    assert_match(/k8s\.pod\.name=my-pod,k8s\.namespace\.name=default/, value)
    assert_match(/process\.pid=#{Process.pid}/, value)
  end

  def test_existing_otel_resource_attributes_wins_over_auto_detected_on_key_collision
    ENV["OTEL_RESOURCE_ATTRIBUTES"] = "process.command=checkout-worker"

    value = ::Valkey::OpenTelemetry.send(:build_resource_attributes_env, nil)

    assert_match(/process\.command=checkout-worker(,|\z)/, value)
    refute_match(/process\.command=#{Regexp.escape($PROGRAM_NAME)}/, value)
  end

  def test_malformed_existing_entries_without_an_equals_sign_are_skipped
    ENV["OTEL_RESOURCE_ATTRIBUTES"] = "not-a-pair,k8s.pod.name=my-pod"

    value = ::Valkey::OpenTelemetry.send(:build_resource_attributes_env, nil)

    refute_match(/not-a-pair/, value)
    assert_match(/k8s\.pod\.name=my-pod/, value)
  end

  def test_build_resource_attributes_env_with_no_existing_env_var
    ENV.delete("OTEL_RESOURCE_ATTRIBUTES")

    value = ::Valkey::OpenTelemetry.send(:build_resource_attributes_env, nil)

    refute_match(/\A,/, value)
  end

  def test_commas_in_values_are_replaced_since_they_break_the_list_format
    value = ::Valkey::OpenTelemetry.send(:build_resource_attributes_env, { "custom.attr" => "a,b" })

    assert_match(/custom\.attr=a_b/, value)
  end

  def test_commas_in_keys_are_replaced_since_they_break_the_list_format
    value = ::Valkey::OpenTelemetry.send(:build_resource_attributes_env, { "custom,key" => "value" })

    assert_match(/custom_key=value/, value)
  end

  # A "=" in a key would otherwise be read as the key/value separator, merging part of the key
  # into the value (e.g. {"deployment=region" => "us-west"} would round-trip as
  # {"deployment" => "region=us-west"}).
  def test_equals_signs_in_keys_are_replaced_but_preserved_in_values
    value = ::Valkey::OpenTelemetry.send(:build_resource_attributes_env, { "deployment=region" => "a=b" })

    assert_match(/deployment_region=a=b/, value)
  end

  def test_sanitize_key_replaces_commas_and_equals_signs
    assert_equal "process.pid", ::Valkey::OpenTelemetry.send(:sanitize_otel_resource_key, "process.pid")
    assert_equal "a_b_c", ::Valkey::OpenTelemetry.send(:sanitize_otel_resource_key, "a,b=c")
  end

  def test_sanitize_value_replaces_commas_but_keeps_equals_signs
    assert_equal "/usr/bin/ruby (a=b)",
                 ::Valkey::OpenTelemetry.send(:sanitize_otel_resource_value, "/usr/bin/ruby (a=b)")
    assert_equal "a_b=c", ::Valkey::OpenTelemetry.send(:sanitize_otel_resource_value, "a,b=c")
  end

  def test_parse_otel_resource_attributes_trims_whitespace_keeps_last_duplicate_and_extra_equals
    parsed = ::Valkey::OpenTelemetry.send(
      :parse_otel_resource_attributes,
      "spaced.key = spaced value,dup=first,dup=last,padded=value=="
    )

    assert_equal(
      { "spaced.key" => "spaced value", "dup" => "last", "padded" => "value==" },
      parsed
    )
  end

  def test_with_resource_attributes_env_sets_and_restores_env_var
    ENV["OTEL_RESOURCE_ATTRIBUTES"] = "pre.existing=value"

    seen_during_block = nil
    ::Valkey::OpenTelemetry.send(:with_resource_attributes_env, { "host.name" => "web-1" }) do
      seen_during_block = ENV.fetch("OTEL_RESOURCE_ATTRIBUTES", nil)
    end

    assert_match(/pre\.existing=value/, seen_during_block)
    assert_match(/host\.name=web-1\z/, seen_during_block)
    assert_equal "pre.existing=value", ENV.fetch("OTEL_RESOURCE_ATTRIBUTES", nil)
  end

  def test_with_resource_attributes_env_restores_to_unset_when_originally_unset
    ENV.delete("OTEL_RESOURCE_ATTRIBUTES")

    ::Valkey::OpenTelemetry.send(:with_resource_attributes_env, nil) { nil }

    refute ENV.key?("OTEL_RESOURCE_ATTRIBUTES")
  end

  def test_with_resource_attributes_env_restores_even_if_block_raises
    ENV["OTEL_RESOURCE_ATTRIBUTES"] = "pre.existing=value"

    assert_raises(RuntimeError) do
      ::Valkey::OpenTelemetry.send(:with_resource_attributes_env, nil) { raise "boom" }
    end

    assert_equal "pre.existing=value", ENV.fetch("OTEL_RESOURCE_ATTRIBUTES", nil)
  end

  def test_init_sets_resource_attributes_env_for_the_duration_of_the_ffi_call
    original_initialized = ::Valkey::OpenTelemetry.instance_variable_get(:@initialized)
    original_config = ::Valkey::OpenTelemetry.config
    ::Valkey::OpenTelemetry.instance_variable_set(:@initialized, false)

    seen_during_ffi_call = nil
    stub_init = lambda do |_config|
      seen_during_ffi_call = ENV.fetch("OTEL_RESOURCE_ATTRIBUTES", nil)
      FFI::Pointer::NULL
    end

    Valkey::Bindings.stub(:init_open_telemetry, stub_init) do
      ::Valkey::OpenTelemetry.init(
        traces: { endpoint: "file:///tmp/valkey_ruby_resource_attributes_test.json" },
        resource_attributes: { "host.name" => "web-1", "host.ip" => "10.0.0.1" }
      )
    end

    assert_match(/host\.name=web-1/, seen_during_ffi_call)
    assert_match(/host\.ip=10\.0\.0\.1/, seen_during_ffi_call)
    assert_match(/process\.pid=#{Process.pid}/, seen_during_ffi_call)
  ensure
    ::Valkey::OpenTelemetry.instance_variable_set(:@initialized, original_initialized)
    ::Valkey::OpenTelemetry.instance_variable_set(:@config, original_config)
  end

  def test_init_raises_on_non_hash_resource_attributes
    original_initialized = ::Valkey::OpenTelemetry.instance_variable_get(:@initialized)
    ::Valkey::OpenTelemetry.instance_variable_set(:@initialized, false)

    assert_raises(ArgumentError) do
      ::Valkey::OpenTelemetry.init(
        traces: { endpoint: "file:///tmp/valkey_ruby_resource_attributes_test.json" },
        resource_attributes: "not-a-hash"
      )
    end
  ensure
    ::Valkey::OpenTelemetry.instance_variable_set(:@initialized, original_initialized)
  end
end
