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

  def chat_stream(model:, prompt: nil, messages: nil, tools: nil, &block)
    # Use /api/chat endpoint for proper chat API with history and tools support
    require 'net/http'
    require 'uri'
    require 'json'

    # Normalize messages - prefer messages array over prompt
    payload_messages = if messages.present?
                         normalize_messages_for_chat(messages)
                       elsif prompt
                         [{ role: 'user', content: prompt.to_s }]
                       else
                         raise ArgumentError, 'prompt or messages required'
                       end

    uri = URI("#{OLLAMA_HOST}/api/chat")
    body = {
      model: model,
      messages: payload_messages,
      stream: true
    }

    # Add tools if provided
    body[:tools] = tools if tools.present?

    Rails.logger.debug { "DEBUG: Starting chat stream to #{uri} with #{payload_messages.length} messages" }

    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 3000
    http.use_ssl = false

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request.body = body.to_json

    accumulated_tool_calls = []
    
    http.request(request) do |response|
      response.read_body do |chunk|
        chunk.lines.each do |line|
          line = line.strip
          next if line.empty?

          begin
            data = JSON.parse(line)
            Rails.logger.debug { "DEBUG: Received chunk: #{data.keys.inspect}, done: #{data['done']}" }

            # Handle chat API response format
            if data['message']
              message = data['message']
              
              # Accumulate tool calls during streaming (they might come in chunks)
              if message['tool_calls'].is_a?(Array) && message['tool_calls'].any?
                accumulated_tool_calls.concat(message['tool_calls'])
                Rails.logger.debug { "DEBUG: Accumulated tool calls: #{accumulated_tool_calls.length} total" }
              end
              
              # Log full message structure for debugging when done
              if data['done'] == true
                Rails.logger.debug { "DEBUG: Final message structure: #{message.keys.inspect}" }
                Rails.logger.debug { "DEBUG: Message content: #{message['content'].inspect}" }
                Rails.logger.debug { "DEBUG: Message tool_calls type: #{message['tool_calls'].class}, value: #{message['tool_calls'].inspect}" }
                if message['tool_calls'].is_a?(Array)
                  Rails.logger.debug { "DEBUG: Tool calls array length: #{message['tool_calls'].length}" }
                  message['tool_calls'].each_with_index do |tc, idx|
                    Rails.logger.debug { "DEBUG: Tool call #{idx}: #{tc.inspect}" }
                  end
                end
              end
              
              Rails.logger.debug do
                tool_calls_present = message['tool_calls'].is_a?(Array) ? message['tool_calls'].any? : message['tool_calls'].present?
                "DEBUG: Message content present: #{message['content'].present?}, tool_calls present: #{tool_calls_present}"
              end

              # Stream content
              if message['content'].present?
                content = message['content']
                Rails.logger.debug { "DEBUG: Streaming content chunk: #{content[0..100]}..." }
                yield({ type: 'content', text: content })
              end

              # Handle structured tool calls (yield when done with all accumulated tool calls)
              if data['done'] == true
                # Use accumulated tool calls if available, otherwise check final message
                final_tool_calls = accumulated_tool_calls.any? ? accumulated_tool_calls : (message['tool_calls'] if message['tool_calls'].is_a?(Array))
                
                if final_tool_calls && final_tool_calls.any?
                  Rails.logger.debug { "DEBUG: Yielding accumulated tool_calls: #{final_tool_calls.inspect}" }
                  yield({ type: 'tool_calls', tool_calls: final_tool_calls })
                end
              end

              # Check for tool call in content when done (fallback for models that output JSON)
              if data['done'] == true && message['content'].present?
                content = message['content']
                tool_call_match = content.match(/\{\s*"name"\s*:\s*"(\w+)"\s*,\s*"arguments"\s*:\s*(\{[^}]*\})\s*\}/m)
                if tool_call_match && !message['tool_calls']&.any?
                  # Extract tool call from text content
                  tool_name = tool_call_match[1]
                  begin
                    tool_args = JSON.parse(tool_call_match[2])
                    Rails.logger.debug { "DEBUG: Extracted tool call from final content: #{tool_name}" }
                    yield({ type: 'tool_calls', tool_calls: [{
                      function: {
                        name: tool_name,
                        arguments: tool_args
                      }
                    }] })
                  rescue JSON::ParserError => e
                    Rails.logger.debug { "DEBUG: Failed to parse tool call: #{e.message}" }
                  end
                end
              end
            end

            if data['done'] == true
              Rails.logger.debug 'DEBUG: Chat stream complete'
              break
            end
          rescue JSON::ParserError => e
            Rails.logger.debug { "DEBUG: Parse error: #{e.message}, line: #{line[0..200]}" }
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
    if messages.present?
      return messages.map do |msg|
        role = msg[:role] || msg['role'] || 'user'
        content = (msg[:content] || msg['content'] || '').to_s
        { role: role, content: content }
      end
    end

    raise ArgumentError, 'prompt or messages required' unless prompt.present?

    [{ role: 'user', content: prompt.to_s }]
  end

  def messages_to_prompt(messages)
    return nil unless messages.present?

    messages.map do |msg|
      role = (msg[:role] || msg['role'] || 'user').to_s.capitalize
      content = (msg[:content] || msg['content'] || '').to_s
      "#{role}: #{content}"
    end.join("\n")
  end

  def normalize_messages_for_chat(messages)
    messages.map do |msg|
      role = msg[:role] || msg['role'] || 'user'
      content = (msg[:content] || msg['content'] || '').to_s

      normalized = { role: role.to_s, content: content }

      # Handle tool calls in assistant messages
      if role.to_s == 'assistant' && (msg[:tool_calls] || msg['tool_calls'])
        normalized[:tool_calls] = (msg[:tool_calls] || msg['tool_calls']).map do |tc|
          if tc.is_a?(Hash)
            {
              function: {
                name: tc[:function]&.dig(:name) || tc['function']&.dig('name') || tc[:name] || tc['name'],
                arguments: tc[:function]&.dig(:arguments) || tc['function']&.dig('arguments') || tc[:arguments] || tc['arguments'] || {}
              }
            }
          else
            tc
          end
        end
      end

      # Handle tool results (Ollama expects role: 'tool' with tool_name)
      if role.to_s == 'tool'
        normalized[:role] = 'tool'
        normalized[:tool_name] = msg[:tool_name] || msg['tool_name'] || 'web_search'
        # Ensure content is a string
        normalized[:content] = content.to_s
      end

      normalized
    end
  end
end
