# frozen_string_literal: true

# AgentRouter: Intelligently routes queries to appropriate agents or direct LLM
class AgentRouter
  TRADING_KEYWORDS = %w[
    nifty banknifty sensex reliance tcs infy hdfc icici
    stock equity index option call put strike premium
    ltp price quote ohlc candle indicator rsi macd adx
    supertrend bollinger atr technical analysis trading
    buy sell hold position portfolio
  ].freeze

  TECHNICAL_ANALYSIS_KEYWORDS = %w[
    analyze analysis indicator rsi macd adx supertrend
    bollinger atr technical chart pattern trend support
    resistance breakout breakdown
  ].freeze

  def self.should_use_agent?(prompt, deep_mode: false)
    prompt_lower = prompt.downcase

    # Check if query has a specific symbol/instrument name
    has_symbol = extract_symbol_from_prompt(prompt)

    # Deep mode: use agent for trading queries (even without symbol, for research)
    return :technical_analysis if deep_mode && trading_related?(prompt_lower)

    # Technical analysis agent requires a symbol for specific analysis
    # Only route if we have both trading keywords AND a symbol
    if (technical_analysis_related?(prompt_lower) || trading_related?(prompt_lower)) && has_symbol
      return :technical_analysis
    end

    # If trading keywords but no symbol, use direct LLM (can explain concepts generically)
    # Default: use direct LLM
    :direct
  end

  def self.extract_symbol_from_prompt(prompt)
    return nil if prompt.blank?

    prompt_upper = prompt.upcase

    # Check for known indices
    return 'NIFTY' if prompt_upper.include?('NIFTY')
    return 'BANKNIFTY' if prompt_upper.include?('BANKNIFTY')
    return 'SENSEX' if prompt_upper.include?('SENSEX')

    # Check for common stock symbols
    known_stocks = %w[RELIANCE TCS INFY HDFC ICICI SBI AXIS WIPRO BAJAJ LT MARUTI TITAN]
    known_stocks.each do |stock|
      return stock if prompt_upper.include?(stock)
    end

    # Exclude technical indicator names (these are not stock symbols)
    indicator_names = %w[RSI MACD ADX ATR EMA SMA BOLLINGER SUPER TREND]
    is_indicator = indicator_names.any? { |ind| prompt_upper.include?(ind) }

    # Only extract symbol if it's not an indicator explanation/query
    # Look for patterns like "explain RSI", "what is MACD", "how does ADX work"
    explanation_patterns = /\b(explain|what is|how does|define|describe|tell me about)\s+[A-Z]{2,10}/i
    is_explanation = prompt.match?(explanation_patterns)

    # If it's an explanation about an indicator, don't treat it as a symbol
    return nil if is_indicator && is_explanation

    # Try to extract uppercase word that looks like a symbol (3-10 chars)
    # But skip if it's a known indicator name
    symbol_match = prompt.match(/\b([A-Z]{3,10})\b/)
    if symbol_match
      potential_symbol = symbol_match[1]
      # Don't treat indicator names as symbols
      return nil if indicator_names.any? { |ind| potential_symbol.include?(ind) || ind.include?(potential_symbol) }

      return potential_symbol
    end

    nil
  end

  def self.trading_related?(prompt_lower)
    TRADING_KEYWORDS.any? { |keyword| prompt_lower.include?(keyword) }
  end

  def self.technical_analysis_related?(prompt_lower)
    TECHNICAL_ANALYSIS_KEYWORDS.any? { |keyword| prompt_lower.include?(keyword) }
  end
end
