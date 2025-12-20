# frozen_string_literal: true

namespace :instruments do
  desc 'Import and cache instruments from DhanHQ CSV'
  task import: :environment do
    puts 'Starting instruments import and cache...'
    start_time = Time.current

    begin
      result   = InstrumentsImporter.import_from_url
      duration = result[:duration] || (Time.current - start_time)
      puts "\n✅ Import completed successfully in #{duration.round(2)} seconds!"
      puts "Total Instruments: #{result[:instrument_total]}"
      puts "Total Derivatives: #{result[:derivative_total]}"

      puts "\n--- Stats ---"
      puts "Instruments cached: #{result[:instrument_rows]}"
      puts "Derivatives cached: #{result[:derivative_rows]}"
      puts "TOTAL: #{result[:instrument_total] + result[:derivative_total]}"
    rescue StandardError => e
      puts "❌ Import failed: #{e.message}"
      puts e.backtrace.join("\n")
      exit 1
    end
  end

  desc 'Reimport instruments and derivatives (updates cache)'
  task reimport: :environment do
    puts 'Starting instruments reimport (cache update)...'
    puts 'Note: This will update the cached instrument data.'
    puts ''
    Rake::Task['instruments:import'].invoke
  end

  desc 'Check instrument import freshness and counts'
  task status: :environment do
    last_import_raw = if defined?(Setting) && Setting.table_exists?
                        Setting.fetch('instruments.last_imported_at')
                      else
                        Rails.cache.read('instruments.last_imported_at')
                      end

    unless last_import_raw
      puts '❌ No instrument import recorded yet.'
      puts '   Run: bin/rails instruments:import'
      exit 1
    end

    imported_at = Time.zone.parse(last_import_raw.to_s)
    age_seconds = Time.current - imported_at
    max_age     = InstrumentsImporter::CACHE_MAX_AGE

    puts "Last import at: #{imported_at}"
    puts "Age (seconds): #{age_seconds.round(2)}"

    duration = if defined?(Setting) && Setting.table_exists?
                 Setting.fetch('instruments.last_import_duration_sec')
               else
                 Rails.cache.read('instruments.last_import_duration_sec')
               end
    puts "Import duration (sec): #{duration || 'unknown'}"

    instrument_rows = if defined?(Setting) && Setting.table_exists?
                        Setting.fetch('instruments.last_instrument_rows', '0')
                      else
                        Rails.cache.read('instruments.last_instrument_rows') || '0'
                      end
    puts "Last instrument rows: #{instrument_rows}"

    derivative_rows = if defined?(Setting) && Setting.table_exists?
                        Setting.fetch('instruments.last_derivative_rows', '0')
                      else
                        Rails.cache.read('instruments.last_derivative_rows') || '0'
                      end
    puts "Last derivative rows: #{derivative_rows}"

    instrument_total = if defined?(Instrument) && Instrument.table_exists?
                         Instrument.count
                       elsif defined?(Setting) && Setting.table_exists?
                         Setting.fetch('instruments.instrument_total', '0')
                       else
                         Rails.cache.read('instruments.instrument_total') || '0'
                       end
    puts "Total instruments: #{instrument_total}"

    derivative_total = if defined?(Derivative) && Derivative.table_exists?
                         Derivative.count
                       elsif defined?(Setting) && Setting.table_exists?
                         Setting.fetch('instruments.derivative_total', '0')
                       else
                         Rails.cache.read('instruments.derivative_total') || '0'
                       end
    puts "Total derivatives: #{derivative_total}"

    if age_seconds > max_age
      puts "Status: ⚠️  STALE (older than #{max_age.inspect})"
      puts "   Run: bin/rails instruments:reimport"
      exit 1
    end

    puts 'Status: ✅ OK'
  rescue ArgumentError => e
    puts "❌ Failed to parse last import timestamp: #{e.message}"
    exit 1
  end

  desc 'Clear all instruments and derivatives (DANGER: Will fail if active positions exist)'
  task :clear, [:force] => :environment do |_t, args|
    puts '⚠️  WARNING: This will delete ALL instruments and derivatives!'
    puts '⚠️  This is usually NOT needed since imports use upsert (add/update only).'
    puts ''

    # Check for active position trackers if model exists
    if defined?(PositionTracker) && PositionTracker.table_exists?
      active_trackers = PositionTracker.where(status: 'active')
      if active_trackers.any?
        puts "ERROR: Found #{active_trackers.count} active position tracker(s) that reference instruments."
        puts 'Active trackers:'
        active_trackers.limit(10).each do |tracker|
          puts "  - Order: #{tracker.order_no}, Instrument ID: #{tracker.instrument_id}, Status: #{tracker.status}, Symbol: #{tracker.symbol}"
        end

        if args[:force] == 'true'
          puts ''
          puts "FORCE mode enabled: Marking active position trackers as 'closed'..."
          active_trackers.update_all(status: 'closed', updated_at: Time.current)
          puts "Marked #{active_trackers.count} active tracker(s) as closed."
        else
          puts ''
          puts 'To force clear (will mark active positions as closed), run:'
          puts '  bin/rails instruments:clear[true]'
          puts 'Or manually close/exit positions first.'
          puts ''
          puts '💡 TIP: You probably don\'t need to clear - just run `bin/rails instruments:reimport`'
          puts '    which uses upsert and safely adds/updates without deleting.'
          raise 'Cannot clear instruments while active position trackers exist'
        end
      end
    end

    puts ''
    puts 'Proceeding with deletion of all instruments and derivatives...'
    Derivative.delete_all if defined?(Derivative) && Derivative.table_exists?
    Instrument.delete_all if defined?(Instrument) && Instrument.table_exists?
    puts '✅ Cleared successfully!'
  end
end

# Provide aliases for legacy singular namespace usage
namespace :instrument do
  desc 'Alias for instruments:import'
  task import: 'instruments:import'

  desc 'Alias for instruments:clear'
  task clear: 'instruments:clear'

  desc 'Alias for instruments:reimport'
  task reimport: 'instruments:reimport'
end
