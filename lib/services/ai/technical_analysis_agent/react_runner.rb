# frozen_string_literal: true

require 'timeout'

module Services
  module Ai
    class TechnicalAnalysisAgent
      # ReAct Runner: Rails-controlled loop orchestrating tool calls
      # LLM only plans and reasons, Rails executes and controls flow
      module ReactRunner
        MAX_ITERATIONS = 10
        MAX_TIME_SECONDS = 300
        PLANNING_TIMEOUT = 30 # Shorter timeout for planning steps

        def execute_react_loop(query:, stream: false, model: nil, &block)
          # Store model for use in planning and synthesis
          @react_model = model

          context = AgentContext.new(user_query: query)
          iteration = 0

          yield("🔍 Starting analysis loop\n") if block_given?

          loop do
            iteration += 1

            # Termination check
            if context.should_terminate?(max_iterations: MAX_ITERATIONS, max_time_seconds: MAX_TIME_SECONDS)
              if block_given?
                yield("⏹️  Termination condition met (iterations: #{iteration}, observations: #{context.observations.length})\n")
              end
              break
            end

            # Plan next step (LLM decides what tool to call)
            yield("🤔 Planning step #{iteration}...\n") if block_given?

            begin
              llm_response = plan_next_step(context, stream: stream, &block)
            rescue Timeout::Error, StandardError => e
              Rails.logger.error("[ReActRunner] Planning step failed: #{e.class} - #{e.message}")
              yield("⚠️  Planning timeout/error, using fallback logic\n") if block_given?

              # Smart fallback: continue workflow based on query and current state
              tool_call = determine_fallback_tool(context, iteration)
              unless tool_call
                # If we have no observations and no symbol, this is likely a general query
                if context.observations.empty? && iteration == 1
                  symbol = extract_symbol_from_query_fallback(context.user_query)
                  unless symbol
                    if block_given?
                      yield("ℹ️  No instrument symbol found. This query may be better handled by direct LLM.\n")
                    end
                    yield("💡 Try: 'Analyze NIFTY' or 'What is the price of RELIANCE?'\n") if block_given?
                    break
                  end
                end
                yield("⏹️  Cannot determine next step, proceeding to synthesis\n") if block_given?
                break
              end
            else
              break unless llm_response

              # Extract tool call from LLM response
              tool_call = extract_tool_call_from_plan(llm_response)

              # If LLM didn't provide tool call, use fallback
              unless tool_call
                tool_call = determine_fallback_tool(context, iteration)
                unless tool_call
                  yield("⏹️  No tool call from LLM and no fallback, proceeding to synthesis\n") if block_given?
                  break
                end
              end
            end

            # Handle final flag
            if tool_call && tool_call['final'] == true
              yield("✅ Ready for final synthesis\n") if block_given?
              break
            end

            next unless tool_call && tool_call['tool']

            tool_name = tool_call['tool']
            tool_input = tool_call['arguments'] || {}

            # Validate tool exists
            unless @tools.key?(tool_name)
              error_msg = "Unknown tool: #{tool_name}"
              yield("❌ #{error_msg}\n") if block_given?
              context.add_observation(tool_name, tool_input, { error: error_msg })
              break
            end

            # Execute tool (Rails-controlled)
            yield("🔧 Executing: #{tool_name}\n") if block_given?

            # Log tool call for auditability
            Rails.logger.info("[ReActRunner] Tool call: #{tool_name} with args: #{tool_input.inspect}")

            begin
              tool_result = execute_tool({ 'tool' => tool_name, 'arguments' => tool_input })

              # Log tool result
              result_preview = tool_result.is_a?(Hash) && tool_result[:error] ? "ERROR: #{tool_result[:error]}" : 'SUCCESS'
              Rails.logger.info("[ReActRunner] Tool result (#{tool_name}): #{result_preview}")

              context.add_observation(tool_name, tool_input, tool_result)

              if tool_result[:error]
                error_message = tool_result[:error].to_s
                yield("⚠️  Tool error: #{error_message}\n") if block_given?

                # Check for fatal HTTP errors that should stop retrying
                if fatal_http_error?(error_message)
                  fatal_code = extract_http_status_code(error_message)
                  yield("🛑 Fatal error detected (#{fatal_code}). Stopping analysis loop.\n") if block_given?
                  Rails.logger.warn("[ReActRunner] Fatal HTTP error (#{fatal_code}) detected, stopping loop")
                  break
                end
              elsif block_given?
                yield("✅ Tool completed successfully\n")
              end
            rescue StandardError => e
              error_message = e.message.to_s
              error_result = { error: "#{e.class}: #{error_message}" }
              context.add_observation(tool_name, tool_input, error_result)
              yield("❌ Tool exception: #{error_message}\n") if block_given?
              Rails.logger.error("[ReActRunner] Tool execution error: #{e.class} - #{error_message}")

              # Check for fatal HTTP errors in exceptions too
              if fatal_http_error?(error_message)
                fatal_code = extract_http_status_code(error_message)
                yield("🛑 Fatal error detected (#{fatal_code}). Stopping analysis loop.\n") if block_given?
                Rails.logger.warn("[ReActRunner] Fatal HTTP error (#{fatal_code}) in exception, stopping loop")
                break
              end
            end

            # Check if we have enough data for final analysis
            if context.ready_for_analysis? && iteration >= 2
              yield("📊 Sufficient data collected, proceeding to synthesis\n") if block_given?
              break
            end
          end

          # Check if we have any observations before synthesis
          if context.observations.empty?
            yield("ℹ️  No data collected. This query may not require technical analysis.\n") if block_given?
            if block_given?
              yield("💡 For technical analysis, please specify a symbol (e.g., 'Analyze NIFTY', 'What is the price of RELIANCE?').\n")
            end

            # Return early with helpful message
            return {
              analysis: {
                instrument: 'GENERAL',
                verdict: 'NO_TRADE',
                confidence: 0.0,
                reasoning: 'No instrument data was collected. This query appears to be a general question about trading concepts rather than a specific instrument analysis. For technical analysis, please include a symbol (e.g., NIFTY, RELIANCE, TCS).'
              },
              analysis_valid: false,
              analysis_errors: ['No instrument data collected'],
              context: context.full_context,
              iterations: iteration,
              generated_at: Time.current,
              provider: @client.provider
            }
          end

          # Final synthesis (LLM reasons over all facts)
          yield("📝 Synthesizing final analysis...\n") if block_given?
          final_analysis_raw = synthesize_analysis(context, stream: stream, &block)

          # Check if we got a fallback analysis (JSON string from build_fallback_analysis)
          is_fallback_json = final_analysis_raw.is_a?(String) && final_analysis_raw.strip.start_with?('{') && final_analysis_raw.include?('"instrument"')

          # Parse and validate structured output
          structured_output = if is_fallback_json
                                # Fallback analysis is already valid JSON string, parse it directly
                                begin
                                  parsed = JSON.parse(final_analysis_raw)
                                  { valid: true, data: parsed, errors: [] }
                                rescue JSON::ParserError => e
                                  Rails.logger.error("[ReActRunner] Failed to parse fallback JSON: #{e.message}")
                                  parse_structured_output(final_analysis_raw)
                                end
                              else
                                parse_structured_output(final_analysis_raw)
                              end

          # Format and stream the final analysis result
          if block_given?
            # Enrich analysis data with LTP from context if available
            enriched_data = structured_output[:data] || {}
            if context.instrument_data && !enriched_data['ltp']
              ltp = context.instrument_data['ltp'] || context.instrument_data[:ltp]
              enriched_data['ltp'] = ltp if ltp
            end

            # If validation failed but we have minimal data, still show it without error
            if !structured_output[:valid] && enriched_data.empty?
              # No data at all - show error
              error_msg = "⚠️ Analysis validation failed: #{structured_output[:errors]&.join(', ')}"
              yield("\n\n#{error_msg}\n")
            else
              # We have data (valid or not), format and show it
              # Only show validation error if we have very minimal data
              if !structured_output[:valid] && enriched_data.keys.length <= 1
                error_msg = "⚠️ Analysis validation failed: #{structured_output[:errors]&.join(', ')}"
                yield("\n\n#{error_msg}\n")
              end
              formatted_result = format_analysis_result(enriched_data)
              if formatted_result.present?
                # Stream formatted result as content (not progress)
                yield("\n\n#{formatted_result}\n")
              end
            end
          end

          {
            analysis: structured_output[:data],
            analysis_valid: structured_output[:valid],
            analysis_errors: structured_output[:errors],
            context: context.full_context,
            iterations: iteration,
            generated_at: Time.current,
            provider: @client.provider
          }
        rescue StandardError => e
          error_msg = "Error: #{e.class} - #{e.message}"
          yield(error_msg) if block_given?
          Rails.logger.error("[ReActRunner] Error: #{e.class} - #{e.message}")
          Rails.logger.error("[ReActRunner] Backtrace: #{e.backtrace.first(10).join("\n")}")
          nil
        end

        private

        # Check if error message contains a fatal HTTP status code
        # Fatal errors: 401 (Unauthorized), 403 (Forbidden), 404 (Not Found), 429 (Rate Limited)
        def fatal_http_error?(error_message)
          return false unless error_message.is_a?(String)

          # Check for HTTP status codes in the error message
          # Pattern: "401:", "429:", "404:", etc.
          fatal_codes = [401, 403, 404, 429]
          fatal_codes.any? { |code| error_message.match?(/\b#{code}\b/) }
        end

        # Extract HTTP status code from error message
        def extract_http_status_code(error_message)
          return nil unless error_message.is_a?(String)

          # Try to extract status code (e.g., "401: Unknown error" -> "401")
          match = error_message.match(/\b(401|403|404|429)\b/)
          match ? match[1].to_i : nil
        end

        def plan_next_step(context, stream: false, &block)
          planning_prompt = build_react_planning_prompt(context)

          # Simplified user message to reduce tokens
          user_message = if context.observations.empty?
                           "Query: #{context.user_query}\n\nWhat tool first? JSON: {\"tool\": \"tool_name\", \"arguments\": {...}}"
                         else
                           "Obs: #{context.observations.length}, Instrument: #{context.instrument_resolved}\n\nNext tool? JSON: {\"tool\": \"...\", \"arguments\": {...}} or {\"final\": true}"
                         end

          messages = [
            { role: 'system', content: planning_prompt },
            { role: 'user', content: user_message }
          ]

          selected_model = @react_model || if @client.provider == :ollama
                                             ENV['OLLAMA_MODEL'] || @client.selected_model || 'llama3.1:8b'
                                           else
                                             'gpt-4o'
                                           end

          if stream && block_given?
            response_chunks = +''
            begin
              Timeout.timeout(PLANNING_TIMEOUT) do
                @client.chat_stream(messages: messages, model: selected_model, temperature: 0.3) do |chunk|
                  response_chunks << chunk if chunk
                  # Don't stream planning chunks to UI
                end
              end
            rescue Timeout::Error
              Rails.logger.warn("[ReActRunner] Planning step timed out after #{PLANNING_TIMEOUT}s")
              raise
            end
            response_chunks
          else
            begin
              Timeout.timeout(PLANNING_TIMEOUT) do
                @client.chat(messages: messages, model: selected_model, temperature: 0.3)
              end
            rescue Timeout::Error
              Rails.logger.warn("[ReActRunner] Planning step timed out after #{PLANNING_TIMEOUT}s")
              raise
            end
          end
        end

        def extract_tool_call_from_plan(response)
          # Try to extract JSON tool call from response
          json_match = response.match(/\{[\s\n]*"tool"[\s\n]*:[\s\n]*"[^"]+"[\s\n]*,?[\s\n]*"arguments"[\s\n]*:[\s\n]*\{[^}]*\}/m)
          return nil unless json_match

          begin
            JSON.parse(json_match[0])
          rescue JSON::ParserError
            # Try parsing entire response
            begin
              parsed = JSON.parse(response)
              parsed if parsed['tool'] || parsed['final']
            rescue JSON::ParserError
              nil
            end
          end
        end

        def synthesize_analysis(context, stream: false, &block)
          synthesis_prompt = build_react_synthesis_prompt(context)

          messages = [
            { role: 'system', content: synthesis_prompt },
            { role: 'user', content: 'Based on all collected facts, provide the final structured analysis.' }
          ]

          selected_model = @react_model || if @client.provider == :ollama
                                             ENV['OLLAMA_MODEL'] || @client.selected_model || 'llama3.1:8b'
                                           else
                                             'gpt-4o'
                                           end

          # Use shorter timeout for synthesis (60s instead of 120s)
          synthesis_timeout = 60

          if stream && block_given?
            response_chunks = +''
            begin
              Timeout.timeout(synthesis_timeout) do
                @client.chat_stream(messages: messages, model: selected_model, temperature: 0.3) do |chunk|
                  response_chunks << chunk if chunk
                  yield(chunk) if block_given? # Stream synthesis to UI
                end
              end
            rescue Timeout::Error
              Rails.logger.warn("[ReActRunner] Synthesis timed out after #{synthesis_timeout}s")
              # Use fallback analysis when timeout occurs (response is likely incomplete)
              build_fallback_analysis(context)
            else
              # Check if response is complete enough (has JSON structure)
              if response_chunks.strip.length < 50 || !response_chunks.include?('{')
                Rails.logger.info('[ReActRunner] Response too short or incomplete, using fallback analysis')
                build_fallback_analysis(context)
              else
                response_chunks
              end
            end
          else
            begin
              Timeout.timeout(synthesis_timeout) do
                @client.chat(messages: messages, model: selected_model, temperature: 0.3)
              end
            rescue Timeout::Error
              Rails.logger.warn("[ReActRunner] Synthesis timed out after #{synthesis_timeout}s")
              # Return fallback analysis
              build_fallback_analysis(context)
            end
          end
        end

        def determine_fallback_tool(context, iteration)
          query_upper = context.user_query.upcase
          symbol = extract_symbol_from_query_fallback(context.user_query)

          # Step 1: Resolve instrument if not done
          if !context.instrument_resolved && iteration == 1 && symbol
            # Auto-detect segment (index vs equity) using helper method
            segment = detect_segment_for_symbol(symbol, nil)
            exchange = detect_exchange_for_index(symbol, nil)

            return {
              'tool' => 'get_instrument_ltp',
              'arguments' => {
                'underlying_symbol' => symbol,
                'segment' => segment,
                'exchange' => exchange
              }
            }
          end

          # Step 2: If instrument resolved, check what data we need
          if context.instrument_resolved && iteration >= 2
            # Check what tools have been called
            called_tools = context.observations.map { |obs| obs[:tool] }

            # Detect if user wants analysis/indicators (broader detection)
            wants_analysis = query_upper.include?('ANALYZE') ||
                             query_upper.include?('ANALYSIS') ||
                             query_upper.include?('INDICATOR') ||
                             query_upper.include?('RSI') ||
                             query_upper.include?('MACD') ||
                             query_upper.include?('ADX') ||
                             query_upper.include?('TECHNICAL') ||
                             query_upper.include?('SUPERTREND') ||
                             query_upper.include?('BOLLINGER') ||
                             query_upper.match?(/\b(TREND|SUPPORT|RESISTANCE|PATTERN)\b/)

            # Check if query is just asking for LTP/price (simple query)
            is_simple_ltp_query = query_upper.match?(/\b(LTP|PRICE|CURRENT|LAST)\b/) &&
                                  !wants_analysis

            # If simple LTP query and we already have LTP, proceed to synthesis
            return { 'final' => true } if is_simple_ltp_query && called_tools.include?('get_instrument_ltp')

            # If user wants analysis/indicators, fetch data and calculate indicators
            if wants_analysis
              # Step 2a: Get historical data if not already fetched
              unless called_tools.include?('get_historical_data')
                instrument_data = context.instrument_data || context.observations.find do |obs|
                  obs[:tool] == 'get_instrument_ltp'
                end&.dig(:result)
                if instrument_data
                  underlying_symbol = instrument_data['underlying_symbol'] || instrument_data[:underlying_symbol] || symbol
                  segment = instrument_data['segment'] || instrument_data[:segment] || detect_segment_for_symbol(
                    underlying_symbol, nil
                  )

                  Rails.logger.info("[ReActRunner] Fallback: Fetching historical data for #{underlying_symbol} (#{segment})")
                  return {
                    'tool' => 'get_historical_data',
                    'arguments' => {
                      'underlying_symbol' => underlying_symbol,
                      'segment' => segment,
                      'interval' => '15',
                      'days' => 3
                    }
                  }
                end
              end

              # Step 2b: Calculate indicators if we have historical data but no indicators yet
              if called_tools.include?('get_historical_data') && !called_tools.include?('calculate_indicator')
                instrument_data = context.instrument_data || context.observations.find do |obs|
                  obs[:tool] == 'get_instrument_ltp'
                end&.dig(:result)
                if instrument_data
                  symbol_key = instrument_data['underlying_symbol'] || instrument_data[:underlying_symbol] || symbol || 'NIFTY'

                  Rails.logger.info("[ReActRunner] Fallback: Calculating RSI indicator for #{symbol_key}")
                  return {
                    'tool' => 'calculate_indicator',
                    'arguments' => {
                      'index_key' => symbol_key,
                      'indicator' => 'RSI',
                      'period' => 14,
                      'interval' => '15'
                    }
                  }
                end
              end

              # Step 2c: If we have RSI, calculate additional indicators for comprehensive analysis
              if called_tools.include?('calculate_indicator') && iteration >= 3
                # Check if we've calculated multiple indicators
                indicator_calls = called_tools.count { |t| t == 'calculate_indicator' }

                # Calculate MACD if not done yet (for trend analysis)
                if indicator_calls == 1
                  instrument_data = context.instrument_data || context.observations.find do |obs|
                    obs[:tool] == 'get_instrument_ltp'
                  end&.dig(:result)
                  if instrument_data
                    symbol_key = instrument_data['underlying_symbol'] || instrument_data[:underlying_symbol] || symbol || 'NIFTY'
                    Rails.logger.info("[ReActRunner] Fallback: Calculating MACD indicator for #{symbol_key}")
                    return {
                      'tool' => 'calculate_indicator',
                      'arguments' => {
                        'index_key' => symbol_key,
                        'indicator' => 'MACD',
                        'period' => 14,
                        'interval' => '15'
                      }
                    }
                  end
                end
              end
            end

            # Only proceed to synthesis if:
            # 1. Simple LTP query and we have LTP, OR
            # 2. We have indicators/data and user didn't ask for analysis, OR
            # 3. We have sufficient data (LTP + historical + at least one indicator)
            has_sufficient_data = called_tools.include?('get_instrument_ltp') &&
                                  (is_simple_ltp_query ||
                                   (called_tools.include?('get_historical_data') && called_tools.include?('calculate_indicator')))

            return { 'final' => true } if has_sufficient_data
          end

          nil
        end

        def extract_symbol_from_query_fallback(query)
          # Simple fallback to extract symbol from query
          query_upper = query.upcase

          if query_upper.include?('NIFTY')
            'NIFTY'
          elsif query_upper.include?('BANKNIFTY')
            'BANKNIFTY'
          elsif query_upper.include?('SENSEX')
            'SENSEX'
          else
            # Try to find any uppercase word (likely symbol)
            match = query.match(/\b([A-Z]{2,10})\b/)
            match ? match[1] : nil
          end
        end

        def format_analysis_result(analysis_data)
          return nil unless analysis_data.is_a?(Hash)

          lines = []
          lines << '📊 **Analysis Result**'
          lines << ''

          # Instrument
          lines << "**Instrument:** #{analysis_data['instrument']}" if analysis_data['instrument']

          # LTP if available
          if analysis_data['ltp'] || (analysis_data['indicators'] && analysis_data['indicators'].is_a?(Hash))
            # Try to extract LTP from context if not directly in analysis
            ltp = analysis_data['ltp']
            lines << "**Current Price:** #{ltp}" if ltp
          end

          # Trend
          if analysis_data['trend']
            trend_emoji = case analysis_data['trend'].to_s.upcase
                          when 'BULLISH' then '📈'
                          when 'BEARISH' then '📉'
                          else '➡️'
                          end
            lines << "**Trend:** #{trend_emoji} #{analysis_data['trend']}"
          end

          # Indicators
          if analysis_data['indicators'] && analysis_data['indicators'].is_a?(Hash) && analysis_data['indicators'].any?
            lines << ''
            lines << '**Indicators:**'
            analysis_data['indicators'].each do |key, value|
              lines << "  - #{key}: #{value}"
            end
          end

          # Verdict
          if analysis_data['verdict']
            verdict_emoji = case analysis_data['verdict'].to_s.upcase
                            when 'BULLISH_BIAS' then '🟢'
                            when 'BEARISH_BIAS' then '🔴'
                            when 'NO_TRADE' then '⚪'
                            else '🟡'
                            end
            lines << ''
            lines << "**Verdict:** #{verdict_emoji} #{analysis_data['verdict']}"
          end

          # Recommendation
          if analysis_data['recommendation'] && analysis_data['recommendation'].is_a?(Hash)
            rec = analysis_data['recommendation']
            lines << ''
            lines << '**Recommendation:**'
            lines << "  - **Action:** #{rec['action']}" if rec['action']
            lines << "  - **Strike:** #{rec['strike_preference']}" if rec['strike_preference'].present?
            lines << "  - **Risk Note:** #{rec['risk_note']}" if rec['risk_note'].present?
          end

          # Confidence
          if analysis_data['confidence']
            confidence_pct = (analysis_data['confidence'].to_f * 100).round(1)
            lines << ''
            lines << "**Confidence:** #{confidence_pct}%"
          end

          # Reasoning
          if analysis_data['reasoning']
            lines << ''
            lines << '**Reasoning:**'
            lines << analysis_data['reasoning']
          end

          lines.join("\n")
        end

        def build_react_planning_prompt(context)
          # Show only essential tools to reduce prompt size
          essential_tools = {
            'get_instrument_ltp' => 'Get LTP for instrument (start here for instrument resolution)',
            'get_ohlc' => 'Get OHLC data for instrument',
            'get_historical_data' => 'Get historical candle data',
            'calculate_indicator' => 'Calculate technical indicator (RSI, MACD, ADX, Supertrend, ATR, BollingerBands)',
            'analyze_option_chain' => 'Analyze option chain for derivatives'
          }

          tools_summary = essential_tools.map { |name, desc| "- #{name}: #{desc}" }.join("\n")

          <<~PROMPT
            You are a technical analysis agent. Decide which tool to call next.

            RULES:
            1. You CANNOT fetch data or compute indicators - you MUST use tools
            2. Call tools one at a time based on what you need
            3. Start with instrument resolution (get_instrument_ltp or get_ohlc)

            Available tools:
            #{tools_summary}

            Current context:
            - Query: #{context.user_query}
            - Observations: #{context.observations.length}
            - Instrument resolved: #{context.instrument_resolved}

            Respond with ONLY JSON (no markdown, no explanation):
            {"tool": "tool_name", "arguments": {...}} OR {"final": true}

            Example: {"tool": "get_instrument_ltp", "arguments": {"underlying_symbol": "NIFTY", "segment": "index"}}
          PROMPT
        end

        def build_react_synthesis_prompt(context)
          # Determine instrument type from collected data
          instrument_data = context.instrument_data || context.observations.find do |obs|
            obs[:tool] == 'get_instrument_ltp'
          end&.dig(:result)
          instrument_type = if instrument_data
                              segment = instrument_data['segment'] || instrument_data[:segment] || ''
                              symbol = (instrument_data['underlying_symbol'] || instrument_data[:underlying_symbol] || '').to_s.upcase
                              if segment == 'index' || %w[NIFTY BANKNIFTY SENSEX].include?(symbol)
                                'index'
                              else
                                'stock'
                              end
                            else
                              'unknown'
                            end

          # Build concise observations summary
          observations_summary = context.observations.map do |obs|
            if obs[:result][:error]
              "#{obs[:tool]}: ERROR"
            else
              # Extract key values only
              result = obs[:result]
              key_data = []
              key_data << "LTP: #{result['ltp'] || result[:ltp]}" if result['ltp'] || result[:ltp]
              if obs[:tool] == 'calculate_indicator' && (result['indicator'] == 'rsi' || result[:indicator] == 'rsi')
                key_data << "RSI: #{result['value'] || result[:value]}"
              end
              key_data << "Candles: #{result['count'] || result[:count]}" if result['count'] || result[:count]
              "#{obs[:tool]}: #{key_data.join(', ') || 'OK'}"
            end
          end.join("\n")

          # Build recommendation guidance based on instrument type
          recommendation_guidance = if instrument_type == 'index'
                                      <<~GUIDANCE
                                        RECOMMENDATION GUIDANCE FOR INDICES (NIFTY, BANKNIFTY, SENSEX):
                                        - Focus on OPTIONS TRADING strategies
                                        - Actions: "BUY_CALLS" (bullish) or "BUY_PUTS" (bearish)
                                        - Strike preferences: "ATM", "ATM+1", "ATM-1", "OTM+1", etc.
                                        - Risk notes: Include IV considerations, expiry timing, stop-loss levels
                                        - Timeframe: Short-term (intraday to weekly expiry)
                                        - Example: {"action": "BUY_CALLS", "strike_preference": "ATM+1", "risk_note": "Target: 2-3x premium, Stop: 50% premium loss. Avoid post 2:30pm IV crush"}
                                      GUIDANCE
                                    elsif instrument_type == 'stock'
                                      <<~GUIDANCE
                                        RECOMMENDATION GUIDANCE FOR STOCKS:
                                        - Focus on SWING TRADING, LONG-TERM INVESTMENT, PORTFOLIO BUILDING
                                        - Actions: "BUY" (for swing/long-term), "SELL" (for profit booking), "HOLD" (for existing positions), "NO_TRADE" (if uncertain)
                                        - Strike preferences: Not applicable (leave empty "")
                                        - Risk notes: Include entry levels, target prices, stop-loss, holding period, portfolio allocation
                                        - Timeframe: Medium to long-term (weeks to months)
                                        - Example: {"action": "BUY", "strike_preference": "", "risk_note": "Entry: Current LTP, Target: +15% (3 months), Stop: -8%, Allocation: 5% of portfolio"}
                                      GUIDANCE
                                    else
                                      <<~GUIDANCE
                                        RECOMMENDATION GUIDANCE:
                                        - If instrument type unknown, use "NO_TRADE"
                                        - Provide conservative recommendation
                                      GUIDANCE
                                    end

          <<~PROMPT
            Synthesize collected facts into structured JSON analysis.

            Query: #{context.user_query}
            Instrument Type: #{instrument_type.upcase}
            Facts:
            #{observations_summary}

            #{recommendation_guidance}

            Respond with ONLY this JSON (no markdown, no explanation):
            {
              "instrument": "SYMBOL",
              "analysis_type": "TECHNICAL" | "TECHNICAL + DERIVATIVES",
              "timeframes_used": ["5m", "15m", "1h"],
              "trend": "Bullish" | "Bearish" | "Neutral",
              "indicators": {
                "RSI_5m": 62.1,
                "ADX_15m": 29.4,
                "Supertrend_15m": "Bullish"
              },
              "derivatives": {
                "near_expiry_bias": "CALL_OI_BUILD" | "PUT_OI_BUILD" | "NEUTRAL",
                "pcr": 0.84
              },
              "verdict": "BULLISH_BIAS" | "BEARISH_BIAS" | "NEUTRAL" | "NO_TRADE",
              "recommendation": {
                "action": "BUY_CALLS" | "BUY_PUTS" | "BUY" | "SELL" | "HOLD" | "NO_TRADE",
                "strike_preference": "ATM+1" | "" (empty for stocks),
                "risk_note": "Detailed risk and strategy note"
              },
              "confidence": 0.71,
              "reasoning": "Brief explanation of the analysis"
            }

            CRITICAL RULES:
            1. If confidence < 0.6, verdict MUST be "NO_TRADE"
            2. If critical data missing, verdict MUST be "NO_TRADE"
            3. For INDICES: recommendation.action should be "BUY_CALLS" or "BUY_PUTS" (options trading)
            4. For STOCKS: recommendation.action should be "BUY", "SELL", "HOLD", or "NO_TRADE" (swing/long-term)
            5. Only use values from facts, no assumptions
            6. strike_preference should be empty "" for stocks
          PROMPT
        end

        def build_fallback_analysis(context)
          # Build a simple analysis from collected data when LLM times out
          instrument_data = context.instrument_data || context.observations.find do |obs|
            obs[:tool] == 'get_instrument_ltp'
          end&.dig(:result)

          if instrument_data
            symbol = instrument_data['underlying_symbol'] || instrument_data[:underlying_symbol] || 'UNKNOWN'
            ltp = instrument_data['ltp'] || instrument_data[:ltp]
            segment = instrument_data['segment'] || instrument_data[:segment] || ''
            symbol_upper = symbol.to_s.upcase

            # Determine if index or stock
            is_index = segment == 'index' || %w[NIFTY BANKNIFTY SENSEX].include?(symbol_upper)

            # Build recommendation based on instrument type
            recommendation = if is_index
                               {
                                 'action' => 'NO_TRADE',
                                 'strike_preference' => '',
                                 'risk_note' => 'Insufficient data - only LTP available. Technical indicators not calculated. Options trading requires indicator confirmation.'
                               }
                             else
                               {
                                 'action' => 'NO_TRADE',
                                 'strike_preference' => '',
                                 'risk_note' => 'Insufficient data - only LTP available. Technical indicators not calculated. Swing/long-term investment requires comprehensive analysis.'
                               }
                             end

            {
              'instrument' => symbol,
              'analysis_type' => is_index ? 'TECHNICAL + DERIVATIVES' : 'TECHNICAL',
              'timeframes_used' => [],
              'trend' => 'Neutral',
              'indicators' => {},
              'derivatives' => is_index ? { 'near_expiry_bias' => 'NEUTRAL', 'pcr' => 0.0 } : nil,
              'verdict' => 'NO_TRADE',
              'recommendation' => recommendation,
              'confidence' => 0.3,
              'reasoning' => "Analysis incomplete: Only LTP data collected (#{ltp}). Technical indicators were not calculated due to planning timeouts. Recommendation: NO_TRADE due to insufficient data."
            }.compact.to_json
          else
            {
              'instrument' => 'UNKNOWN',
              'verdict' => 'NO_TRADE',
              'confidence' => 0.0,
              'reasoning' => 'No data collected - analysis failed'
            }.to_json
          end
        end
      end
    end
  end
end
