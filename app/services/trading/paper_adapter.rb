# frozen_string_literal: true

require "securerandom"

module Trading
  module PaperAdapter
    extend self

    def place_order(mode: :simple, **params)
      order_id = "PAPER_#{SecureRandom.hex(4).upcase}"
      {
        "orderId" => order_id,
        "orderStatus" => mode == :bracket ? "BRACKET_SIMULATED" : "PAPER_SIMULATED",
        "payload" => params
      }
    end

    def modify_order(order_id:, **params)
      {
        "orderId" => order_id,
        "orderStatus" => "PAPER_MODIFIED",
        "payload" => params
      }
    end

    def exit_order(order_id:)
      {
        "orderId" => order_id,
        "orderStatus" => "PAPER_EXITED"
      }
    end
  end
end
