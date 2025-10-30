# frozen_string_literal: true

# Cached symbol-to-security_id mapper
# Reduces API calls by caching lookups for 6 hours
module Dhan
  class InstrumentIndex
    class Error < StandardError; end

    # Get security_id for a symbol
    # @param symbol [String] Symbol name (e.g., "RELIANCE", "NIFTY 50")
    # @param exchange [String] Exchange segment (default: "NSE")
    # @return [String, nil] Security ID as string, or nil if not found
    def self.security_id_for(symbol, exchange: 'NSE')
      return nil if symbol.blank?

      symbol = symbol.upcase.strip
      cache_key = "dhan:sid:#{exchange}:#{symbol}"

      Rails.cache.fetch(cache_key, expires_in: 6.hours) do
        Rails.logger.info "🔍 Looking up security_id for: #{symbol} on #{exchange}"

        # Use DhanHQ's find_anywhere for flexible matching
        instrument = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)

        if instrument
          security_id = instrument.security_id.to_s
          Rails.logger.info "✅ Found security_id: #{security_id} for #{symbol}"
          security_id
        else
          Rails.logger.warn "⚠️ No instrument found for #{symbol}"
          nil
        end
      end
    rescue StandardError => e
      Rails.logger.error "❌ security_id_for failed for #{symbol}: #{e.message}"
      nil
    end

    # Get full instrument details (not just security_id)
    # @param symbol [String] Symbol name
    # @param exchange [String] Exchange segment (default: "NSE")
    # @return [Hash, nil] Instrument details or nil if not found
    def self.find_instrument(symbol, exchange: 'NSE')
      return nil if symbol.blank?

      symbol = symbol.upcase.strip
      cache_key = "dhan:instrument:#{exchange}:#{symbol}"

      Rails.cache.fetch(cache_key, expires_in: 6.hours) do
        Rails.logger.info "🔍 Looking up instrument: #{symbol} on #{exchange}"

        instrument = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)

        if instrument
          {
            symbol: instrument.symbol_name || instrument.underlying_symbol,
            security_id: instrument.security_id.to_s,
            exchange_segment: instrument.exchange_segment,
            instrument_type: instrument.instrument,
            display_name: instrument.display_name || instrument.symbol_name
          }
        end
      end
    rescue StandardError => e
      Rails.logger.error "❌ find_instrument failed for #{symbol}: #{e.message}"
      nil
    end

    # Batch lookup security IDs for multiple symbols
    # More efficient than individual calls
    # @param symbols [Array<String>] Array of symbol names
    # @param exchange [String] Exchange segment (default: "NSE")
    # @return [Hash] Map of symbol => security_id
    def self.batch_security_ids(symbols, exchange: 'NSE')
      return {} if symbols.blank?

      symbols.to_h { |s| [s.upcase.strip, security_id_for(s, exchange: exchange)] }
    end
  end
end
