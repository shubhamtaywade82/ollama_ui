# frozen_string_literal: true

# Executes tools and chains them together for multi-step operations
class ToolExecutor
  def self.execute_tool(tool_name, **params)
    tool = DhanAgentToolMapper.get_tool(tool_name)
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

  # Multi-step workflows
  def self.workflow_option_chain(symbol)
    # Step 1: Find instrument
    instrument = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)
    return { error: 'Instrument not found' } unless instrument

    # Step 2: Get option chain
    chain = DhanHQ::Models::OptionChain.fetch(
      underlying_scrip: instrument.security_id.to_s,
      underlying_seg: instrument.exchange_segment,
      expiry: nil # Let it use next available expiry
    )

    {
      instrument: instrument,
      option_chain: chain
    }
  end

  def self.workflow_quote_with_analysis(symbol)
    # Step 1: Find instrument
    instrument = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)
    return { error: 'Instrument not found' } unless instrument

    # Step 2: Get quote
    quote_response = DhanHQ::Models::MarketFeed.quote(
      instrument.exchange_segment => [instrument.security_id.to_i]
    )

    # Step 3: Get historical data for analysis
    historical = DhanHQ::Models::HistoricalData.intraday(
      security_id: instrument.security_id,
      exchange_segment: instrument.exchange_segment,
      instrument: instrument.instrument,
      interval: '15',
      from_date: 7.days.ago.strftime('%Y-%m-%d'),
      to_date: Time.zone.today.strftime('%Y-%m-%d')
    )

    quote_data = quote_response.dig('data', instrument.exchange_segment, instrument.security_id)

    {
      quote: quote_data,
      historical: historical,
      instrument: instrument
    }
  end

  def self.workflow_place_order_with_risk_check(symbol, quantity, price, transaction_type)
    # Step 1: Find instrument
    instrument = DhanHQ::Models::Instrument.find_anywhere(symbol, exact_match: true)
    return { error: 'Instrument not found' } unless instrument

    # Step 2: Get current quote
    quote_response = DhanHQ::Models::MarketFeed.ltp(
      instrument.exchange_segment => [instrument.security_id.to_i]
    )

    # Step 3: Check margin
    margin = DhanHQ::Models::Margin.fetch

    # Step 4: Validate order
    order_value = quantity * price
    return { error: 'Insufficient margin' } if order_value > margin.available_amount

    # Step 5: Place order
    order = DhanHQ::Models::Order.create(
      transaction_type: transaction_type,
      exchange_segment: instrument.exchange_segment,
      product_type: 'MARGIN',
      order_type: price.positive? ? 'LIMIT' : 'MARKET',
      security_id: instrument.security_id,
      quantity: quantity,
      price: price,
      validity: 'DAY'
    )

    {
      instrument: instrument,
      order: order,
      quote: quote_response,
      margin_used: order_value
    }
  end
end
