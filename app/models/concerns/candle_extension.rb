# frozen_string_literal: true

module CandleExtension
  extend ActiveSupport::Concern

  included do
    def candles(interval: '5')
      @ohlc_cache ||= {}

      cached_series = @ohlc_cache[interval]
      return cached_series if cached_series && !ohlc_stale?(interval)

      fetch_fresh_candles(interval)
    end

    def fetch_fresh_candles(interval)
      # For DhanHQ, fetch OHLC data using Trading::Dhan service
      # Include today's data to get the most recent completed candles
      include_today = !Rails.env.test? &&
                      ENV['BACKTEST_MODE'] != '1' &&
                      ENV['SCRIPT_MODE'] != '1'

      if include_today
        to_date = Time.zone.today.to_s
        from_date = (Date.parse(to_date) - 2).to_s # Last 2 days including today
        Rails.logger.debug { "[CandleExtension] Fetching OHLC for #{symbol_name || security_id} @ #{interval}m: from_date=#{from_date}, to_date=#{to_date}" }

        # Use Trading::Dhan to fetch OHLC data
        begin
          raw_data = Trading::Dhan.ohlc(
            security_id: security_id,
            segment: exchange_segment || 'NSE',
            interval: interval,
            count: 200
          )
        rescue StandardError => e
          Rails.logger.error("[CandleExtension] Failed to fetch OHLC: #{e.message}")
          return nil
        end
      else
        # For backtest/script mode, use default
        begin
          raw_data = Trading::Dhan.ohlc(
            security_id: security_id,
            segment: exchange_segment || 'NSE',
            interval: interval,
            count: 200
          )
        rescue StandardError => e
          Rails.logger.error("[CandleExtension] Failed to fetch OHLC: #{e.message}")
          return nil
        end
      end

      return nil if raw_data.blank?

      # Normalize raw_data to array format if needed
      candles_array = if raw_data.is_a?(Array)
                        raw_data
                      elsif raw_data.is_a?(Hash) && raw_data['data']
                        raw_data['data']
                      elsif raw_data.is_a?(Hash) && raw_data[:data]
                        raw_data[:data]
                      else
                        [raw_data]
                      end

      symbol_name_for_series = symbol_name || underlying_symbol || security_id.to_s

      @ohlc_cache[interval] = CandleSeries.new(symbol: symbol_name_for_series, interval: interval).tap do |series|
        series.load_from_raw(candles_array)
      end
    end

    def ohlc_stale?(interval)
      @last_ohlc_fetched ||= {}

      # Default cache duration: 5 minutes
      cache_duration_minutes = ENV.fetch('OHLC_CACHE_DURATION_MINUTES', '5').to_i

      return true unless @last_ohlc_fetched[interval]

      Time.current - @last_ohlc_fetched[interval] > cache_duration_minutes.minutes
    ensure
      @last_ohlc_fetched[interval] = Time.current
    end

    def candle_series(interval: '5')
      candles(interval: interval)
    end

    def rsi(period = 14, interval: '5')
      cs = candles(interval: interval)
      cs&.rsi(period)
    end

    def macd(fast_period = 12, slow_period = 26, signal_period = 9, interval: '5')
      cs = candles(interval: interval)
      macd_result = cs&.macd(fast_period, slow_period, signal_period)
      return nil unless macd_result

      {
        macd: macd_result[0],
        signal: macd_result[1],
        histogram: macd_result[2]
      }
    end

    def adx(period = 14, interval: '5')
      cs = candles(interval: interval)
      cs&.adx(period)
    end

    def supertrend_signal(period: 7, multiplier: 3.0, interval: '5')
      cs = candles(interval: interval)
      cs&.supertrend_signal(period: period, multiplier: multiplier)
    end

    def liquidity_grab_up?(interval: '5')
      cs = candles(interval: interval)
      cs&.liquidity_grab_up?
    end

    def liquidity_grab_down?(interval: '5')
      cs = candles(interval: interval)
      cs&.liquidity_grab_down?
    end

    def bollinger_bands(period: 20, interval: '5')
      cs = candles(interval: interval)
      return nil unless cs

      cs.bollinger_bands(period: period)
    end

    def donchian_channel(period: 20, interval: '5')
      cs = candles(interval: interval)
      return nil unless cs
      return nil unless defined?(TechnicalAnalysis)

      dc = cs.candles.each_with_index.map do |c, _i|
        {
          date_time: Time.zone.at(c.timestamp || 0),
          value: c.close
        }
      end
      TechnicalAnalysis::Dc.calculate(dc, period: period)
    rescue StandardError => e
      Rails.logger.warn("[CandleExtension] Donchian Channel calculation failed: #{e.message}")
      nil
    end

    def obv(interval: '5')
      series = candles(interval: interval)
      return nil unless series
      return nil unless defined?(TechnicalAnalysis)

      dcv = series.candles.each_with_index.map do |c, _i|
        {
          date_time: Time.zone.at(c.timestamp || 0),
          close: c.close,
          volume: c.volume || 0
        }
      end

      TechnicalAnalysis::Obv.calculate(dcv)
    rescue ArgumentError => e
      # OBV.calculate might have different signature - try alternative approach
      Rails.logger.warn("[CandleExtension] OBV calculation failed: #{e.message}")
      nil
    rescue TypeError, StandardError => e
      raise if e.is_a?(NoMethodError)

      Rails.logger.warn("[CandleExtension] OBV calculation failed: #{e.message}")
      nil
    end
  end
end

