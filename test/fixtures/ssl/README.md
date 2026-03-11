# SSL Test Certificates

This directory contains self-signed SSL certificates for testing purposes only.

## Files

- `ca-cert.pem` - Certificate Authority certificate
- `ca-key.pem` - Certificate Authority private key
- `server-cert.pem` - Server certificate (signed by CA)
- `server-key.pem` - Server private key
- `client-cert.pem` - Client certificate (signed by CA)
- `client-key.pem` - Client private key

## Regenerating Certificates

If you need to regenerate the certificates (e.g., they've expired), run:

```bash
ruby test/fixtures/ssl/generate_certs.rb
```

## Usage in Tests

Use the `SslHelper` module in tests:

```ruby
require_relative "support/helper/ssl"

class MyTest < Minitest::Test
  include SslHelper

  def test_ssl_connection
    client = Valkey.new(
      host: "127.0.0.1",
      port: 6379,
      ssl: true,
      ssl_params: {
        ca_file: ssl_ca_cert_path,
        cert: ssl_client_cert_path,
        key: ssl_client_key_path
      }
    )
  end
end
```

Or use OpenSSL objects directly:

```ruby
ssl_params: {
  ca_file: ssl_ca_cert,      # Returns OpenSSL::X509::Certificate
  cert: ssl_client_cert,     # Returns OpenSSL::X509::Certificate
  key: ssl_client_key        # Returns OpenSSL::PKey::RSA
}
```

## ⚠️ Security Warning

**These certificates are for TESTING ONLY!**

- Self-signed certificates
- Private keys are committed to the repository
- DO NOT use in production
- Valid for 1 year from generation date

