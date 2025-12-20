# frozen_string_literal: true

require 'timeout'

# Load all modules
require_relative 'technical_analysis_agent/helpers'
require_relative 'technical_analysis_agent/prompt_builder'
require_relative 'technical_analysis_agent/learning'
require_relative 'technical_analysis_agent/tool_registry'
require_relative 'technical_analysis_agent/tool_executor'
require_relative 'technical_analysis_agent/conversation_executor'
require_relative 'technical_analysis_agent/tools'

module Services
  module Ai
    # Technical Analysis Agent with Function Calling
    # Integrates with instruments, DhanHQ, indicators, and trading tools
    class TechnicalAnalysisAgent
      # Include all modules
      include Helpers
      include PromptBuilder
      include Learning
      include ToolRegistry
      include ToolExecutor
      include ConversationExecutor
      include Tools

      class << self
        def analyze(query:, stream: false, &)
          new.analyze(query: query, stream: stream, &)
        end
      end

      def initialize
        @client = Services::Ai::OpenaiClient.instance
        @tools = build_tools_registry
        @tool_cache = {} # Cache tool results within conversation
        @index_config_cache = nil # Cache index configs
        @analyzer_cache = {} # Cache analyzer instances
        @error_history = [] # Track errors in current conversation for learning
        @learned_patterns = load_learned_patterns # Load learned patterns from storage
      end

      def analyze(query:, stream: false, &)
        return nil unless @client.enabled?

        # Clear caches for new conversation
        @tool_cache = {}
        @index_config_cache = nil
        @analyzer_cache = {}
        @error_history = []
        @current_query_keywords = extract_keywords(query) # Store for error learning

        # Build system prompt with available tools
        system_prompt = build_system_prompt

        # Truncate user query if too long (max 2000 chars ≈ 500 tokens)
        max_query_length = ENV.fetch('AI_MAX_QUERY_LENGTH', '2000').to_i
        if query.length > max_query_length
          Rails.logger.warn("[TechnicalAnalysisAgent] User query truncated from #{query.length} to #{max_query_length} characters")
          query = query[0..max_query_length - 1] + '... [truncated]'
        end

        # Add current date context to user query
        current_date = Time.zone.today.strftime('%Y-%m-%d')
        enhanced_query = "#{query}\n\nIMPORTANT: Today's date is #{current_date}. Always use current dates (not past dates like 2023)."

        # Add learned patterns to system prompt if available (but limit size)
        if @learned_patterns.any?
          learned_context = build_learned_context
          # Limit learned context to prevent bloat (max 500 chars)
          if learned_context.present? && learned_context.length > 500
            learned_context = learned_context[0..500] + '... [truncated]'
          end
          system_prompt += "\n\n#{learned_context}" if learned_context.present?
        end

        # Check prompt size and warn if too large
        estimated_tokens = estimate_prompt_tokens(system_prompt + enhanced_query)
        max_tokens = ENV.fetch('AI_MAX_INITIAL_TOKENS', '3000').to_i
        if estimated_tokens > max_tokens
          Rails.logger.warn("[TechnicalAnalysisAgent] Large initial prompt detected: ~#{estimated_tokens} tokens (max: #{max_tokens}). This may cause slow responses.")
          # Truncate system prompt if extremely large
          if system_prompt.length > 5000
            system_prompt = system_prompt[0..5000] + '... [system prompt truncated]'
            Rails.logger.warn("[TechnicalAnalysisAgent] System prompt truncated to 5000 characters")
          end
        end

        # Initial user query
        messages = [
          { role: 'system', content: system_prompt },
          { role: 'user', content: enhanced_query }
        ]

        # Auto-select model (prefer faster models for agent)
        model = if @client.provider == :ollama
                  # For agent, prefer faster models - llama3.1:8b is good balance
                  ENV['OLLAMA_MODEL'] || @client.selected_model || 'llama3.1:8b'
                else
                  'gpt-4o'
                end

        # No max_iterations limit - agent will iterate until it provides a final analysis
        # Safety limits are built into execute_conversation methods

        # Execute conversation with function calling
        if stream && block_given?
          execute_conversation_stream(messages: messages, model: model, &)
        else
          execute_conversation(messages: messages, model: model)
        end
      end
    end
  end
end
