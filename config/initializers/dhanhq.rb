# frozen_string_literal: true
require 'dhan_hq'
DhanHQ.configure_with_env
DhanHQ.logger.level = (ENV['DHAN_LOG_LEVEL'] || 'INFO').upcase.then { |level| Logger.const_get(level) }
Rails.logger.info "✅ DhanHQ configured successfully"
