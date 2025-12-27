# frozen_string_literal: true

class ChatsController < ApplicationController
  include ActionController::Live

  protect_from_forgery with: :null_session

  def index
    @examples = chat_examples
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

  def stream
    model  = params[:model].to_s
    prompt = params[:prompt].to_s.strip # Trim spaces from start and end
    deep_mode = ['true', true].include?(params[:deep_mode])
    messages = params[:messages] || [] # Conversation history

    if prompt.blank? && messages.empty?
      return render json: { error: 'Prompt or messages are required.' }, status: :unprocessable_entity
    end

    return render json: { error: 'Model is required.' }, status: :unprocessable_entity if model.blank?

    # Route to appropriate agent or use direct LLM
    agent_type = AgentRouter.should_use_agent?(prompt, deep_mode: deep_mode)

    if agent_type == :technical_analysis
      # Route to Technical Analysis Agent
      stream_technical_analysis_agent(prompt, deep_mode: deep_mode)
    else
      # Direct LLM response with chat API (supports history and tools)
      stream_direct_llm(model, prompt: prompt, messages: messages)
    end
  rescue StandardError => e
    Rails.logger.error "Chat stream error: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n") if e.backtrace
    response.stream.write("data: #{{ type: 'error', text: e.message }.to_json}\n\n")
    response.stream.flush
  ensure
    response.stream.close
  end

  private

  def stream_direct_llm(model, prompt: nil, messages: [])
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'
    response.headers['Connection'] = 'keep-alive'

    # Build conversation history
    conversation_messages = messages.dup || []

    # Add current prompt as user message if provided (already trimmed)
    # Only add if it's not already the last message (avoid duplication)
    if prompt.present?
      last_message = conversation_messages.last
      unless last_message && last_message[:role] == 'user' && last_message[:content] == prompt
        conversation_messages << { role: 'user', content: prompt }
      end
    end

    # Define web search tool for Ollama
    tools = [
      {
        type: 'function',
        function: {
          name: 'web_search',
          description: 'Search the web for latest information, news, facts, or current data. Use this when you need up-to-date information that may not be in your training data.',
          parameters: {
            type: 'object',
            properties: {
              query: {
                type: 'string',
                description: 'The search query to find information on the web'
              }
            },
            required: ['query']
          }
        }
      }
    ]

    client = OllamaClient.new
    accumulated_content = ''
    assistant_message_with_tools = nil
    max_iterations = 5 # Prevent infinite loops
    iteration = 0

    loop do
      iteration += 1
      break if iteration > max_iterations

      tool_calls_received = false
      current_tool_calls = []
      assistant_message_content = ''
      assistant_message_with_tools = nil

      # Only pass tools on first iteration (prevent repeated tool calls)
      tools_to_use = iteration == 1 ? tools : nil

      # Stream chat with tools - collect full response
      client.chat_stream(model: model, messages: conversation_messages, tools: tools_to_use) do |chunk|
        case chunk[:type]
        when 'content'
          # Accumulate all content (we'll check for tool calls after stream completes)
          if chunk[:text]
            assistant_message_content += chunk[:text]
            accumulated_content += chunk[:text]
            stream_event('content', { text: chunk[:text] })
          end

        when 'tool_calls'
          # Handle structured tool calls (received when stream is done)
          tool_calls = chunk[:tool_calls] || []
          tool_calls_received = true
          current_tool_calls = tool_calls
          Rails.logger.debug { "DEBUG: Received #{tool_calls.length} tool_calls" }
        end
      end

      Rails.logger.debug do
        "DEBUG: Stream complete. Content: #{assistant_message_content.length} chars, Tool calls: #{tool_calls_received}"
      end

      # Check if content contains a tool call (some models output tool calls as JSON text)
      if !tool_calls_received && assistant_message_content.present?
        # Try to extract tool call from accumulated content
        tool_call_match = assistant_message_content.match(/\{\s*"name"\s*:\s*"(\w+)"\s*,\s*"arguments"\s*:\s*(\{[^}]*\})\s*\}/m)
        if tool_call_match
          tool_name = tool_call_match[1]
          begin
            tool_args = JSON.parse(tool_call_match[2])
            tool_calls_received = true
            current_tool_calls = [{
              function: {
                name: tool_name,
                arguments: tool_args
              }
            }]
            Rails.logger.debug do
              "DEBUG: Extracted tool call from content: #{tool_name} with args: #{tool_args.inspect}"
            end
            # Remove tool call JSON from content (don't show it to user)
            assistant_message_content = assistant_message_content.gsub(
              /\{\s*"name"\s*:\s*"#{tool_name}"\s*,\s*"arguments"\s*:\s*\{[^}]*\}\s*\}/m, ''
            ).strip
            # Update accumulated_content to remove tool call JSON
            accumulated_content = accumulated_content.gsub(
              /\{\s*"name"\s*:\s*"#{tool_name}"\s*,\s*"arguments"\s*:\s*\{[^}]*\}\s*\}/m, ''
            ).strip
          rescue JSON::ParserError => e
            Rails.logger.debug { "DEBUG: Failed to parse tool call from content: #{e.message}" }
          end
        end
      end

      # If no tool calls, we're done
      break unless tool_calls_received && current_tool_calls.any?

      # Add assistant message with tool calls to conversation
      assistant_message_with_tools = {
        role: 'assistant',
        content: assistant_message_content,
        tool_calls: current_tool_calls.map do |tc|
          {
            function: {
              name: tc[:function]&.dig(:name) || tc['function']&.dig('name'),
              arguments: tc[:function]&.dig(:arguments) || tc['function']&.dig('arguments') || {}
            }
          }
        end
      }
      conversation_messages << assistant_message_with_tools

      # Execute all tool calls
      tool_results = []
      current_tool_calls.each do |tool_call|
        function = tool_call[:function] || tool_call['function'] || {}
        tool_name = function[:name] || function['name']
        arguments = function[:arguments] || function['arguments'] || {}

        next unless tool_name == 'web_search'

        query = arguments[:query] || arguments['query'] || ''
        stream_event('info', { text: "🔍 Searching web for: #{query}" })

        # Execute web search
        search_results = WebSearchService.search(query, max_results: 5)

        if search_results[:error]
          tool_results << {
            role: 'tool',
            content: "Error: #{search_results[:error]}",
            tool_name: 'web_search'
          }
          stream_event('info', { text: "⚠️ Search error: #{search_results[:error]}" })
        else
          # Format search results (include scraped content if available)
          results_text = search_results[:results].map do |result|
            text = "Title: #{result[:title]}\nSnippet: #{result[:snippet]}"
            # Include scraped content if available (more detailed)
            text += "\nContent: #{result[:content]}" if result[:content].present?
            text += "\nURL: #{result[:url]}"
            text
          end.join("\n\n")

          tool_results << {
            role: 'tool',
            content: "Search results for '#{query}':\n\n#{results_text}",
            tool_name: 'web_search'
          }
          stream_event('info', { text: "✅ Found #{search_results[:results].length} results" })
        end
      end

      # Add tool results to conversation
      conversation_messages.concat(tool_results)

      # Add a user message to prompt the model to use the tool results and provide an answer
      # This prevents the model from calling tools again
      conversation_messages << {
        role: 'user',
        content: "Based on the web search results above, please provide a comprehensive answer to the user's question. Use the information from the search results to give an accurate and up-to-date response. Do not call any more tools - provide your answer now."
      }

      # Reset for next iteration (but keep accumulated_content to preserve all content)
      assistant_message_content = ''
    end

    # Send final result (ensure we always send something)
    if accumulated_content.present?
      stream_event('result', { text: accumulated_content })
    elsif assistant_message_content.present?
      stream_event('result', { text: assistant_message_content })
    else
      # If no content was accumulated, send a message indicating the response is being processed
      Rails.logger.warn('DEBUG: No content accumulated after stream completion')
    end
  end

  def stream_technical_analysis_agent(prompt, deep_mode: false)
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'
    response.headers['Connection'] = 'keep-alive'

    # Direct streaming (immediate execution, no background job)
    stream_event('info',
                 { text: deep_mode ? '🔬 Deep Mode: Researching and analyzing...' : '🔍 Analyzing with Technical Analysis Agent...' })

    accumulated_response = ''

    begin
      Services::Ai::TechnicalAnalysisAgent.analyze(query: prompt, stream: true, use_react: true) do |chunk|
        next unless chunk.present?

        # TechnicalAnalysisAgent streams string chunks directly
        if chunk.is_a?(String)
          # Detect if this is a progress message (short single-line status updates)
          chunk_stripped = chunk.strip
          is_progress = chunk_stripped.match?(/^[🔍📊🤔🔧⚙️✅📋💭⚠❌🏁⏹ℹ💡]/) &&
                        (chunk_stripped.lines.length <= 2) &&
                        !chunk_stripped.include?('**Analysis Result**') &&
                        !chunk_stripped.include?('**Instrument:**') &&
                        !chunk_stripped.include?('**Current Price:**') &&
                        !chunk_stripped.include?('**Trend:**') &&
                        !chunk_stripped.include?('**Verdict:**') &&
                        !chunk_stripped.include?('**Recommendation:**')

          if is_progress
            # This is a progress/log message - send as info
            stream_event('info', { text: chunk_stripped })
          else
            # This is actual content - accumulate and stream immediately
            accumulated_response += chunk
            stream_event('content', { text: chunk })
          end
        end

        # Flush to ensure immediate delivery
        response.stream.flush if response.stream.respond_to?(:flush)
      end

      # Final result
      if accumulated_response.present?
        stream_event('result', {
                       type: 'success',
                       text: accumulated_response,
                       formatted: accumulated_response
                     })
      else
        stream_event('error', { text: 'No response generated' })
      end
    rescue StandardError => e
      Rails.logger.error("[TechnicalAnalysisAgent] Error: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
      stream_event('error', { text: e.message })
    end
  end

  def stream_event(type, data)
    response.stream.write("data: #{{ type: type, **data }.to_json}\n\n")
  end

  def chat_examples
    Rails.cache.fetch('chat_examples', expires_in: 1.hour) do
      [
        {
          category: '💬 General Chat',
          examples: [
            'Explain quantum computing in simple terms',
            'What are the latest trends in AI?',
            'Help me write a Python function',
            'Summarize the benefits of meditation'
          ]
        },
        {
          category: '📊 Trading & Finance',
          examples: [
            'What is technical analysis?',
            'Explain RSI indicator',
            'How does options trading work?',
            'What is the difference between stocks and bonds?'
          ]
        },
        {
          category: '🔬 Deep Research',
          examples: [
            'Research the impact of AI on healthcare',
            'Analyze the pros and cons of renewable energy',
            'Compare different programming languages',
            'Explain blockchain technology'
          ]
        },
        {
          category: '💡 Creative & Learning',
          examples: [
            'Write a short story about time travel',
            'Create a study plan for learning Python',
            'Suggest ways to improve productivity',
            'Explain machine learning concepts'
          ]
        }
      ]
    end
  end
end
