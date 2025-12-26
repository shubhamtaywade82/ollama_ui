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
    prompt = params[:prompt].to_s
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
    response.stream.write("data: #{{ error: e.message }.to_json}\n\n")
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

    # Add current prompt as user message if provided
    conversation_messages << { role: 'user', content: prompt } if prompt.present?

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
        Rails.logger.debug { "DEBUG: Received chunk type: #{chunk[:type]}" }
        case chunk[:type]
        when 'content'
          # Accumulate all content (we'll check for tool calls after stream completes)
          if chunk[:text]
            assistant_message_content += chunk[:text]
            accumulated_content += chunk[:text]
            stream_event('content', { text: chunk[:text] })
            Rails.logger.debug { "DEBUG: Streamed content chunk (#{chunk[:text].length} chars)" }
          end

        when 'tool_calls'
          # Handle structured tool calls (received when stream is done)
          tool_calls = chunk[:tool_calls] || []
          tool_calls_received = true
          current_tool_calls = tool_calls
          Rails.logger.debug { "DEBUG: Received structured tool_calls: #{tool_calls.inspect}" }
        end
      end

      Rails.logger.debug do
        "DEBUG: Stream complete. Content length: #{assistant_message_content.length}, tool_calls_received: #{tool_calls_received}"
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

    # Use background job for non-blocking execution
    job_id = SecureRandom.uuid
    TechnicalAnalysisJob.perform_later(job_id, prompt, use_react: true)

    # Stream progress from job via polling
    stream_event('info',
                 { text: deep_mode ? '🔬 Deep Mode: Researching and analyzing...' : '🔍 Analyzing with Technical Analysis Agent...' })

    # Poll for results
    max_polls = 120 # 120 seconds max (2 minutes)
    poll_count = 0
    last_event_id = 0
    accumulated_content = ''

    loop do
      sleep(0.5) # Poll every 500ms for faster updates
      poll_count += 1
      break if poll_count >= max_polls

      events = Rails.cache.read("technical_analysis_#{job_id}_events") || []
      new_events = events.select { |e| e[:id] > last_event_id }.sort_by { |e| e[:id] }

      new_events.each do |event|
        case event[:type]
        when 'content'
          content = event[:data][:content] || event[:data][:text] || ''
          accumulated_content += content
          stream_event('content', { text: content })
        when 'progress'
          # Progress messages are optional - can be shown as info if needed
          # stream_event('info', { text: event[:data][:message] })
        when 'result'
          # Result event contains the full accumulated response
          result_text = event[:data][:message] || event[:data][:formatted] || accumulated_content
          if result_text.present?
            # Use result text as it contains the complete formatted analysis
            stream_event('content', { text: result_text })
          elsif accumulated_content.present?
            # Fallback to accumulated content if result text is empty
            stream_event('content', { text: accumulated_content })
          end
          stream_event('result', { text: result_text || accumulated_content })
          return # Done
        when 'error'
          stream_event('error', { text: event[:data][:message] })
          return
        end
        last_event_id = event[:id]
      end

      # Check if job is complete
      status = Rails.cache.read("technical_analysis_#{job_id}_status")
      if status == 'completed'
        # Final check for any remaining events (including result event)
        events = Rails.cache.read("technical_analysis_#{job_id}_events") || []
        events.select { |e| e[:id] > last_event_id }.each do |event|
          case event[:type]
          when 'content'
            content = event[:data][:content] || event[:data][:text] || ''
            accumulated_content += content
            stream_event('content', { text: content })
          when 'result'
            result_text = event[:data][:message] || event[:data][:formatted] || accumulated_content
            stream_event('content', { text: result_text }) if result_text.present?
            stream_event('result', { text: result_text || accumulated_content })
            return
          when 'error'
            stream_event('error', { text: event[:data][:message] })
            return
          end
        end
        # If no result event found but status is completed, send accumulated content
        stream_event('content', { text: accumulated_content }) if accumulated_content.present?
        return
      elsif status == 'failed'
        stream_event('error', { text: 'Analysis failed' })
        return
      end
    end

    # Timeout - send accumulated content if any
    if accumulated_content.present?
      stream_event('content', { text: accumulated_content })
    else
      stream_event('error', { text: 'Analysis timed out' })
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
