# frozen_string_literal: true

# Maps all DhanHQ models to agent tools/functions
module DhanAgentToolMapper
  # List of all available DhanHQ models and their methods
  TOOLS = {
    # Account & Portfolio
    account_balance: {
      model: 'DhanHQ::Models::Funds',
      method: 'fetch',
      params: [],
      description: 'Get account balance, available funds, margin details'
    },

    account_margin: {
      model: 'DhanHQ::Models::Margin',
      method: 'fetch',
      params: [],
      description: 'Get margin requirements and details'
    },

    account_profile: {
      model: 'DhanHQ::Models::Profile',
      method: 'fetch',
      params: [],
      description: 'Get user profile and account details'
    },

    # Instruments & Search
    search_instrument: {
      model: 'DhanHQ::Models::Instrument',
      method: 'find_anywhere',
      params: ['symbol', 'exact_match'],
      description: 'Search for instrument by symbol across all exchanges'
    },

    get_instruments_by_segment: {
      model: 'DhanHQ::Models::Instrument',
      method: 'by_segment',
      params: ['exchange_segment'],
      description: 'Get all instruments for a specific exchange segment (NSE_EQ, NSE_FNO, etc)'
    },

    # Positions & Holdings
    get_positions: {
      model: 'DhanHQ::Models::Position',
      method: 'all',
      params: [],
      description: 'Get all open positions'
    },

    get_holdings: {
      model: 'DhanHQ::Models::Holding',
      method: 'all',
      params: [],
      description: 'Get all holdings (demat stocks)'
    },

    # Market Data - Live
    get_live_quote: {
      model: 'DhanHQ::Models::MarketFeed',
      method: 'quote',
      params: ['instruments_hash'],
      description: 'Get live quote with LTP, OHLC, volume, depth for instruments'
    },

    get_last_price: {
      model: 'DhanHQ::Models::MarketFeed',
      method: 'ltp',
      params: ['instruments_hash'],
      description: 'Get last traded price for instruments'
    },

    get_ohlc: {
      model: 'DhanHQ::Models::MarketFeed',
      method: 'ohlc',
      params: ['instruments_hash'],
      description: 'Get OHLC data for instruments'
    },

    # Market Data - Historical
    get_historical_intraday: {
      model: 'DhanHQ::Models::HistoricalData',
      method: 'intraday',
      params: ['security_id', 'exchange_segment', 'instrument', 'interval', 'from_date', 'to_date'],
      description: 'Get intraday historical data (1-60 minute candles)'
    },

    get_historical_daily: {
      model: 'DhanHQ::Models::HistoricalData',
      method: 'daily',
      params: ['security_id', 'exchange_segment', 'instrument', 'from_date', 'to_date'],
      description: 'Get daily historical data'
    },

    # Options
    get_option_chain: {
      model: 'DhanHQ::Models::OptionChain',
      method: 'fetch',
      params: ['underlying_scrip', 'underlying_seg', 'expiry'],
      description: 'Get option chain for underlying stock/indices'
    },

    # Orders
    place_order: {
      model: 'DhanHQ::Models::Order',
      method: 'create',
      params: ['transaction_type', 'exchange_segment', 'product_type', 'order_type', 'security_id', 'quantity', 'price'],
      description: 'Place a new order (market or limit)'
    },

    get_orders: {
      model: 'DhanHQ::Models::Order',
      method: 'all',
      params: [],
      description: 'Get all orders'
    },

    modify_order: {
      model: 'DhanHQ::Models::Order',
      method: 'update',
      params: ['order_id', 'price', 'quantity'],
      description: 'Modify existing order'
    },

    cancel_order: {
      model: 'DhanHQ::Models::Order',
      method: 'cancel',
      params: ['order_id'],
      description: 'Cancel an order'
    },

    # Super Orders (Multi-leg)
    place_super_order: {
      model: 'DhanHQ::Models::SuperOrder',
      method: 'create',
      params: ['transaction_type', 'exchange_segment', 'product_type', 'security_id', 'quantity', 'price', 'target_price', 'stop_loss_price'],
      description: 'Place bracket/CO order with target and stop-loss'
    },

    get_super_orders: {
      model: 'DhanHQ::Models::SuperOrder',
      method: 'all',
      params: [],
      description: 'Get all super orders'
    },

    modify_super_order: {
      model: 'DhanHQ::Models::SuperOrder',
      method: 'update',
      params: ['order_id', 'leg_name', 'price'],
      description: 'Modify super order leg'
    },

    cancel_super_order_leg: {
      model: 'DhanHQ::Models::SuperOrder',
      method: 'cancel_leg',
      params: ['order_id', 'leg_name'],
      description: 'Cancel specific leg of super order'
    },

    # Trades
    get_trades: {
      model: 'DhanHQ::Models::Trade',
      method: 'all',
      params: [],
      description: 'Get all executed trades'
    },

    # Additional tools
    get_expired_options: {
      model: 'DhanHQ::Models::ExpiredOptionsData',
      method: 'fetch',
      params: ['from_date', 'to_date'],
      description: 'Get expired options data'
    },

    get_ledger_entries: {
      model: 'DhanHQ::Models::LedgerEntry',
      method: 'all',
      params: [],
      description: 'Get ledger entries/transactions'
    }
  }.freeze

  # Get tool by name
  def self.get_tool(tool_name)
    TOOLS[tool_name.to_sym]
  end

  # Get all available tools as JSON for LLM
  def self.tools_for_llm
    TOOLS.map do |name, config|
      {
        name: name,
        description: config[:description],
        parameters: config[:params].map do |param|
          {
            name: param,
            type: infer_type(param)
          }
        end
      }
    end
  end

  # Execute a tool by name with parameters
  def self.execute_tool(tool_name, **params)
    tool = get_tool(tool_name)
    return { error: "Tool #{tool_name} not found" } unless tool

    model_class = tool[:model].constantize
    method = tool[:method].to_sym

    case method
    when :fetch, :all
      model_class.send(method)
    when :create, :update, :cancel, :cancel_leg
      model_class.new(**params).save
    else
      model_class.send(method, **params)
    end
  end

  private

  def self.infer_type(param_name)
    case param_name.to_s
    when /date|time/
      'date'
    when /id|quantity|qty|number|amount|price/
      'number'
    when /segment|type|side/
      'string'
    else
      'string'
    end
  end
end

