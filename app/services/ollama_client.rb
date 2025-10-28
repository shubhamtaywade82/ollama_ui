# frozen_string_literal: true

require 'http'

class OllamaClient
  # Use the .env file value or default to localhost
  OLLAMA_HOST = if File.exist?('.env')
                   File.readlines('.env').find { |line| line.start_with?('OLLAMA_HOST=') }&.split('=', 2)&.last&.strip || 'http://localhost:11434'
                 else
                   'http://localhost:11434'
                 end
  OLLAMA_API_KEY = 'ollama' # Default API key for Ollama

  def initialize
    @client = OpenAI::Client.new(
      access_token: OLLAMA_API_KEY,
      uri_base: "#{OLLAMA_HOST}/v1",
      request_timeout: 7700,
      read_timeout: 8300
    )
  end

  def tags
    # Ollama doesn't support OpenAI-compatible /v1/models, use /api/tags instead
    res = HTTP.timeout(10).get("#{OLLAMA_HOST}/api/tags")
    raise "Ollama /api/tags failed (#{res.status})" unless res.status.success?

    json = JSON.parse(res.to_s)
    (json['models'] || []).map { |m| m['name'] }.sort
  rescue StandardError => e
    raise "Failed to fetch models from Ollama: #{e.message}"
  end

  def chat(model:, prompt:)
    puts "DEBUG: Sending chat request to #{OLLAMA_HOST}/v1 with model: #{model}"

    response = @client.chat(
      parameters: {
        model: model,
        messages: [{ role: 'user', content: prompt }],
        temperature: 0.7,
        stream: false
      }
    )

    puts "DEBUG: Chat response received"
    response.dig('choices', 0, 'message', 'content').to_s
  rescue Net::ReadTimeout => e
    raise "Request timed out. The model may be loading or responding slowly. Try again or use a smaller model."
  rescue StandardError => e
    puts "DEBUG: Chat error: #{e.class} - #{e.message}"
    raise "Failed to chat with Ollama: #{e.message}"
  end

  def chat_stream(model:, prompt:, &block)
    require 'net/http'
    require 'uri'
    require 'json'

    uri = URI("#{OLLAMA_HOST}/api/generate")
    body = {
      model: model,
      prompt: prompt,
      stream: true
    }

    puts "DEBUG: Starting stream to #{uri}"

    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 300
    http.use_ssl = false

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request.body = body.to_json

    http.request(request) do |response|
      response.read_body do |chunk|
        chunk.lines.each do |line|
          line = line.strip
          next if line.empty?

          puts "DEBUG: Received: #{line[0..100]}..."

          begin
            data = JSON.parse(line)
            if data['response']
              block.call({ type: 'content', text: data['response'] })
            end
            if data['done'] == true
              puts "DEBUG: Stream complete"
              break
            end
          rescue JSON::ParserError => e
            puts "DEBUG: Parse error: #{e.message}"
          end
        end
      end
    end
  rescue StandardError => e
    puts "DEBUG: Stream error: #{e.class} - #{e.message}"
    puts e.backtrace.first(5)
    raise "Failed to stream from Ollama: #{e.message}"
  end
end
