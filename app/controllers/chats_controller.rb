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

    client = OllamaClient.new
    accumulated_content = ''

    # Stream chat response
    client.chat_stream(model: model, messages: conversation_messages) do |chunk|
      case chunk[:type]
      when 'content'
        if chunk[:text]
          accumulated_content += chunk[:text]
          stream_event('content', { text: chunk[:text] })
        end
      end
    end

    # Send final result
    if accumulated_content.present?
      stream_event('result', { text: accumulated_content })
    else
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
