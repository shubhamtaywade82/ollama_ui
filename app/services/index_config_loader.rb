# frozen_string_literal: true

# Unified service for loading index configurations
# Simplified for DhanHQ - uses DhanHQ::Models::Instrument to find indices
class IndexConfigLoader
  include Singleton

  CACHE_TTL = 30.seconds

  # Load all index configurations
  # @return [Array<Hash>] Array of index configurations with :key, :segment, :security_id
  def self.load_indices
    instance.load_indices
  end

  def initialize
    @cached_indices = nil
    @cached_at = nil
  end

  def load_indices
    return @cached_indices if cached?

    # Common Indian indices
    indices = [
      {
        key: 'NIFTY',
        segment: 'NSE_EQ',
        security_id: '2885', # NIFTY 50
        exchange: 'NSE'
      },
      {
        key: 'BANKNIFTY',
        segment: 'NSE_EQ',
        security_id: '26009', # BANK NIFTY
        exchange: 'NSE'
      },
      {
        key: 'SENSEX',
        segment: 'BSE_EQ',
        security_id: '1', # SENSEX
        exchange: 'BSE'
      }
    ]

    # Try to find actual security_ids from DhanHQ if available
    indices.map! do |idx|
      begin
        instrument = DhanHQ::Models::Instrument.find_anywhere(idx[:key], exact_match: true)
        if instrument
          idx[:security_id] = instrument.security_id.to_s
          idx[:segment] = instrument.exchange_segment
          idx[:exchange] = instrument.exchange
        end
      rescue StandardError => e
        Rails.logger.debug("[IndexConfigLoader] Could not find instrument for #{idx[:key]}: #{e.message}")
      end
      idx
    end

    @cached_indices = indices
    @cached_at = Time.current
    indices
  rescue StandardError => e
    Rails.logger.error("[IndexConfigLoader] Error loading indices: #{e.class} - #{e.message}")
    # Return default indices on error
    @cached_indices = [
      { key: 'NIFTY', segment: 'NSE_EQ', security_id: '2885', exchange: 'NSE' },
      { key: 'BANKNIFTY', segment: 'NSE_EQ', security_id: '26009', exchange: 'NSE' },
      { key: 'SENSEX', segment: 'BSE_EQ', security_id: '1', exchange: 'BSE' }
    ]
    @cached_at = Time.current
    @cached_indices
  end

  def cached?
    @cached_at && @cached_indices && (Time.current - @cached_at) < CACHE_TTL
  end

  def clear_cache!
    @cached_indices = nil
    @cached_at = nil
  end
end

