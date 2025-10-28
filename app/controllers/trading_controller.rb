# frozen_string_literal: true

require 'dhan_hq'

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
    segments = [{ segment: 'NSE_EQ' }, { segment: 'BSE_EQ' }, { segment: 'NSE_FNO' }, { segment: 'BSE_FNO' }]

    segments.each do |config|
      inst = DhanHQ::Models::Instrument.find(config[:segment], symbol)
      if inst
        render json: {
          symbol: inst.symbol,
          name: inst.trading_symbol || inst.symbol,
          ltp: inst.last_price&.to_f || 0,
          security_id: inst.security_id,
          exchange_segment: config[:segment]
        }
        return
      end
    end

    render json: { error: "Symbol #{symbol} not found" }
  rescue StandardError => e
    render json: { error: e.message }, status: :bad_gateway
  end
end

