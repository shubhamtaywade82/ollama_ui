# frozen_string_literal: true

# Implements Plan-Execute-Observe-Refine loop for iterative agent behavior
class IterativeAgentExecutor
  MAX_ITERATIONS = 5

  def initialize(prompt:)
    @prompt = prompt
    @user_prompt = prompt.downcase
    @plan = []
    @observations = []
    @execution_results = []
    @iteration = 0
  end

  def execute
    loop do
      @iteration += 1
      break if @iteration > MAX_ITERATIONS

      # PLAN: Generate or refine plan
      refine_plan unless @plan.any?

      # EXECUTE: Try to execute the plan
      result = execute_current_step

      # OBSERVE: Analyze the result
      observation = observe_result(result)

      # REFINE: Decide if we need to adjust
      break if should_complete?(observation)

      refine_plan_based_on(observation) unless result[:success]
    end

    compile_final_result
  end

  private

  def refine_plan
    # Use LLM to generate a plan
    plan_prompt = <<~PROMPT
      User request: "#{@prompt}"

      Available tools: #{DhanAgentToolMapper.tools_for_llm.map { |t| t[:name] }.join(', ')}

      Generate a step-by-step plan to fulfill this request.
      Return JSON array:
      [
        {"step": 1, "tool": "tool_name", "params": {}, "description": "..."},
        {"step": 2, "tool": "tool_name", "params": {}, "description": "..."}
      ]
    PROMPT

    ai_response = OllamaClient.new.chat(
      model: 'qwen2.5:1.5b-instruct',
      prompt: plan_prompt
    )

    @plan = parse_plan(ai_response)
  rescue StandardError => e
    Rails.logger.error "Plan generation failed: #{e.message}"
    @plan = generate_fallback_plan
  end

  def parse_plan(ai_response)
    json_match = ai_response.match(/\[[\s\S]*\]/)
    return generate_fallback_plan unless json_match

    JSON.parse(json_match[0])
  rescue JSON::ParserError
    generate_fallback_plan
  end

  def generate_fallback_plan
    # Fallback to simple plan based on keywords
    if @user_prompt.include?('option') && @user_prompt.include?('chain')
      [
        { step: 1, tool: 'search_instrument', params: {}, description: 'Find the underlying instrument' },
        { step: 2, tool: 'get_option_chain', params: {}, description: 'Fetch option chain' }
      ]
    elsif @user_prompt.include?('quote') || @user_prompt.include?('price')
      [
        { step: 1, tool: 'search_instrument', params: {}, description: 'Find the symbol' },
        { step: 2, tool: 'get_live_quote', params: {}, description: 'Get live quote' }
      ]
    else
      [{ step: 1, tool: 'general_help', params: {}, description: 'Provide help' }]
    end
  end

  def execute_current_step
    current_step = @plan[@execution_results.length]
    return { success: true, result: 'No more steps' } unless current_step

    Rails.logger.info "Executing step #{current_step[:step]}: #{current_step[:description]}"

    # Extract params from previous results
    enriched_params = enrich_params(current_step[:params])

    # Execute the tool
    result = execute_step_tool(current_step[:tool], enriched_params)
    @execution_results << { step: current_step, result: result }
    result
  rescue StandardError => e
    {
      success: false,
      error: e.message,
      result: nil
    }
  end

  def execute_step_tool(tool_name, _params)
    case tool_name.to_s
    when /search_instrument/
      symbol = extract_symbol_from_prompt
      DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)
    when /get_option_chain/
      # Use previous result (instrument)
      instrument = find_previous_result_of_type(:instrument)
      return { error: 'Instrument not found' } unless instrument

      DhanHQ::Models::OptionChain.fetch(
        underlying_scrip: instrument.security_id.to_s,
        underlying_seg: instrument.exchange_segment,
        expiry: nil
      )
    when /get_live_quote/
      instrument = find_previous_result_of_type(:instrument)
      return { error: 'Instrument not found' } unless instrument

      DhanHQ::Models::MarketFeed.quote(
        instrument.exchange_segment => [instrument.security_id.to_i]
      )
    when /get_account_balance/
      DhanHQ::Models::Funds.fetch
    when /get_positions/
      DhanHQ::Models::Position.all
    when /get_holdings/
      DhanHQ::Models::Holding.all
    else
      { error: "Unknown tool: #{tool_name}" }
    end
  end

  def find_previous_result_of_type(_type)
    # Find instrument from previous results
    @execution_results.reverse_each do |result|
      next unless result[:result]
      next unless result[:result].is_a?(DhanHQ::Models::Instrument)

      return result[:result]
    end
    nil
  end

  def enrich_params(params)
    # Enrich params based on previous results and prompt
    enriched = params.dup || {}
    enriched[:symbol] ||= extract_symbol_from_prompt if params.empty?
    enriched
  end

  def observe_result(result)
    {
      success: !result[:error],
      has_data: result.present?,
      complete: check_completeness(result),
      observations: analyze_result(result)
    }
  end

  def analyze_result(result)
    observations = []

    if result.is_a?(DhanHQ::Models::Instrument)
      observations << "Found instrument: #{result.symbol_name} (ID: #{result.security_id})"
    end

    observations << 'Retrieved data successfully' if result.is_a?(Hash) && result[:data]

    observations << "Retrieved #{result.length} items" if result.is_a?(Array)

    observations
  end

  def check_completeness(result)
    # Check if we have enough data to complete the request
    return true if @prompt.include?('option chain') && result.is_a?(Hash) && result[:data]

    return true if @prompt.include?('quote') && result.is_a?(Hash) && result[:data]

    false
  end

  def should_complete?(observation)
    observation[:success] && observation[:complete]
  end

  def refine_plan_based_on(observation)
    # If last step failed, try an alternative approach
    Rails.logger.info "Previous step failed, refining plan... Observations: #{observation[:observations]}"

    return unless @plan.length.positive? && @execution_results.last

    failed_step = @execution_results.last[:step]
    # Try alternative tool for this step
    alternative_tool = suggest_alternative(failed_step[:tool])
    @plan[@execution_results.length - 1][:tool] = alternative_tool if alternative_tool
  end

  def suggest_alternative(tool_name)
    case tool_name.to_s
    when /search_instrument/
      'get_instruments_by_segment'
    when /get_option_chain/
      'search_instrument' # Maybe need to find instrument first
    end
  end

  def compile_final_result
    if @execution_results.empty?
      return {
        type: :error,
        message: 'Failed to execute',
        formatted: '❌ Could not fulfill request'
      }
    end

    final_result = @execution_results.last[:result]

    {
      type: :success,
      message: "Completed in #{@execution_results.length} steps",
      data: final_result,
      formatted: format_result(final_result),
      plan: @plan,
      steps_taken: @execution_results.length
    }
  end

  def format_result(result)
    return format_instrument(result) if result.is_a?(DhanHQ::Models::Instrument)

    if result.is_a?(Hash)
      if result[:data].is_a?(Hash)
        # Option chain or quote
        return format_option_chain_or_quote(result)
      end

      return "<pre>#{JSON.pretty_generate(result)}</pre>"
    end

    return "<pre>Found #{result.length} items</pre>" if result.is_a?(Array)

    result.to_s
  end

  def format_instrument(inst)
    <<~HTML
      <div class="bg-gradient-to-r from-blue-50 to-purple-50 p-4 rounded-lg">
        <h3>#{inst.symbol_name}</h3>
        <p>Security ID: #{inst.security_id}</p>
        <p>Exchange: #{inst.exchange_segment}</p>
      </div>
    HTML
  end

  def format_option_chain_or_quote(result)
    # Generic formatting
    "<pre>#{JSON.pretty_generate(result)}</pre>"
  end

  def extract_symbol_from_prompt
    patterns = [
      /(?:for|of|is)\s+([A-Z]{3,})/i,
      /\b([A-Z]{3,})\b/
    ]

    patterns.each do |pattern|
      match = @prompt.match(pattern)
      return match[1].upcase if match
    end

    nil
  end
end
