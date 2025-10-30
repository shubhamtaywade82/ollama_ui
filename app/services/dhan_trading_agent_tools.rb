# frozen_string_literal: true

# Enumeration of all tools/capabilities that the Trading Agent can use
module DhanTradingAgentTools
  # Trading Tools (Order Management)
  ORDER_TOOLS = [
    { name: :place_market_order, description: 'Place market buy/sell order', api: 'POST /v2/orders' },
    { name: :place_limit_order, description: 'Place limit order with specified price', api: 'POST /v2/orders' },
    { name: :place_sl_order, description: 'Place stop-loss order', api: 'POST /v2/orders' },
    { name: :modify_order, description: 'Modify existing order price/quantity', api: 'PUT /v2/orders/:order_id' },
    { name: :cancel_order, description: 'Cancel pending order', api: 'DELETE /v2/orders/:order_id' },
    { name: :get_order_status, description: 'Check order status and execution details', api: 'GET /v2/orders' }
  ].freeze

  # Super Order Tools (Multi-leg Orders)
  SUPER_ORDER_TOOLS = [
    { name: :place_bracket_order, description: 'Place bracket order (entry + target + stop-loss)',
      api: 'POST /v2/super/orders' },
    { name: :place_co_order, description: 'Place cover order with stop-loss', api: 'POST /v2/super/orders' },
    { name: :modify_super_order, description: 'Modify super order legs', api: 'PUT /v2/super/orders/:order_id' },
    { name: :cancel_super_order_leg, description: 'Cancel specific leg of super order',
      api: 'DELETE /v2/super/orders/:order_id/:leg' }
  ].freeze

  # Portfolio Tools
  PORTFOLIO_TOOLS = [
    { name: :get_positions, description: 'Get all open positions', api: 'GET /v2/positions' },
    { name: :get_holdings, description: 'Get all holdings/demat stocks', api: 'GET /v2/holdings' },
    { name: :get_funds, description: 'Get account funds and margin', api: 'GET /v2/funds' },
    { name: :get_trades, description: 'Get executed trades', api: 'GET /v2/trades' },
    { name: :get_statements, description: 'Get account statements', api: 'GET /v2/statement' },
    { name: :get_margin, description: 'Get margin requirements', api: 'GET /v2/margin' }
  ].freeze

  # Market Data Tools
  MARKET_DATA_TOOLS = [
    { name: :get_quote, description: 'Get live quote (LTP + OHLC + volume + depth)', api: 'POST /v2/marketfeed/quote' },
    { name: :get_ltp, description: 'Get last traded price', api: 'POST /v2/marketfeed/ltp' },
    { name: :get_ohlc, description: 'Get OHLC data', api: 'POST /v2/marketfeed/ohlc' },
    { name: :get_historical_intraday, description: 'Get intraday historical data (1min to 60min candles)',
      api: 'POST /v2/charts/intraday' },
    { name: :get_historical_daily, description: 'Get daily historical data', api: 'POST /v2/charts/historical' },
    { name: :get_option_chain, description: 'Get option chain for underlying', api: 'GET /v2/option_chain' },
    { name: :get_expired_options, description: 'Get expired options data', api: 'GET /v2/expiredoptions' },
    { name: :get_instruments, description: 'Search/lookup instruments', api: 'GET /v2/instrument/:segment' }
  ].freeze

  # Analysis Tools (Built on Market Data)
  ANALYSIS_TOOLS = [
    { name: :calculate_support_resistance,
      description: 'Calculate support and resistance levels using historical data' },
    { name: :calculate_indicators, description: 'Calculate technical indicators (RSI, MACD, Bollinger Bands)' },
    { name: :scan_markets, description: 'Scan markets for specific criteria (breakouts, volumes, etc)' },
    { name: :backtest_strategy, description: 'Backtest trading strategy on historical data' },
    { name: :calculate_risk_reward, description: 'Calculate risk-reward ratio for trades' }
  ].freeze

  # Risk Management Tools
  RISK_TOOLS = [
    { name: :calculate_position_size, description: 'Calculate optimal position size based on risk' },
    { name: :check_margin_required, description: 'Check margin required for position' },
    { name: :validate_order, description: 'Validate order parameters before placement' },
    { name: :check_circuit_limits, description: 'Check if symbol has circuit limits' },
    { name: :check_asm_gsm_status, description: 'Check ASM/GSM status of symbol' }
  ].freeze

  # All Tools Combined
  ALL_TOOLS = {
    orders: ORDER_TOOLS,
    super_orders: SUPER_ORDER_TOOLS,
    portfolio: PORTFOLIO_TOOLS,
    market_data: MARKET_DATA_TOOLS,
    analysis: ANALYSIS_TOOLS,
    risk: RISK_TOOLS
  }.freeze

  # Tool Descriptions for LLM
  def self.tool_descriptions
    all_tools = ORDER_TOOLS + SUPER_ORDER_TOOLS + PORTFOLIO_TOOLS + MARKET_DATA_TOOLS
    all_tools.map do |tool|
      "#{tool[:name]}: #{tool[:description]}"
    end.join("\n")
  end

  # Get available tools based on user role/intent
  def self.get_tools_for_intent(intent)
    case intent
    when :trade
      ORDER_TOOLS + SUPER_ORDER_TOOLS + RISK_TOOLS
    when :portfolio
      PORTFOLIO_TOOLS + ANALYSIS_TOOLS
    when :market_data
      MARKET_DATA_TOOLS + ANALYSIS_TOOLS
    when :analysis
      MARKET_DATA_TOOLS + ANALYSIS_TOOLS
    else
      ALL_TOOLS.values.flatten
    end
  end
end
