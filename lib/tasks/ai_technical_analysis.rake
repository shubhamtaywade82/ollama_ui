# frozen_string_literal: true

namespace :ai do
  desc 'Show example prompts and capabilities of the technical analysis agent'
  task examples: :environment do
    puts '=' * 100
    puts 'Technical Analysis Agent - Example Prompts & Capabilities'
    puts '=' * 100
    puts ''

    # Static examples organized by category
    static_examples = [
      {
        category: '📊 Market Data Queries',
        prompts: [
          'What is the current price of RELIANCE?',
          'Get the LTP for NIFTY and TCS',
          'What is the OHLC data for INFY?',
          'Show me historical price data for RELIANCE for the last 7 days'
        ]
      },
      {
        category: '📈 Technical Indicators',
        prompts: [
          'What is the current RSI for RELIANCE?',
          'Calculate MACD for TCS on 15-minute timeframe',
          'What is the ADX value for INFY?',
          'Calculate ATR for RELIANCE',
          'What is the Bollinger Bands for TCS?'
        ]
      },
      {
        category: '💰 Trading Statistics',
        prompts: [
          'What are my current trading statistics?',
          'Show me win rate and PnL for today',
          'What is my realized PnL for today?',
          'Get trading stats for a specific date (YYYY-MM-DD)'
        ]
      },
      {
        category: '📋 Position Management',
        prompts: [
          'What are my current active positions?',
          'Show me all active positions with their PnL',
          'What is the current PnL for my positions?'
        ]
      },
      {
        category: '🔍 Complex Analysis',
        prompts: [
          'Analyze RELIANCE: get RSI, MACD, and current price',
          'Compare TCS and INFY: show RSI, ADX, and current prices',
          'Full analysis for RELIANCE: indicators and historical data',
          'What is the market condition for TCS? Check indicators'
        ]
      }
    ]

    # Display static examples
    static_examples.each_with_index do |example, idx|
      puts "#{idx + 1}. #{example[:category]}"
      puts '-' * 100
      example[:prompts].each do |prompt|
        puts "   • #{prompt}"
      end
      puts ''
    end

    # Try to get AI-generated examples if AI is enabled
    if Services::Ai::OpenaiClient.instance.enabled?
      puts '=' * 100
      puts '🤖 AI-Generated Example Prompts'
      puts '=' * 100
      puts ''
      puts 'Generating additional examples based on available tools...'
      puts ''

      begin
        ai_query = <<~QUERY
          Based on the available tools (get_comprehensive_analysis, get_instrument_ltp, get_ohlc, calculate_indicator,
          get_historical_data, get_trading_stats, get_active_positions), generate 5 creative and practical
          example prompts that a user might ask. Make them diverse and cover different use cases.
          Return only the prompts, one per line, without numbering or explanations.
        QUERY

        result = Services::Ai::TechnicalAnalysisAgent.analyze(query: ai_query)
        if result && result[:analysis]
          puts 'AI Suggestions:'
          puts '-' * 100
          # Extract prompts from AI response (split by lines, filter empty)
          prompts = result[:analysis].split("\n").map(&:strip).reject(&:empty?)
          prompts.each do |prompt|
            # Clean up common prefixes like "- ", "• ", numbers, etc.
            cleaned = prompt.gsub(/^[-•\d.\s]+/, '').strip
            puts "   • #{cleaned}" if cleaned.length > 10
          end
          puts ''
        end
      rescue StandardError => e
        Rails.logger.debug { "[AI Examples] Failed to generate AI examples: #{e.class} - #{e.message}" }
        puts '   (AI example generation skipped - using static examples only)'
        puts ''
      end
    end

    puts '=' * 100
    puts 'Usage:'
    puts '=' * 100
    puts ''
    puts '  bundle exec rake ai:technical_analysis["your question here"]'
    puts ''
    puts '  # With streaming:'
    puts '  STREAM=true bundle exec rake ai:technical_analysis["your question"]'
    puts ''
    puts 'Available Tools:'
    puts '  📊 Market Data:'
    puts '    • get_comprehensive_analysis - Get all data in one call (LTP, OHLC, indicators)'
    puts '    • get_instrument_ltp - Get LTP for specific instruments'
    puts '    • get_ohlc - Get OHLC data'
    puts '    • get_historical_data - Get historical candles'
    puts ''
    puts '  📈 Technical Analysis:'
    puts '    • calculate_indicator - Calculate RSI, MACD, ADX, ATR, BollingerBands'
    puts ''
    puts '  💰 Trading & Positions:'
    puts '    • get_trading_stats - Get trading statistics (win rate, PnL)'
    puts '    • get_active_positions - Get active positions'
    puts ''
  end

  desc 'Technical analysis agent - Ask questions about markets, indicators, positions'
  task :technical_analysis, [:query] => :environment do |_t, args|
    query = args[:query] || ENV.fetch('QUERY', nil)

    unless query.present?
      puts 'Usage: bundle exec rake ai:technical_analysis["your question"]'
      puts '   Or: QUERY="your question" bundle exec rake ai:technical_analysis'
      puts ''
      puts 'For example prompts and capabilities, run:'
      puts '  bundle exec rake ai:examples'
      puts ''
      puts 'Quick examples:'
      puts '  bundle exec rake ai:technical_analysis["What is the current RSI for RELIANCE?"]'
      puts '  bundle exec rake ai:technical_analysis["Analyze TCS: get comprehensive analysis"]'
      puts '  bundle exec rake ai:technical_analysis["What are my current positions and their PnL?"]'
      exit 1
    end

    unless Services::Ai::OpenaiClient.instance.enabled?
      puts '❌ AI integration is not enabled or configured.'
      puts '   Set OPENAI_API_KEY or OLLAMA_BASE_URL environment variable'
      exit 1
    end

    puts '=' * 100
    puts 'Technical Analysis Agent'
    puts '=' * 100
    puts ''
    puts "Query: #{query}"
    puts ''
    puts "Provider: #{Services::Ai::OpenaiClient.instance.provider}"
    puts ''

    # Check if streaming is requested
    stream = %w[true 1].include?(ENV.fetch('STREAM', nil))

    if stream
      puts '📊 Analysis (streaming):'
      puts '-' * 100
      puts ''
      result = Services::Ai::TechnicalAnalysisAgent.analyze(query: query, stream: true) do |chunk|
        print chunk if chunk
        $stdout.flush
      end
      puts ''
      puts ''
      puts '-' * 100
      puts "Generated at: #{result[:generated_at]}" if result
    else
      result = Services::Ai::TechnicalAnalysisAgent.analyze(query: query)

      if result
        puts '📊 Analysis:'
        puts '-' * 100
        puts result[:analysis]
        puts ''
        puts "Generated at: #{result[:generated_at]}"
        puts "Provider: #{result[:provider]}"
      else
        puts '❌ Failed to generate analysis'
        exit 1
      end
    end
  end
end

