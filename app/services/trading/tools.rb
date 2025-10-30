# frozen_string_literal: true

module Trading
  module Tools
    extend self

    # --- Market Data -------------------------------------------------------

    def market_quote(security_id:, segment: "NSE")
      data = Trading::Dhan.quote(security_id: security_id, segment: segment)
      observation("market.quote", ok: true, result: data, hint: "Quote retrieved for #{security_id}")
    rescue Trading::Dhan::Error => e
      observation("market.quote", ok: false, result: e.message, hint: "Quote fetch failed")
    end

    def market_ohlc(security_id:, segment: "NSE", interval: "5m", count: 120)
      raw = Trading::Dhan.ohlc(security_id: security_id, segment: segment, interval: interval, count: count)
      summary = summarize_candles(raw, interval, count)
      observation("market.ohlc", ok: true, result: summary, hint: "Fetched #{summary[:candle_count]} candles")
    rescue Trading::Dhan::Error => e
      observation("market.ohlc", ok: false, result: e.message, hint: "OHLC fetch failed")
    end

    def market_option_chain(underlying_security_id:, segment: "NSE", expiry:)
      result = option_chain_cache.fetch([underlying_security_id.to_s, expiry], expires_in: option_chain_ttl.seconds) do
        Trading::Dhan.option_chain(
          underlying_security_id: underlying_security_id,
          segment: segment,
          expiry: expiry
        )
      end

      observation("market.option_chain", ok: true, result: result, hint: "Option chain #{expiry} cached #{option_chain_ttl}s")
    rescue Trading::Dhan::Error => e
      observation("market.option_chain", ok: false, result: e.message, hint: "Option chain fetch failed")
    end

    def positions_list
      positions = Array(Trading::Dhan.positions)
      result = positions.map do |position|
        {
          symbol: position.try(:trading_symbol) || position.try(:symbol),
          security_id: position.try(:security_id),
          net_qty: position.try(:net_qty).to_i,
          pnl: (position.try(:unrealized_profit) || position.try(:mtm))&.to_f,
          avg_price: (position.try(:buy_avg) || position.try(:cost_price))&.to_f
        }.compact
      end

      observation("positions.list", ok: true, result: { positions: result, count: result.length }, hint: "Positions snapshot ready")
    rescue Trading::Dhan::Error => e
      observation("positions.list", ok: false, result: e.message, hint: "Positions fetch failed")
    end

    # --- Risk --------------------------------------------------------------

    def risk_analyze(prompt_context:)
      observation("risk.analyze", ok: true, result: prompt_context, hint: "Context forwarded to planner")
    end

    # --- Orders ------------------------------------------------------------

    def orders_place(**params)
      response = Trading::Dhan.place_order(**params)
      payload = order_payload(response)
      observation("orders.place", ok: true, result: payload, hint: "Order placed (#{payload[:status] || 'accepted'})")
    rescue Trading::Dhan::Error => e
      observation("orders.place", ok: false, result: e.message, hint: "Order placement failed")
    end

    def orders_place_bracket(**params)
      response = Trading::Dhan.place_bracket(**params)
      payload = order_payload(response)
      observation("orders.place_bracket", ok: true, result: payload, hint: "Bracket order processed")
    rescue Trading::Dhan::Error => e
      observation("orders.place_bracket", ok: false, result: e.message, hint: "Bracket order failed")
    end

    def orders_modify_sl(order_id:, leg_name: nil, **params)
      response = Trading::Dhan.modify_order(order_id: order_id, leg_name: leg_name, **params)
      payload = order_payload(response, fallback_id: order_id)
      observation("orders.modify_sl", ok: true, result: payload, hint: "Stop loss adjusted")
    rescue Trading::Dhan::Error => e
      observation("orders.modify_sl", ok: false, result: e.message, hint: "Stop loss update failed")
    end

    def orders_exit(order_id:)
      response = Trading::Dhan.exit_order(order_id: order_id)
      payload = order_payload(response, fallback_id: order_id)
      observation("orders.exit", ok: true, result: payload, hint: "Order exit requested")
    rescue Trading::Dhan::Error => e
      observation("orders.exit", ok: false, result: e.message, hint: "Order exit failed")
    end

    private

    def observation(tool, ok:, result:, hint:)
      {
        tool: tool,
        ok: ok,
        result: result,
        hint: hint
      }
    end

    def summarize_candles(raw, interval, count)
      return { raw: raw } unless raw.respond_to?(:[])

      closes = Array(raw[:close] || raw["close"]).compact
      return { candle_count: count, interval: interval, raw: raw } if closes.empty?

      base = {
        candle_count: closes.length,
        last_price: closes.last.to_f,
        high: closes.max.to_f,
        low: closes.min.to_f,
        interval: interval
      }

      if raw.respond_to?(:slice)
        base.merge!(raw.slice(:time, :timestamp, "time", "timestamp"))
      end

      base
    end

    def option_chain_cache
      @option_chain_cache ||= Rails.cache
    end

    def option_chain_ttl
      Integer(Trading::Config.fetch(:cooldowns, :option_chain_cache, default: 30))
    rescue ArgumentError, TypeError
      30
    end

    def order_payload(response, fallback_id: nil)
      if response.respond_to?(:order_id)
        { order_id: response.order_id, status: response.try(:order_status) || "accepted" }
      else
        hash = response.is_a?(Hash) ? response.with_indifferent_access : {}
        {
          order_id: hash[:order_id] || hash[:orderId] || fallback_id,
          status: hash[:status] || hash[:order_status] || hash[:orderStatus]
        }.compact
      end
    end
  end
end
