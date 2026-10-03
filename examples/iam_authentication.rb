# frozen_string_literal: true

# AWS IAM authentication example for standalone or cluster mode.
#
# Run: bundle exec ruby examples/iam_authentication.rb
# See examples/README.md for prerequisites and environment variables.

require "valkey"

host = ENV.fetch("VALKEY_HOST")
port = Integer(ENV.fetch("VALKEY_PORT", 6379))
cluster_mode = ENV.fetch("VALKEY_CLUSTER_MODE", "false") == "true"

service = case ENV.fetch("VALKEY_IAM_SERVICE", "ELASTICACHE").upcase
          when "ELASTICACHE"
            Valkey::ServiceType::ELASTICACHE
          when "MEMORYDB"
            Valkey::ServiceType::MEMORYDB
          else
            raise ArgumentError, "VALKEY_IAM_SERVICE must be ELASTICACHE or MEMORYDB"
          end

iam_options = {
  cluster_name: ENV.fetch("VALKEY_IAM_CLUSTER_NAME"),
  service: service,
  region: ENV.fetch("AWS_REGION")
}
refresh_interval = ENV.fetch("VALKEY_IAM_REFRESH_INTERVAL_SECONDS", nil)
iam_options[:refresh_interval_seconds] = Integer(refresh_interval) if refresh_interval

connection_options = {
  ssl: true,
  username: ENV.fetch("VALKEY_IAM_USERNAME"),
  iam_config: Valkey::IamAuthConfig.new(**iam_options)
}

if cluster_mode
  connection_options[:nodes] = [{ host: host, port: port }]
  connection_options[:cluster_mode] = true
else
  connection_options[:host] = host
  connection_options[:port] = port
end

client = nil
begin
  client = Valkey.new(**connection_options)
  puts "PING: #{client.ping}"
  puts "IAM token refresh: #{client.refresh_iam_token}"
ensure
  client&.close
end
