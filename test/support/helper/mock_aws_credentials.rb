# frozen_string_literal: true

module Helper
  # Placeholder AWS credentials for IAM tests. SigV4 token signing is local, so any
  # credentials let glide-core build a token against a server without IAM enforcement.
  module MockAwsCredentials
    CREDENTIALS = {
      "AWS_ACCESS_KEY_ID" => "test_access_key",
      "AWS_SECRET_ACCESS_KEY" => "test_secret_key",
      "AWS_SESSION_TOKEN" => "test_session_token"
    }.freeze

    # Must run before glide-ffi is loaded: glide-core threads read the environment,
    # and writing ENV while another thread calls getenv is undefined behavior.
    # Real credentials already in the environment are left untouched.
    def self.install
      return unless ENV.fetch("AWS_ACCESS_KEY_ID", "").empty?

      ENV.update(CREDENTIALS)
    end
  end
end
