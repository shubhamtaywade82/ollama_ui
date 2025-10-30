# frozen_string_literal: true

module Trading
  class Dhan
    class Error < StandardError; end

    SEGMENT_KEYS = {
      "NSE" => "NSE_EQ",
      "NSE_EQ" => "NSE_EQ",
      "NSE_FNO" => "NSE_FNO",
      "BSE" => "BSE_EQ",
      "MCX" => "MCX",
      "NSE_CURRENCY" => "NSE_CURRENCY",
      "BSE_CURRENCY" => "BSE_CURRENCY"
    }.freeze

    TIME_ZONE = "Asia/Kolkata"

    class << self
      # -------- Market Data --------

      def quote(security_id:, segment: "NSE")
        configure_client!

        response = market_feed.quote(segment_payload(segment, security_id))
        extract_market_node(response, segment, security_id) ||
          raise(Error, "quote: missing data for #{segment} #{security_id}")
      rescue StandardError => e
        raise Error, "quote: #{e.message}"
      end

      def ohlc(security_id:, segment: "NSE", interval: "5m", count: 120)
        configure_client!

        instrument = locate_instrument(security_id, segment)
        raise Error, "ohlc: instrument not found for #{security_id}" unless instrument

        window = candle_window(interval, count)
        params = {
          security_id: security_id.to_s,
          exchange_segment: segment_key(segment),
          instrument: instrument.instrument,
          interval: window[:interval_code],
          from_date: window[:from].strftime("%Y-%m-%d"),
          to_date: window[:to].strftime("%Y-%m-%d")
        }

        historical_data.intraday(params)
      rescue StandardError => e
        raise Error, "ohlc: #{e.message}"
      end

      def historical(security_id:, segment: "NSE", interval: "1d", from:, to:)
        configure_client!

        instrument = locate_instrument(security_id, segment)
        raise Error, "historical: instrument not found for #{security_id}" unless instrument

        params = {
          security_id: security_id.to_s,
          exchange_segment: segment_key(segment),
          instrument: instrument.instrument,
          from_date: from,
          to_date: to
        }
        params[:interval] = interval_code(interval) if interval

        historical_data.daily(params)
      rescue StandardError => e
        raise Error, "historical: #{e.message}"
      end

      def option_chain(underlying_security_id:, segment: "NSE", expiry:)
        configure_client!

        payload = {
          exchange_segment: segment_key(segment),
          underlying_security_id: underlying_security_id.to_s,
          expiry: expiry
        }

        option_chain_resource.fetch(payload)
      rescue StandardError => e
        raise Error, "option_chain: #{e.message}"
      end

      def positions
        configure_client!

        positions_resource.all
      rescue StandardError => e
        raise Error, "positions: #{e.message}"
      end

      # -------- Orders (incl. Bracket) --------

      def place_order(**params)
        return Trading::PaperAdapter.place_order(**params.merge(mode: :simple)) unless live?

        configure_client!
        orders_resource.create(params)
      rescue StandardError => e
        raise Error, "place_order: #{e.message}"
      end

      def place_bracket(**params)
        return Trading::PaperAdapter.place_order(**params.merge(mode: :bracket)) unless live?

        configure_client!
        super_orders_resource.create(params)
      rescue StandardError => e
        raise Error, "place_bracket: #{e.message}"
      end

      def modify_order(order_id:, leg_name: nil, **params)
        return Trading::PaperAdapter.modify_order(order_id: order_id, leg_name: leg_name, **params) unless live?

        configure_client!

        if leg_name || params.key?(:trigger_price)
          payload = params.dup
          payload[:leg_name] = leg_name if leg_name
          super_orders_resource.update(order_id, payload.compact)
        else
          orders_resource.update(order_id, params)
        end
      rescue StandardError => e
        raise Error, "modify_order: #{e.message}"
      end

      def exit_order(order_id:)
        return Trading::PaperAdapter.exit_order(order_id: order_id) unless live?

        configure_client!
        orders_resource.cancel(order_id)
      rescue StandardError => e
        raise Error, "exit_order: #{e.message}"
      end

      def live?
        ActiveModel::Type::Boolean.new.cast(ENV.fetch("LIVE_TRADING", "false"))
      end

      private

      def configure_client!
        return if defined?(@configured) && @configured

        client_id = env_fetch!("DHAN_CLIENT_ID")
        access_token = env_fetch!("DHAN_ACCESS_TOKEN")

        DhanHQ.configure do |config|
          config.client_id = client_id
          config.access_token = access_token
          base_override = ENV.fetch("DHAN_BASE_URL", nil)
          config.base_url = base_override if base_override.present?
        end

        @configured = true
      end

      def env_fetch!(key)
        ENV.fetch(key) { raise Error, "configuration missing #{key}" }
      end

      def segment_key(segment)
        SEGMENT_KEYS.fetch(segment.to_s.upcase, segment.to_s)
      end

      def segment_payload(segment, security_id)
        { segment_key(segment) => [security_id.to_i] }
      end

      def extract_market_node(response, segment, security_id)
        key = segment_key(segment)
        response.dig(:data, key, security_id.to_s) ||
          response.dig(:data, key, security_id.to_i)
      end

      def candle_window(interval, count)
        minutes = normalized_interval(interval)
        to_time = Time.current.in_time_zone(TIME_ZONE)
        {
          interval_code: minutes.to_s,
          from: (to_time - (minutes * count.to_i).minutes),
          to: to_time
        }
      end

      def interval_code(interval)
        return interval.to_s if interval =~ /\A\d+\z/

        interval.to_s.delete_suffix("m")
      end

      def normalized_interval(interval)
        code = interval_code(interval)
        Integer(code)
      rescue ArgumentError
        raise Error, "unsupported interval #{interval}"
      end

      def locate_instrument(security_id, segment)
        candidates = [segment_key(segment), segment.to_s].uniq

        candidates.each do |seg|
          records = Array(DhanHQ::Models::Instrument.by_segment(seg))
          match = records.find { |instrument| instrument.security_id.to_i == security_id.to_i }
          return match if match
        end

        nil
      rescue StandardError
        nil
      end

      def market_feed
        @market_feed ||= DhanHQ::Resources::MarketFeed.new
      end

      def historical_data
        @historical_data ||= DhanHQ::Resources::HistoricalData.new
      end

      def option_chain_resource
        @option_chain_resource ||= DhanHQ::Resources::OptionChain.new
      end

      def positions_resource
        @positions_resource ||= DhanHQ::Resources::Positions.new
      end

      def orders_resource
        @orders_resource ||= DhanHQ::Resources::Orders.new
      end

      def super_orders_resource
        @super_orders_resource ||= DhanHQ::Resources::SuperOrders.new
      end
    end
  end
end
