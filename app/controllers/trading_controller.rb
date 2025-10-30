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

    if inst && inst.exchange_segment && inst.security_id
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

  def historical
    symbol = params[:symbol]&.upcase
    timeframe = params[:timeframe] || 'intraday' # 'intraday' or 'daily'
    interval = params[:interval] || '15' # minutes for intraday
    from_date = params[:from_date] || 7.days.ago.strftime('%Y-%m-%d')
    to_date = params[:to_date] || Date.today.strftime('%Y-%m-%d')

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
