# frozen_string_literal: true

class TradingController < ApplicationController
  protect_from_forgery with: :null_session

  def index
    # Trading chat interface
  end

  def account_info
    fund = DhanHQ::Models::Funds.fetch

    pp fund
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

    # Use DhanHQ's find_anywhere method to search across all segments
    inst = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)

    if inst
      render json: {
        symbol: inst.symbol_name || inst.underlying_symbol,
        name: inst.display_name || inst.symbol_name,
        security_id: inst.security_id,
        exchange_segment: inst.exchange_segment,
        instrument_type: inst.instrument,
        lot_size: inst.lot_size,
        tick_size: inst.tick_size
      }
    else
      render json: { error: "Symbol #{symbol} not found in any exchange segment" }
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :bad_gateway
  end
end

