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

    if prompt.blank? || model.blank?
      return render json: { error: 'Model and prompt are required.' }, status: :unprocessable_entity
    end

    # Route to appropriate agent or use direct LLM
    agent_type = AgentRouter.should_use_agent?(prompt, deep_mode: deep_mode)

    if agent_type == :technical_analysis
      # Route to Technical Analysis Agent
      stream_technical_analysis_agent(prompt, deep_mode: deep_mode)
    else
      # Direct LLM response (fast, no agent)
      stream_direct_llm(model, prompt)
    end
  rescue StandardError => e
    response.stream.write("data: #{{ error: e.message }.to_json}\n\n")
  ensure
    response.stream.close
  end

  private

  def stream_direct_llm(model, prompt)
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'

    OllamaClient.new.chat_stream(model:, prompt:) do |chunk|
      response.stream.write("data: #{chunk.to_json}\n\n")
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
