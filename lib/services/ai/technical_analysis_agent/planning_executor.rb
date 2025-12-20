# frozen_string_literal: true

module Services
  module Ai
    class TechnicalAnalysisAgent
      # Planning-based executor: Plan → Execute → Analyze → Loop
      # Uses smaller prompts for better performance
      module PlanningExecutor
        def execute_planning_loop(query:, stream: false, &)
          # Phase 1: Planning (small prompt)
          plan = create_plan(query, stream: stream, &)
          return nil unless plan && plan['plan']&.any?

          # Phase 2: Execute plan steps
          results = execute_plan_steps(plan, stream: stream, &)

          # Phase 3: Synthesize results
          final_analysis = synthesize_results(query, plan, results, stream: stream, &)

          {
            analysis: final_analysis,
            plan: plan,
            results: results,
            generated_at: Time.current,
            provider: @client.provider
          }
        rescue StandardError => e
          error_msg = "[Agent] Error: #{e.class} - #{e.message}"
          yield(error_msg) if block_given?
          Rails.logger.error("[TechnicalAnalysisAgent] Planning loop error: #{e.class} - #{e.message}")
          Rails.logger.error("[TechnicalAnalysisAgent] Backtrace: #{e.backtrace.first(5).join("\n")}")
          nil
        end

        private

        def create_plan(query, stream: false, &_block)
          yield("📋 [Planning] Creating analysis plan...\n") if block_given?

          planning_prompt = build_planning_prompt
          user_message = "User query: #{query}\n\nCreate a step-by-step plan to analyze this query."

          messages = [
            { role: 'system', content: planning_prompt },
            { role: 'user', content: user_message }
          ]

          model = if @client.provider == :ollama
                    ENV['OLLAMA_MODEL'] || @client.selected_model || 'llama3.1:8b'
                  else
                    'gpt-4o'
                  end

          plan_response = if stream && block_given?
                            response_chunks = +''
                            @client.chat_stream(messages: messages, model: model, temperature: 0.3) do |chunk|
                              response_chunks << chunk if chunk
                              # Don't yield raw plan JSON chunks - only yield progress messages
                            end
                            response_chunks
                          else
                            @client.chat(messages: messages, model: model, temperature: 0.3)
                          end

          # Extract plan from response
          plan = extract_plan_from_response(plan_response)

          if plan && plan['plan']&.any?
            yield("✅ [Planning] Plan created with #{plan['plan'].length} steps\n") if block_given?
            plan['original_query'] = query
            plan
          else
            yield("⚠️  [Planning] Failed to create plan, falling back to direct execution\n") if block_given?
            # Fallback: create simple plan
            {
              'plan' => [
                {
                  'step' => 1,
                  'tool' => 'get_comprehensive_analysis',
                  'params' => extract_symbol_from_query(query),
                  'purpose' => 'Get comprehensive market data and indicators'
                }
              ],
              'original_query' => query
            }
          end
        end

        def execute_plan_steps(plan, stream: false, &_block)
          results = []
          plan_steps = plan['plan'] || []

          plan_steps.each_with_index do |step_info, idx|
            step_num = idx + 1
            total_steps = plan_steps.length

            yield("⚙️  [Step #{step_num}/#{total_steps}] Executing: #{step_info['purpose']}\n") if block_given?

            # Build execution prompt for this step
            execution_prompt = build_execution_prompt(step_info, [step_info['tool']])
            next unless execution_prompt

            messages = [
              { role: 'system', content: execution_prompt },
              { role: 'user', content: 'Execute this step now.' }
            ]

            model = if @client.provider == :ollama
                      ENV['OLLAMA_MODEL'] || @client.selected_model || 'llama3.1:8b'
                    else
                      'gpt-4o'
                    end

            # Get tool call from LLM
            step_response = if stream && block_given?
                              response_chunks = +''
                              @client.chat_stream(messages: messages, model: model, temperature: 0.3) do |chunk|
                                response_chunks << chunk if chunk
                              end
                              response_chunks
                            else
                              @client.chat(messages: messages, model: model, temperature: 0.3)
                            end

            # Extract and execute tool call
            tool_call = extract_tool_call(step_response)
            if tool_call
              yield("🔧 [Step #{step_num}] Tool: #{tool_call['tool']}\n") if block_given?

              # Execute tool
              tool_result = execute_tool(tool_call)

              results << {
                step: step_num,
                tool: tool_call['tool'],
                result: tool_result,
                purpose: step_info['purpose']
              }

              yield("✅ [Step #{step_num}] Completed\n") if block_given?
            else
              yield("⚠️  [Step #{step_num}] No tool call detected\n") if block_given?
              results << {
                step: step_num,
                tool: nil,
                result: { error: 'No tool call in response' },
                purpose: step_info['purpose']
              }
            end
          end

          results
        end

        def synthesize_results(_query, plan, results, stream: false, &_block)
          yield("📊 [Synthesis] Analyzing results...\n") if block_given?

          # Build results summary
          results_summary = results.map do |r|
            result_preview = if r[:result].is_a?(Hash) && r[:result][:error]
                               "Error: #{r[:result][:error]}"
                             elsif r[:result].is_a?(Hash)
                               # Extract key data points
                               keys = r[:result].keys.first(5)
                               "#{keys.join(', ')}: #{r[:result].slice(*keys).to_json[0..200]}..."
                             else
                               r[:result].to_s[0..200]
                             end

            "Step #{r[:step]} (#{r[:tool]}): #{result_preview}"
          end.join("\n")

          analysis_prompt = build_analysis_prompt(plan, results_summary)

          messages = [
            { role: 'system', content: analysis_prompt },
            { role: 'user', content: 'Provide the final comprehensive analysis now.' }
          ]

          model = if @client.provider == :ollama
                    ENV['OLLAMA_MODEL'] || @client.selected_model || 'llama3.1:8b'
                  else
                    'gpt-4o'
                  end

          final_analysis = if stream && block_given?
                             response_chunks = +''
                             @client.chat_stream(messages: messages, model: model, temperature: 0.3) do |chunk|
                               response_chunks << chunk if chunk
                               yield(chunk) if block_given?
                             end
                             response_chunks
                           else
                             @client.chat(messages: messages, model: model, temperature: 0.3)
                           end

          yield("\n✅ [Synthesis] Analysis complete\n") if block_given?
          final_analysis
        end

        def extract_plan_from_response(response)
          # Try to extract JSON plan from response
          json_match = response.match(/\{[\s\n]*"plan"[\s\n]*:[\s\n]*\[.*?\]/m)
          return nil unless json_match

          begin
            # Try to find complete JSON object
            json_str = json_match[0]
            # Try to close the JSON properly
            json_str += '}' unless json_str.include?('}')
            JSON.parse(json_str)
          rescue JSON::ParserError
            # Try alternative extraction
            begin
              JSON.parse(response)
            rescue JSON::ParserError
              nil
            end
          end
        end

        def extract_symbol_from_query(query)
          # Simple extraction - look for common symbols
          query_upper = query.upcase

          if query_upper.include?('NIFTY')
            { 'underlying_symbol' => 'NIFTY', 'segment' => 'index', 'exchange' => 'NSE' }
          elsif query_upper.include?('BANKNIFTY')
            { 'underlying_symbol' => 'BANKNIFTY', 'segment' => 'index', 'exchange' => 'NSE' }
          elsif query_upper.include?('SENSEX')
            { 'underlying_symbol' => 'SENSEX', 'segment' => 'index', 'exchange' => 'BSE' }
          else
            # Try to extract any uppercase word (likely symbol)
            symbol_match = query.match(/\b([A-Z]{2,10})\b/)
            if symbol_match
              { 'underlying_symbol' => symbol_match[1], 'segment' => 'equity', 'exchange' => 'NSE' }
            else
              { 'underlying_symbol' => 'NIFTY', 'segment' => 'index', 'exchange' => 'NSE' } # Default
            end
          end
        end
      end
    end
  end
end
