# frozen_string_literal: true

class TradingController < ApplicationController
  protect_from_forgery with: :null_session

  def index
    # Trading chat interface
  end

  def account_info
    fund = DhanHQ::Models::Funds.fetch

    render json: {
      equity: fund.available_balance.to_f,
      buying_power: fund.available_balance.to_f,
      cash: fund.available_balance.to_f,
      collateral: fund.collateral_amount.to_f,
      utilized: fund.utilized_amount.to_f,
      withdrawable: fund.withdrawable_balance.to_f,
      account_status: 'ACTIVE',
      broker: 'DhanHQ'
    }
  rescue StandardError => e
    render json: { error: e.message }, status: :bad_gateway
  end

  def positions
    positions = DhanHQ::Models::Position.all.map do |pos|
      {
        symbol: pos.trading_symbol || pos.symbol,
        qty: pos.net_qty.to_f,
        market_value: pos.cost_price&.to_f || 0,
        unrealized_pl: pos.unrealized_profit&.to_f || 0,
        buy_avg: pos.buy_avg&.to_f || 0,
        sell_avg: pos.sell_avg&.to_f || 0
      }
    end
    render json: { positions: positions }
  rescue StandardError => e
    render json: { error: e.message }, status: :bad_gateway
  end

  def holdings
    holdings = DhanHQ::Models::Holding.all.map do |hold|
      {
        symbol: hold.trading_symbol || hold.symbol,
        qty: hold.quantity.to_f,
        market_value: hold.current_value&.to_f || 0,
        invested: hold.average_price&.to_f || 0,
        current_price: hold.current_price&.to_f || 0
      }
    end
    render json: { holdings: holdings }
  rescue StandardError => e
    render json: { error: e.message }, status: :bad_gateway
  end

  def quote
    symbol = params[:symbol]&.upcase

    return render json: { error: 'Symbol parameter required' }, status: :unprocessable_entity if symbol.blank?

    # Find the instrument first to get security_id and exchange_segment
    inst = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)

    if inst&.exchange_segment && inst.security_id
      # Extract values to avoid nil issues
      exchange_segment = inst.exchange_segment.to_s
      security_id = inst.security_id.to_i

      # Create proper hash for quote call
      quote_params = { exchange_segment => [security_id] }

      # Get live quote using MarketFeed.quote
      quote_response = DhanHQ::Models::MarketFeed.quote(quote_params)

      # Extract the actual quote data from nested response
      quote_data = quote_response.dig('data', exchange_segment, security_id.to_s) ||
                   quote_response.dig('data', exchange_segment, security_id)

      if quote_data
        render json: {
          symbol: inst.symbol_name || inst.underlying_symbol,
          name: inst.display_name || inst.symbol_name,
          security_id: security_id,
          exchange_segment: exchange_segment,
          last_price: quote_data['last_price'] || quote_data[:last_price],
          volume: quote_data['volume'] || quote_data[:volume],
          ohlc: quote_data['ohlc'] || quote_data[:ohlc] || {},
          fifty_two_week_high: quote_data['52_week_high'] || quote_data[:fifty_two_week_high],
          fifty_two_week_low: quote_data['52_week_low'] || quote_data[:fifty_two_week_low],
          average_price: quote_data['average_price'] || quote_data[:average_price]
        }
      else
        render json: { error: "No quote data returned for #{symbol}" }, status: :not_found
      end
    else
      render json: { error: "Symbol #{symbol} not found in any exchange segment" }, status: :not_found
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :bad_gateway
  end

  def agent
    user_prompt = params[:prompt].to_s

    # Use the DhanTradingAgent to process the prompt
    agent = DhanTradingAgent.new(prompt: user_prompt)
    result = agent.execute

    render json: {
      type: result[:type],
      message: result[:message],
      formatted: result[:formatted],
      data: result[:data]
    }
  rescue StandardError => e
    render json: {
      type: :error,
      message: "Agent error: #{e.message}",
      formatted: "❌ Error: #{e.message}"
    }, status: :bad_gateway
  end

  def agent_stream
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'
    @stream_client_closed = false

    begin
      user_prompt = params[:prompt].to_s
      agent_mode = params[:mode] || 'trading' # 'trading' or 'technical_analysis'

      if user_prompt.blank?
        stream_event('error', { message: 'Prompt cannot be blank' })
        return
      end

      if agent_mode == 'technical_analysis'
        # Use TechnicalAnalysisAgent
        stream_technical_analysis(user_prompt)
      else
        # Use DhanTradingAgent (default)
        stream_trading_agent(user_prompt)
      end
    rescue StandardError => e
      stream_event('error', { message: e.message })
    ensure
      response.stream.close
    end
  end

  def technical_analysis_stream
    # Check if background execution is enabled (default: true to avoid blocking)
    use_background = params[:background] != 'false' && ENV.fetch('AI_USE_BACKGROUND_JOBS', 'true') == 'true'

    if use_background
      # Background execution via ActiveJob (non-blocking)
      technical_analysis_background
    else
      # Direct streaming (blocks web server - use only if background is disabled)
      technical_analysis_stream_direct
    end
  end

  def technical_analysis_background
    user_prompt = params[:prompt].to_s
    if user_prompt.blank?
      render json: { error: 'Prompt cannot be blank' }, status: :unprocessable_entity
      return
    end

    # Limit prompt size
    max_prompt_length = ENV.fetch('AI_MAX_PROMPT_LENGTH', '2000').to_i
    if user_prompt.length > max_prompt_length
      user_prompt = user_prompt[0..max_prompt_length - 1] + '... [truncated]'
    end

    # Generate unique job ID
    job_id = SecureRandom.uuid

    # Enqueue background job (non-blocking)
    use_planning = params[:use_planning] != 'false'
    TechnicalAnalysisJob.perform_later(job_id, user_prompt, use_planning: use_planning)

    # Return job ID immediately (non-blocking)
    render json: {
      job_id: job_id,
      status: 'queued',
      message: 'Analysis started in background. Connect to ActionCable channel for updates.',
      channel: "technical_analysis_#{job_id}"
    }
  end

  def technical_analysis_stream_direct
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'
    @stream_client_closed = false

    begin
      user_prompt = params[:prompt].to_s
      if user_prompt.blank?
        stream_event('error', { message: 'Prompt cannot be blank' })
        return
      end

      # Limit prompt size to prevent token bloat (max 2000 characters ≈ 500 tokens)
      max_prompt_length = ENV.fetch('AI_MAX_PROMPT_LENGTH', '2000').to_i
      if user_prompt.length > max_prompt_length
        user_prompt = user_prompt[0..max_prompt_length - 1] + '... [truncated]'
        stream_event('progress', { message: "⚠️ Prompt truncated to #{max_prompt_length} characters to optimize performance" })
      end

      stream_technical_analysis(user_prompt)
    rescue StandardError => e
      stream_event('error', { message: e.message })
    ensure
      response.stream.close
    end
  end

  def technical_analysis_status
    job_id = params[:job_id]
    last_event = params[:last_event]&.to_i || 0

    # Get events from cache (stored by background job)
    cache_key = "technical_analysis_#{job_id}"
    events_data = Rails.cache.read(cache_key) || { events: [], last_event_id: 0, status: 'running' }

    # Return only new events
    new_events = events_data[:events].select { |e| e[:id] > last_event }

    render json: {
      job_id: job_id,
      status: events_data[:status] || 'running',
      events: new_events,
      last_event_id: events_data[:last_event_id] || 0
    }
  rescue StandardError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def stream_trading_agent(user_prompt)
    progress_callback = lambda do |event_type, payload|
      stream_event(event_type, payload)
    end

    agent = DhanTradingAgent.new(prompt: user_prompt, progress_callback: progress_callback)
    result = agent.execute

    stream_event('result', {
      type: result[:type].to_s,
      message: result[:message],
      formatted: result[:formatted]
    })
  end

  def stream_technical_analysis(user_prompt)
    stream_event('start', { message: 'Technical Analysis Agent started' })
    stream_event('mode', { mode: 'technical_analysis' })

    accumulated_response = ''

    begin
      Services::Ai::TechnicalAnalysisAgent.analyze(query: user_prompt, stream: true) do |chunk|
        next unless chunk.present?

        # TechnicalAnalysisAgent streams string chunks directly
        if chunk.is_a?(String)
          # Detect if this is a progress message (starts with emoji indicators)
          if chunk.match?(/^[🔍📊🤔🔧⚙️✅📋💭⚠️❌🏁]/)
            # This is a progress/log message - send to progress sidebar
            stream_event('progress', { message: chunk.strip })
          else
            # This is actual content - accumulate and stream
            accumulated_response += chunk
            stream_event('content', { content: chunk })
          end
        end
      end

      # Final result
      stream_event('result', {
        type: 'success',
        message: accumulated_response,
        formatted: accumulated_response
      })
    rescue StandardError => e
      Rails.logger.error("[TechnicalAnalysisAgent] Error: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      stream_event('error', { message: "Analysis failed: #{e.message}" })
    end
  end

  def stream_event(event_type, payload)
    return if @stream_client_closed

    event = { type: event_type.to_s, data: payload }
    response.stream.write("data: #{event.to_json}\n\n")
    response.stream.flush if response.stream.respond_to?(:flush)
  rescue IOError, ActionController::Live::ClientDisconnected
    @stream_client_closed = true
  end

  def historical
    symbol = params[:symbol]&.upcase
    timeframe = params[:timeframe] || 'intraday' # 'intraday' or 'daily'
    interval = params[:interval] || '15' # minutes for intraday
    from_date = params[:from_date] || 7.days.ago.strftime('%Y-%m-%d')
    to_date = params[:to_date] || Time.zone.today.strftime('%Y-%m-%d')

    # Find the instrument
    inst = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)

    if inst
      params_hash = {
        security_id: inst.security_id,
        exchange_segment: inst.exchange_segment,
        instrument: inst.instrument,
        from_date: from_date,
        to_date: to_date
      }

      # Add interval for intraday
      params_hash[:interval] = interval if timeframe == 'intraday'

      # Add expiry_code for F&O
      params_hash[:expiry_code] = 0 if inst.instrument == 'FUTURES'

      # Get historical data
      data = if timeframe == 'daily'
               DhanHQ::Models::HistoricalData.daily(params_hash)
             else
               DhanHQ::Models::HistoricalData.intraday(params_hash)
             end

      render json: {
        symbol: inst.symbol_name || inst.underlying_symbol,
        security_id: inst.security_id,
        timeframe: timeframe,
        data: data
      }
    else
      render json: { error: "Symbol #{symbol} not found" }
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :bad_gateway
  end
end
