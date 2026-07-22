# frozen_string_literal: true

module SslHelper
  # Directory holding the TLS certificates for the test suite.
  def ssl_fixtures_path
    dir = ENV.fetch("TLS_CERT_DIR", nil)
    return dir if dir && Dir.exist?(dir)

    raise <<~MSG
      TLS_CERT_DIR is not set to a valid directory. Start a TLS server
      and set TLS_CERT_DIR to the directory with the certificates.
    MSG
  end

  def ssl_ca_cert_path
    File.join(ssl_fixtures_path, "ca.crt")
  end

  def ssl_client_cert_path
    File.join(ssl_fixtures_path, "server.crt")
  end

  def ssl_client_key_path
    File.join(ssl_fixtures_path, "server.key")
  end

  # Load CA certificate as OpenSSL object
  def ssl_ca_cert
    OpenSSL::X509::Certificate.new(File.read(ssl_ca_cert_path))
  end

  # Load client certificate as OpenSSL object
  def ssl_client_cert
    OpenSSL::X509::Certificate.new(File.read(ssl_client_cert_path))
  end

  # Load client key as OpenSSL object
  def ssl_client_key
    OpenSSL::PKey::RSA.new(File.read(ssl_client_key_path))
  end
end
