# frozen_string_literal: true

module Services
  module Ai
    class TechnicalAnalysisAgent
      # AgentContext: Rails-owned fact accumulator for ReAct loop
      # Stores only deterministic tool results, no LLM reasoning
      class AgentContext
        attr_reader :user_query, :observations, :instrument_resolved, :started_at, :instrument_data

        def initialize(user_query:)
          @user_query = user_query
          @observations = [] # Array of { tool: String, input: Hash, result: Hash, timestamp: Time }
          @instrument_resolved = false
          @instrument_data = nil
          @started_at = Time.current
        end

        # Add observation from tool execution
        def add_observation(tool_name, tool_input, tool_result)
          # Normalize tool_result to handle both symbol and string keys
          normalized_result = tool_result.is_a?(Hash) ? tool_result.deep_stringify_keys : tool_result

          observation = {
            tool: tool_name.to_s,
            input: tool_input.deep_stringify_keys,
            result: normalized_result,
            timestamp: Time.current
          }
          @observations << observation

          # Track instrument resolution
          # Check for error using both symbol and string keys for compatibility
          error_present = if normalized_result.is_a?(Hash)
                            normalized_result['error'].present? || normalized_result[:error].present?
                          else
                            false
                          end

          if tool_name.to_s.in?(%w[get_instrument_ltp get_ohlc get_comprehensive_analysis]) && !error_present
            @instrument_resolved = true
            @instrument_data = normalized_result
          end

          observation
        end

        # Get all facts as JSON (for LLM reasoning)
        def facts_summary
          {
            user_query: @user_query,
            instrument_resolved: @instrument_resolved,
            observations_count: @observations.length,
            observations: @observations.map do |obs|
              {
                tool: obs[:tool],
                result_preview: summarize_result(obs[:result])
              }
            end
          }
        end

        # Get full context for final synthesis
        def full_context
          {
            user_query: @user_query,
            instrument_resolved: @instrument_resolved,
            instrument_data: @instrument_data,
            observations: @observations,
            elapsed_seconds: (Time.current - @started_at).round(2)
          }
        end

        # Check if we have enough data for analysis
        def ready_for_analysis?
          return false unless @instrument_resolved
          return false if @observations.empty?

          # Must have at least price context (LTP or OHLC)
          @observations.any? do |obs|
            tool_name = obs[:tool] || obs['tool']
            result = obs[:result] || obs['result']
            next false unless tool_name && result

            tool_name.to_s.in?(%w[get_instrument_ltp get_ohlc get_comprehensive_analysis]) &&
              (result.is_a?(Hash) ? (result['error'].blank? && result[:error].blank?) : true)
          end
        end

        # Check termination conditions
        def should_terminate?(max_iterations: 10, max_time_seconds: 300)
          return true if @observations.length >= max_iterations
          return true if (Time.current - @started_at) > max_time_seconds
          return true if ready_for_analysis? && @observations.length >= 3 # Minimum viable analysis

          false
        end

        private

        def summarize_result(result)
          return 'ERROR' if result.is_a?(Hash) && (result['error'].present? || result[:error].present?)

          # Extract key fields for preview
          return result.to_s[0..200] unless result.is_a?(Hash)

          keys = result.keys.first(5)
          result.slice(*keys).to_json[0..200]
        end
      end
    end
  end
end
