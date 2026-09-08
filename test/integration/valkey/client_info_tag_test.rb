# frozen_string_literal: true

module ValkeyTests
  # Tests for the `lib_name` and `client_info_tag` options. Assertions on the reported
  # name need CLIENT SETINFO, so Valkey/Redis 7.2+; the rejection tests do not.
  module ClientInfoTag
    # Asserts the EXACT lib-name reported by CLIENT INFO. The regex anchors on the
    # field delimiter so "CustomLibSURPRISE" / "CustomLib(unexpected)" do not pass.
    def assert_lib_name(expected, info)
      actual = info[/(?:\A|\s)lib-name=(\S*)/, 1]
      assert_equal expected, actual,
                   "expected lib-name=#{expected.inspect}, got #{actual.inspect}"
    end

    def test_empty_client_info_tag_is_treated_as_absent
      omit_version("7.2")

      client = _new_client(client_info_tag: "")
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("GlideRuby", info)
      ensure
        client&.close
      end
    end

    def test_empty_client_info_tag_with_lib_name_is_treated_as_absent
      omit_version("7.2")

      client = _new_client(lib_name: "CustomLib", client_info_tag: "")
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("CustomLib", info)
      ensure
        client&.close
      end
    end

    def test_empty_lib_name_with_tag_uses_default_base
      omit_version("7.2")

      client = _new_client(lib_name: "", client_info_tag: "my-framework:1.0")
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("GlideRuby(my-framework:1.0)", info)
      ensure
        client&.close
      end
    end

    CORE_REJECTED_TAGS = {
      "space" => "has space",
      "tab" => "has\ttab",
      "newline" => "has\nnewline"
    }.freeze

    CORE_REJECTED_TAGS.each do |label, value|
      define_method(:"test_core_rejects_client_info_tag_#{label}") do
        client = nil
        # A connection failure also raises CannotConnectError, so the message
        # assertion is what distinguishes rejection from an unreachable server.
        error = assert_raises(Valkey::CannotConnectError) do
          client = _new_client(client_info_tag: value)
        end
        assert_match(/library name must contain only printable ASCII/, error.message)
      ensure
        client&.close
      end
    end

    # Cases transcribed from glide-core's library-name regex (upstream #6891);
    # the accepted grammar is documented in README's Connection Options.
    CORE_REJECTED_LIB_NAMES = {
      "space" => "Glide Ruby",
      "tab" => "Glide\tRuby",
      "newline" => "Glide\nRuby",
      "non_ascii" => "café",
      "del_control_char" => "GlideRuby\x7F",
      "unclosed_paren" => "GlideRuby(",
      "empty_parens" => "GlideRuby()",
      "paren_only" => "(tag)",
      "double_tag" => "GlideRuby(tag)(second)",
      "trailing_suffix_after_tag" => "GlideRuby(tag)suffix"
    }.freeze

    CORE_REJECTED_LIB_NAMES.each do |label, value|
      define_method(:"test_core_rejects_lib_name_#{label}") do
        client = nil
        error = assert_raises(Valkey::CannotConnectError) do
          client = _new_client(lib_name: value)
        end
        assert_match(/library name must contain only printable ASCII/, error.message)
      ensure
        client&.close
      end
    end

    def test_core_accepts_valid_composed_lib_name_and_tag
      omit_version("7.2")

      client = _new_client(lib_name: "custom-lib", client_info_tag: "framework:1.2")
      begin
        assert_lib_name("custom-lib(framework:1.2)", client.call("CLIENT", "INFO"))
      ensure
        client&.close
      end
    end

    def test_empty_lib_name_falls_back_to_default_without_error
      omit_version("7.2")

      client = _new_client(lib_name: "")
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("GlideRuby", info)
      ensure
        client&.close
      end
    end

    def test_client_info_tag_appends_to_default_lib_name
      omit_version("7.2")

      client = _new_client(client_info_tag: "my-framework:1.0")
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("GlideRuby(my-framework:1.0)", info)
      ensure
        client&.close
      end
    end

    def test_lib_name_override
      omit_version("7.2")

      client = _new_client(lib_name: "CustomLib")
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("CustomLib", info)
      ensure
        client&.close
      end
    end

    def test_lib_name_with_client_info_tag
      omit_version("7.2")

      client = _new_client(lib_name: "MyLib", client_info_tag: "v2.0")
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("MyLib(v2.0)", info)
      ensure
        client&.close
      end
    end

    def test_default_lib_name_when_no_options
      omit_version("7.2")

      client = _new_client
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("GlideRuby", info)
      ensure
        client&.close
      end
    end

    def test_client_info_tag_with_special_characters
      omit_version("7.2")

      client = _new_client(client_info_tag: "lmcache:1.2.3-beta+build.42")
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("GlideRuby(lmcache:1.2.3-beta+build.42)", info)
      ensure
        client&.close
      end
    end
  end
end
