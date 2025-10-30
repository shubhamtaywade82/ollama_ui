# frozen_string_literal: true

require "http"

class Trading::LlmClient
  DEFAULT_HOST = ENV.fetch("OLLAMA_HOST", "http://localhost:11434")
  DEFAULT_MODEL = ENV.fetch("TRADING_AGENT_MODEL", "phi3:mini")

  def initialize(host: DEFAULT_HOST, model: DEFAULT_MODEL)
    @host = host
    @model = model
  end

  def chat!(messages)
    response = HTTP.timeout(connect: 5, read: 60)
                   .post("#{@host}/api/chat", json: request_payload(messages))

    raise "LLM error #{response.status}" unless response.status.success?

    parsed = JSON.parse(response.to_s)
    parsed.dig("message", "content").to_s
  rescue StandardError => e
    Rails.logger.error("Trading::LlmClient error: #{e.message}")
    raise
  end

  private

  def request_payload(messages)
    {
      model: @model,
      stream: false,
      messages: messages.map { |msg| { role: msg[:role] || msg["role"], content: msg[:content] || msg["content"] } }
    }
  end
end
