# frozen_string_literal: true

module TradingExamplesHelper
  def trading_examples
    Rails.cache.fetch('trading_examples', expires_in: 1.hour) do
      [
        {
          category: '📊 Market Data',
          examples: [
            'What is the current price of RELIANCE?',
            'Get the LTP for NIFTY and TCS',
            'What is the OHLC data for INFY?',
            'Show me historical price data for RELIANCE for the last 7 days'
          ]
        },
        {
          category: '📈 Technical Analysis',
          examples: [
            'Analyze NIFTY with technical indicators',
            'What is the current RSI for RELIANCE?',
            'Calculate MACD for TCS on 15-minute timeframe',
            'What is the ADX value for INFY?',
            'Calculate ATR for RELIANCE',
            'What is the Bollinger Bands for TCS?'
          ]
        },
        {
          category: '💰 Account & Positions',
          examples: [
            'What are my current positions?',
            'Show me account balance',
            'What is my portfolio value?',
            'Get my trading statistics'
          ]
        },
        {
          category: '🔍 Complex Analysis',
          examples: [
            'Analyze RELIANCE: get RSI, MACD, and current price',
            'Compare TCS and INFY: show RSI, ADX, and current prices',
            'Full analysis for RELIANCE: indicators and historical data',
            'What is the market condition for TCS? Check indicators'
          ]
        }
      ]
    end
  end
end
