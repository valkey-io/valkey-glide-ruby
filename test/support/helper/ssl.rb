# frozen_string_literal: true

module SslHelper
  # Path to SSL certificates directory.
  # In CI, cluster_manager.py generates certs in valkey-glide/utils/tls_crts/.
  # For local development, certs can be generated in test/fixtures/ssl/.
  def ssl_fixtures_path
    if ENV["TLS_CERT_DIR"] && Dir.exist?(ENV["TLS_CERT_DIR"])
      ENV["TLS_CERT_DIR"]
    else
      File.expand_path("../../fixtures/ssl", __dir__)
    end
  end

  # Path to CA certificate file
  def ssl_ca_cert_path
    # cluster_manager.py uses ca.crt, local fixtures use ca-cert.pem
    cm_path = File.join(ssl_fixtures_path, "ca.crt")
    local_path = File.join(ssl_fixtures_path, "ca-cert.pem")
    File.exist?(cm_path) ? cm_path : local_path
  end

  # Path to client/server certificate file
  def ssl_client_cert_path
    # cluster_manager.py uses server.crt, local fixtures use client-cert.pem
    cm_path = File.join(ssl_fixtures_path, "server.crt")
    local_path = File.join(ssl_fixtures_path, "client-cert.pem")
    File.exist?(cm_path) ? cm_path : local_path
  end

  # Path to client/server key file
  def ssl_client_key_path
    # cluster_manager.py uses server.key, local fixtures use client-key.pem
    cm_path = File.join(ssl_fixtures_path, "server.key")
    local_path = File.join(ssl_fixtures_path, "client-key.pem")
    File.exist?(cm_path) ? cm_path : local_path
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
