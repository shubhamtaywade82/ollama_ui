# frozen_string_literal: true

module Trading
  class LlmClient
    DEFAULT_MODEL = ENV.fetch('TRADING_AGENT_MODEL', 'phi3:mini')

    def initialize(model: DEFAULT_MODEL, client: OllamaClient.new)
      @client = client
      @model = model
    end

    def chat!(messages)
      normalized_messages = normalize_messages(messages)
      @client.chat(model: @model, messages: normalized_messages)
    rescue StandardError => e
      Rails.logger.error("Trading::LlmClient error: #{e.message}")
      raise
    end

    def chat_stream!(messages)
      normalized_messages = normalize_messages(messages)
      @client.chat_stream(model: @model, messages: normalized_messages) do |chunk|
        yield chunk[:text].to_s if chunk && chunk[:text]
      end
      nil
    end

    private

    def normalize_messages(messages)
      Array(messages).map do |msg|
        role = msg[:role] || msg['role'] || 'user'
        content = msg[:content] || msg['content']
        {
          role: role,
          content: content.to_s
        }
      end
    end
  end
end
