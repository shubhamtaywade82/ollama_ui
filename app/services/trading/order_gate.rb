# frozen_string_literal: true

# Trading::OrderGate - Idempotent bracket/simple order placement and modification
module Trading
  class OrderGate
    class << self
      def place_bracket!(plan, idem:)
        return if defined?(Idem) && Idem.seen?(idem)

        # plan: {symbol, qty, segment, product, boStopLossValue, boProfitValue, order_type}
        resp = Trading::Dhan.place_bracket(**plan)
        Idem.mark!(idem, resp['order_id'] || resp.dig('data', 'order_id')) if defined?(Idem)
        resp
      end

      def modify_sl!(ctx)
        Trading::Dhan.modify_order(**ctx[:modify_params])
      end

      def exit!(ctx)
        Trading::Dhan.exit_order(order_id: ctx[:exit_order_id])
      end
    end
  end
end
