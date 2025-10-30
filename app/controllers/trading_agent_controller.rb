# frozen_string_literal: true

# Trading agent controller - handles agentic loop execution
class TradingAgentController < ApplicationController
  protect_from_forgery with: :null_session

  # Run the trading agent with a goal
  # POST /trading_agent/run
  # Body: { "goal": "Scan NIFTY for long CE opportunities..." }
  def run
    goal = params[:goal].to_s.strip

    return render json: { error: 'goal parameter required' }, status: :unprocessable_entity if goal.blank?

    Rails.logger.info "🎯 Trading Agent Request: #{goal}"

    # Run the agent
    result = Trading::AgentRunner.new(goal: goal).run

    # Store execution for audit (optional)
    # TradingAgentExecution.create(goal: goal, result: result) if defined?(TradingAgentExecution)

    if result[:ok]
      render json: {
        success: true,
        goal: goal,
        steps_taken: result[:steps_taken],
        steps: result[:steps],
        note: result[:note],
        summary: summarize_execution(result)
      }
    else
      render json: {
        success: false,
        error: result[:error],
        steps_taken: result[:steps_taken],
        steps: result[:steps]
      }, status: :internal_server_error
    end
  rescue StandardError => e
    Rails.logger.error "❌ Trading Agent Controller error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    render json: {
      success: false,
      error: e.message
    }, status: :internal_server_error
  end

  private

  # Summarize execution result for UI
  def summarize_execution(result)
    return {} if result[:steps].empty?

    last_step = result[:steps].last
    last_obs = last_step[:observation] || {}

    {
      final_tool: last_step[:tool_call]['tool'],
      final_status: last_obs[:ok] ? 'success' : 'error',
      final_hint: last_obs[:hint],
      tools_used: result[:steps].map { |s| s[:tool_call]['tool'] }.uniq
    }
  end
end
