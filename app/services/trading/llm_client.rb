# frozen_string_literal: true

require 'http'

module Trading
  class LlmClient
    DEFAULT_HOST = ENV.fetch('OLLAMA_HOST', 'http://localhost:11434')
    DEFAULT_MODEL = ENV.fetch('TRADING_AGENT_MODEL', 'phi3:mini')

    def initialize(host: DEFAULT_HOST, model: DEFAULT_MODEL)
      @host = host
      @model = model
    end

    def chat!(messages)
      response = HTTP.timeout(connect: 5, read: 60)
                     .post("#{@host}/api/chat", json: request_payload(messages))

      raise "LLM error #{response.status}" unless response.status.success?

      parsed = JSON.parse(response.to_s)
      parsed.dig('message', 'content').to_s
    rescue StandardError => e
      Rails.logger.error("Trading::LlmClient error: #{e.message}")
      raise
    end

    def chat_stream!(messages)
      require 'http'
      require 'json'
      stream_url = "#{@host}/api/chat"
      resp = HTTP.headers('Content-Type' => 'application/json')
                 .stream(:post, stream_url, json: request_payload(messages).merge(stream: true))
      buffer = ''
      resp.body.each do |chunk|
        buffer << chunk
        buffer.split("\n").each do |line|
          next if line.strip.empty?

          begin
            line_data = JSON.parse(line)
            yield line_data['message']['content'].to_s if line_data['message'] && line_data['message']['content']
          rescue JSON::ParserError
            # ignore incomplete lines
          end
        end
        buffer = '' if buffer.include?("\n")
      end
      nil
    end

    private

    def request_payload(messages)
      {
        model: @model,
        stream: false,
        messages: messages.map { |msg| { role: msg[:role] || msg['role'], content: msg[:content] || msg['content'] } }
      }
    end
  end
end
