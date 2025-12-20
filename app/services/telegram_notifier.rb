# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

# TelegramNotifier: Send notifications to Telegram via Bot API
class TelegramNotifier
  TELEGRAM_BOT_TOKEN = ENV['TELEGRAM_BOT_TOKEN']
  TELEGRAM_CHAT_ID = ENV['TELEGRAM_CHAT_ID']
  TELEGRAM_API_URL = 'https://api.telegram.org/bot'

  class << self
    # Check if Telegram notifications are enabled
    def enabled?
      TELEGRAM_BOT_TOKEN.present? && TELEGRAM_CHAT_ID.present?
    end

    # Send a message to Telegram
    # @param message [String] Message to send
    # @param parse_mode [String] Parse mode ('Markdown', 'HTML', or nil)
    # @return [Boolean] true if successful, false otherwise
    def send_message(message, parse_mode: 'Markdown')
      return false unless enabled?

      return false if message.blank?

      begin
        uri = URI("#{TELEGRAM_API_URL}#{TELEGRAM_BOT_TOKEN}/sendMessage")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'

        payload = {
          chat_id: TELEGRAM_CHAT_ID,
          text: message,
          parse_mode: parse_mode
        }.compact

        request.body = payload.to_json

        response = http.request(request)

        if response.code == '200'
          Rails.logger.info('[TelegramNotifier] Message sent successfully')
          true
        else
          Rails.logger.error("[TelegramNotifier] Failed to send message: #{response.code} - #{response.body}")
          false
        end
      rescue StandardError => e
        Rails.logger.error("[TelegramNotifier] Error sending message: #{e.class} - #{e.message}")
        false
      end
    end

    # Send a formatted analysis notification
    # @param analysis [Hash] Analysis result hash
    # @return [Boolean]
    def send_analysis_notification(analysis)
      return false unless enabled?

      instrument = analysis[:instrument] || analysis['instrument'] || 'UNKNOWN'
      verdict = analysis[:verdict] || analysis['verdict'] || 'UNKNOWN'
      confidence = analysis[:confidence] || analysis['confidence'] || 0.0
      reasoning = analysis[:reasoning] || analysis['reasoning'] || 'No reasoning provided'
      ltp = analysis[:ltp] || analysis['ltp']
      trend = analysis[:trend] || analysis['trend']

      # Build message
      message = <<~MSG
        📊 **#{instrument} Option Buying Analysis**

        **Current Price:** #{ltp || 'N/A'}
        **Trend:** #{trend || 'N/A'}
        **Verdict:** #{verdict}
        **Confidence:** #{(confidence * 100).round(1)}%

        **Reasoning:**
        #{reasoning}

        _Analysis time: #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}_
      MSG

      send_message(message)
    end
  end
end

