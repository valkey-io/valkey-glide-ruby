# frozen_string_literal: true

require "test_helper"
require "json"
require "openssl"
require "tempfile"

# `ssl_params` resolution: PEM text, file paths and OpenSSL objects reach the
# FFI payload, and no error message ever echoes the supplied value.
class TestSslParams < Minitest::Test
  KEY = OpenSSL::PKey::EC.generate("prime256v1")
  CERT = OpenSSL::X509::Certificate.new.tap do |cert|
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=valkey-glide-ruby-test")
    cert.public_key = KEY
    cert.not_before = Time.now
    cert.not_after = Time.now + 3600
    cert.sign(KEY, OpenSSL::Digest.new("SHA256"))
  end
  KEY_PEM = KEY.to_pem
  CERT_PEM = CERT.to_pem
  KEY_BODY = KEY_PEM.lines[1..-2].join

  def captured_json_options(ssl_params)
    json = nil
    fake_response = Valkey::Bindings::ConnectionResponse.new
    fake_response[:conn_ptr] = FFI::Pointer.new(0x1)

    Valkey::Bindings.stub(:create_client_from_uri, lambda { |_uri, payload, _client_type, _callback|
      json = payload
      fake_response.to_ptr
    }) do
      Valkey::Bindings.stub(:free_connection_response, nil) do
        client = ::Valkey.new(host: "localhost", port: 6380, ssl: true, ssl_params: ssl_params)
        client.instance_variable_set(:@connection, nil)
      end
    end

    JSON.parse(json)
  end

  def assert_no_leak(error, *secrets)
    messages = [error.message, error.full_message(highlight: false)]
    secrets.each do |secret|
      messages.each { |message| refute_includes message, secret }
      secret.each_line { |line| messages.each { |message| refute_includes message, line.strip } if line.strip.size > 8 }
    end
    assert_nil error.cause
  end

  def test_pem_strings_are_passed_through_as_content
    json = captured_json_options(ca_file: CERT_PEM, cert: CERT_PEM, key: KEY_PEM)

    assert_equal [CERT_PEM], json["root_certs"]
    assert_equal CERT_PEM, json["client_cert"]
    assert_equal KEY_PEM, json["client_key"]
  end

  def test_file_paths_are_read
    Tempfile.create(["key", ".pem"]) do |key_file|
      key_file.write(KEY_PEM)
      key_file.close
      Tempfile.create(["cert", ".pem"]) do |cert_file|
        cert_file.write(CERT_PEM)
        cert_file.close

        json = captured_json_options(ca_file: cert_file.path, cert: cert_file.path, key: key_file.path)

        assert_equal [CERT_PEM], json["root_certs"]
        assert_equal CERT_PEM, json["client_cert"]
        assert_equal KEY_PEM, json["client_key"]
      end
    end
  end

  def test_openssl_objects_are_converted_to_pem
    json = captured_json_options(ca_file: CERT, cert: CERT, key: KEY)

    assert_equal [CERT_PEM], json["root_certs"]
    assert_equal CERT_PEM, json["client_cert"]
    assert_equal KEY_PEM, json["client_key"]
  end

  def test_missing_path_names_the_option_but_not_the_value
    { ca_file: "CA", cert: "Cert", key: "Key" }.each do |option, label|
      path = "/nonexistent/secret-#{option}.pem"
      error = assert_raises(ArgumentError) { captured_json_options(option => path) }

      assert_match(/\A#{label} file does not exist/, error.message)
      assert_includes error.message, "PEM text"
      assert_no_leak(error, path)
    end
  end

  def test_key_material_without_pem_header_is_never_echoed
    { ca_file: CERT_PEM.lines[1..-2].join, cert: CERT_PEM.lines[1..-2].join, key: KEY_BODY }.each do |option, value|
      error = assert_raises(ArgumentError) { captured_json_options(option => value) }

      assert_no_leak(error, value)
    end
  end

  def test_pem_values_are_not_echoed_when_a_later_option_fails
    error = assert_raises(ArgumentError) do
      captured_json_options(ca_file: CERT_PEM, cert: CERT_PEM, key: KEY_PEM, ca_path: "/nonexistent/dir")
    end

    assert_match(/CA path does not exist/, error.message)
    assert_no_leak(error, CERT_PEM, KEY_PEM, "/nonexistent/dir")
  end

  def test_read_failure_does_not_echo_the_path
    Tempfile.create(["key", ".pem"]) do |key_file|
      key_file.write(KEY_PEM)
      key_file.close
      raise_eacces = ->(path) { raise Errno::EACCES, path }

      error = File.stub(:binread, raise_eacces) do
        assert_raises(ArgumentError) { captured_json_options(key: key_file.path) }
      end

      assert_match(/\AKey file could not be read/, error.message)
      assert_no_leak(error, key_file.path)
    end
  end
end
