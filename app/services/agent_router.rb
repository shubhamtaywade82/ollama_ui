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

    # Exclude documentation/configuration queries early
    # These should never go to technical analysis agent
    return :direct if documentation_query?(prompt, prompt_lower)

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

  def self.documentation_query?(prompt, prompt_lower)
    # Check for documentation/configuration keywords
    doc_keywords = %w[
      config.yaml config.json yaml json documentation reference guide
      api documentation http https url ssl certificate proxy
      mcp server model context protocol continue.dev
      docker exec ollama list models provider roles
      autocomplete embed rerank summarize
    ]

    # If prompt contains multiple documentation keywords, it's likely a doc query
    doc_keyword_count = doc_keywords.count { |kw| prompt_lower.include?(kw) }

    # Also check for patterns like "config.yaml reference", "documentation", etc.
    doc_patterns = [
      /config\.(yaml|json)/i,
      /documentation|reference|guide/i,
      /continue\.dev/i,
      /docker\s+exec/i,
      /ollama\s+list/i
    ]

    has_doc_pattern = doc_patterns.any? { |pattern| prompt.match?(pattern) }

    # If we have 2+ doc keywords or a clear doc pattern, it's a documentation query
    doc_keyword_count >= 2 || has_doc_pattern
  end

  def self.extract_symbol_from_prompt(prompt)
    return nil if prompt.blank?

    prompt_upper = prompt.upcase

    # Check for known indices first (common ones)
    known_indices = %w[NIFTY BANKNIFTY SENSEX]
    known_indices.each do |index|
      return index if prompt_upper.include?(index) && symbol_exists_in_database?(index)
    end

    # Extract potential symbols from prompt (3-10 uppercase letters)
    potential_symbols = prompt_upper.scan(/\b([A-Z]{3,10})\b/).flatten.uniq

    # Check each potential symbol against database
    potential_symbols.each do |potential_symbol|
      # Skip if it's a known indicator or documentation keyword
      next if skip_symbol?(potential_symbol)

      # Check if symbol exists in database using LIKE query
      return potential_symbol if symbol_exists_in_database?(potential_symbol)
    end

    nil
  end

  def self.skip_symbol?(symbol)
    # Exclude technical indicator names (these are not stock symbols)
    indicator_names = %w[RSI MACD ADX ATR EMA SMA BOLLINGER SUPER TREND]
    return true if indicator_names.any? { |ind| symbol.include?(ind) || ind.include?(symbol) }

    # Exclude documentation/configuration keywords
    documentation_keywords = %w[CONFIG YAML JSON API HTTP HTTPS URL SSL MCP NODE ENV PORT]
    return true if documentation_keywords.any? { |kw| symbol.include?(kw) || kw.include?(symbol) }

    false
  end

  def self.symbol_exists_in_database?(symbol)
    return false unless defined?(Instrument) && Instrument.table_exists?

    # Check if symbol exists in underlying_symbol or symbol_name
    Instrument.where('UPPER(underlying_symbol) LIKE ? OR UPPER(symbol_name) LIKE ?', "%#{symbol}%", "%#{symbol}%")
              .exists?
  rescue StandardError => e
    Rails.logger.error "Failed to check symbol in database: #{e.message}"
    false
  end

  def self.trading_related?(prompt_lower)
    TRADING_KEYWORDS.any? { |keyword| prompt_lower.include?(keyword) }
  end

  def self.technical_analysis_related?(prompt_lower)
    TECHNICAL_ANALYSIS_KEYWORDS.any? { |keyword| prompt_lower.include?(keyword) }
  end

  # Get all valid symbols from Instrument model (cached for performance)
  def self.get_valid_symbols
    return @valid_symbols_cache if @valid_symbols_cache

    @valid_symbols_cache = if defined?(Instrument) && Instrument.table_exists?
                             load_symbols_from_database
                           else
                             [].to_set
                           end
  end

  def self.load_symbols_from_database
    # Get unique underlying_symbols and symbol_names from database
    symbols = Instrument.where.not(underlying_symbol: [nil, ''])
                        .distinct
                        .pluck(:underlying_symbol)
                        .compact
                        .map(&:upcase)

    symbol_names = Instrument.where.not(symbol_name: [nil, ''])
                             .distinct
                             .pluck(:symbol_name)
                             .compact
                             .map(&:upcase)

    # Combine and deduplicate, then convert to Set for fast lookup
    (symbols + symbol_names).uniq.to_set
  rescue StandardError => e
    Rails.logger.error "Failed to load valid symbols: #{e.message}"
    # Fallback to common symbols if database query fails
    %w[NIFTY BANKNIFTY SENSEX RELIANCE TCS INFY HDFC ICICI SBI AXIS WIPRO BAJAJ LT MARUTI TITAN].to_set
  end

  # Clear the cache (useful for testing or when instruments are updated)
  def self.clear_symbol_cache!
    @valid_symbols_cache = nil
  end
end
