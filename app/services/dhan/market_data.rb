# frozen_string_literal: true

# Reliable wrapper for DhanHQ market data APIs
# Handles errors, retries, caching, and common pain points
module Dhan
  class MarketData
    class Error < StandardError; end

    # Search for instruments by symbol/name
    # @param query [String] Symbol or name to search for
    # @param exchange [String] Exchange segment (default: "NSE")
    # @return [Array<Hash>] Array of matching instruments
    def self.instruments_search(query:, exchange: 'NSE')
      return [] if query.blank?

      Rails.logger.info "🔍 Searching instruments: #{query} on #{exchange}"

      # Use DhanHQ's Instrument.find_anywhere for flexible search
      results = DhanHQ::Models::Instrument.find_anywhere(query, exact_match: false)
      results = [results] unless results.is_a?(Array)

      # Filter by exchange if specified (some results might have exchange info)
      instruments = results.map do |inst|
        {
          symbol: inst.symbol_name || inst.underlying_symbol,
          security_id: inst.security_id.to_s,
          exchange_segment: inst.exchange_segment,
          instrument_type: inst.instrument,
          display_name: inst.display_name || inst.symbol_name
        }
      end

      Rails.logger.info "✅ Found #{instruments.size} instruments"
      instruments
    rescue StandardError => e
      Rails.logger.error "❌ instruments_search failed: #{e.message}"
      raise Error, "instruments_search failed: #{e.message}"
    end

    # Get full instrument master list for an exchange segment
    # Cached for 24 hours to reduce API calls
    # @param exchange [String] Exchange segment (default: "NSE")
    # @return [Array] Master list of instruments
    def self.instrument_master(exchange: 'NSE')
      Rails.cache.fetch("dhan:master:#{exchange}", expires_in: 24.hours) do
        Rails.logger.info "📋 Fetching instrument master for #{exchange}"

        # Get all instruments for the segment
        instruments = DhanHQ::Models::Instrument.by_segment(exchange)
        instruments = [instruments] unless instruments.is_a?(Array)

        instruments.map do |inst|
          {
            symbol: inst.symbol_name || inst.underlying_symbol,
            security_id: inst.security_id.to_s,
            exchange_segment: inst.exchange_segment,
            instrument_type: inst.instrument,
            display_name: inst.display_name || inst.symbol_name
          }
        end
      end
    rescue StandardError => e
      Rails.logger.error "❌ instrument_master failed: #{e.message}"
      raise Error, "instrument_master failed: #{e.message}"
    end

    # Get live quote/LTP for a security
    # @param security_id [String, Integer] Security ID
    # @param segment [String] Exchange segment (default: "NSE")
    # @return [Hash] Quote data with last_price, volume, OHLC, etc.
    def self.quote(security_id:, segment: 'NSE')
      instrument = DhanHQ::Models::Instrument.find_anywhere(security_id.to_s, exact_match: true)
      raise Error, "Invalid security_id: #{security_id}" unless instrument

      instrument.quote
    rescue StandardError => e
      Rails.logger.error "❌ quote failed: #{e.message}"
      raise Error, "quote failed: #{e.message}"
    end

    # Get intraday OHLC data
    # @param security_id [String, Integer] Security ID
    # @param segment [String] Exchange segment (default: "NSE")
    # @param timeframe [String] Interval like "15" for 15 minutes (default: "15")
    # @param count [Integer] Number of candles (default: 50)
    # @return [Hash] OHLC data with open, high, low, close arrays
    def self.ohlc(security_id:, segment: 'NSE', timeframe: '15', count: 50)
      instrument = DhanHQ::Models::Instrument.find_anywhere(security_id.to_s, exact_match: true)
      raise Error, "Invalid security_id: #{security_id}" unless instrument

      # Instance method covers ohlc. If gem lacks ohlc, fallback to legacy params-based:
      instrument.ohlc
    rescue StandardError => e
      Rails.logger.error "❌ ohlc failed: #{e.message}"
      raise Error, "ohlc failed: #{e.message}"
    end

    # Get historical OHLC data (daily candles)
    # @param security_id [String, Integer] Security ID
    # @param segment [String] Exchange segment (default: "NSE")
    # @param from [String] Start date in YYYY-MM-DD format
    # @param to [String] End date in YYYY-MM-DD format
    # @param timeframe [String] "1d" for daily (default: "1d")
    # @return [Hash] Historical OHLC data
    def self.historical(security_id:, from:, to:, segment: 'NSE', timeframe: '1d')
      security_id = security_id.to_i
      segment = segment.to_s

      # Validate date format
      Date.parse(from)
      Date.parse(to)

      Rails.logger.info "📊 Getting historical: security_id=#{security_id}, #{from} to #{to}"

      params = {
        security_id: security_id,
        exchange_segment: segment,
        instrument: get_instrument_type(security_id, segment),
        from_date: from,
        to_date: to
      }

      # Add expiry_code for F&O if needed (detect from instrument type)
      instrument_type = get_instrument_type(security_id, segment)
      params[:expiry_code] = 0 if instrument_type == 'FUTURES'

      data = DhanHQ::Models::HistoricalData.daily(params)

      {
        security_id: security_id.to_s,
        segment: segment,
        timeframe: timeframe,
        from: from,
        to: to,
        data: data
      }
    rescue Date::Error => e
      Rails.logger.error "❌ Invalid date format: #{e.message}"
      raise Error, "Invalid date format. Use YYYY-MM-DD: #{e.message}"
    rescue StandardError => e
      Rails.logger.error "❌ historical failed: #{e.message}"
      raise Error, "historical failed: #{e.message}"
    end

    # Get option chain for an underlying
    # @param underlying_security_id [String, Integer] Security ID of the underlying
    # @param segment [String] Exchange segment (default: "NSE")
    # @param expiry [String] Expiry date in YYYY-MM-DD format
    # @return [Hash] Option chain data with calls and puts
    def self.option_chain(underlying_security_id:, expiry:, segment: 'NSE')
      instrument = DhanHQ::Models::Instrument.find_anywhere(underlying_security_id.to_s, exact_match: true)
      raise Error, "Invalid underlying_security_id: #{underlying_security_id}" unless instrument

      instrument.option_chain(expiry: expiry)
    rescue StandardError => e
      Rails.logger.error "❌ option_chain failed: #{e.message}"
      raise Error, "option_chain failed: #{e.message}"
    end

    # Helper to infer instrument type from security_id
    # Falls back to 'EQUITY' if unable to determine
    def self.get_instrument_type(security_id, segment)
      # Try to find the instrument by searching in the segment
      begin
        instruments = DhanHQ::Models::Instrument.by_segment(segment)
        instruments = [instruments] unless instruments.is_a?(Array)
        inst = instruments.find { |i| i.security_id.to_i == security_id.to_i }
        return inst.instrument if inst&.instrument
      rescue StandardError
        # Ignore errors, fall back to EQUITY
      end
      'EQUITY' # Default fallback
    end
  end
end
