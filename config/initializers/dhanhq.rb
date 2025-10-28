# frozen_string_literal: true

begin
  require 'dhan_hq'

  # Configure DhanHQ with environment variables
  if ENV['CLIENT_ID'].present? && ENV['ACCESS_TOKEN'].present?
    DhanHQ.configure_with_env
    DhanHQ.logger.level = (ENV['DHAN_LOG_LEVEL'] || 'INFO').upcase.then { |level| Logger.const_get(level) }
    Rails.logger.info "✅ DhanHQ configured successfully"
  else
    Rails.logger.warn "⚠️  DhanHQ not configured: CLIENT_ID and ACCESS_TOKEN required in .env"
  end
rescue LoadError => e
  Rails.logger.warn "⚠️  DhanHQ gem not loaded: #{e.message}"
rescue StandardError => e
  Rails.logger.error "❌ DhanHQ configuration error: #{e.message}"
end

