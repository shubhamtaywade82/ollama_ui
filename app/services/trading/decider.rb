# frozen_string_literal: true

# Trading::Decider - Tiny prompt, returns {"action","reason","order"} JSON
module Trading
  class Decider
    PROMPT = <<~P.strip
      You are a concise trading decider. Input: signal + quote.
      Output strict JSON: {"action":"no_trade|place|wait", "reason":"...", "order":{...}}
      Order JSON keys: symbol, quantity, order_type, exchange_segment, product_type, boStopLossValue, boProfitValue.
      Keep TP 25–35 ₹ realistic, SL ~20% of option premium unless specified.
    P

    def self.call(signal:, quote:)
      messages = [
        { role: 'system', content: PROMPT },
        { role: 'user', content: { signal: signal, quote: quote }.to_json }
      ]
      out = Trading::LlmClient.new.chat!(messages)
      begin
        JSON.parse(out)
      rescue StandardError
        { 'action' => 'no_trade', 'reason' => 'parse_error' }
      end
    end
  end
end
