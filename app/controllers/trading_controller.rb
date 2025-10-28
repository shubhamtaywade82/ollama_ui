# frozen_string_literal: true

class TradingController < ApplicationController
  protect_from_forgery with: :null_session

  def index
    # Trading chat interface
  end

  def account_info
    info = DhanhqClient.new.account_info
    render json: info
  rescue StandardError => e
    render json: { error: e.message }, status: :bad_gateway
  end

  def positions
    positions = DhanhqClient.new.positions
    render json: { positions: positions }
  rescue StandardError => e
    render json: { error: e.message }, status: :bad_gateway
  end

  def holdings
    holdings = DhanhqClient.new.holdings
    render json: { holdings: holdings }
  rescue StandardError => e
    render json: { error: e.message }, status: :bad_gateway
  end

  def quote
    symbol = params[:symbol]&.upcase
    quote = DhanhqClient.new.get_quote(symbol)
    render json: quote
  rescue StandardError => e
    render json: { error: e.message }, status: :bad_gateway
  end
end

