# frozen_string_literal: true

namespace :jobs do
  desc 'Check status of scheduled jobs'
  task status: :environment do
    puts '=' * 80
    puts 'Scheduled Jobs Status'
    puts '=' * 80
    puts ''

    begin
      # Check if Solid Queue tables exist
      if ActiveRecord::Base.connection.table_exists?('solid_queue_recurring_tasks')
        puts '✅ Solid Queue tables exist'
        puts ''

        # List all recurring tasks
        tasks = SolidQueue::RecurringTask.all
        if tasks.any?
          puts "📋 Found #{tasks.count} recurring task(s):"
          puts ''
          tasks.each do |task|
            puts "  Key: #{task.key}"
            puts "    Schedule: #{task.schedule}"
            puts "    Class: #{task.class_name || 'Command'}"
            puts "    Queue: #{task.queue_name || 'default'}"
            puts "    Description: #{task.description}" if task.description.present?
            puts ''
          end

          # Check specifically for SENSEX job
          sensex_task = SolidQueue::RecurringTask.find_by(key: 'sensex_option_analysis')
          if sensex_task
            puts '✅ SENSEX Option Analysis Job is scheduled!'
            puts "   Schedule: #{sensex_task.schedule}"
            puts "   Class: #{sensex_task.class_name}"

            # Check next execution
            if ActiveRecord::Base.connection.table_exists?('solid_queue_recurring_executions')
              next_execution = SolidQueue::RecurringExecution
                               .where(task_key: 'sensex_option_analysis')
                               .order(run_at: :asc)
                               .first

              if next_execution
                puts "   Next run: #{next_execution.run_at}"
                time_until = next_execution.run_at - Time.current
                if time_until > 0
                  puts "   Time until next run: #{time_until.to_i} seconds"
                else
                  puts '   ⚠️  Next run is in the past (job worker may not be running)'
                end
              else
                puts '   Next run: Will be scheduled when job worker starts'
              end
            end

            # Check recent job executions
            if ActiveRecord::Base.connection.table_exists?('solid_queue_jobs')
              recent_jobs = SolidQueue::Job
                            .where(class_name: 'SensexOptionAnalysisJob')
                            .order(created_at: :desc)
                            .limit(3)

              if recent_jobs.any?
                puts ''
                puts '   Recent executions:'
                recent_jobs.each do |job|
                  status = if job.finished_at
                             job.finished_at > 1.hour.ago ? '✅ Completed' : 'Completed'
                           elsif job.scheduled_at && job.scheduled_at > Time.current
                             '⏰ Scheduled'
                           else
                             '🔄 Running/Pending'
                           end
                  puts "     - #{job.created_at.strftime('%Y-%m-%d %H:%M:%S')}: #{status}"
                end
              end
            end
          else
            puts '❌ SENSEX Option Analysis Job not found in recurring tasks'
            puts ''
            puts 'To load tasks from config/recurring.yml, restart the job worker:'
            puts '  bin/jobs'
            puts ''
            puts 'Or manually load:'
            puts '  bin/rails runner "SolidQueue::RecurringTask.load_from_config"'
          end
        else
          puts '⚠️  No recurring tasks found'
          puts ''
          puts 'Tasks are loaded from config/recurring.yml when job worker starts.'
          puts 'Start the job worker with: bin/jobs'
        end
      else
        puts '❌ Solid Queue tables do not exist'
        puts ''
        puts 'Run migrations to create them:'
        puts '  bin/rails db:migrate'
        puts ''
        puts 'If using separate queue database:'
        puts '  bin/rails db:migrate:queue'
      end
    rescue StandardError => e
      puts "❌ Error checking job status: #{e.class} - #{e.message}"
      puts ''
      puts 'This might mean:'
      puts '  1. Database migrations not run: bin/rails db:migrate'
      puts '  2. Job worker not started: bin/jobs'
      puts '  3. Recurring tasks not loaded yet'
    end

    puts ''
    puts '=' * 80
  end

  desc 'Manually trigger SENSEX analysis job'
  task sensex: :environment do
    puts 'Triggering SENSEX Option Analysis Job...'
    SensexOptionAnalysisJob.perform_later
    puts '✅ Job enqueued!'
    puts 'Check logs for execution status.'
  end

  desc 'Enqueue recurring task manually (for testing)'
  task enqueue_sensex: :environment do
    task = SolidQueue::RecurringTask.find_by(key: 'sensex_option_analysis')
    if task
      puts "Enqueueing recurring task: #{task.key}"
      # Enqueue immediately
      execution = task.enqueue(at: Time.current)
      puts '✅ Task enqueued!'
      puts "  Execution ID: #{execution.id}" if execution.respond_to?(:id)
      puts "  Run at: #{execution.run_at}" if execution.respond_to?(:run_at)
      puts ''
      puts 'The job will be processed when the job worker is running.'
      puts 'Start job worker with: bin/jobs'
      puts ''
      puts 'Or run the job immediately:'
      puts '  bundle exec rake jobs:sensex'
    else
      puts '❌ Task not found. Run: bundle exec rake jobs:load'
    end
  end

  desc 'Load recurring tasks from config/recurring.yml'
  task load: :environment do
    puts 'Loading recurring tasks from config/recurring.yml...'
    SolidQueue::RecurringTask.load_from_config
    puts '✅ Tasks loaded!'
    puts ''
    puts 'Run "rake jobs:status" to verify.'
  end
end
