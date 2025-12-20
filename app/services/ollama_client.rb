# frozen_string_literal: true

require 'http'

class OllamaClient
  # Use the .env file value or default to localhost
  OLLAMA_HOST = if File.exist?('.env')
                  File.readlines('.env').find do |line|
                    line.start_with?('OLLAMA_HOST=')
                  end&.split('=', 2)&.last&.strip || 'http://localhost:11434'
                else
                  'http://localhost:11434'
                end
  OLLAMA_API_KEY = 'ollama' # Default API key for Ollama

  def initialize
    @client = OpenAI::Client.new(
      access_token: OLLAMA_API_KEY,
      uri_base: "#{OLLAMA_HOST}/v1",
      request_timeout: 9000,
      read_timeout: 9000
    )
  end

  def tags
    # Ollama doesn't support OpenAI-compatible /v1/models, use /api/tags instead
    res = HTTP.timeout(1000).get("#{OLLAMA_HOST}/api/tags")
    raise "Ollama /api/tags failed (#{res.status})" unless res.status.success?

    json = JSON.parse(res.to_s)
    (json['models'] || []).map { |m| m['name'] }.sort
  rescue StandardError => e
    raise "Failed to fetch models from Ollama: #{e.message}"
  end

  def chat(model:, prompt: nil, messages: nil, temperature: 0.7)
    payload_messages = normalize_messages(prompt: prompt, messages: messages)

    Rails.logger.debug { "DEBUG: Sending chat request to #{OLLAMA_HOST}/v1 with model: #{model}" }

    response = @client.chat(
      parameters: {
        model: model,
        messages: payload_messages,
        temperature: temperature,
        stream: false
      }
    )

    Rails.logger.debug 'DEBUG: Chat response received'
    response.dig('choices', 0, 'message', 'content').to_s
  rescue Net::ReadTimeout
    raise 'Request timed out. The model may be loading or responding slowly. Try again or use a smaller model.'
  rescue StandardError => e
    Rails.logger.debug { "DEBUG: Chat error: #{e.class} - #{e.message}" }
    raise "Failed to chat with Ollama: #{e.message}"
  end

  def chat_stream(model:, prompt: nil, messages: nil)
    prompt ||= messages_to_prompt(messages)
    raise ArgumentError, 'prompt or messages required' unless prompt && !prompt.empty?

    require 'net/http'
    require 'uri'
    require 'json'

    uri = URI("#{OLLAMA_HOST}/api/generate")
    body = {
      model: model,
      prompt: prompt,
      stream: true
    }

    Rails.logger.debug { "DEBUG: Starting stream to #{uri}" }

    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 3000
    http.use_ssl = false

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request.body = body.to_json

    http.request(request) do |response|
      response.read_body do |chunk|
        chunk.lines.each do |line|
          line = line.strip
          next if line.empty?

          # puts "DEBUG: Received: #{line[0..100]}..."

          begin
            data = JSON.parse(line)
            yield({ type: 'content', text: data['response'] }) if data['response']
            if data['done'] == true
              Rails.logger.debug 'DEBUG: Stream complete'
              break
            end
          rescue JSON::ParserError => e
            Rails.logger.debug { "DEBUG: Parse error: #{e.message}" }
          end
        end
      end
    end
  rescue StandardError => e
    Rails.logger.debug { "DEBUG: Stream error: #{e.class} - #{e.message}" }
    Rails.logger.debug e.backtrace.first(5)
    raise "Failed to stream from Ollama: #{e.message}"
  end

  private

  def normalize_messages(prompt:, messages:)
    if messages && !messages.empty?
      return messages.map do |msg|
        role = msg[:role] || msg['role'] || 'user'
        content = (msg[:content] || msg['content'] || '').to_s
        { role: role, content: content }
      end
    end

    unless prompt && !prompt.empty?
      raise ArgumentError, 'prompt or messages required'
    end

    [{ role: 'user', content: prompt.to_s }]
  end

  def messages_to_prompt(messages)
    return nil unless messages && !messages.empty?

    messages.map do |msg|
      role = (msg[:role] || msg['role'] || 'user').to_s.capitalize
      content = (msg[:content] || msg['content'] || '').to_s
      "#{role}: #{content}"
    end.join("\n")
  end
end
