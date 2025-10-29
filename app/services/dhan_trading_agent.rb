# frozen_string_literal: true

# AI Trading Agent that interprets user commands using LLM and executes DhanHQ operations
class DhanTradingAgent
  def initialize(prompt:)
    @prompt = prompt
    @user_prompt = prompt.downcase
  end

  # Main method to process user prompt and return response
  def execute
    # Check if we need iterative refinement for complex tasks
    if requires_iteration?
      return execute_with_iteration
    end

    # Use AI to select tool
    intent = understand_intent

    # Execute based on selected tool
    if intent[:tool]
      execute_with_tool(intent[:tool], intent[:params])
    else
      # Fallback to action-based routing
      case intent[:action]
      when :account_balance
        get_account_balance
      when :positions
        get_positions
      when :holdings
        get_holdings
      when :quote
        get_quote_details(intent[:symbol])
      when :historical_data
        get_historical_data(intent[:symbol], intent[:timeframe], intent[:interval])
      when :instrument_search
        search_instrument(intent[:symbol])
      else
        general_help
      end
    end
  end

  def requires_iteration?
    # Complex tasks that need multi-step execution (find instrument, then fetch data)
    needs_iteration =
      @user_prompt.include?('historical') ||
      @user_prompt.include?('ohlc') ||
      @user_prompt.include?('candle') ||
      @user_prompt.include?('chart') ||
      (@user_prompt.include?('option') && @user_prompt.include?('chain')) ||
      @user_prompt.match?(/buy|sell|order/) && !@user_prompt.include?('show') ||
      @user_prompt.include?('analyze') ||
      @user_prompt.include?('compare') ||
      @user_prompt.include?('option')

    Rails.logger.info "🤔 Requires iteration? #{needs_iteration} (prompt: #{@prompt})"
    needs_iteration
  end

  def execute_with_iteration
    # Use IntelligentTradingAgent for complex tasks with full reasoning loop
    agent = IntelligentTradingAgent.new(prompt: @prompt)
    agent.execute
  end

  def execute_with_tool(tool_name, params = {})
    # Check if this needs a workflow (multi-step)
    if tool_name.to_s.include?('option_chain') || @user_prompt.include?('option')
      result = execute_workflow(:option_chain, params)
    elsif tool_name.to_s.include?('place_order') || @user_prompt.match?(/buy|sell|order/i)
      result = execute_workflow(:place_order_with_risk_check, params)
    elsif tool_name.to_s.include?('quote') || tool_name.to_s.include?('price')
      result = execute_workflow(:quote_with_analysis, params)
    else
      # Simple tool execution
      result = DhanAgentToolMapper.execute_tool(tool_name, **params)
      {
        type: :success,
        message: "Executed #{tool_name}",
        data: result,
        formatted: format_tool_result(tool_name, result)
      }
    end

    result
  rescue StandardError => e
    {
      type: :error,
      message: "Tool execution failed: #{e.message}",
      formatted: "❌ Error: #{e.message}"
    }
  end

  def execute_workflow(workflow_name, params)
    case workflow_name
    when :option_chain
      execute_option_chain_workflow(params)
    when :place_order_with_risk_check
      execute_order_workflow(params)
    when :quote_with_analysis
      execute_quote_workflow(params)
    else
      { type: :error, message: "Unknown workflow" }
    end
  end

  def execute_option_chain_workflow(params)
    symbol = params[:symbol] || extract_symbol_from_prompt

    instrument = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)
    return error_response("Symbol #{symbol} not found") unless instrument

    chain = DhanHQ::Models::OptionChain.fetch(
      underlying_scrip: instrument.security_id.to_s,
      underlying_seg: instrument.exchange_segment,
      expiry: nil
    )

    {
      type: :success,
      message: "📊 Option Chain for #{symbol}",
      data: chain,
      formatted: format_option_chain(chain)
    }
  rescue StandardError => e
    {
      type: :error,
      message: e.message,
      formatted: "❌ Error fetching option chain: #{e.message}"
    }
  end

  def execute_order_workflow(params)
    symbol = params[:symbol] || extract_symbol_from_prompt
    quantity = params[:quantity] || 1
    price = params[:price] || 0
    transaction_type = params[:transaction_type] || 'BUY'

    # This is a dangerous operation - add confirmation
    {
      type: :warning,
      message: "🔴 DANGER: Order execution disabled",
      formatted: "⚠️ Order placement is DISABLED. This would execute a real trade. Use paper trading mode first."
    }
  end

  def execute_quote_workflow(params)
    symbol = params[:symbol] || extract_symbol_from_prompt

    instrument = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)
    return error_response("Symbol #{symbol} not found") unless instrument

    # Get quote
    quote_response = DhanHQ::Models::MarketFeed.quote(
      instrument.exchange_segment => [instrument.security_id.to_i]
    )
    quote_data = quote_response.dig('data', instrument.exchange_segment, instrument.security_id)

    # Get historical for context
    historical = DhanHQ::Models::HistoricalData.intraday(
      security_id: instrument.security_id,
      exchange_segment: instrument.exchange_segment,
      instrument: instrument.instrument,
      interval: '15',
      from_date: 7.days.ago.strftime('%Y-%m-%d'),
      to_date: Date.today.strftime('%Y-%m-%d')
    )

    {
      type: :success,
      message: "📈 Quote + Analysis for #{symbol}",
      data: {
        quote: quote_data,
        historical: historical
      },
      formatted: format_quote_with_analysis(instrument, quote_data, historical)
    }
  end

  def format_option_chain(chain_data)
    return "No option chain data available" unless chain_data

    # Format option chain display
    calls = chain_data[:data]&.dig(:calls) || []
    puts = chain_data[:data]&.dig(:puts) || []

    html = "<div class='bg-gradient-to-r from-blue-50 to-purple-50 p-4 rounded-lg'>"
    html += "<h3 class='font-bold text-lg mb-3'>📊 Option Chain</h3>"
    html += "<p class='text-sm text-gray-600'>Calls: #{calls.length}, Puts: #{puts.length}</p>"
    html += "<pre class='text-xs mt-2 overflow-auto max-h-64'>#{JSON.pretty_generate(chain_data)}</pre>"
    html += "</div>"
    html
  end

  def format_quote_with_analysis(instrument, quote_data, historical_data)
    last_price = quote_data&.dig('last_price') || 0

    html = <<~HTML
      <div class="bg-gradient-to-r from-purple-50 to-blue-50 p-4 rounded-lg">
        <h3 class="font-bold text-lg mb-3">📈 #{instrument.symbol_name}</h3>
        <div class="text-center mb-4">
          <div class="text-xs text-gray-600 mb-1">Last Price</div>
          <div class="text-4xl font-bold">₹#{last_price.to_f.round(2)}</div>
        </div>
        <p class="text-sm text-gray-600 mb-2">Volume: #{quote_data&.dig('volume')&.to_i&.to_s&.reverse&.gsub(/(\\d{3})(?=\\d)/, '\\1,')&.reverse || 'N/A'}</p>
        <p class="text-xs text-gray-500">Historical data: #{historical_data&.dig(:close)&.length || 0} candles</p>
      </div>
    HTML
    html
  end

  def format_tool_result(tool_name, result)
    # Use the result parameter that was passed in
    case tool_name.to_s
    when /account_balance/
      format_account(result)
    when /get_positions/, /positions/
      format_positions(result)
    when /get_holdings/, /holdings/
      format_holdings(result)
    when /get_quote/, /quote/
      format_quote_tool_result(result)
    when /get_ohlc/, /ohlc/
      format_ohlc_result(result)
    when /historical/
      format_historical_tool_result(result)
    else
      "<pre>#{JSON.pretty_generate(result)}</pre>"
    end
  rescue StandardError => e
    "<div class='text-red-600'>Error formatting result: #{e.message}</div><pre>#{e.backtrace.first(3)}</pre>"
  end

  def format_ohlc_result(result)
    return "No OHLC data available" unless result
    "<pre class='text-xs overflow-auto max-h-64'>#{JSON.pretty_generate(result)}</pre>"
  end

  def format_historical_tool_result(result)
    return "No historical data available" unless result

    closes = result[:close] || result['close'] || []
    if closes.is_a?(Array) && closes.length > 0
      last_close = closes.last.to_f.round(2)
      return "<p>📊 Historical data: #{closes.length} candles, Last close: ₹#{last_close}</p>"
    end

    "<pre>#{JSON.pretty_generate(result)}</pre>"
  end

  def format_quote_tool_result(result)
    return "No data available" unless result
    "<pre>#{JSON.pretty_generate(result)}</pre>"
  end

  # Use Ollama LLM to select and execute tools
  def understand_intent
    # Get tool descriptions for LLM
    tools = DhanAgentToolMapper.tools_for_llm
    tool_descriptions = tools.map { |t| "#{t[:name]}: #{t[:description]}" }.join("\n")

    context = <<~PROMPT
      You are a trading assistant. User request: "#{@prompt}"

      Available tools:
      #{tool_descriptions}

      Return ONLY JSON with:
      {
        "tool_name": "exact tool name to use",
        "symbol": "extracted symbol if any",
        "params": {}
      }

      Choose the BEST tool for this request. Return ONLY the JSON.
    PROMPT

    # Call Ollama to select tool
    ai_response = OllamaClient.new.chat(
      model: "qwen2.5:1.5b-instruct",
      prompt: context
    )

    # Parse AI response
    parse_tool_selection(ai_response)
  rescue StandardError => e
    Rails.logger.error "Agent error: #{e.message}"
    fallback_intent
  end

  def parse_tool_selection(ai_response)
    # Extract JSON from response
    json_match = ai_response.match(/\{[\s\S]*\}/)
    return fallback_intent unless json_match

    intent = JSON.parse(json_match[0], symbolize_names: true)

    {
      tool: intent[:tool_name]&.to_sym,
      symbol: intent[:symbol],
      params: intent[:params] || {},
      action: tool_to_action(intent[:tool_name])
    }
  rescue JSON::ParserError
    fallback_intent
  end

  def tool_to_action(tool_name)
    case tool_name&.to_s
    when /account|balance|fund/i
      :account_balance
    when /position/i
      :positions
    when /holding|portfolio/i
      :holdings
    when /quote|price|ltp/i
      :quote
    when /historical/i
      :historical_data
    when /search|find|instrument/i
      :instrument_search
    else
      :unknown
    end
  end

  def parse_intent_from_ai(ai_response)
    # Try to extract JSON from AI response
    json_match = ai_response.match(/\{[\s\S]*\}/)
    return fallback_intent unless json_match

    JSON.parse(json_match[0])
  rescue JSON::ParserError
    fallback_intent
  end

  def fallback_intent
    { action: command_type, symbol: extract_symbol_from_prompt }
  end

  private

  def command_type
    return :account_balance if @user_prompt.match?(/\b(balance|account|cash|equity|funds)\b/)
    return :positions if @user_prompt.match?(/\b(position|open position)\b/)
    return :holdings if @user_prompt.match?(/\b(holding|portfolio|investments)\b/)
    return :quote if @user_prompt.match?(/\b(quote|price|ltp|last price|current price)/)
    return :historical_data if @user_prompt.match?(/\b(historical|ohlc|candle|chart)\b/)
    return :instrument_search if @user_prompt.match?(/\b(find|search|lookup)\b/)
    :unknown
  end

  def get_account_balance
    fund = DhanHQ::Models::Funds.fetch
    {
      type: :account,
      message: "💰 Your Account Balance",
      data: {
        available: fund.available_balance,
        utilized: fund.utilized_amount,
        collateral: fund.collateral_amount,
        withdrawable: fund.withdrawable_balance
      },
      formatted: format_account(fund)
    }
  end

  def get_positions
    positions = DhanHQ::Models::Position.all
    {
      type: :positions,
      message: "📊 Your Open Positions",
      data: positions.map { |p| position_to_hash(p) },
      formatted: format_positions(positions)
    }
  end

  def get_holdings
    holdings = DhanHQ::Models::Holding.all
    {
      type: :holdings,
      message: "💼 Your Holdings",
      data: holdings.map { |h| holding_to_hash(h) },
      formatted: format_holdings(holdings)
    }
  end

  def get_quote_details(symbol = nil)
    symbol ||= extract_symbol_from_prompt
    return error_response("Please specify a symbol") unless symbol

    inst = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)
    return error_response("Symbol #{symbol} not found") unless inst

    quote_data = get_live_quote(inst)
    {
      type: :quote,
      message: "📈 Quote for #{symbol}",
      data: quote_data,
      formatted: format_quote(inst, quote_data)
    }
  end

  def get_historical_data(symbol = nil, timeframe = nil, interval = nil)
    symbol ||= extract_symbol_from_prompt
    return error_response("Please specify a symbol") unless symbol

    inst = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)
    return error_response("Symbol #{symbol} not found") unless inst

    timeframe ||= @user_prompt.include?("daily") ? "daily" : "intraday"
    interval ||= extract_interval

    data = fetch_historical(inst, timeframe, interval)
    {
      type: :historical,
      message: "📊 Historical Data for #{symbol} (#{timeframe})",
      data: data,
      formatted: format_historical(inst, data, timeframe)
    }
  end

  def search_instrument(symbol = nil)
    symbol ||= extract_symbol_from_prompt
    return error_response("Please specify a symbol to search") unless symbol

    inst = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: false)
    return error_response("No instrument found for #{symbol}") unless inst

    {
      type: :search,
      message: "🔍 Instrument Details",
      data: instrument_to_hash(inst),
      formatted: format_instrument(inst)
    }
  end

  def general_help
    {
      type: :help,
      message: "🤖 Trading Assistant Commands",
      formatted: help_text
    }
  end

  # Helper methods

  def extract_symbol_from_prompt
    match = @user_prompt.match(/\b(reliance|tcs|infy|wipro|hdfc|sbi|axis|icici|bajaj|lt|hero|maruti|titangar|britannia|titan|dmart|adanient|ultracemco|hindunilever|asianpaint|nifty|banknifty|sensex)\b/i)
    match ? match[1].upcase : (@user_prompt.match(/\b([A-Z]{3,})\b/)&.[](1))
  end

  def extract_interval
    match = @user_prompt.match(/(\d+)\s*min/i)
    match ? match[1] : "15"
  end

  def get_live_quote(instrument)
    quote_response = DhanHQ::Models::MarketFeed.quote(
      instrument.exchange_segment => [instrument.security_id.to_i]
    )

    quote_data = quote_response.dig('data', instrument.exchange_segment, instrument.security_id)
    {
      last_price: quote_data&.dig('last_price'),
      volume: quote_data&.dig('volume'),
      ohlc: quote_data&.dig('ohlc'),
      high_52w: quote_data&.dig('52_week_high'),
      low_52w: quote_data&.dig('52_week_low')
    }
  end

  def fetch_historical(instrument, timeframe, interval)
    params = {
      security_id: instrument.security_id,
      exchange_segment: instrument.exchange_segment,
      instrument: instrument.instrument,
      from_date: 7.days.ago.strftime('%Y-%m-%d'),
      to_date: Date.today.strftime('%Y-%m-%d')
    }
    params[:interval] = interval if timeframe == "intraday"

    timeframe == "daily" ?
      DhanHQ::Models::HistoricalData.daily(params) :
      DhanHQ::Models::HistoricalData.intraday(params)
  end

  def position_to_hash(pos)
    {
      symbol: pos.trading_symbol,
      qty: pos.net_qty,
      value: pos.cost_price,
      pnl: pos.unrealized_profit
    }
  end

  def holding_to_hash(hold)
    {
      symbol: hold.trading_symbol,
      qty: hold.quantity,
      invested: hold.average_price,
      current: hold.current_price
    }
  end

  def instrument_to_hash(inst)
    {
      symbol: inst.symbol_name,
      underlying: inst.underlying_symbol,
      security_id: inst.security_id,
      exchange: inst.exchange_segment,
      instrument: inst.instrument,
      lot_size: inst.lot_size,
      tick_size: inst.tick_size
    }
  end

  # Formatting methods

  def format_account(fund)
    <<~HTML
      💰 <strong>Available Balance:</strong> ₹#{fund.available_balance.to_f.round(2).to_s}
      <br>📊 <strong>Utilized:</strong> ₹#{fund.utilized_amount.to_f.round(2).to_s}
      <br>💵 <strong>Withdrawable:</strong> ₹#{fund.withdrawable_balance.to_f.round(2).to_s}
    HTML
  end

  def format_positions(positions)
    return "<p>No open positions</p>" if positions.empty?

    html = "<table class='w-full text-sm'><thead><tr><th>Symbol</th><th>Qty</th><th>Value</th><th>P&L</th></tr></thead><tbody>"
    positions.each do |pos|
      pnl_color = pos.unrealized_profit >= 0 ? "text-green-600" : "text-red-600"
      html += "<tr><td>#{pos.trading_symbol}</td><td>#{pos.net_qty}</td>"
      html += "<td>₹#{pos.cost_price.to_f.round(2)}</td>"
      html += "<td class='#{pnl_color}'>₹#{pos.unrealized_profit.to_f.round(2)}</td></tr>"
    end
    html += "</tbody></table>"
  end

  def format_holdings(holdings)
    return "<p>No holdings</p>" if holdings.empty?

    html = "<table class='w-full text-sm'><thead><tr><th>Symbol</th><th>Qty</th><th>Invested</th><th>Current</th></tr></thead><tbody>"
    holdings.each do |hold|
      html += "<tr><td>#{hold.trading_symbol}</td><td>#{hold.quantity}</td>"
      html += "<td>₹#{hold.average_price.to_f.round(2)}</td>"
      html += "<td>₹#{hold.current_price.to_f.round(2)}</td></tr>"
    end
    html += "</tbody></table>"
  end

  def format_quote(instrument, quote_data)
    <<~HTML
      📈 <strong>#{instrument.symbol_name}</strong>
      <br>💰 <strong>Last Price:</strong> ₹#{quote_data[:last_price].to_f.round(2)}
      <br>📊 <strong>Volume:</strong> #{quote_data[:volume].to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}
      <br>📈 <strong>52W High:</strong> ₹#{quote_data[:high_52w].to_f.round(2)} | <strong>52W Low:</strong> ₹#{quote_data[:low_52w].to_f.round(2)}
    HTML
  end

  def format_historical(instrument, data, timeframe)
    return "<p>No historical data available</p>" unless data && data[:close] && data[:close].length > 0

    closes = data[:close] || []
    last_price = closes.last.to_f.round(2) rescue 0

    "#{instrument.symbol_name} - Last 7 days #{timeframe} data. Last close: ₹#{last_price} (#{closes.length} candles)"
  end

  def format_instrument(inst)
    <<~HTML
      🔍 <strong>#{inst.symbol_name}</strong> (#{inst.underlying_symbol})
      <br>📍 Exchange: #{inst.exchange_segment} | Security ID: #{inst.security_id}
      <br>📋 Instrument: #{inst.instrument} | Lot Size: #{inst.lot_size}
    HTML
  end

  def help_text
    <<~HTML
      💬 Try these commands:
      <br>• "Show my account balance"
      <br>• "What are my positions?"
      <br>• "Get quote for RELIANCE"
      <br>• "Find historical data for TCS"
      <br>• "Search for INFY"
    HTML
  end

  def error_response(message)
    {
      type: :error,
      message: message,
      formatted: "❌ #{message}"
    }
  end
end

