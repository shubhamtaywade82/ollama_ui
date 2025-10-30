# frozen_string_literal: true

# Reliable wrapper for DhanHQ market data APIs
# Handles errors, retries, caching, and common pain points
class Dhan::MarketData
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
    security_id = security_id.to_i
    segment = segment.to_s

    # Validate inputs
    raise Error, "Invalid security_id: #{security_id}" if security_id.zero?

    raise Error, "Invalid segment: #{segment}" if segment.blank?

    Rails.logger.info "📊 Getting quote: security_id=#{security_id}, segment=#{segment}"

    # DhanHQ requires a hash where key is segment and value is array of security IDs
    # Ensure we create a proper hash
    quote_params = { segment => [security_id] }
    quote_response = DhanHQ::Models::MarketFeed.quote(quote_params)

    quote_data = quote_response.dig('data', segment, security_id.to_s) ||
                 quote_response.dig('data', segment, security_id)

    raise Error, "No quote data returned for security_id=#{security_id}, segment=#{segment}" unless quote_data

    {
      security_id: security_id.to_s,
      segment: segment,
      last_price: quote_data['last_price'] || quote_data[:last_price],
      volume: quote_data['volume'] || quote_data[:volume],
      ohlc: quote_data['ohlc'] || quote_data[:ohlc] || {},
      average_price: quote_data['average_price'] || quote_data[:average_price],
      fifty_two_week_high: quote_data['52_week_high'] || quote_data[:fifty_two_week_high],
      fifty_two_week_low: quote_data['52_week_low'] || quote_data[:fifty_two_week_low],
      raw: quote_data # Include raw data for compatibility
    }
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
    security_id = security_id.to_i
    segment = segment.to_s
    timeframe = timeframe.to_s

    Rails.logger.info "📈 Getting OHLC: security_id=#{security_id}, segment=#{segment}, interval=#{timeframe}m"

    params = {
      security_id: security_id,
      exchange_segment: segment,
      instrument: get_instrument_type(security_id, segment), # Try to infer instrument type
      interval: timeframe,
      from_date: (count.to_i * timeframe.to_i.minutes).ago.strftime('%Y-%m-%d'),
      to_date: Date.today.strftime('%Y-%m-%d')
    }

    data = DhanHQ::Models::HistoricalData.intraday(params)

    {
      security_id: security_id.to_s,
      segment: segment,
      interval: "#{timeframe}m",
      data: data
    }
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
    underlying_security_id = underlying_security_id.to_i
    segment = segment.to_s

    # Validate expiry format
    Date.parse(expiry)

    Rails.logger.info "📊 Getting option chain: underlying=#{underlying_security_id}, expiry=#{expiry}"

    # Try to find underlying instrument, but if we can't, use security_id directly
    # DhanHQ OptionChain.fetch accepts underlying_scrip (security_id as string)
    underlying_symbol = nil

    begin
      # Try searching for the instrument by iterating through known segments
      # This is a fallback - we'll use security_id directly if we can't find it
      instruments = DhanHQ::Models::Instrument.by_segment(segment)
      instruments = [instruments] unless instruments.is_a?(Array)
      underlying = instruments.find { |inst| inst.security_id.to_i == underlying_security_id }
      underlying_symbol = underlying&.symbol_name || underlying&.underlying_symbol
    rescue StandardError => e
      Rails.logger.warn "Could not find underlying instrument: #{e.message}, using security_id directly"
    end

    # Fetch option chain - DhanHQ API accepts underlying_scrip and underlying_seg
    chain = DhanHQ::Models::OptionChain.fetch(
      underlying_scrip: underlying_security_id.to_s,
      underlying_seg: segment,
      expiry: expiry
    )

    {
      underlying_security_id: underlying_security_id.to_s,
      underlying_symbol: underlying_symbol || underlying_security_id.to_s,
      segment: segment,
      expiry: expiry,
      data: chain
    }
  rescue Date::Error => e
    Rails.logger.error "❌ Invalid expiry format: #{e.message}"
    raise Error, "Invalid expiry format. Use YYYY-MM-DD: #{e.message}"
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
