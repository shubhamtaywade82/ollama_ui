# frozen_string_literal: true

# Trading::DataBus - Provides fast, cached access to all market data (quote/ohlc/option_chain)
# Uses short TTL caches (10-30s) for resilience & lower latency
module Trading
  class DataBus
    class << self
      # Quote cache (3s default)
      def quote(security_id, segment)
        cache("q:#{security_id}:#{segment}", 3) { Trading::Dhan.quote(security_id: security_id, segment: segment) }
      end

      # OHLC cache (10s default)
      def ohlc(security_id, segment, tf, n)
        cache("ohlc:#{security_id}:#{segment}:#{tf}:#{n}", 10) { Trading::Dhan.ohlc(security_id: security_id, segment: segment, interval: tf, count: n) }
      end

      # Options chain cache (20s default)
      def option_chain(security_id, segment, expiry)
        cache("chain:#{security_id}:#{segment}:#{expiry}", 20) { Trading::Dhan.option_chain(underlying_security_id: security_id, segment: segment, expiry: expiry) }
      end

      def cache(key, ttl, &)
        Rails.cache.fetch("trading:databus:#{key}", expires_in: ttl.seconds, &)
      end
    end
  end
end
