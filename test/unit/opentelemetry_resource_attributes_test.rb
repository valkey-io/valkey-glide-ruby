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

  def test_existing_otel_resource_attributes_is_preserved_and_prepended
    ENV["OTEL_RESOURCE_ATTRIBUTES"] = "k8s.pod.name=my-pod,k8s.namespace.name=default"

    value = ::Valkey::OpenTelemetry.send(:build_resource_attributes_env, nil)

    assert_match(/\Ak8s\.pod\.name=my-pod,k8s\.namespace\.name=default,/, value)
    assert_match(/process\.pid=#{Process.pid}/, value)
  end

  def test_build_resource_attributes_env_with_no_existing_env_var
    ENV.delete("OTEL_RESOURCE_ATTRIBUTES")

    value = ::Valkey::OpenTelemetry.send(:build_resource_attributes_env, nil)

    refute_match(/\A,/, value)
  end

  def test_commas_are_replaced_since_they_break_the_list_format
    value = ::Valkey::OpenTelemetry.send(:build_resource_attributes_env, { "custom.attr" => "a,b" })

    assert_match(/custom\.attr=a_b/, value)
  end

  def test_sanitize_leaves_non_comma_characters_untouched
    assert_equal "process.pid", ::Valkey::OpenTelemetry.send(:sanitize_otel_resource_component, "process.pid")
    assert_equal "/usr/bin/ruby (a=b)",
                 ::Valkey::OpenTelemetry.send(:sanitize_otel_resource_component, "/usr/bin/ruby (a=b)")
  end

  def test_with_resource_attributes_env_sets_and_restores_env_var
    ENV["OTEL_RESOURCE_ATTRIBUTES"] = "pre.existing=value"

    seen_during_block = nil
    ::Valkey::OpenTelemetry.send(:with_resource_attributes_env, { "host.name" => "web-1" }) do
      seen_during_block = ENV.fetch("OTEL_RESOURCE_ATTRIBUTES", nil)
    end

    assert_match(/\Apre\.existing=value,/, seen_during_block)
    assert_match(/host\.name=web-1/, seen_during_block)
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
