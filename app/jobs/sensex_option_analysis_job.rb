# frozen_string_literal: true

# SensexOptionAnalysisJob: Analyzes SENSEX for option buying opportunities every 5 minutes
class SensexOptionAnalysisJob < ApplicationJob
  queue_as :default

  # Retry on failure (up to 3 times with exponential backoff)
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform
    Rails.logger.info('[SensexOptionAnalysisJob] Starting SENSEX option buying analysis')

    # Query for SENSEX analysis with focus on option buying
    query = 'Analyze SENSEX for option buying opportunities. Focus on CALL options if bullish, PUT options if bearish. Provide detailed technical analysis with indicators.'

    # Get model from ENV or use default (nil = auto-select)
    # Set SENSEX_ANALYSIS_MODEL environment variable to specify a model
    model = ENV.fetch('SENSEX_ANALYSIS_MODEL', nil).presence

    if model
      Rails.logger.info("[SensexOptionAnalysisJob] Using specified model: #{model}")
    else
      Rails.logger.info('[SensexOptionAnalysisJob] Using auto-selected model (set SENSEX_ANALYSIS_MODEL env var to specify)')
    end

    begin
      # Use Technical Analysis Agent to analyze SENSEX
      analysis_result = Services::Ai::TechnicalAnalysisAgent.analyze(
        query: query,
        stream: false,
        use_react: true,
        model: model
      )

      # Extract structured analysis
      if analysis_result && analysis_result[:analysis]
        analysis_data = analysis_result[:analysis]

        # Check if we should send notification (only for actionable signals)
        verdict = analysis_data[:verdict] || analysis_data['verdict']
        confidence = (analysis_data[:confidence] || analysis_data['confidence'] || 0.0).to_f

        # Only notify if:
        # 1. Not NO_TRADE
        # 2. Confidence is above 50%
        should_notify = verdict != 'NO_TRADE' && confidence >= 0.5

        if should_notify
          # Enrich analysis with additional context
          enriched_analysis = analysis_data.dup
          enriched_analysis[:instrument] = 'SENSEX'
          enriched_analysis[:analysis_type] = 'Option Buying'
          enriched_analysis[:timestamp] = Time.current

          # Send Telegram notification
          if TelegramNotifier.enabled?
            TelegramNotifier.send_analysis_notification(enriched_analysis)
            Rails.logger.info('[SensexOptionAnalysisJob] Analysis notification sent to Telegram')
          else
            Rails.logger.warn('[SensexOptionAnalysisJob] Telegram notifier not configured, skipping notification')
          end
        else
          Rails.logger.info("[SensexOptionAnalysisJob] Analysis completed but no notification sent (verdict: #{verdict}, confidence: #{(confidence * 100).round(1)}%)")
        end

        # Log analysis result
        Rails.logger.info("[SensexOptionAnalysisJob] Analysis completed - Verdict: #{verdict}, Confidence: #{(confidence * 100).round(1)}%")
      else
        Rails.logger.warn('[SensexOptionAnalysisJob] Analysis returned no result')
      end
    rescue StandardError => e
      Rails.logger.error("[SensexOptionAnalysisJob] Error during analysis: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      raise # Re-raise to trigger retry
    end
  end
end
