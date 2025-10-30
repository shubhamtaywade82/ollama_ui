# frozen_string_literal: true

# Trading::RiskGuards - Market hours, capital and safety validation
module Trading
  class RiskGuards
    MARKET_TZ = 'Asia/Kolkata'

    class << self
      def check!(ctx, checks)
        checks.each do |check|
          case check
          when :hours
            raise 'Market closed' unless market_open_now?
          when :capital
            raise 'Insufficient capital' unless capital_ok?(ctx)
          end
        end
      end

      def market_open_now?
        t = Time.now.in_time_zone(MARKET_TZ)
        wd = t.wday.between?(1, 5)
        hm = t.strftime('%H%M').to_i
        wd && hm >= 915 && hm <= 1530
      end

      def capital_ok?(_ctx)
        # TODO: implement capital/risk checks (stub = true for now)
        true
      end
    end
  end
end
