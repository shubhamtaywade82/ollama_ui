# frozen_string_literal: true

class Trading::AgentRunner
  DEFAULT_MAX_STEPS = 10

  def initialize(goal:, system_prompt: nil, max_steps: nil)
    @goal = goal
    @config = Trading::Config.settings
    @max_steps = max_steps || @config.fetch(:max_steps_per_run, DEFAULT_MAX_STEPS)
    @system_prompt = system_prompt || default_system_prompt
    @llm = Trading::LlmClient.new
    @steps = []
    @last_step_started_at = nil
  end

  def run
    return market_closed_response unless within_market_hours?

    messages = bootstrap_messages

    @max_steps.times do |index|
      enforce_cooldown

      raw_reply = @llm.chat!(messages)
      tool_call = safe_json(raw_reply)
      break unless tool_call

      observation = dispatch(tool_call)
      step_record = build_step_record(index, tool_call, observation)
      @steps << step_record

      messages << { role: "assistant", content: tool_call.to_json }
      messages << { role: "user", content: observation.to_json }

      break if stop_condition?(tool_call, observation)
      break if critical_failure?(observation)
    end

    {
      ok: true,
      goal: @goal,
      steps_taken: @steps.length,
      steps: @steps
    }
  rescue StandardError => e
    Rails.logger.error("Trading::AgentRunner failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    {
      ok: false,
      error: e.message,
      steps_taken: @steps.length,
      steps: @steps
    }
  end

  private

  def bootstrap_messages
    [
      { role: "system", content: @system_prompt },
      { role: "user", content: render_user_goal }
    ]
  end

  def safe_json(payload)
    json_block = payload.strip[/\{.*\}/m]
    return nil unless json_block

    decoded = JSON.parse(json_block)
    required = %w[tool args success_criteria]
    return decoded if required.all? { |key| decoded.key?(key) }

    Rails.logger.warn("AgentRunner: tool call missing keys -> #{decoded}")
    nil
  rescue JSON::ParserError => e
    Rails.logger.warn("AgentRunner: JSON parse failed #{e.message}")
    nil
  end

  def dispatch(tool_call)
    tool = tool_call.fetch("tool")
    args = symbolize(tool_call["args"] || {})

    case tool
    when "market.quote" then Trading::Tools.market_quote(**args)
    when "market.ohlc" then Trading::Tools.market_ohlc(**args)
    when "market.option_chain" then Trading::Tools.market_option_chain(**args)
    when "positions.list" then Trading::Tools.positions_list
    when "risk.analyze" then Trading::Tools.risk_analyze(**args)
    when "orders.place" then Trading::Tools.orders_place(**args)
    when "orders.place_bracket" then Trading::Tools.orders_place_bracket(**args)
    when "orders.modify_sl" then Trading::Tools.orders_modify_sl(**args)
    when "orders.exit" then Trading::Tools.orders_exit(**args)
    else
      { tool: tool, ok: false, result: "Unknown tool #{tool}", hint: "Unsupported tool" }
    end
  rescue ArgumentError => e
    { tool: tool, ok: false, result: "Argument error: #{e.message}", hint: "Fix payload" }
  rescue StandardError => e
    Rails.logger.error("AgentRunner: dispatch error #{e.message}")
    { tool: tool, ok: false, result: "Dispatch failure: #{e.message}", hint: "Executor error" }
  end

  def stop_condition?(tool_call, observation)
    criteria = tool_call["success_criteria"].to_s.downcase
    return false if criteria.empty?

    success_signals = [
      /order.*placed/,
      /filled/,
      /bracket.*placed/,
      /exit(ed)?/,
      /no-trade/,
      /idle/
    ]

    observation_ok = observation[:ok] || observation["ok"]
    result_text = observation[:result] || observation["result"]
    hint_text = observation[:hint] || observation["hint"]

    return true if criteria.include?("stop") || criteria.include?("complete")
    return false unless observation_ok

    [result_text, hint_text].compact.any? do |text|
      success_signals.any? { |pattern| text.to_s.match?(pattern) }
    end
  end

  def critical_failure?(observation)
    return false if observation[:ok] || observation["ok"]

    message = [observation[:result], observation["result"], observation[:hint], observation["hint"]].compact.join(" ")
    message.downcase!

    %w[unauthorized authentication rate\ limit invalid\ credentials].any? do |pattern|
      message.include?(pattern)
    end
  end

  def build_step_record(index, tool_call, observation)
    {
      step: index + 1,
      requested_at: Time.current,
      tool_call: tool_call,
      observation: observation
    }
  end

  def enforce_cooldown
    seconds = @config.dig(:cooldowns, :step) || 1
    return unless @last_step_started_at

    elapsed = Time.current - @last_step_started_at
    sleep(seconds - elapsed) if elapsed < seconds
  ensure
    @last_step_started_at = Time.current
  end

  def symbolize(hash)
    hash.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
  end

  def within_market_hours?
    hours = @config.fetch(:market_hours, {})
    open = hours[:open] || "09:15"
    close = hours[:close] || "15:30"

    ist = ActiveSupport::TimeZone["Asia/Kolkata"]
    zone_time = ist.now
    from = ist.parse("#{zone_time.to_date} #{open}")
    to = ist.parse("#{zone_time.to_date} #{close}")

    zone_time.between?(from, to)
  rescue StandardError => e
    Rails.logger.warn("AgentRunner: market hours check failed #{e.message}")
    true
  end

  def market_closed_response
    {
      ok: true,
      goal: @goal,
      steps_taken: 0,
      steps: [],
      note: "Market is currently closed; skipping run."
    }
  end

  def render_user_goal
    <<~PROMPT
      Goal: #{@goal}
      Current time IST: #{Time.current.in_time_zone("Asia/Kolkata").strftime("%H:%M")}
      Risk config: capital ₹#{@config[:capital_base]}, risk #{@config[:per_trade_risk_pct]}%, target ₹#{@config[:target_profit]}, max positions #{@config[:max_concurrent_positions]}.
      Emit exactly one JSON tool call per response with keys thought, tool, args, success_criteria.
    PROMPT
  end

  def default_system_prompt
    <<~SYSTEM
      You are a looped trading agent for Indian index options (CE/PE buying).
      Act in the sequence Plan → Act → Observe and keep iterating until the goal is satisfied,
      a hard stop is met, or you decide no-trade is safer.

      Available tools:
      - market.quote, market.ohlc, market.option_chain, positions.list
      - risk.analyze
      - orders.place, orders.place_bracket, orders.modify_sl, orders.exit

      Rules:
      - Start by confirming instrument ids before trading.
      - Use bracket orders when entering trades; populate boStopLossValue and boProfitValue.
      - Enforce risk budget and respect market hours (IST 09:15–15:30).
      - If there is no edge, emit risk.analyze with success_criteria containing "no-trade".
      - Respond with JSON only. No markdown, no comments.
    SYSTEM
  end
end
