#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to generate test SSL certificates for testing
# These are self-signed certificates for testing purposes only

require "openssl"
require "fileutils"

# Output directory
output_dir = File.dirname(__FILE__)

puts "Generating test SSL certificates in #{output_dir}..."

# Generate CA key
ca_key = OpenSSL::PKey::RSA.new(2048)
File.write(File.join(output_dir, "ca-key.pem"), ca_key.to_pem)
puts "✓ Generated CA private key: ca-key.pem"

# Generate CA certificate
ca_cert = OpenSSL::X509::Certificate.new
ca_cert.version = 2
ca_cert.serial = 1
ca_cert.subject = OpenSSL::X509::Name.parse("/C=US/ST=Test/L=Test/O=Valkey Test/CN=Test CA")
ca_cert.issuer = ca_cert.subject # Self-signed
ca_cert.public_key = ca_key.public_key
ca_cert.not_before = Time.now
ca_cert.not_after = Time.now + (365 * 24 * 60 * 60) # 1 year

# CA extensions
ef = OpenSSL::X509::ExtensionFactory.new
ef.subject_certificate = ca_cert
ef.issuer_certificate = ca_cert
ca_cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
ca_cert.add_extension(ef.create_extension("keyUsage", "keyCertSign, cRLSign", true))
ca_cert.add_extension(ef.create_extension("subjectKeyIdentifier", "hash", false))
ca_cert.add_extension(ef.create_extension("authorityKeyIdentifier", "keyid:always", false))

ca_cert.sign(ca_key, OpenSSL::Digest.new("SHA256"))
File.write(File.join(output_dir, "ca-cert.pem"), ca_cert.to_pem)
puts "✓ Generated CA certificate: ca-cert.pem"

# Generate server key
server_key = OpenSSL::PKey::RSA.new(2048)
File.write(File.join(output_dir, "server-key.pem"), server_key.to_pem)
puts "✓ Generated server private key: server-key.pem"

# Generate server certificate
server_cert = OpenSSL::X509::Certificate.new
server_cert.version = 2
server_cert.serial = 2
server_cert.subject = OpenSSL::X509::Name.parse("/C=US/ST=Test/L=Test/O=Valkey Test/CN=localhost")
server_cert.issuer = ca_cert.subject
server_cert.public_key = server_key.public_key
server_cert.not_before = Time.now
server_cert.not_after = Time.now + (365 * 24 * 60 * 60) # 1 year

# Server extensions
ef = OpenSSL::X509::ExtensionFactory.new
ef.subject_certificate = server_cert
ef.issuer_certificate = ca_cert
server_cert.add_extension(ef.create_extension("keyUsage", "digitalSignature,keyEncipherment", true))
server_cert.add_extension(ef.create_extension("extendedKeyUsage", "serverAuth", true))
server_cert.add_extension(ef.create_extension("subjectAltName", "DNS:localhost,DNS:127.0.0.1,IP:127.0.0.1", false))

server_cert.sign(ca_key, OpenSSL::Digest.new("SHA256"))
File.write(File.join(output_dir, "server-cert.pem"), server_cert.to_pem)
puts "✓ Generated server certificate: server-cert.pem"

# Generate client key
client_key = OpenSSL::PKey::RSA.new(2048)
File.write(File.join(output_dir, "client-key.pem"), client_key.to_pem)
puts "✓ Generated client private key: client-key.pem"

# Generate client certificate
client_cert = OpenSSL::X509::Certificate.new
client_cert.version = 2
client_cert.serial = 3
client_cert.subject = OpenSSL::X509::Name.parse("/C=US/ST=Test/L=Test/O=Valkey Test/CN=Test Client")
client_cert.issuer = ca_cert.subject
client_cert.public_key = client_key.public_key
client_cert.not_before = Time.now
client_cert.not_after = Time.now + (365 * 24 * 60 * 60) # 1 year

# Client extensions
ef = OpenSSL::X509::ExtensionFactory.new
ef.subject_certificate = client_cert
ef.issuer_certificate = ca_cert
client_cert.add_extension(ef.create_extension("keyUsage", "digitalSignature,keyEncipherment", true))
client_cert.add_extension(ef.create_extension("extendedKeyUsage", "clientAuth", true))

client_cert.sign(ca_key, OpenSSL::Digest.new("SHA256"))
File.write(File.join(output_dir, "client-cert.pem"), client_cert.to_pem)
puts "✓ Generated client certificate: client-cert.pem"

puts "\nAll test certificates generated successfully!"
puts "\nFiles created:"
puts "  - ca-cert.pem        (CA certificate - use for ssl_params[:ca_file])"
puts "  - ca-key.pem         (CA private key)"
puts "  - server-cert.pem    (Server certificate)"
puts "  - server-key.pem     (Server private key)"
puts "  - client-cert.pem    (Client certificate - use for ssl_params[:cert])"
puts "  - client-key.pem     (Client private key - use for ssl_params[:key])"
puts "\nNote: These are self-signed certificates for TESTING ONLY!"
