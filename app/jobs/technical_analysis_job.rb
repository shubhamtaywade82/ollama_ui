# frozen_string_literal: true

class TechnicalAnalysisJob < ApplicationJob
  queue_as :default

  # Don't retry on failure - user can retry manually
  discard_on StandardError do |job, error|
    job_id = job.arguments.first
    Rails.logger.error("[TechnicalAnalysisJob] Job failed: #{error.class} - #{error.message}")

    # Store error in cache for polling fallback
    begin
      cache_key = "technical_analysis_#{job_id}"
      events_data = Rails.cache.read(cache_key) || { events: [], last_event_id: 0, status: 'running' }
      error_event = { type: 'error', data: { message: error.message }, id: (events_data[:last_event_id] || 0) + 1 }
      events_data[:events] << error_event
      events_data[:last_event_id] = error_event[:id]
      events_data[:status] = 'failed'
      Rails.cache.write(cache_key, events_data, expires_in: 1.hour)
    rescue StandardError => e
      Rails.logger.warn("[TechnicalAnalysisJob] Failed to store error event: #{e.message}")
    end

    # Broadcast error to ActionCable channel (if available)
    begin
      if defined?(ActionCable) && ActionCable.server
        ActionCable.server.broadcast("technical_analysis_#{job_id}", error_event || { type: 'error', data: { message: error.message } })
      end
    rescue StandardError => e
      Rails.logger.warn("[TechnicalAnalysisJob] ActionCable broadcast failed: #{e.message}")
    end
  end

  def perform(job_id, query, use_react: true)
    Rails.logger.info("[TechnicalAnalysisJob] Starting analysis for job #{job_id}")

    # Initialize event storage
    initialize_event_storage(job_id)

    # Broadcast/store start event
    start_event = { type: 'start', data: { message: 'Technical Analysis Agent started' }, id: 0 }
    store_event(job_id, start_event)
    broadcast_event(job_id, start_event)

    accumulated_response = ''
    event_id = 1

    begin
      # Execute analysis with streaming callbacks
      Services::Ai::TechnicalAnalysisAgent.analyze(query: query, stream: true, use_react: use_react) do |chunk|
        next unless chunk.present?

        if chunk.is_a?(String)
          # Detect if this is a progress message
          if chunk.match?(/^[🔍📊🤔🔧⚙️✅📋💭⚠️❌🏁]/)
            # Progress message - send to progress channel
            progress_event = { type: 'progress', data: { message: chunk.strip }, id: event_id }
            event_id += 1
            store_event(job_id, progress_event)
            broadcast_event(job_id, progress_event)
          else
            # Content chunk - accumulate and stream
            accumulated_response += chunk
            content_event = { type: 'content', data: { content: chunk }, id: event_id }
            event_id += 1
            store_event(job_id, content_event)
            broadcast_event(job_id, content_event)
          end
        end
      end

      # Broadcast/store final result
      result_event = {
        type: 'result',
        data: {
          type: 'success',
          message: accumulated_response,
          formatted: accumulated_response
        },
        id: event_id
      }
      store_event(job_id, result_event, status: 'completed')
      broadcast_event(job_id, result_event)

      Rails.logger.info("[TechnicalAnalysisJob] Analysis completed for job #{job_id}")
    rescue StandardError => e
      Rails.logger.error("[TechnicalAnalysisJob] Error: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

      error_event = { type: 'error', data: { message: "Analysis failed: #{e.message}" }, id: event_id }
      store_event(job_id, error_event, status: 'failed')
      broadcast_event(job_id, error_event)
      raise # Re-raise to trigger discard_on
    end
  end

  private

  def initialize_event_storage(job_id)
    cache_key = "technical_analysis_#{job_id}"
    Rails.cache.write(cache_key, {
      events: [],
      last_event_id: 0,
      status: 'running'
    }, expires_in: 1.hour)
  end

  def store_event(job_id, event, status: nil)
    cache_key = "technical_analysis_#{job_id}"
    events_data = Rails.cache.read(cache_key) || { events: [], last_event_id: 0, status: 'running' }

    events_data[:events] << event
    events_data[:last_event_id] = event[:id] || events_data[:events].length
    events_data[:status] = status if status

    # Keep only last 100 events to prevent memory bloat
    if events_data[:events].length > 100
      events_data[:events] = events_data[:events].last(100)
    end

    Rails.cache.write(cache_key, events_data, expires_in: 1.hour)
  end

  def broadcast_event(job_id, event)
    # Broadcast to ActionCable if available
    if defined?(ActionCable) && ActionCable.server
      begin
        ActionCable.server.broadcast("technical_analysis_#{job_id}", event)
      rescue StandardError => e
        Rails.logger.warn("[TechnicalAnalysisJob] ActionCable broadcast failed: #{e.message}")
      end
    end
  end
end

