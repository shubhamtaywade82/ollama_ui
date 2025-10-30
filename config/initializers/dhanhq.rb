# frozen_string_literal: true

require 'dhan_hq'
require 'faraday/retry'

# Configure DhanHQ with environment variables
DhanHQ.configure_with_env
DhanHQ.logger.level = (ENV['DHAN_LOG_LEVEL'] || 'INFO').upcase.then { |level| Logger.const_get(level) }

# Enhanced wrapper module for DhanHQ client
module Dhan
  class << self
    # Access the configured DhanHQ client
    # This provides a clean interface and allows for future enhancements
    def client
      DhanHQ
    end

    # Validate configuration
    def configured?
      DhanHQ.configured?
    rescue StandardError
      false
    end
  end
end

Rails.logger.info '✅ DhanHQ configured successfully'
Rails.logger.info '✅ Dhan wrapper module initialized'
