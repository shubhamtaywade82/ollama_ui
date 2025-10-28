# frozen_string_literal: true

class ChatsController < ApplicationController
  protect_from_forgery with: :null_session

  def index
    # No server data needed; Stimulus will fetch models
  end

  def models
    models = OllamaClient.new.tags
    render json: { models: }
  rescue StandardError => e
    render json: { error: e.message }, status: :bad_gateway
  end

  def create
    model  = params[:model].to_s
    prompt = params[:prompt].to_s

    if prompt.blank? || model.blank?
      return render json: { error: 'Model and prompt are required.' }, status: :unprocessable_entity
    end

    response_text = OllamaClient.new.chat(model:, prompt:)
    render json: { text: response_text }
  rescue StandardError => e
    render json: { error: e.message }, status: :bad_gateway
  end
end
