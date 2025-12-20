# frozen_string_literal: true

namespace :trading do
  desc 'Analyze trading day: PnL after each exit, profitable periods, entry/exit conditions'
  task analyze_day: :environment do
    today = Time.zone.today
    puts '=' * 100
    puts "TRADING DAY ANALYSIS: #{today.strftime('%Y-%m-%d')}"
    puts '=' * 100
    puts ''

    # Check if PositionTracker model exists
    unless defined?(PositionTracker)
      puts '❌ PositionTracker model not found. Run migrations first:'
      puts '   bin/rails db:migrate'
      exit 1
    end

    # Get all paper positions for today, ordered by exit time (or created_at if not exited)
    all_positions = PositionTracker.where('created_at >= ?', today.beginning_of_day)
                                   .order(Arel.sql('COALESCE(exited_at, created_at) ASC'))

    exited_positions = all_positions.where.not(exited_at: nil).order(:exited_at)
    active_positions = all_positions.where(exited_at: nil)

    puts '📊 OVERVIEW'
    puts '-' * 100
    puts "Total positions: #{all_positions.count}"
    puts "Exited positions: #{exited_positions.count}"
    puts "Active positions: #{active_positions.count}"
    puts ''

    # Calculate cumulative stats after each exit
    cumulative_realized_pnl = BigDecimal('0')
    cumulative_trades = 0
    winners = 0
    losers = 0
    max_profit = BigDecimal('0')
    max_loss = BigDecimal('0')
    max_drawdown = BigDecimal('0')
    peak_pnl = BigDecimal('0')

    profitable_periods = []
    losing_periods = []

    puts '=' * 100
    puts 'TRADE-BY-TRADE ANALYSIS WITH CUMULATIVE STATS'
    puts '=' * 100
    puts ''

    exited_positions.each_with_index do |position, _idx|
      pnl = position.last_pnl_rupees || BigDecimal('0')
      pnl_pct = (position.last_pnl_pct || 0) * 100.0
      cumulative_realized_pnl += pnl
      cumulative_trades += 1

      if pnl.positive?
        winners += 1
      else
        losers += 1
      end

      # Track peak and drawdown
      peak_pnl = cumulative_realized_pnl if cumulative_realized_pnl > peak_pnl
      drawdown = peak_pnl - cumulative_realized_pnl
      max_drawdown = drawdown if drawdown > max_drawdown

      max_profit = cumulative_realized_pnl if cumulative_realized_pnl > max_profit
      max_loss = cumulative_realized_pnl if cumulative_realized_pnl < max_loss

      # Track profitable/losing periods
      if cumulative_realized_pnl.positive?
        profitable_periods << {
          trade_num: cumulative_trades,
          time: position.exited_at,
          cumulative_pnl: cumulative_realized_pnl,
          pnl_pct: (cumulative_realized_pnl / BigDecimal('100_000')) * 100.0
        }
      else
        losing_periods << {
          trade_num: cumulative_trades,
          time: position.exited_at,
          cumulative_pnl: cumulative_realized_pnl,
          pnl_pct: (cumulative_realized_pnl / BigDecimal('100_000')) * 100.0
        }
      end

      win_rate = cumulative_trades.positive? ? (winners.to_f / cumulative_trades * 100.0) : 0.0

      # Display trade details
      puts "[Trade ##{cumulative_trades}] #{position.symbol || 'N/A'}"
      puts "  Entry: #{position.created_at.strftime('%H:%M:%S')} @ ₹#{position.entry_price || 'N/A'}"
      puts "  Exit:  #{position.exited_at&.strftime('%H:%M:%S') || 'N/A'} @ ₹#{position.exit_price || 'N/A'}"
      puts "  Qty: #{position.quantity || 0}"
      puts "  Trade PnL: ₹#{pnl.round(2)} (#{pnl_pct.round(2)}%)"
      puts "  Exit Reason: #{position.meta&.dig('exit_reason') || 'N/A'}"
      puts ''
      puts '  📈 CUMULATIVE STATS AFTER THIS TRADE:'
      puts "     Realized PnL: ₹#{cumulative_realized_pnl.round(2)}"
      puts "     Total Trades: #{cumulative_trades}"
      puts "     Winners: #{winners} | Losers: #{losers}"
      puts "     Win Rate: #{win_rate.round(2)}%"
      puts "     Peak PnL: ₹#{peak_pnl.round(2)}"
      puts "     Max Drawdown: ₹#{max_drawdown.round(2)}"
      puts ''

      # Show entry/exit conditions from metadata
      meta = position.meta.is_a?(Hash) ? position.meta : {}
      if meta.any?
        puts '  📋 ENTRY CONDITIONS:'
        puts "     Index: #{meta['index_key'] || 'N/A'}"
        puts "     Direction: #{meta['direction'] || 'N/A'}"
        puts "     Strategy: #{meta['entry_strategy'] || 'N/A'}"
        puts "     Timeframe: #{meta['entry_timeframe'] || 'N/A'}"
        puts ''
        puts '  📋 EXIT CONDITIONS:'
        puts "     Exit Type: #{meta['exit_type'] || 'N/A'}"
        puts "     Exit Direction: #{meta['exit_direction'] || 'N/A'}"
        puts ''
      end

      puts '-' * 100
      puts ''
    end

    # Final summary
    puts '=' * 100
    puts 'FINAL SUMMARY'
    puts '=' * 100
    puts ''
    puts '📊 Overall Performance:'
    puts "  Total Trades: #{cumulative_trades}"
    puts "  Winners: #{winners}"
    puts "  Losers: #{losers}"
    puts "  Win Rate: #{cumulative_trades.positive? ? (winners.to_f / cumulative_trades * 100.0).round(2) : 0}%"
    puts ''
    puts '💰 PnL Summary:'
    puts "  Realized PnL: ₹#{cumulative_realized_pnl.round(2)}"
    puts "  Total PnL: ₹#{cumulative_realized_pnl.round(2)}"
    puts ''
    puts '📈 Peak Performance:'
    puts "  Max Profit Reached: ₹#{max_profit.round(2)}"
    puts "  Max Loss Reached: ₹#{max_loss.round(2)}"
    puts "  Max Drawdown: ₹#{max_drawdown.round(2)}"
    puts ''

    # Profitable periods analysis
    puts '=' * 100
    puts 'PROFITABLE PERIODS'
    puts '=' * 100
    puts ''
    if profitable_periods.any?
      profitable_periods.each do |period|
        puts "  Trade ##{period[:trade_num]} at #{period[:time].strftime('%H:%M:%S')}: ₹#{period[:cumulative_pnl].round(2)} (#{period[:pnl_pct].round(2)}%)"
      end
    else
      puts '  No profitable periods (always in loss)'
    end
    puts ''

    # Losing periods analysis
    puts '=' * 100
    puts 'LOSING PERIODS'
    puts '=' * 100
    puts ''
    if losing_periods.any?
      losing_periods.each do |period|
        puts "  Trade ##{period[:trade_num]} at #{period[:time].strftime('%H:%M:%S')}: ₹#{period[:cumulative_pnl].round(2)} (#{period[:pnl_pct].round(2)}%)"
      end
    else
      puts '  No losing periods (always profitable)'
    end
    puts ''

    puts '=' * 100
    puts 'ANALYSIS COMPLETE'
    puts '=' * 100
  end
end

