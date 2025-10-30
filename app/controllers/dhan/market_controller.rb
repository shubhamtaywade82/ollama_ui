# frozen_string_literal: true

# Market data API endpoints for DhanHQ integration
# Provides reliable access to instruments, quotes, OHLC, historical, and option chains
module Dhan
  class MarketController < ApplicationController
    protect_from_forgery with: :null_session

    # Search instruments by query string
    # GET /dhan/search_instruments?q=NIFTY&exchange=NSE
    def search_instruments
      q = params[:q].to_s.strip
      exchange = params[:exchange].presence || 'NSE'

      return render json: { error: 'q parameter required' }, status: :unprocessable_entity if q.blank?

      data = Dhan::MarketData.instruments_search(query: q, exchange: exchange)
      render json: { instruments: data }
    rescue Dhan::MarketData::Error => e
      render json: { error: e.message }, status: :bad_gateway
    end

    # Get live quote/LTP for a security
    # GET /dhan/quote?security_id=1234567890123456&segment=NSE
    # or GET /dhan/quote?symbol=RELIANCE&segment=NSE
    def quote
      security_id = params[:security_id].presence
      symbol = params[:symbol]&.upcase&.strip
      segment = params[:segment].presence || 'NSE'

      # Support both security_id and symbol lookups
      if security_id.blank? && symbol.present?
        security_id = Dhan::InstrumentIndex.security_id_for(symbol, exchange: segment)
        return render json: { error: "Symbol #{symbol} not found" }, status: :not_found unless security_id
      end

      if security_id.blank?
        return render json: { error: 'security_id or symbol required' },
                      status: :unprocessable_entity
      end

      data = Dhan::MarketData.quote(security_id: security_id, segment: segment)
      render json: data
    rescue Dhan::MarketData::Error => e
      render json: { error: e.message }, status: :bad_gateway
    end

    # Get intraday OHLC data
    # GET /dhan/ohlc?security_id=1234567890123456&segment=NSE&timeframe=15&count=120
    # or GET /dhan/ohlc?symbol=RELIANCE&segment=NSE&timeframe=15&count=120
    def ohlc
      security_id = params[:security_id].presence
      symbol = params[:symbol]&.upcase&.strip
      segment = params[:segment].presence || 'NSE'
      timeframe = params[:timeframe].presence || '15' # minutes
      count = (params[:count].presence || 50).to_i

      # Support both security_id and symbol lookups
      if security_id.blank? && symbol.present?
        security_id = Dhan::InstrumentIndex.security_id_for(symbol, exchange: segment)
        return render json: { error: "Symbol #{symbol} not found" }, status: :not_found unless security_id
      end

      if security_id.blank?
        return render json: { error: 'security_id or symbol required' },
                      status: :unprocessable_entity
      end

      data = Dhan::MarketData.ohlc(
        security_id: security_id,
        segment: segment,
        timeframe: timeframe,
        count: count
      )
      render json: data
    rescue Dhan::MarketData::Error => e
      render json: { error: e.message }, status: :bad_gateway
    end

    # Get historical OHLC data (daily candles)
    # GET /dhan/historical?security_id=1234567890123456&segment=NSE&from=2025-09-01&to=2025-10-29
    # or GET /dhan/historical?symbol=RELIANCE&segment=NSE&from=2025-09-01&to=2025-10-29
    def historical
      security_id = params[:security_id].presence
      symbol = params[:symbol]&.upcase&.strip
      segment = params[:segment].presence || 'NSE'
      timeframe = params[:timeframe].presence || '1d'
      from = params[:from].presence || 30.days.ago.to_date.to_s
      to = params[:to].presence || Time.zone.today.to_s

      # Support both security_id and symbol lookups
      if security_id.blank? && symbol.present?
        security_id = Dhan::InstrumentIndex.security_id_for(symbol, exchange: segment)
        return render json: { error: "Symbol #{symbol} not found" }, status: :not_found unless security_id
      end

      if security_id.blank?
        return render json: { error: 'security_id or symbol required' },
                      status: :unprocessable_entity
      end

      data = Dhan::MarketData.historical(
        security_id: security_id,
        segment: segment,
        timeframe: timeframe,
        from: from,
        to: to
      )
      render json: data
    rescue Dhan::MarketData::Error => e
      render json: { error: e.message }, status: :bad_gateway
    end

    # Get option chain for an underlying
    # GET /dhan/option_chain?underlying_security_id=1234567890123456&segment=NSE&expiry=2025-11-06
    # or GET /dhan/option_chain?underlying_symbol=NIFTY 50&segment=NSE&expiry=2025-11-06
    def option_chain
      underlying_security_id = params[:underlying_security_id].presence
      underlying_symbol = params[:underlying_symbol]&.upcase&.strip
      segment = params[:segment].presence || 'NSE'
      expiry = params[:expiry].to_s

      return render json: { error: 'expiry required (YYYY-MM-DD)' }, status: :unprocessable_entity if expiry.blank?

      # Support both security_id and symbol lookups
      if underlying_security_id.blank? && underlying_symbol.present?
        underlying_security_id = Dhan::InstrumentIndex.security_id_for(underlying_symbol, exchange: segment)
        unless underlying_security_id
          return render json: { error: "Underlying symbol #{underlying_symbol} not found" }, status: :not_found
        end
      end

      if underlying_security_id.blank?
        return render json: { error: 'underlying_security_id or underlying_symbol required' },
                      status: :unprocessable_entity
      end

      data = Dhan::MarketData.option_chain(
        underlying_security_id: underlying_security_id,
        segment: segment,
        expiry: expiry
      )
      render json: data
    rescue Dhan::MarketData::Error => e
      render json: { error: e.message }, status: :bad_gateway
    rescue Date::Error => e
      render json: { error: "Invalid expiry format. Use YYYY-MM-DD: #{e.message}" }, status: :unprocessable_entity
    end
  end
end
