# frozen_string_literal: true

# Intelligent Trading Agent with iterative Plan-Execute-Observe-Refine loop
class IntelligentTradingAgent
  MAX_ITERATIONS = 10

  def initialize(prompt:)
    @prompt = prompt
    @iteration = 0
    @context = {}  # Stores information gathered during execution
    @plan = []
    @completed_steps = []
    @current_step_index = 0
  end

  def execute
    Rails.logger.info "Starting intelligent agent for: #{@prompt}"

    loop do
      @iteration += 1
      Rails.logger.info "Iteration #{@iteration}"

      break if @iteration > MAX_ITERATIONS
      break if task_complete?

      # STEP 1: REASON - Understand what we need to do
      if @reasoning.nil? || @plan.empty?
        reason_step
      end

      # STEP 2: PLAN - Decide next action
      if @plan.empty?
        plan_next_step
      end

      # STEP 3: EXECUTE - Perform the action
      break if @current_step_index >= @plan.length
      execute_current_step

      # STEP 4: OBSERVE - Analyze results
      observe_result

      # STEP 5: REFINE - Adjust if needed
      refine_plan
    end

    result = compile_final_result
    Rails.logger.info "📊 Final result: #{result[:type]} - #{result[:message]}"
    result
  end

  private

  def reason_step
    Rails.logger.info "REASONING: Understanding request..."

    reasoning_prompt = <<~PROMPT
      User request: "#{@prompt}"

      Available tools: #{DhanAgentToolMapper.tools_for_llm.map { |t| "#{t[:name]} (#{t[:description]})" }.join(", ")}

      Analyze this request and return JSON:
      {
        "goal": "what the user wants to achieve",
        "required_tools": ["list of tool names needed"],
        "parameters_needed": {
          "symbol": "extract from prompt or state 'needs_lookup'",
          "dates": "calculate or state 'needs_calculation'",
          "quantities": "extract or state 'needs_user_input'"
        },
        "dependencies": ["what needs to be done first"]
      }
    PROMPT

    ai_response = OllamaClient.new.chat(
      model: "qwen2.5:1.5b-instruct",
      prompt: reasoning_prompt
    )

    parse_reasoning(ai_response)
  rescue StandardError => e
    Rails.logger.error "Reasoning error: #{e.message}"
  end

  def parse_reasoning(ai_response)
    json_match = ai_response.match(/\{[\s\S]*\}/)
    return unless json_match

    @reasoning = JSON.parse(json_match[0], symbolize_names: true)
    Rails.logger.info "Reasoning: #{@reasoning.inspect}"
  rescue JSON::ParserError
    Rails.logger.error "Failed to parse reasoning"
  end

  def plan_next_step
    Rails.logger.info "PLANNING: Step #{@current_step_index + 1}"

    current_goal = @reasoning[:goal] || @prompt
    required_tools = @reasoning[:required_tools] || []

    if required_tools.empty?
      # Generate plan from scratch
      generate_initial_plan
      return
    end

    # Check if we need to find an instrument first (if any tool needs a symbol)
    needs_instrument = required_tools.any? { |tool|
      tool.to_s.match?(/quote|historical|ohlc|option|price|market/i)
    }

    # Add search_instrument as FIRST step if needed (before any other steps)
    if needs_instrument && !required_tools.any? { |t| t.to_s.include?('instrument') }
      Rails.logger.info "🔍 Adding search_instrument as first step (required for data tools)"
      symbol = extract_symbol
      if symbol
        @plan.insert(0, {
          id: 0,
          tool: :search_instrument,
          description: "Find instrument for #{symbol}",
          params: { symbol: symbol },
          status: 'pending'
        })
      end
    end

    # Plan each tool execution
    required_tools.each_with_index do |tool_name, idx|
      tool = DhanAgentToolMapper::TOOLS[tool_name.to_sym]
      next unless tool

      step = {
        id: @plan.length,
        tool: tool_name.to_sym,
        tool_class: tool[:model],
        description: tool[:description],
        params_needed: tool[:params] || [],
        params: {},
        status: 'pending'
      }

      @plan << step
    end

    # Reassign IDs to be sequential after insert
    @plan.each_with_index do |step, idx|
      step[:id] = idx
    end

    enrich_plan_with_params
    Rails.logger.info "📋 Plan created: #{@plan.map { |s| "#{s[:id]}-#{s[:tool]}" }.join(' → ')}"
  end

  def generate_initial_plan
    # Get available tools for context
    tools_description = DhanTradingAgentTools.all.map do |tool|
      "- #{tool[:name]}: #{tool[:description]}"
    end.join("\n")

    planning_prompt = <<~PROMPT
      User wants: "#{@prompt}"

      You are a trading assistant. Based on the user's request, create a step-by-step plan using available tools.

      Available Tools:
      #{tools_description}

      For different types of requests, use these approaches:

      1. **Single Stock Query** (e.g., "Show me RELIANCE price"):
         - Step 1: Use 'search_instrument' with symbol from user
         - Step 2: Use appropriate tool (get_quote, get_historical_data, etc.)

      2. **Screening/Filtering** (e.g., "Show top 10 gainers", "Stocks with high volume"):
         - Step 1: Use 'get_instruments_by_segment' to get stock list
         - Step 2: Use 'get_quote' on multiple stocks
         - Step 3: Rank/filter results

      3. **Portfolio Analysis** (e.g., "Best performing stocks in my portfolio"):
         - Step 1: Use 'get_holdings' to get portfolio
         - Step 2: Use 'get_quote' for each holding
         - Step 3: Calculate performance

      4. **Historical/Trend Analysis** (e.g., "Which stocks moved up today"):
         - Step 1: Identify symbols
         - Step 2: Use 'search_instrument' for each
         - Step 3: Use 'get_historical_data' for trend analysis

      Return ONLY a JSON array of steps:
      [
        {
          "step": 1,
          "tool": "exact_tool_name_from_available_tools",
          "description": "what this step does",
          "params": {
            "param_name": "value or null"
          }
        }
      ]

      Be specific about which tool to use and what parameters are needed.
    PROMPT

    ai_response = OllamaClient.new.chat(model: "qwen2.5:1.5b-instruct", prompt: planning_prompt)
    @plan = parse_ai_plan(ai_response) || generate_fallback_plan

    Rails.logger.info "📋 Generated plan: #{@plan.length} steps"
  rescue StandardError => e
    Rails.logger.error "Plan generation error: #{e.message}"
    @plan = generate_fallback_plan
  end

  def parse_ai_plan(ai_response)
    json_match = ai_response.match(/\[[\s\S]*\]/)
    return nil unless json_match

    parsed = JSON.parse(json_match[0], symbolize_names: true)

    # Convert AI plan format to our step format
    parsed.map.with_index do |step, idx|
      {
        id: step[:step] || idx,
        tool: step[:tool]&.to_sym || step[:action]&.to_sym,
        description: step[:description] || step[:why],
        params: step[:params] || {},
        status: 'pending'
      }
    end
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse AI plan: #{e.message}"
    nil
  end

  def enrich_plan_with_params
    @plan.each do |step|
      # Extract params based on tool requirements
      step[:params] = extract_params_for_step(step)

      Rails.logger.info "📝 Step #{step[:id]}: #{step[:tool]} → #{step[:description]} with params: #{step[:params].inspect}"
    end
  end

  def extract_params_for_step(step)
    params = {}
    return params if step[:params_needed].nil?

    step[:params_needed].each do |param|
      case param.to_s
      when /symbol/
        params[:symbol] = extract_symbol
        # If not found, we might need to look it up
        if params[:symbol].nil?
          params[:symbol_needs_lookup] = true
        end
      when /date|from_date|to_date/
        params[:from_date] ||= 7.days.ago.strftime('%Y-%m-%d')
        params[:to_date] ||= Date.today.strftime('%Y-%m-%d')
      when /interval/
        params[:interval] = '15' # Default 15 min candles
      when /timeframe/
        params[:timeframe] = 'intraday'
      when /quantity|qty/
        params[:quantity] = extract_quantity
      when /price/
        params[:price] = 0 # Market order if no price
      when /transaction_type/
        params[:transaction_type] = extract_transaction_type
      end
    end

    params
  end

  def execute_current_step
    current_step = @plan[@current_step_index]
    return unless current_step

    Rails.logger.info "EXECUTING: #{current_step[:tool]} with params: #{current_step[:params].inspect}"

    # Check if we need to gather information first
    resolved_params = resolve_params(current_step[:params] || {})

    Rails.logger.info "🔧 Resolved params: #{resolved_params.inspect}"

    result = execute_tool(current_step[:tool], resolved_params)

    @completed_steps << {
      step: current_step,
      result: result,
      timestamp: Time.now
    }

    current_step[:status] = 'completed'
    @current_step_index += 1
  rescue StandardError => e
    Rails.logger.error "❌ Execution error: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
    @completed_steps << {
      step: current_step,
      result: { error: e.message },
      timestamp: Time.now
    }
    current_step[:status] = 'failed'
  end

  def resolve_params(params)
    params = {} if params.nil?
    resolved = params.dup

    # If symbol needs lookup, find it
    if params && params[:symbol_needs_lookup]
      symbol = extract_symbol || prompt_for_symbol
      resolved[:symbol] = symbol
      resolved.delete(:symbol_needs_lookup)

      # Lookup instrument and store in context
      instrument = find_instrument(symbol)
      @context[:instrument] = instrument if instrument
      resolved[:instrument] = instrument if instrument
    end

    # If we have an instrument in context, enrich params with instrument details
    if @context[:instrument]
      inst = @context[:instrument]
      resolved[:security_id] = inst.security_id.to_i
      resolved[:exchange_segment] = inst.exchange_segment.to_s
      resolved[:instrument] = inst.instrument.to_s

      Rails.logger.info "✅ Enriched params with instrument: #{inst.symbol_name} (ID: #{inst.security_id})"
    end

    # Only add dates if they're NOT already set and the tool needs them
    # Don't add dates to search_instrument or other non-historical tools
    unless params.nil? || params.empty?
      # Only add default dates if the params hash is for historical data
      if resolved.key?(:timeframe) || @prompt.match?(/historical|intraday|daily/i)
        resolved[:from_date] ||= 7.days.ago.strftime('%Y-%m-%d')
        resolved[:to_date] ||= Date.today.strftime('%Y-%m-%d')
      end
    end

    resolved
  end

  def execute_tool(tool_name, params = {})
    Rails.logger.info "🔧 Executing tool: #{tool_name.to_s} with params: #{params.inspect}"

    case tool_name.to_s
    when /search_instrument|get_instruments_by_segment|find_instrument/
      symbol = params[:symbol] || extract_symbol
      Rails.logger.info "🔍 Finding instrument: #{symbol}"
      instrument = find_instrument(symbol)

      if instrument
        @context[:instrument] = instrument
        Rails.logger.info "✅ Found instrument: #{instrument.symbol_name} (ID: #{instrument.security_id})"
      else
        Rails.logger.warn "⚠️ Instrument not found for: #{symbol}"
      end
      instrument

    when /get_live_quote|get_quote|quote/
      return { error: "No instrument found. Need to search for symbol first." } unless @context[:instrument]
      get_quote_for_instrument(params)

    when /get_historical_intraday|historical_intraday|intraday/
      unless @context[:instrument]
        Rails.logger.error "❌ No instrument in context for historical data"
        return { error: "No instrument found. Need to search for symbol first." }
      end
      params[:timeframe] = 'intraday'
      get_historical_for_instrument(params)

    when /get_historical_daily|historical_daily|daily|historical/
      unless @context[:instrument]
        Rails.logger.error "❌ No instrument in context for historical data"
        return { error: "No instrument found. Need to search for symbol first." }
      end
      params[:timeframe] = 'daily'
      get_historical_for_instrument(params)

    when /get_ohlc|ohlc/
      return { error: "No instrument found. Need to search for symbol first." } unless @context[:instrument]
      get_ohlc_for_instrument(params)

    when /get_option_chain|option_chain/
      unless @context[:instrument]
        Rails.logger.error "❌ No instrument in context for option chain"
        return { error: "No instrument found. Need to search for symbol first." }
      end
      Rails.logger.info "🔗 Getting option chain with instrument in context"
      get_option_chain_for_instrument(params)

    when /account_balance|get_account_balance|balance/
      DhanHQ::Models::Funds.fetch

    when /get_positions|positions/
      DhanHQ::Models::Position.all

    when /get_holdings|holdings/
      DhanHQ::Models::Holding.all

    when /screen_stocks|top_gainers|top_losers|best_performing/
      screen_stocks(params)

    when /rank_stocks|compare_stocks/
      rank_stocks(params)

    else
      { error: "Unknown tool: #{tool_name}" }
    end
  end

  def screen_stocks(params)
    Rails.logger.info "🔍 Screening stocks with params: #{params.inspect}"

    # Default to market-wide unless user explicitly asks for portfolio
    user_query = @prompt.to_s.downcase
    mode = params[:mode] ||
           (user_query.match?(/my\s+(portfolio|stocks|holdings)/i) ? 'portfolio' : 'market')

    Rails.logger.info "🎯 Mode determined: #{mode} (query: #{user_query})"

    if mode == 'portfolio'
      # Get top performers from user's portfolio
      screen_portfolio_stocks(params)
    else
      # Get top performers from market (specific index or segment)
      screen_market_stocks(params)
    end
  end

  def screen_portfolio_stocks(params)
    Rails.logger.info "📊 Screening from PORTFOLIO holdings"

    holdings = DhanHQ::Models::Holding.all

    if holdings.empty?
      return { message: "No holdings in portfolio", stocks: [] }
    end

    # Get quotes for each holding
    screened_stocks = holdings.map do |hold|
      begin
        inst = DhanHQ::Models::Instrument.find_anywhere(hold.trading_symbol, exact_match: true)
        next unless inst

        # Ensure exchange_segment is a string
        exchange_segment = inst.exchange_segment.to_s
        security_id = inst.security_id.to_i

        quote_response = DhanHQ::Models::MarketFeed.quote(
          exchange_segment => [security_id]
        )
        quote_data = quote_response.dig('data', exchange_segment, security_id.to_s)
        current_price = quote_data&.dig('last_price')&.to_f

        {
          symbol: hold.trading_symbol,
          current_price: current_price,
          invested_price: hold.average_price.to_f,
          quantity: hold.quantity.to_f,
          pnl: (current_price - hold.average_price.to_f) * hold.quantity.to_f,
          change_percent: calculate_change(hold.average_price.to_f, current_price)
        }
      rescue StandardError => e
        Rails.logger.error "Error fetching quote for #{hold.trading_symbol}: #{e.message}"
        nil
      end
    end.compact

    # Sort by performance
    criteria = params[:sort_by] || 'performance'
    ranked_stocks = screened_stocks.sort_by do |stock|
      case criteria.to_s
      when 'performance', 'gain'
        -(stock[:change_percent] || 0)
      when 'loss', 'worst'
        stock[:change_percent] || 0
      when 'pnl'
        -(stock[:pnl] || 0)
      else
        -(stock[:change_percent] || 0)
      end
    end

    { stocks: ranked_stocks.take(params[:limit] || 10), mode: 'portfolio' }

  rescue StandardError => e
    Rails.logger.error "Portfolio screening error: #{e.message}"
    { error: e.message, stocks: [] }
  end

  def screen_market_stocks(params)
    Rails.logger.info "📊 Screening from MARKET (NIFTY stocks)"

    # Get NIFTY 50 or NIFTY 100 stocks
    index_name = params[:index] || 'NIFTY50'
    segment = 'NSE_EQ' # NSE Equity segment

    # Get instruments for the index/segment
    instruments = DhanHQ::Models::Instrument.by_segment(segment)

    if instruments.empty?
      return { message: "No stocks found for #{index_name}", stocks: [] }
    end

    # Get quotes for a sample of popular stocks (limit to top traded)
    # Popular stocks: RELIANCE, TCS, HDFC BANK, ICICI BANK, INFY, HINDUNILVR, etc.
    popular_symbols = ['RELIANCE', 'TCS', 'HDFC BANK', 'ICICI BANK', 'INFY', 'HINDUNILVR', 'BHARTIARTL', 'SBIN', 'BAJFINANCE', 'HDFCLIFE']

    screened_stocks = popular_symbols.map do |symbol|
      begin
        inst = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)
        next unless inst

        # Ensure exchange_segment is a string
        exchange_segment = inst.exchange_segment.to_s
        security_id = inst.security_id.to_i

        Rails.logger.info "📊 Getting quote for #{symbol}: segment=#{exchange_segment}, id=#{security_id}"

        quote_response = DhanHQ::Models::MarketFeed.quote(
          exchange_segment => [security_id]
        )
        quote_data = quote_response.dig('data', exchange_segment, security_id.to_s)

        ohlc = quote_data&.dig('ohlc') || {}
        last_price = quote_data&.dig('last_price')&.to_f || 0
        prev_close = ohlc['close']&.to_f || last_price
        day_change = last_price - prev_close
        day_change_percent = prev_close > 0 ? ((day_change / prev_close) * 100) : 0

        {
          symbol: symbol,
          current_price: last_price,
          prev_close: prev_close,
          day_change: day_change,
          day_change_percent: day_change_percent,
          volume: quote_data&.dig('volume')&.to_i
        }
      rescue StandardError => e
        Rails.logger.error "Error fetching quote for #{symbol}: #{e.message}"
        nil
      end
    end.compact

    # Sort by day change percent
    ranked_stocks = screened_stocks.sort_by { |s| -(s[:day_change_percent] || 0) }

    { stocks: ranked_stocks.take(params[:limit] || 10), mode: 'market' }

  rescue StandardError => e
    Rails.logger.error "Market screening error: #{e.message}"
    { error: e.message, stocks: [] }
  end

  def rank_stocks(params)
    Rails.logger.info "📊 Ranking stocks with params: #{params.inspect}"
    screen_stocks(params.merge(sort_by: params[:metric] || 'performance'))
  end

  def calculate_change(invested, current)
    return 0 unless invested && current && invested > 0
    ((current.to_f - invested) / invested.to_f) * 100
  end

  def find_instrument(symbol)
    return nil unless symbol

    Rails.logger.info "🔎 Searching for instrument: #{symbol}"

    # For indices like NIFTY, try to find in IDX_I segment first
    if symbol.match?(/NIFTY|SENSEX|BANKNIFTY|FINNIFTY|MIDCPNIFTY/i)
      Rails.logger.info "📌 Searching for index #{symbol} in IDX_I segment"
      begin
        result = DhanHQ::Models::Instrument.find("IDX_I", symbol.upcase)
        if result
          Rails.logger.info "✅ Found index: #{result.symbol_name} (#{result.security_id})"
          return result
        end
      rescue StandardError => e
        Rails.logger.info "Index not found in IDX_I, trying general search"
      end
    end

    # General search
    result = DhanHQ::Models::Instrument.find_anywhere(symbol.upcase, exact_match: false)

    if result
      Rails.logger.info "✅ Found: #{result.symbol_name} (#{result.security_id}) in #{result.exchange_segment}"
    else
      Rails.logger.warn "❌ No instrument found for: #{symbol}"
    end

    result
  rescue StandardError => e
    Rails.logger.error "❌ Error finding instrument: #{e.message}"
    nil
  end

  def get_quote_for_instrument(params = {})
    return { error: "No instrument in context" } unless @context[:instrument]

    inst = @context[:instrument]
    # Ensure exchange_segment is a string
    exchange_segment = inst.exchange_segment.to_s
    security_id = inst.security_id.to_i

    Rails.logger.info "📊 Getting quote for instrument: #{inst.symbol_name}"

    quote_response = DhanHQ::Models::MarketFeed.quote(
      exchange_segment => [security_id]
    )

    quote_response.dig('data', exchange_segment, security_id.to_s)
  end

  def get_historical_for_instrument(params = {})
    return { error: "No instrument in context" } unless @context[:instrument]

    inst = @context[:instrument]
    timeframe = (params[:timeframe] || 'intraday').to_s

    # Ensure all params are strings
    params_for_api = {
      security_id: inst.security_id.to_i,
      exchange_segment: inst.exchange_segment.to_s,
      instrument: inst.instrument.to_s,
      from_date: (params[:from_date] || 7.days.ago.strftime('%Y-%m-%d')).to_s,
      to_date: (params[:to_date] || Date.today.strftime('%Y-%m-%d')).to_s
    }

    # Add interval for intraday (must be a string)
    params_for_api[:interval] = (params[:interval] || '15').to_s if timeframe == 'intraday'

    # Add expiry_code for F&O (integer)
    params_for_api[:expiry_code] = 0 if inst.instrument.to_s == 'FUTURES'

    Rails.logger.info "📊 Fetching #{timeframe} data with params: #{params_for_api.inspect}"

    # Call the correct method directly instead of using .send
    result = if timeframe == 'daily'
               DhanHQ::Models::HistoricalData.daily(params_for_api)
             else
               DhanHQ::Models::HistoricalData.intraday(params_for_api)
             end

    Rails.logger.info "✅ Got #{result[:close]&.length || 0} candles" if result.is_a?(Hash)

    result
  rescue StandardError => e
    Rails.logger.error "Historical data error: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
    { error: e.message }
  end

  def get_ohlc_for_instrument(params = {})
    return { error: "No instrument in context" } unless @context[:instrument]

    inst = @context[:instrument]
    exchange_segment = inst.exchange_segment.to_s
    security_id = inst.security_id.to_i

    quote_response = DhanHQ::Models::MarketFeed.ohlc(
      exchange_segment => [security_id]
    )

    quote_response.dig('data', exchange_segment, security_id.to_s)
  end

  def get_option_chain_for_instrument(params = {})
    return { error: "No instrument in context" } unless @context[:instrument]

    inst = @context[:instrument]
    expiry = params[:expiry]

    # If no expiry specified, get the expiry list from DhanHQ and use the first one
    unless expiry
      Rails.logger.info "📅 No expiry specified, fetching expiry list for #{inst.symbol_name}"

      begin
        # Call the expiry list endpoint - use fetch_expiry_list not expiry_list
        response = DhanHQ::Models::OptionChain.fetch_expiry_list(
          underlying_scrip: inst.security_id.to_i,
          underlying_seg: inst.exchange_segment.to_s
        )

        # Parse the response to get available expiries
        expiry_list = if response.is_a?(Hash)
                        response[:data] || response['data'] || []
                      elsif response.is_a?(Array)
                        response
                      else
                        []
                      end

        if expiry_list.is_a?(Array) && expiry_list.length > 0
          expiry = expiry_list.first.to_s
          Rails.logger.info "✅ Found expiries: #{expiry_list.first(3).join(', ')}. Using first: #{expiry}"
          @context[:available_expiries] = expiry_list
        else
          # Fallback: use next Thursday
          next_thursday = Date.today
          next_thursday += 1 until next_thursday.thursday?
          expiry = next_thursday.strftime('%Y-%m-%d')
          Rails.logger.warn "⚠️ No expiries found, using calculated Thursday: #{expiry}"
        end
      rescue StandardError => e
        Rails.logger.error "Failed to get expiry list: #{e.message}"
        # Fallback to calculated expiry
        next_thursday = Date.today
        next_thursday += 1 until next_thursday.thursday?
        expiry = next_thursday.strftime('%Y-%m-%d')
      end
    end

    Rails.logger.info "🔗 Fetching option chain for #{inst.symbol_name} (expiry: #{expiry})"

    option_chain_result = DhanHQ::Models::OptionChain.fetch(
      underlying_scrip: inst.security_id.to_s,
      underlying_seg: inst.exchange_segment.to_s,
      expiry: expiry
    )

    {
      instrument: inst,
      expiry: expiry,
      chain: option_chain_result
    }
  rescue StandardError => e
    Rails.logger.error "Option chain error: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(3).join("\n")}"
    { error: "Failed to fetch option chain: #{e.message}" }
  end

  def observe_result
    return if @completed_steps.empty?

    last_result = @completed_steps.last[:result]

    Rails.logger.info "OBSERVING: #{last_result.class}"

    # Store useful data in context
    if last_result.is_a?(DhanHQ::Models::Instrument)
      @context[:instrument] = last_result
    elsif last_result.is_a?(Hash)
      @context.merge!(last_result)
    end
  end

  def refine_plan
    # Check if we need to add more steps
    return if @completed_steps.empty?

    last_result = @completed_steps.last[:result]

    # If the last step found an instrument, but we still need more data
    if last_result.is_a?(DhanHQ::Models::Instrument) && @prompt.include?('quote')
      # Add get_quote step if not already there
      unless @plan.any? { |s| s[:tool].to_s.include?('quote') }
        @plan << {
          id: @plan.length,
          tool: :get_live_quote,
          description: "Get live quote",
          params: {},
          status: 'pending'
        }
      end
    end
  end

  def task_complete?
    # Check if we've completed the request
    return true if @completed_steps.any? && @current_step_index >= @plan.length
    return true if @completed_steps.last&.dig(:result, :error) && @iteration > 3

    false
  end

  def extract_symbol
    @symbol ||= begin
      # First, try to extract symbols that are NOT common words
      common_words = ['OPTION', 'CHAIN', 'STOCKS', 'SHOW', 'GET', 'FOR', 'OF', 'IS', 'ME', 'MY', 'THE', 'A', 'AN']

      patterns = [
        # Pattern 1: "Get option chain for NIFTY" - extract NIFTY
        /(?:option.*chain|chain.*option)\s+for\s+(\w+)/i,
        # Pattern 2: "for RELIANCE", "of TCS", "is WIPRO"
        /(?:for|of|is|get|show)\s+([A-Z]{3,})\b/i,
        # Pattern 3: "RELIANCE price", "TCS quote"
        /\b([A-Z]{3,})\b.*(?:price|quote|ohlc|historical|intraday|daily)/i,
        # Pattern 4: Any standalone uppercase word at the end
        /\b([A-Z]{3,})\b$/
      ]

      patterns.each do |pattern|
        match = @prompt.match(pattern)
        if match && match[1] && match[1].length >= 3 && !common_words.include?(match[1].upcase)
          return match[1].upcase
        end
      end
      nil
    end
  end

  def extract_quantity
    match = @prompt.match(/(\d+)\s*(?:shares?|qty|quantity)/i)
    match ? match[1].to_i : 1
  end

  def extract_transaction_type
    @prompt.match?(/buy/i) ? 'BUY' : 'SELL'
  end

  def prompt_for_symbol
    # Could prompt user, but for now return nil
    nil
  end

  def generate_fallback_plan
    if @prompt.match?(/option.*chain/i)
      return [
        { tool: :search_instrument, description: "Find instrument", params: { symbol: extract_symbol } },
        { tool: :get_option_chain, description: "Get option chain", params: {} }
      ]
    end

    if @prompt.match?(/historical.*data|historical|ohlc|candle|chart/i)
      symbol = extract_symbol
      return [
        { tool: :search_instrument, description: "Find instrument for #{symbol}", params: { symbol: symbol } },
        { tool: :get_historical_intraday, description: "Get historical data", params: { from_date: 7.days.ago.strftime('%Y-%m-%d'), to_date: Date.today.strftime('%Y-%m-%d') } }
      ]
    end

    if @prompt.match?(/ohlc|quote|price/i)
      symbol = extract_symbol
      return [
        { tool: :search_instrument, description: "Find instrument", params: { symbol: symbol } },
        { tool: :get_live_quote, description: "Get quote", params: {} }
      ]
    end

    [{ tool: :general_help, description: "Provide help" }]
  end

  def compile_final_result
    if @completed_steps.empty?
      return {
        type: :error,
        message: "Task not completed",
        formatted: "❌ Could not fulfill request"
      }
    end

    final_data = @completed_steps.last[:result]

    {
      type: :success,
      message: "Completed in #{@completed_steps.length} steps",
      data: final_data,
      formatted: format_final_result(final_data),
      plan: @plan.map { |s| { tool: s[:tool], description: s[:description], status: s[:status] } },
      completed_steps: @completed_steps.length,
      instrument: @context[:instrument]&.symbol_name
    }
  end

  def format_final_result(result)
    case result
    when DhanHQ::Models::Instrument
      format_instrument_result(result)
    when Hash
      if result[:error]
        "<div class='text-red-600'>❌ #{result[:error]}</div>"
      elsif result[:close] || result[:open] || result['close'] || result['open']
        # Historical data (OHLCV format)
        format_historical_data(result)
      elsif result[:stocks] || result.is_a?(Array)
        # Screened/ranked stocks
        format_screened_stocks(result[:stocks] || result)
      elsif result[:chain] || result[:expiry]
        # Option chain result
        format_option_chain_result(result)
      else
        "<pre class='text-xs overflow-auto max-h-96'>#{JSON.pretty_generate(result)}</pre>"
      end
    else
      result.to_s
    end
  end

  def format_screened_stocks(result_data)
    # Handle both array and hash with :stocks key
    stocks = result_data.is_a?(Array) ? result_data : (result_data[:stocks] || [])
    mode = result_data.is_a?(Hash) ? result_data[:mode] : nil

    return "<p>📊 No stocks found</p>" if stocks.nil? || stocks.empty?

    title = mode == 'portfolio' ? "📊 Top Performers in Your Portfolio" : "📈 Top Gaining Stocks (Market)"

    html = <<~HTML
      <div class="bg-gradient-to-r from-blue-50 to-purple-50 p-4 rounded-lg">
        <h3 class="font-bold text-lg mb-3">#{title}</h3>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b">
    HTML

    if mode == 'portfolio'
      html += <<~HTML
                <th class="text-left p-2">Symbol</th>
                <th class="text-right p-2">Invested</th>
                <th class="text-right p-2">Current</th>
                <th class="text-right p-2">Qty</th>
                <th class="text-right p-2">P&L</th>
                <th class="text-right p-2">Change %</th>
      HTML
    else
      html += <<~HTML
                <th class="text-left p-2">Symbol</th>
                <th class="text-right p-2">Prev Close</th>
                <th class="text-right p-2">Current</th>
                <th class="text-right p-2">Change</th>
                <th class="text-right p-2">Change %</th>
                <th class="text-right p-2">Volume</th>
      HTML
    end

    html += <<~HTML
              </tr>
            </thead>
            <tbody>
    HTML

    stocks.each do |stock|
      if mode == 'portfolio'
        change = stock[:change_percent] || 0
        change_color = change >= 0 ? "text-green-600" : "text-red-600"
        change_sign = change >= 0 ? "+" : ""
        pnl = stock[:pnl] || 0
        pnl_color = pnl >= 0 ? "text-green-600" : "text-red-600"

        html += <<~HTML
          <tr class="border-b">
            <td class="p-2 font-semibold">#{stock[:symbol]}</td>
            <td class="text-right p-2">₹#{stock[:invested_price]&.to_f&.round(2) || '-'}</td>
            <td class="text-right p-2">₹#{stock[:current_price]&.to_f&.round(2) || '-'}</td>
            <td class="text-right p-2">#{stock[:quantity]&.to_i || '-'}</td>
            <td class="text-right p-2 #{pnl_color} font-semibold">₹#{pnl.round(2)}</td>
            <td class="text-right p-2 #{change_color} font-semibold">#{change_sign}#{change.round(2)}%</td>
          </tr>
        HTML
      else
        change = stock[:day_change_percent] || 0
        change_color = change >= 0 ? "text-green-600" : "text-red-600"
        change_sign = change >= 0 ? "+" : ""
        volume = stock[:volume] || 0

        html += <<~HTML
          <tr class="border-b">
            <td class="p-2 font-semibold">#{stock[:symbol]}</td>
            <td class="text-right p-2">₹#{stock[:prev_close]&.to_f&.round(2) || '-'}</td>
            <td class="text-right p-2">₹#{stock[:current_price]&.to_f&.round(2) || '-'}</td>
            <td class="text-right p-2 #{change_color}">#{change_sign}₹#{stock[:day_change]&.to_f&.round(2) || '-'}</td>
            <td class="text-right p-2 #{change_color} font-semibold">#{change_sign}#{change.round(2)}%</td>
            <td class="text-right p-2">#{volume.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}</td>
          </tr>
        HTML
      end
    end

    html += <<~HTML
            </tbody>
          </table>
          <p class="text-xs text-gray-500 mt-2">Showing top #{stocks.length} stocks</p>
        </div>
      </div>
    HTML

    html
  end

  def format_historical_data(data)
    closes = data[:close] || data['close'] || []
    opens = data[:open] || data['open'] || []
    highs = data[:high] || data['high'] || []
    lows = data[:low] || data['low'] || []
    volumes = data[:volume] || data['volume'] || []
    timestamps = data[:timestamp] || data['timestamp'] || []

    symbol_name = @context[:instrument]&.symbol_name || "Instrument"

    html = <<~HTML
      <div class="bg-gradient-to-r from-blue-50 to-purple-50 p-4 rounded-lg">
        <h3 class="font-bold text-lg mb-3">📊 #{symbol_name} - Historical Data</h3>
        <p class="text-sm text-gray-600 mb-2">📈 #{closes.length} candles collected</p>
    HTML

    if closes.length > 0
      html += <<~HTML
        <div class="overflow-x-auto">
          <table class="w-full text-xs">
            <thead>
              <tr class="border-b">
                <th class="text-left p-1">Time</th>
                <th class="text-right p-1">Open</th>
                <th class="text-right p-1">High</th>
                <th class="text-right p-1">Low</th>
                <th class="text-right p-1">Close</th>
                <th class="text-right p-1">Volume</th>
              </tr>
            </thead>
            <tbody>
      HTML

      # Show last 10 candles
      candles_to_show = [10, closes.length].min
      start_idx = closes.length - candles_to_show

      (start_idx...closes.length).each do |i|
        timestamp = timestamps[i] ? Time.at(timestamps[i]).strftime('%H:%M') : '-'
        html += <<~HTML
          <tr class="border-b">
            <td class="p-1">#{timestamp}</td>
            <td class="text-right p-1">₹#{opens[i]&.to_f&.round(2) || '-'}</td>
            <td class="text-right p-1 text-green-600">₹#{highs[i]&.to_f&.round(2) || '-'}</td>
            <td class="text-right p-1 text-red-600">₹#{lows[i]&.to_f&.round(2) || '-'}</td>
            <td class="text-right p-1 font-semibold">₹#{closes[i]&.to_f&.round(2) || '-'}</td>
            <td class="text-right p-1">#{volumes[i]&.to_i&.to_s&.reverse&.gsub(/(\d{3})(?=\d)/, '\\1,')&.reverse || '-'}</td>
          </tr>
        HTML
      end

      html += <<~HTML
            </tbody>
          </table>
          <p class="text-xs text-gray-500 mt-2">Showing last #{candles_to_show} of #{closes.length} candles</p>
        </div>
      HTML
    end

    html += "</div>"
    html
  end

  def format_instrument_result(inst)
    <<~HTML
      <div class="bg-gradient-to-r from-blue-50 to-purple-50 p-4 rounded-lg">
        <h3 class="font-bold text-lg">#{inst.symbol_name}</h3>
        <p class="text-sm">Security ID: #{inst.security_id}</p>
        <p class="text-sm">Exchange: #{inst.exchange_segment}</p>
      </div>
    HTML
  end

  def format_option_chain_result(result_data)
    return "<p>❌ No option chain data available</p>" unless result_data.is_a?(Hash)

    chain_data = result_data[:chain] || result_data['chain'] || result_data
    inst = result_data[:instrument] || @context[:instrument]
    expiry = result_data[:expiry]

    symbol_name = inst&.symbol_name || 'Instrument'

    html = <<~HTML
      <div class="bg-gradient-to-r from-blue-50 to-purple-50 p-4 rounded-lg">
        <h3 class="font-bold text-lg mb-3">🔗 Option Chain: #{symbol_name}</h3>
        <p class="text-sm text-gray-600 mb-3">Expiry: #{expiry}</p>
    HTML

    if chain_data.is_a?(Hash) && chain_data[:data]
      # Format option chain OC data
      oc = chain_data[:data][:oc] || chain_data[:data]['oc'] || {}
      if oc.is_a?(Hash)
        # Show first few strikes
        strikes = oc.keys.first(5)

        html += <<~HTML
          <div class="overflow-x-auto">
            <p class="text-xs text-gray-500">Showing first 5 strikes of available option chain data</p>
            <pre class="text-xs mt-2 overflow-auto max-h-96 bg-gray-100 p-3 rounded">#{JSON.pretty_generate(oc.slice(*strikes))}</pre>
          </div>
        HTML
      else
        html += "<p class='text-sm'>Option chain data received</p>"
      end
    else
      html += "<pre class='text-xs overflow-auto max-h-96'>#{JSON.pretty_generate(chain_data)}</pre>"
    end

    html += "</div>"
    html
  end
end

