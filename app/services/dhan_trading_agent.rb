# frozen_string_literal: true

# AI Trading Agent that interprets user commands using LLM and executes DhanHQ operations
class DhanTradingAgent
  def initialize(prompt:)
    @prompt = prompt
    @user_prompt = prompt.downcase
  end

  # Main method to process user prompt and return response
  def execute
    Rails.logger.info "🎯 DhanTradingAgent.execute: '#{@prompt}'"

    # Check if we need iterative refinement for complex tasks
    if requires_iteration?
      Rails.logger.info '📋 Using iterative agent'
      return execute_with_iteration
    end

    # Use AI to select tool
    intent = understand_intent
    Rails.logger.info "🧠 Intent: tool=#{intent[:tool]}, action=#{intent[:action]}, symbol=#{intent[:symbol]}"

    # Execute based on selected tool
    result = if intent[:tool]
               Rails.logger.info "🔧 Executing tool: #{intent[:tool]}"
               case intent[:tool].to_sym
               when :account_balance
                 get_account_balance
               when :positions
                 get_positions
               when :holdings
                 get_holdings
               else
                 execute_with_tool(intent[:tool], intent[:params])
               end
             elsif intent[:action]
               Rails.logger.info "⚡ Executing action: #{intent[:action]}"
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
                 # Try direct quote detection as fallback
                 if @user_prompt.match?(/\b(quote|price|ltp|last price|current price)\b/) && extract_symbol_from_prompt
                   Rails.logger.info '🎯 Fallback: Direct quote detection'
                   get_quote_details
                 else
                   general_help
                 end
               end
             else
               # Try direct quote detection as final fallback
               Rails.logger.info '🔄 Final fallback: Checking for quote request'
               if @user_prompt.match?(/\b(quote|price|ltp|last price|current price)\b/) && extract_symbol_from_prompt
                 symbol = extract_symbol_from_prompt
                 Rails.logger.info "✅ Detected quote for symbol: #{symbol}"
                 get_quote_details
               else
                 Rails.logger.warn '⚠️ No intent matched, returning help'
                 general_help
               end
             end

    Rails.logger.info "📤 Result type: #{result.class}, has keys: #{result.is_a?(Hash) ? result.keys.inspect : 'N/A'}"

    # Ensure result has required fields
    if result.nil?
      Rails.logger.error '❌ Result is nil!'
      return error_response('Unexpected error: no result returned')
    end

    unless result.is_a?(Hash) && result[:type] && result[:formatted]
      Rails.logger.error "❌ Result missing required fields! Result: #{result.inspect[0..200]}"
      return error_response('Result format invalid: missing type or formatted')
    end

    # FINAL LLM SUMMARIZATION STEP (only LLM response used)
    llm_summary = nil
    begin
      llm_summary = llm_summarize_final(@prompt, result[:data])
    rescue StandardError => e
      Rails.logger.error "LLM summarize_final error: #{e.message}"
    end
    if llm_summary.present?
      result[:formatted] = llm_summary
    else
      result[:formatted] = "<div class='text-yellow-600'>⚠️ LLM summarization failed. Showing raw data.</div>" \
                           "<pre class='text-xs'>" +
                           JSON.pretty_generate(result[:data]) +
                           '</pre>'
      Rails.logger.warn 'LLM failed or returned blank—falling back to raw JSON for :formatted.'
    end

    result
  rescue StandardError => e
    Rails.logger.error "❌ DhanTradingAgent.execute failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    error_response("Execution failed: #{e.message}")
  end

  def requires_iteration?
    # Complex tasks that need multi-step execution (find instrument, then fetch data)
    # NOTE: Simple quote requests should NOT use iteration
    needs_iteration =
      (@user_prompt.include?('historical') && !@user_prompt.match?(/\b(quote|price|ltp)\b/)) ||
      (@user_prompt.include?('ohlc') && !@user_prompt.match?(/\b(quote|price|ltp)\b/)) ||
      @user_prompt.include?('candle') ||
      @user_prompt.include?('chart') ||
      (@user_prompt.include?('option') && @user_prompt.include?('chain')) ||
      (@user_prompt.match?(/buy|sell|order/) && @user_prompt.exclude?('show')) ||
      @user_prompt.include?('analyze') ||
      @user_prompt.include?('compare')

    Rails.logger.info "🤔 Requires iteration? #{needs_iteration} (prompt: #{@prompt})"
    needs_iteration
  end

  def execute_with_iteration
    # Use IntelligentTradingAgent for complex tasks with full reasoning loop
    agent = IntelligentTradingAgent.new(prompt: @prompt)
    result = agent.execute

    # Ensure IntelligentTradingAgent result has the expected format
    if result.is_a?(Hash) && result[:type] && result[:formatted]
      result
    elsif result.is_a?(Hash)
      # Convert IntelligentTradingAgent format to expected format
      # Handle case where data might be an Instrument or other non-Hash object
      data = result[:data]

      # If data is an Instrument, format it properly
      if data.is_a?(DhanHQ::Models::Instrument)
        {
          type: result[:type] || :success,
          message: result[:message] || "Found instrument: #{data.symbol_name}",
          formatted: result[:formatted] || format_instrument_for_display(data),
          data: {
            symbol: data.symbol_name,
            security_id: data.security_id,
            exchange_segment: data.exchange_segment
          }
        }
      else
        {
          type: result[:type] || :success,
          message: result[:message] || 'Task completed',
          formatted: result[:formatted] || format_result_for_display(data || result),
          data: data || result
        }
      end
    elsif result.is_a?(DhanHQ::Models::Instrument)
      # Direct Instrument result
      {
        type: :success,
        message: "Found instrument: #{result.symbol_name}",
        formatted: format_instrument_for_display(result),
        data: {
          symbol: result.symbol_name,
          security_id: result.security_id,
          exchange_segment: result.exchange_segment
        }
      }
    else
      error_response("Iterative agent returned unexpected result: #{result.class}")
    end
  rescue StandardError => e
    Rails.logger.error "❌ execute_with_iteration failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    error_response("Iterative execution failed: #{e.message}")
  end

  def format_result_for_display(result)
    # Handle Instrument objects
    return format_instrument_for_display(result) if result.is_a?(DhanHQ::Models::Instrument)

    # Handle Hash results
    if result.is_a?(Hash)
      if result[:error]
        "❌ #{result[:error]}"
      elsif result[:data]
        "<pre class='text-xs overflow-auto'>#{JSON.pretty_generate(result[:data])}</pre>"
      else
        "<pre class='text-xs overflow-auto'>#{JSON.pretty_generate(result)}</pre>"
      end
    elsif result.is_a?(Array)
      "<pre class='text-xs overflow-auto'>#{JSON.pretty_generate(result)}</pre>"
    else
      result.to_s
    end
  end

  def format_instrument_for_display(instrument)
    <<~HTML
      <div class="bg-gradient-to-r from-blue-50 to-purple-50 p-4 rounded-lg">
        <h3 class="font-bold text-lg mb-2">🔍 #{instrument.symbol_name || instrument.underlying_symbol || 'Unknown'}</h3>
        <p class="text-sm text-gray-600">Security ID: #{instrument.security_id}</p>
        <p class="text-sm text-gray-600">Exchange: #{instrument.exchange_segment}</p>
        <p class="text-sm text-gray-600">Instrument Type: #{instrument.instrument || 'N/A'}</p>
      </div>
    HTML
  end

  def execute_with_tool(tool_name, params = {})
    # Handle search_instrument specially - if user wants quote, go straight to quote workflow
    if tool_name.to_s.include?('search_instrument') || tool_name.to_s.include?('instrument')
      # If this is part of a quote request, use quote workflow instead
      if @user_prompt.match?(/\b(quote|price|ltp|last price|current price)\b/)
        Rails.logger.info '🔄 search_instrument detected for quote request, routing to quote workflow'
        symbol = normalize_symbol(params[:symbol]) || extract_symbol_from_prompt
        return execute_workflow(:quote_with_analysis, { symbol: symbol }.merge(params.reject { |k| k == :symbol }))
      else
        # Actual instrument search
        symbol = normalize_symbol(params[:symbol]) || extract_symbol_from_prompt
        return search_instrument(symbol)
      end
    end

    # Check if this needs a workflow (multi-step)
    # Treat "contracts" as alias for option-chain requests
    if tool_name.to_s.include?('option_chain') || @user_prompt.match?(/\b(option|contracts?)\b/i)
      result = execute_workflow(:option_chain, params)
    elsif tool_name.to_s.include?('place_order') || @user_prompt.match?(/buy|sell|order/i)
      result = execute_workflow(:place_order_with_risk_check, params)
    elsif tool_name.to_s.include?('quote') || tool_name.to_s.include?('price') || tool_name.to_s.include?('get_live_quote')
      # Always use workflow for quote to ensure symbol is resolved first
      result = execute_workflow(:quote_with_analysis, params)
    elsif tool_name.to_s.include?('historical') || tool_name.to_s.include?('intraday') || tool_name.to_s.include?('daily') || tool_name.to_s.include?('ohlc') || tool_name.to_s.include?('candle')
      # Historical data needs symbol lookup first, so use get_historical_data method
      symbol = normalize_symbol(params[:symbol]) || extract_symbol_from_prompt
      result = get_historical_data(symbol, params[:timeframe], params[:interval])
    else
      # Simple tool execution - only for tools that don't need params or have all required params
      begin
        raw_result = DhanAgentToolMapper.execute_tool(tool_name, **params)

        # Check if result is an error hash
        if raw_result.is_a?(Hash) && raw_result[:error]
          Rails.logger.warn "Tool returned error: #{raw_result[:error]}"

          # If it's a quote-related tool that failed, try workflow instead
          if tool_name.to_s.include?('quote') || @user_prompt.match?(/\b(quote|price|ltp)\b/)
            Rails.logger.info '🔄 Retrying with quote workflow'
            symbol = normalize_symbol(params[:symbol]) || extract_symbol_from_prompt
            return execute_workflow(:quote_with_analysis, { symbol: symbol }.merge(params.reject { |k| k == :symbol }))
          end

          return {
            type: :error,
            message: raw_result[:error],
            formatted: "❌ Error: #{raw_result[:error]}"
          }
        end

        {
          type: :success,
          message: "Executed #{tool_name}",
          data: raw_result,
          formatted: format_tool_result(tool_name, raw_result)
        }
      rescue ArgumentError => e
        # If tool execution fails due to missing params, try workflow or fallback
        Rails.logger.warn "Tool execution failed: #{e.message}, trying workflow instead"

        if tool_name.to_s.include?('quote') || @user_prompt.match?(/\b(quote|price|ltp)\b/)
          symbol = normalize_symbol(params[:symbol]) || extract_symbol_from_prompt
          execute_workflow(:quote_with_analysis, { symbol: symbol }.merge(params.reject { |k| k == :symbol }))
        elsif tool_name.to_s.include?('historical') || tool_name.to_s.include?('intraday') || tool_name.to_s.include?('daily') || tool_name.to_s.include?('ohlc') || tool_name.to_s.include?('candle')
          symbol = normalize_symbol(params[:symbol]) || extract_symbol_from_prompt
          get_historical_data(symbol, params[:timeframe], params[:interval])
        elsif tool_name.to_s.include?('option') || @user_prompt.match?(/\b(contracts?|option)\b/i)
          symbol = normalize_symbol(params[:symbol]) || extract_symbol_from_prompt
          execute_workflow(:option_chain, { symbol: symbol }.merge(params.reject { |k| k == :symbol }))
        else
          {
            type: :error,
            message: "Tool execution failed: #{e.message}",
            formatted: "❌ Error: #{e.message}. Try: 'Get quote for [SYMBOL]' or 'Get historical data for [SYMBOL]'"
          }
        end
      end
    end

    result
  rescue StandardError => e
    Rails.logger.error "❌ execute_with_tool failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
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
      { type: :error, message: 'Unknown workflow' }
    end
  end

  def execute_option_chain_workflow(params)
    symbol = params[:symbol] || extract_symbol_from_prompt
    return error_response('Symbol not found in user prompt.') if symbol.blank?

    instrument = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)
    return error_response("Symbol #{symbol} not found") unless instrument

    # Determine expiry: use provided, else fetch list and pick the nearest
    expiry = params[:expiry]
    unless expiry
      begin
        expiries = instrument.expiry_list
        if expiries.is_a?(Array) && expiries.any?
          expiry = expiries.first.to_s
        else
          d = Time.zone.today
          d += 1 until d.thursday?
          expiry = d.strftime('%Y-%m-%d')
        end
      rescue StandardError
        d = Time.zone.today
        d += 1 until d.thursday?
        expiry = d.strftime('%Y-%m-%d')
      end
    end

    chain = instrument.option_chain(expiry: expiry)

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

  def execute_order_workflow(_params)
    # Order execution is disabled for safety in this environment
    # Do not assign unused variables
    {
      type: :warning,
      message: '🔴 DANGER: Order execution disabled',
      formatted: '⚠️ Order placement is DISABLED. This would execute a real trade. Use paper trading mode first.'
    }
  end

  # Normalize symbol parameter to ensure it's a string
  def normalize_symbol(symbol)
    return nil if symbol.nil?
    return symbol.to_s.upcase if symbol.is_a?(String)
    return symbol[:symbol].to_s.upcase if symbol.is_a?(Hash) && symbol[:symbol]
    return symbol['symbol'].to_s.upcase if symbol.is_a?(Hash) && symbol['symbol']

    symbol.to_s.upcase
  rescue StandardError
    nil
  end

  def execute_quote_workflow(params)
    symbol = normalize_symbol(params[:symbol]) || extract_symbol_from_prompt
    Rails.logger.debug symbol
    return error_response('Could not extract trading symbol from your prompt.') if symbol.blank?

    instrument = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)
    return error_response("Symbol #{symbol} not found") unless instrument

    quote_data = nil
    begin
      quote_data = instrument.quote
    rescue StandardError => e
      return error_response("No quote data returned for #{symbol}. #{e.message}")
    end

    {
      type: :success,
      message: "📈 Quote for #{symbol}",
      data: { quote: quote_data }
      # formatted: handled by final LLM call.
    }
  end

  def format_option_chain(chain_data)
    return 'No option chain data available' unless chain_data

    # Normalize shape (top-level or nested under :data)
    data_node = chain_data[:data] || chain_data['data'] || {}
    spot_ltp = chain_data[:last_price] || chain_data['last_price'] || data_node[:last_price] || data_node['last_price']
    oc = chain_data[:oc] || chain_data['oc'] || data_node[:oc] || data_node['oc'] || {}

    html = "<div class='bg-gradient-to-r from-blue-50 to-purple-50 p-4 rounded-lg'>"
    html += "<h3 class='font-bold text-lg mb-3'>📊 Option Chain</h3>"

    unless oc.is_a?(Hash) && oc.any?
      html += "<pre class='text-xs mt-2 overflow-auto max-h-96'>#{JSON.pretty_generate(chain_data)}</pre>"
      html += '</div>'
      return html
    end

    # Build ATM-centered, 10-strike window
    strikes = oc.keys.map { |k| k.to_s.to_f }.sort
    atm = if spot_ltp
            strikes.min_by { |s| (s - spot_ltp.to_f).abs }
          else
            strikes[strikes.length / 2]
          end
    window = 10
    ai = strikes.index(atm) || 0
    start_i = [ai - (window / 2), 0].max
    end_i = [start_i + window - 1, strikes.length - 1].min
    start_i = [end_i - (window - 1), 0].max
    view = strikes[start_i..end_i]

    html += "<div class='text-xs text-gray-700 mb-2'><span class='font-medium'>Spot (LTP):</span> #{spot_ltp} <span class='ml-2 text-gray-500'>ATM:</span> #{atm}</div>"
    html += <<~HTML
      <div class="overflow-x-auto">
        <table class="w-full text-xs">
          <thead>
            <tr class="border-b">
              <th class="text-right p-1 w-20">CE LTP</th>
              <th class="text-right p-1 w-16">CE OI</th>
              <th class="text-right p-1 w-14">CE IV</th>
              <th class="text-right p-1 w-24">CE Bid/Ask</th>
              <th class="text-center p-1 w-20">Strike</th>
              <th class="text-right p-1 w-24">PE Bid/Ask</th>
              <th class="text-right p-1 w-14">PE IV</th>
              <th class="text-right p-1 w-16">PE OI</th>
              <th class="text-right p-1 w-20">PE LTP</th>
            </tr>
          </thead>
          <tbody>
    HTML

    fmt_bucket = lambda do |hash, strike|
      return hash[strike.to_s] if hash.key?(strike.to_s)

      k6 = format('%.6f', strike)
      return hash[k6] if hash.key?(k6)

      k = hash.keys.find { |kk| kk.to_s.to_f == strike }
      k ? hash[k] : nil
    end

    view.each do |s|
      data = fmt_bucket.call(oc, s)
      ce = (data && (data[:ce] || data['ce'])) || {}
      pe = (data && (data[:pe] || data['pe'])) || {}

      ce_iv = (ce[:implied_volatility] || ce['implied_volatility']).to_f
      pe_iv = (pe[:implied_volatility] || pe['implied_volatility']).to_f
      ce_ltp = (ce[:last_price] || ce['last_price']).to_f
      pe_ltp = (pe[:last_price] || pe['last_price']).to_f
      ce_oi  = (ce[:oi] || ce['oi']).to_i
      pe_oi  = (pe[:oi] || pe['oi']).to_i
      ce_bid = ce[:top_bid_price] || ce['top_bid_price'] || ce[:best_bid_price] || ce['best_bid_price']
      ce_ask = ce[:top_ask_price] || ce['top_ask_price'] || ce[:best_ask_price] || ce['best_ask_price']
      pe_bid = pe[:top_bid_price] || pe['top_bid_price'] || pe[:best_bid_price] || pe['best_bid_price']
      pe_ask = pe[:top_ask_price] || pe['top_ask_price'] || pe[:best_ask_price] || pe['best_ask_price']

      is_atm = (s.to_f.round(2) == atm.to_f.round(2))
      row_class = is_atm ? 'bg-yellow-50' : ''
      row_style = is_atm ? 'style="background: rgba(250,204,21,0.25); font-weight:600;"' : ''
      strike_label = is_atm ? '<span class="ml-1 text-[10px] px-1 py-0.5 rounded bg-yellow-200 text-yellow-900 align-middle">ATM</span>' : ''

      html += <<~HTML
        <tr class="border-b #{row_class}" #{row_style}>
          <td class="text-right p-1">#{ce_ltp.positive? ? ce_ltp.round(2) : '-'}</td>
          <td class="text-right p-1">#{ce_oi.positive? ? ce_oi.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse : '-'}</td>
          <td class="text-right p-1">#{ce_iv.positive? ? ce_iv.round(2) : '-'}</td>
          <td class="text-right p-1">#{ce_bid ? ce_bid.to_f.round(2) : '-'} / #{ce_ask ? ce_ask.to_f.round(2) : '-'}</td>
          <td class="text-center p-1 font-semibold">#{s.to_i} #{strike_label}</td>
          <td class="text-right p-1">#{pe_bid ? pe_bid.to_f.round(2) : '-'} / #{pe_ask ? pe_ask.to_f.round(2) : '-'}</td>
          <td class="text-right p-1">#{pe_iv.positive? ? pe_iv.round(2) : '-'}</td>
          <td class="text-right p-1">#{pe_oi.positive? ? pe_oi.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse : '-'}</td>
          <td class="text-right p-1">#{pe_ltp.positive? ? pe_ltp.round(2) : '-'}</td>
        </tr>
      HTML
    end

    html += <<~HTML
          </tbody>
        </table>
        <p class="text-xs text-gray-500 mt-2">Showing #{view.length} strikes around ATM</p>
      </div>
    HTML

    html += '</div>'
    html
  end

  def format_quote_with_analysis(instrument, quote_data, historical_data)
    # Defensive extraction for nested DhanHQ response format
    last_price = 0
    volume = 0
    quote_hash = quote_data

    if quote_data.is_a?(Hash) && quote_data['data'].is_a?(Hash)
      segment = instrument.exchange_segment.to_s
      sid = instrument.security_id.to_s
      # Accept symbol or string keys
      seg_key = quote_data['data'][segment] || quote_data['data'][segment.to_sym]
      q = seg_key[sid] if seg_key && seg_key[sid]
      # Fallback if keys are integer
      q = seg_key[sid.to_i] || seg_key.values.first if !q && seg_key
      if q.is_a?(Hash)
        quote_hash = q
        last_price = q['last_price'] || q[:last_price] || 0
        volume = q['volume'] || q[:volume] || 0
      end
    end

    # If not found, use legacy keys
    last_price = last_price.presence || quote_data&.dig('last_price') || quote_data&.dig(:last_price) || 0
    volume = volume.presence || quote_data&.dig('volume') || quote_data&.dig(:volume) || 0

    # Extract OHLC from nested structure (quote_hash['ohlc'] or quote_hash[:ohlc])
    ohlc = quote_hash&.dig('ohlc') || quote_hash&.dig(:ohlc) || {}
    open_price = ohlc['open'] || ohlc[:open] if ohlc
    high_price = ohlc['high'] || ohlc[:high] if ohlc
    low_price = ohlc['low'] || ohlc[:low] if ohlc
    close_price = ohlc['close'] || ohlc[:close] if ohlc

    # Also check for direct keys (fallback)
    high_price ||= quote_hash&.dig('high') || quote_hash&.dig(:high)
    low_price ||= quote_hash&.dig('low') || quote_hash&.dig(:low)
    open_price ||= quote_hash&.dig('open') || quote_hash&.dig(:open)
    close_price ||= quote_hash&.dig('close') || quote_hash&.dig(:close)

    # Format volume with commas
    volume_formatted = volume.to_i.zero? ? 'N/A' : volume.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse

    historical_count = historical_data&.dig(:close)&.length || historical_data&.dig('close')&.length || 0

    # Calculate price change if possible
    net_change = quote_hash&.dig('net_change') || quote_hash&.dig(:net_change) || 0
    change_display = if net_change.to_f.zero?
                       ''
                     else
                       " <span class='text-sm #{net_change.positive? ? 'text-green-600' : 'text-red-600'}'>#{if net_change.positive?
                                                                                                               '+'
                                                                                                             end}#{net_change.to_f.round(2)}</span>"
                     end

    # Get 52-week high/low
    high_52w = quote_hash&.dig('52_week_high') || quote_hash&.dig(:'52_week_high') || quote_hash&.dig('fifty_two_week_high') || quote_hash&.dig(:fifty_two_week_high) || 0
    low_52w = quote_hash&.dig('52_week_low') || quote_hash&.dig(:'52_week_low') || quote_hash&.dig('fifty_two_week_low') || quote_hash&.dig(:fifty_two_week_low) || 0

    <<~HTML
      <div class="bg-gradient-to-r from-purple-50 to-blue-50 p-4 rounded-lg">
        <h3 class="font-bold text-lg mb-3">📈 #{instrument.symbol_name || instrument.underlying_symbol || 'Unknown'}</h3>
        <div class="text-center mb-4">
          <div class="text-xs text-gray-600 mb-1">Last Traded Price</div>
          <div class="text-4xl font-bold">₹#{last_price.to_f.round(2)}#{change_display}</div>
        </div>
        <p class="text-sm text-gray-600 mb-2">📊 Volume: #{volume_formatted}</p>
        #{if high_52w.positive? || low_52w.positive?
            "<p class='text-xs text-gray-500'>52W High: ₹#{high_52w.to_f.round(2)} | 52W Low: ₹#{low_52w.to_f.round(2)}</p>"
          end}
        <p class='text-xs text-gray-500'>📈 Historical: #{historical_count} candles available</p>
      </div>
    HTML
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
    return 'No OHLC data available' unless result

    "<pre class='text-xs overflow-auto max-h-64'>#{JSON.pretty_generate(result)}</pre>"
  end

  def format_historical_tool_result(result)
    return 'No historical data available' unless result

    closes = result[:close] || result['close'] || []
    if closes.is_a?(Array) && !closes.empty?
      last_close = closes.last.to_f.round(2)
      return "<p>📊 Historical data: #{closes.length} candles, Last close: ₹#{last_close}</p>"
    end

    "<pre>#{JSON.pretty_generate(result)}</pre>"
  end

  def format_quote_tool_result(result)
    return 'No data available' unless result

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
      model: 'qwen2.5:1.5b-instruct',
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
    when /option|contract/i
      :option_chain
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
    # Account & Portfolio
    return :account_balance if @user_prompt.match?(/\b(balance|account|cash|equity|funds|margin|buying power)\b/i)
    return :positions if @user_prompt.match?(/\b(positions?|open positions?)\b/i)
    return :holdings if @user_prompt.match?(/\b(holdings?|portfolio|demat|investments?)\b/i)

    # Market data
    return :quote if @user_prompt.match?(/\b(quote|ltp|price|last price|current price)\b/i)
    return :historical_data if @user_prompt.match?(/\b(historical|history|ohlc|candles?|chart|bars?|klines?)\b/i)
    return :option_chain if @user_prompt.match?(/\b(option|contracts?)\b/i)

    # Discovery
    return :instrument_search if @user_prompt.match?(/\b(find|search|lookup)\b/i)

    :unknown
  end

  def get_account_balance
    fund = DhanHQ::Models::Funds.fetch
    {
      type: :account,
      message: '💰 Your Account Balance',
      data: {
        available: fund.available_balance,
        utilized: fund.utilized_amount,
        collateral: fund.collateral_amount,
        withdrawable: fund.withdrawable_balance
      },
      formatted: format_account(fund)
    }
  rescue StandardError => e
    Rails.logger.error "❌ get_account_balance failed: #{e.message}"
    error_response("Failed to fetch account balance: #{e.message}")
  end

  def get_positions
    positions = DhanHQ::Models::Position.all
    {
      type: :positions,
      message: '📊 Your Open Positions',
      data: positions.map { |p| position_to_hash(p) },
      formatted: format_positions(positions)
    }
  rescue StandardError => e
    Rails.logger.error "❌ get_positions failed: #{e.message}"
    error_response("Failed to fetch positions: #{e.message}")
  end

  def get_holdings
    holdings = DhanHQ::Models::Holding.all
    {
      type: :holdings,
      message: '💼 Your Holdings',
      data: holdings.map { |h| holding_to_hash(h) },
      formatted: format_holdings(holdings)
    }
  rescue StandardError => e
    Rails.logger.error "❌ get_holdings failed: #{e.message}"
    error_response("Failed to fetch holdings: #{e.message}")
  end

  def get_quote_details(symbol = nil)
    symbol = normalize_symbol(symbol) || extract_symbol_from_prompt
    return error_response('Please specify a symbol') if symbol.blank?

    inst = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)
    return error_response("Symbol #{symbol} not found") unless inst

    unless inst.exchange_segment && inst.security_id
      return error_response("Instrument #{symbol} missing required fields (exchange_segment or security_id)")
    end

    quote_data = get_live_quote(inst)

    {
      type: :quote,
      message: "📈 Quote for #{symbol}",
      data: quote_data,
      formatted: format_quote(inst, quote_data)
    }
  rescue StandardError => e
    error_response("Failed to get quote: #{e.message}")
  end

  def get_historical_data(symbol = nil, timeframe = nil, interval = nil)
    symbol ||= extract_symbol_from_prompt
    return error_response('Please specify a symbol') if symbol.blank?

    inst = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)
    return error_response("Symbol #{symbol} not found") unless inst

    unless inst.exchange_segment && inst.security_id && inst.instrument
      return error_response("Instrument #{symbol} missing required fields")
    end

    timeframe ||= @user_prompt.include?('daily') ? 'daily' : 'intraday'
    interval ||= extract_interval

    data = fetch_historical(inst, timeframe, interval)
    {
      type: :historical,
      message: "📊 Historical Data for #{symbol} (#{timeframe})",
      data: data,
      formatted: format_historical(inst, data, timeframe)
    }
  rescue StandardError => e
    Rails.logger.error "❌ get_historical_data failed: #{e.message}"
    error_response("Failed to fetch historical data: #{e.message}")
  end

  def search_instrument(symbol = nil)
    symbol ||= extract_symbol_from_prompt
    return error_response('Please specify a symbol to search') if symbol.blank?

    inst = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: false)
    return error_response("No instrument found for #{symbol}") unless inst

    {
      type: :search,
      message: '🔍 Instrument Details',
      data: instrument_to_hash(inst),
      formatted: format_instrument(inst)
    }
  rescue StandardError => e
    Rails.logger.error "❌ search_instrument failed: #{e.message}"
    error_response("Failed to search instrument: #{e.message}")
  end

  def general_help
    {
      type: :help,
      message: '🤖 Trading Assistant Commands',
      formatted: help_text
    }
  end

  # Helper methods

  # --- Symbol Extraction ---
  # Always use LLM intent[:symbol] if available. Only use LLM fallback if not present.
  def extract_symbol_from_prompt
    return nil if @prompt.blank?

    symbol = @intent[:symbol] if defined?(@intent) && @intent.is_a?(Hash)
    symbol = symbol.to_s.strip.upcase if symbol.present?
    # LLM fallback extraction with short timeout
    if symbol.blank?
      begin
        Timeout.timeout(10) do
          symbol = llm_extract_symbol(@prompt)
        end
      rescue StandardError => e
        Rails.logger.error "LLM symbol extract timed out or failed: #{e.message}"
      end
    end
    # LAST RESORT: fallback to uppercase token heuristic if LLM is down
    if symbol.blank? && @prompt.present?
      symbol = @prompt.scan(/\b[A-Z]{3,}\b/).last
      Rails.logger.info "Symbol fallback extracted: #{symbol.inspect}" if symbol
    end
    symbol.presence
  end

  def llm_extract_symbol(prompt)
    extract_prompt = <<~PROMPT
      User request: "#{prompt}"
      Extract and return ONLY the trading symbol or instrument (e.g. NSE/BSE stocks, futures, indices) in uppercase. If no clear symbol is present, reply with "" (empty string).
    PROMPT
    result = Trading::LlmClient.new.chat!([{ role: 'user', content: extract_prompt }])
    s = result.to_s.strip.upcase
    s.match?(/[A-Z]{3,}/) ? s : nil
  rescue StandardError => e
    Rails.logger.error "LLM symbol extract failed: #{e.message}"
    nil
  end

  def extract_interval
    match = @user_prompt.match(/(\d+)\s*min/i)
    match ? match[1] : '15'
  end

  def get_live_quote(instrument)
    unless instrument&.exchange_segment && instrument.security_id
      raise StandardError,
            'Invalid instrument: missing exchange_segment or security_id'
    end

    begin
      quote_data = instrument.quote
    rescue StandardError => e
      Rails.logger.error "❌ get_live_quote failed: #{e.message}"
      raise
    end
    {
      last_price: quote_data['last_price'] || quote_data[:last_price],
      volume: quote_data['volume'] || quote_data[:volume],
      ohlc: quote_data['ohlc'] || quote_data[:ohlc] || {},
      high_52w: quote_data['52_week_high'] || quote_data[:fifty_two_week_high] || quote_data[:high_52w],
      low_52w: quote_data['52_week_low'] || quote_data[:fifty_two_week_low] || quote_data[:low_52w]
    }
  end

  def fetch_historical(instrument, timeframe, interval)
    params = {
      security_id: instrument.security_id,
      exchange_segment: instrument.exchange_segment,
      instrument: instrument.instrument,
      from_date: 7.days.ago.strftime('%Y-%m-%d'),
      to_date: Time.zone.today.strftime('%Y-%m-%d')
    }
    params[:interval] = interval if timeframe == 'intraday'

    if timeframe == 'daily'
      DhanHQ::Models::HistoricalData.daily(params)
    else
      DhanHQ::Models::HistoricalData.intraday(params)
    end
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
      💰 <strong>Available Balance:</strong> ₹#{fund.available_balance.to_f.round(2)}
      <br>📊 <strong>Utilized:</strong> ₹#{fund.utilized_amount.to_f.round(2)}
      <br>💵 <strong>Withdrawable:</strong> ₹#{fund.withdrawable_balance.to_f.round(2)}
    HTML
  end

  def format_positions(positions)
    return '<p>No open positions</p>' if positions.empty?

    html = "<table class='w-full text-sm'><thead><tr><th>Symbol</th><th>Qty</th><th>Value</th><th>P&L</th></tr></thead><tbody>"
    positions.each do |pos|
      pnl_color = pos.unrealized_profit >= 0 ? 'text-green-600' : 'text-red-600'
      html += "<tr><td>#{pos.trading_symbol}</td><td>#{pos.net_qty}</td>"
      html += "<td>₹#{pos.cost_price.to_f.round(2)}</td>"
      html += "<td class='#{pnl_color}'>₹#{pos.unrealized_profit.to_f.round(2)}</td></tr>"
    end
    html += '</tbody></table>'
  end

  def format_holdings(holdings)
    return '<p>No holdings</p>' if holdings.empty?

    html = "<table class='w-full text-sm'><thead><tr><th>Symbol</th><th>Qty</th><th>Invested</th><th>Current</th></tr></thead><tbody>"
    holdings.each do |hold|
      html += "<tr><td>#{hold.trading_symbol}</td><td>#{hold.quantity}</td>"
      html += "<td>₹#{hold.average_price.to_f.round(2)}</td>"
      html += "<td>₹#{hold.current_price.to_f.round(2)}</td></tr>"
    end
    html += '</tbody></table>'
  end

  def format_quote(instrument, quote_data)
    # Handle both symbol and string keys
    last_price = quote_data[:last_price] || quote_data['last_price'] || 0
    volume = quote_data[:volume] || quote_data['volume'] || 0
    high_52w = quote_data[:high_52w] || quote_data['high_52w'] || quote_data[:'52_week_high'] || quote_data['52_week_high'] || 0
    low_52w = quote_data[:low_52w] || quote_data['low_52w'] || quote_data[:'52_week_low'] || quote_data['52_week_low'] || 0

    volume_formatted = volume.to_i.zero? ? 'N/A' : volume.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse

    <<~HTML
      <div class="bg-gradient-to-r from-purple-50 to-blue-50 p-4 rounded-lg">
        <h3 class="font-bold text-lg mb-3">📈 #{instrument.symbol_name || instrument.underlying_symbol || 'Unknown'}</h3>
        <div class="text-center mb-4">
          <div class="text-xs text-gray-600 mb-1">Last Traded Price</div>
          <div class="text-4xl font-bold">₹#{last_price.to_f.round(2)}</div>
        </div>
        <p class="text-sm text-gray-600 mb-2">📊 Volume: #{volume_formatted}</p>
        #{if high_52w.positive? || low_52w.positive?
            "<p class='text-xs text-gray-500'>52W High: ₹#{high_52w.to_f.round(2)} | 52W Low: ₹#{low_52w.to_f.round(2)}</p>"
          end}
      </div>
    HTML
  end

  def format_historical(instrument, data, timeframe)
    return '<p>No historical data available</p>' unless data && data[:close] && !data[:close].empty?

    closes = data[:close] || []
    last_price = begin
      closes.last.to_f.round(2)
    rescue StandardError
      0
    end

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

  def llm_summarize_final(prompt, result_data)
    summary_prompt = <<~PROMPT
      User request: "#{prompt}"

      Tool/API result data (JSON):
      #{JSON.pretty_generate(result_data)[0..2000]}

      Please provide a concise, user-friendly summary for a trading chat UI. If relevant, highlight key facts (e.g. last price, volume, option chain rows) and interpret results. For errors, use clear explanations. Markdown/HTML allowed for price/volume/table, but keep conversational style.
      ---
      Your reply:
    PROMPT

    response = Trading::LlmClient.new.chat!([{ role: 'user', content: summary_prompt }])
    Rails.logger.info "LLM SUMMARY RESPONSE: #{response.inspect[0..500]}"
    response
  rescue StandardError => e
    Rails.logger.error "LLM summarization failed: #{e.message}"
    nil
  end
end
