# frozen_string_literal: true

module SslHelper
  # Path to SSL fixtures directory
  def ssl_fixtures_path
    File.expand_path("../../fixtures/ssl", __dir__)
  end

  # Path to CA certificate file
  def ssl_ca_cert_path
    File.join(ssl_fixtures_path, "ca-cert.pem")
  end

  # Path to client certificate file
  def ssl_client_cert_path
    File.join(ssl_fixtures_path, "client-cert.pem")
  end

  # Path to client key file
  def ssl_client_key_path
    File.join(ssl_fixtures_path, "client-key.pem")
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
