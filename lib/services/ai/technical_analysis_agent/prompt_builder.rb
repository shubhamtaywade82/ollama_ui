# frozen_string_literal: true

module Services
  module Ai
    class TechnicalAnalysisAgent
      # Handles building and formatting prompts for the AI agent
      module PromptBuilder
        # Minimal planning prompt - just enough to understand the task
        def build_planning_prompt
          <<~PROMPT
            You are a technical analysis agent for Indian markets (NIFTY, BANKNIFTY, SENSEX, stocks like RELIANCE, TCS).

            Your task: Analyze the user's query and create a step-by-step plan.

            Available tool categories:
            - Market data: get_comprehensive_analysis, get_index_ltp, get_instrument_ltp, get_ohlc, get_historical_data
            - Indicators: calculate_indicator (RSI, MACD, ADX, Supertrend, ATR, BollingerBands)
            - Advanced: calculate_advanced_indicator (HolyGrail, TrendDuration)
            - Trading: get_trading_stats, get_active_positions
            - Options: analyze_option_chain
            - Analysis: run_backtest, optimize_indicator

            Create a plan with 2-4 steps. Each step should specify:
            1. Which tool to use
            2. What parameters (symbol, indicator, etc.)
            3. What you expect to learn

            Respond with ONLY a JSON plan:
            {"plan": [{"step": 1, "tool": "tool_name", "params": {...}, "purpose": "..."}, ...]}
          PROMPT
        end

        # Small execution prompt - focused on current step
        def build_execution_prompt(step_info, available_tools_for_step)
          tool_name = step_info['tool']
          tool_def = @tools[tool_name]

          return nil unless tool_def

          # Build minimal tool description
          params_list = tool_def[:parameters].map { |p| "#{p[:name]}(#{p[:type]})" }.join(', ')

          <<~PROMPT
            Execute step #{step_info['step']}: #{step_info['purpose']}

            Tool: #{tool_name}
            Description: #{tool_def[:description].split('.').first}
            Parameters: #{params_list}

            Required params: #{step_info['params'].to_json}

            Call the tool with ONLY JSON (no explanations):
            {"tool": "#{tool_name}", "arguments": #{step_info['params'].to_json}}
          PROMPT
        end

        # Small analysis prompt - synthesize results
        def build_analysis_prompt(plan, results_summary)
          <<~PROMPT
            Synthesize the analysis results into a complete answer.

            Original query context: #{plan['original_query']}

            Results summary:
            #{results_summary}

            Provide a comprehensive analysis with:
            1. Key findings
            2. Indicator interpretations
            3. Actionable insights
            4. Recommendations

            If you need more data, specify which tool and params to call next.
            Otherwise, provide the final analysis.
          PROMPT
        end

        # Legacy full system prompt (kept for backward compatibility, but minimized)
        def build_system_prompt
          <<~PROMPT
            Technical analysis agent for Indian markets.

            SEGMENT: Indices="index", Stocks="equity". Auto-detected.

            EFFICIENCY: Use 'get_comprehensive_analysis' for all data in ONE call.

            TOOLS: #{format_tools_for_prompt_concise}

            INDICATORS:
            - RSI: <30 oversold, >70 overbought, 40-60 neutral
            - MACD: Positive+histogram=bullish, Negative+histogram=bearish
            - ADX: <20 weak, 20-40 moderate, >40 strong trend
            - Supertrend: "long_entry"=bullish, "short_entry"=bearish
            - ATR: Volatility measure
            - Bollinger: Near upper=overbought, near lower=oversold

            RULES:
            1. Use MULTIPLE indicators - look for CONFLUENCE
            2. ADX=strength, Supertrend/MACD=direction
            3. Explain conflicts based on trend context

            FORMAT: {"tool": "name", "arguments": {...}}

            CRITICAL:
            1. Call tools - respond with ONLY JSON for tool calls
            2. After results, provide analysis in natural language
            3. Use CURRENT dates (today: #{Time.zone.today.strftime('%Y-%m-%d')})
          PROMPT
        end

        def format_tools_for_prompt
          @tools.map do |tool_name, tool_def|
            params = tool_def[:parameters].map { |p| "  - #{p[:name]} (#{p[:type]}): #{p[:description]}" }.join("\n")
            <<~TOOL
              **#{tool_name}**
              #{tool_def[:description]}
              Parameters:
              #{params}
            TOOL
          end.join("\n\n")
        end

        # Concise version for smaller prompts
        def format_tools_for_prompt_concise
          @tools.map do |tool_name, tool_def|
            # Shorten descriptions and parameters
            short_desc = tool_def[:description].split('.').first # First sentence only
            params = tool_def[:parameters].map { |p| "#{p[:name]}(#{p[:type]})" }.join(', ')
            "#{tool_name}: #{short_desc}. Params: #{params}"
          end.join("\n")
        end
      end
    end
  end
end
