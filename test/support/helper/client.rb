# frozen_string_literal: true

module Helper
  module Client
    include Generic

    private

    def _format_options(options)
      OPTIONS.merge(options)
    end

    def _new_client(options = {})
      Valkey.new(_format_options(options))
    end
  end
end
