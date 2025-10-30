# frozen_string_literal: true

# Trading::Resolver - Canonical mapping of symbol → security_id (with cache)
module Trading
  class Resolver
    class << self
      # Lookup security_id for a given symbol (returns string). Cached for 6 hours.
      def security_id_for(symbol, exchange: 'NSE')
        return nil if symbol.blank?

        Rails.cache.fetch("trading:resolver:sid:#{exchange}:#{symbol.upcase}", expires_in: 6.hours) do
          rows = Trading::Dhan.client.instruments.search(query: symbol, exchange: exchange)
          row = rows.find { |r| r['symbol'].to_s.upcase == symbol.upcase } || rows.first
          row&.fetch('security_id', row['securityId']) # fallback to other possible key
        end
      end
    end
  end
end
