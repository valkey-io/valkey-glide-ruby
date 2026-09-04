# frozen_string_literal: true

# Tests for client_info_tag and lib_name configuration options.
#
# These options control the CLIENT SETINFO LIB-NAME value sent during
# connection establishment. client_info_tag appends a parenthesized tag
# to the default library name (GlideRuby), while lib_name provides a
# full override.
#
# References:
# - valkey-io/valkey-glide#6389 (Python reference implementation)
# - valkey-io/valkey-glide#6891 (core-side library-name validation, which this
#   file's rejection expectations depend on)
module ValkeyTests
  module ClientInfoTag
    # Asserts the EXACT lib-name reported by CLIENT INFO.
    #
    # CLIENT INFO fields are space-delimited, so an unanchored
    # `assert_match(/lib-name=CustomLib/)` also passes for "CustomLibSURPRISE" or
    # "CustomLib(unexpected)" — i.e. it cannot fail for the wrong-composition bug
    # these tests exist to catch. Anchoring on the delimiter fixes the whole class
    # of that bug rather than one instance.
    def assert_lib_name(expected, info)
      actual = info[/(?:\A|\s)lib-name=(\S*)/, 1]
      assert_equal expected, actual,
                   "expected lib-name=#{expected.inspect}, got #{actual.inspect}"
    end

    # --- Tag composition / empty handling (no character validation here) ---
    #
    # The wrapper performs no character validation of client_info_tag or
    # lib_name; that is glide-core's responsibility (upstream #6891). The one
    # wrapper-side rule is compositional: an empty tag is treated as absent,
    # matching core's empty-means-absent semantics, so it must neither raise nor
    # compose a "GlideRuby()" that core would reject.

    def test_empty_client_info_tag_is_treated_as_absent
      omit_version("7.2") # CLIENT SETINFO (lib-name) requires Valkey/Redis 7.2+

      client = _new_client(client_info_tag: "")
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("GlideRuby", info)
      ensure
        client&.close
      end
    end

    def test_empty_client_info_tag_with_lib_name_is_treated_as_absent
      omit_version("7.2") # CLIENT SETINFO (lib-name) requires Valkey/Redis 7.2+

      client = _new_client(lib_name: "CustomLib", client_info_tag: "")
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("CustomLib", info)
      ensure
        client&.close
      end
    end

    # Regression: an empty lib_name combined with a tag previously composed
    # "(tag)" — an empty string is truthy in Ruby, so the override looked
    # configured — which glide-core rejects. An empty override must be treated as
    # absent so the default base is used.
    def test_empty_lib_name_with_tag_uses_default_base
      omit_version("7.2") # CLIENT SETINFO (lib-name) requires Valkey/Redis 7.2+

      client = _new_client(lib_name: "", client_info_tag: "my-framework:1.0")
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("GlideRuby(my-framework:1.0)", info)
      ensure
        client&.close
      end
    end

    # Whitespace in a tag is rejected by core (it fails the library-name
    # grammar), not by the wrapper.
    CORE_REJECTED_TAGS = {
      "space" => "has space",
      "tab" => "has\ttab",
      "newline" => "has\nnewline"
    }.freeze

    CORE_REJECTED_TAGS.each do |label, value|
      define_method(:"test_core_rejects_client_info_tag_#{label}") do
        client = nil
        # Core validates at Client::new, so client CREATION raises — there is no
        # command to send. Assert the documented Valkey::CannotConnectError
        # (README) rather than the Valkey::BaseError root.
        #
        # Verified caveat: a connection failure ALSO raises CannotConnectError, so
        # narrowing the class does not by itself distinguish "rejected the name"
        # from "could not reach the server". The message assertion below is
        # therefore load-bearing, not decorative — do not remove it. It does couple
        # this test to an upstream message string; that is a deliberate trade for
        # not having a false green.
        error = assert_raises(Valkey::CannotConnectError) do
          client = _new_client(client_info_tag: value)
        end
        assert_match(/library name must contain only printable ASCII/, error.message)
      ensure
        client&.close
      end
    end

    # --- Core-side library-name validation (glide-core, upstream #6891) ---
    #
    # The Ruby wrapper deliberately does NOT re-implement library-name character
    # validation; glide-core validates the composed lib-name before client
    # creation and surfaces a configuration error through the FFI. These tests
    # assert that the error reaches the caller as a Valkey error at client
    # creation, rather than panicking or silently connecting with a name the
    # server ignores.
    #
    # The accepted grammar is documented canonically in README's Connection
    # Options (the `lib_name` row); it is deliberately not restated here, since
    # independent copies of it have already drifted apart. The cases below are
    # transcribed from core's own regex at the pinned commit.
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
        # See the note on CORE_REJECTED_TAGS above: creation raises, the documented
        # error class is asserted, and the message assertion is load-bearing
        # because a connection failure shares that class.
        error = assert_raises(Valkey::CannotConnectError) do
          client = _new_client(lib_name: value)
        end
        assert_match(/library name must contain only printable ASCII/, error.message)
      ensure
        client&.close
      end
    end

    def test_core_accepts_valid_composed_lib_name_and_tag
      omit_version("7.2") # CLIENT SETINFO (lib-name) requires Valkey/Redis 7.2+

      client = _new_client(lib_name: "custom-lib", client_info_tag: "framework:1.2")
      begin
        # Assert the composed name actually reached the server — construction not
        # raising says nothing about what was sent.
        assert_lib_name("custom-lib(framework:1.2)", client.call("CLIENT", "INFO"))
      ensure
        client&.close
      end
    end

    def test_empty_lib_name_falls_back_to_default_without_error
      omit_version("7.2") # CLIENT SETINFO (lib-name) requires Valkey/Redis 7.2+

      client = _new_client(lib_name: "")
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("GlideRuby", info)
      ensure
        client&.close
      end
    end

    # --- Integration tests (server needed) ---

    def test_client_info_tag_appends_to_default_lib_name
      omit_version("7.2") # CLIENT SETINFO (lib-name) requires Valkey/Redis 7.2+

      client = _new_client(client_info_tag: "my-framework:1.0")
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("GlideRuby(my-framework:1.0)", info)
      ensure
        client&.close
      end
    end

    def test_lib_name_override
      omit_version("7.2") # CLIENT SETINFO (lib-name) requires Valkey/Redis 7.2+

      client = _new_client(lib_name: "CustomLib")
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("CustomLib", info)
      ensure
        client&.close
      end
    end

    def test_lib_name_with_client_info_tag
      omit_version("7.2") # CLIENT SETINFO (lib-name) requires Valkey/Redis 7.2+

      client = _new_client(lib_name: "MyLib", client_info_tag: "v2.0")
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("MyLib(v2.0)", info)
      ensure
        client&.close
      end
    end

    def test_default_lib_name_when_no_options
      omit_version("7.2") # CLIENT SETINFO (lib-name) requires Valkey/Redis 7.2+

      client = _new_client
      begin
        info = client.call("CLIENT", "INFO")
        assert_lib_name("GlideRuby", info)
      ensure
        client&.close
      end
    end

    def test_client_info_tag_with_special_characters
      omit_version("7.2") # CLIENT SETINFO (lib-name) requires Valkey/Redis 7.2+

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
