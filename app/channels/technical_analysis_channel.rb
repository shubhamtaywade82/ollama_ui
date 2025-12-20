# frozen_string_literal: true

class TechnicalAnalysisChannel < ApplicationCable::Channel
  def subscribed
    # Subscribe to a specific job ID
    job_id = params[:job_id]
    stream_from "technical_analysis_#{job_id}"

    Rails.logger.info("[TechnicalAnalysisChannel] Subscribed to job #{job_id}")
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
    Rails.logger.info("[TechnicalAnalysisChannel] Unsubscribed from job")
  end
end

