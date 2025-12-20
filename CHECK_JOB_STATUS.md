# How to Check if SENSEX Option Analysis Job is Scheduled

## Step 1: Ensure Database Migrations are Run

First, make sure Solid Queue tables exist:

```bash
# Run migrations if not already done
bin/rails db:migrate

# Or if using separate queue database
bin/rails db:migrate:queue
```

## Step 2: Load Recurring Tasks

Solid Queue loads recurring tasks from `config/recurring.yml` when the job worker starts. The tasks are loaded into the database automatically.

## Step 3: Check Job Status

### Method 1: Rails Console (Recommended)

```bash
bin/rails console
```

Then run:

```ruby
# Check all recurring tasks
SolidQueue::RecurringTask.all.each do |task|
  puts "Key: #{task.key}"
  puts "  Schedule: #{task.schedule}"
  puts "  Class: #{task.class_name}"
  puts "  Description: #{task.description}"
  puts "  Static: #{task.static}"
  puts "---"
end

# Check specifically for SENSEX job
sensex_task = SolidQueue::RecurringTask.find_by(key: 'sensex_option_analysis')
if sensex_task
  puts "✅ SENSEX job is scheduled!"
  puts "  Schedule: #{sensex_task.schedule}"
  puts "  Next run: Check recurring_executions table"
else
  puts "❌ SENSEX job not found in recurring tasks"
end

# Check when it will run next
next_execution = SolidQueue::RecurringExecution
  .where(task_key: 'sensex_option_analysis')
  .order(run_at: :asc)
  .first

if next_execution
  puts "Next execution scheduled for: #{next_execution.run_at}"
else
  puts "No execution scheduled yet (will be created when job worker starts)"
end
```

### Method 2: Check via SQL

```bash
# Connect to database
bin/rails dbconsole

# Then run:
SELECT key, schedule, class_name, description
FROM solid_queue_recurring_tasks
WHERE key = 'sensex_option_analysis';

# Check next execution:
SELECT task_key, run_at, created_at
FROM solid_queue_recurring_executions
WHERE task_key = 'sensex_option_analysis'
ORDER BY run_at ASC
LIMIT 1;
```

### Method 3: Check Job Logs

When the job worker is running, you'll see logs like:

```bash
# Start job worker (if not already running)
bin/jobs

# Look for logs like:
# [SolidQueue] Loading recurring tasks from config/recurring.yml
# [SolidQueue] Enqueued recurring task: sensex_option_analysis
```

### Method 4: Check Recent Job Executions

```ruby
# In Rails console
# Check if job has run recently
SolidQueue::Job
  .where(class_name: 'SensexOptionAnalysisJob')
  .order(created_at: :desc)
  .limit(5)
  .each do |job|
    puts "Job ID: #{job.id}"
    puts "  Created: #{job.created_at}"
    puts "  Finished: #{job.finished_at}"
    puts "  Status: #{job.finished_at ? 'Completed' : 'Running/Pending'}"
    puts "---"
  end
```

## Step 4: Manually Trigger Job (for Testing)

```ruby
# In Rails console
# Enqueue the job manually
SensexOptionAnalysisJob.perform_later

# Or run it immediately (synchronously)
SensexOptionAnalysisJob.perform_now
```

## Step 5: Verify Job Worker is Running

The recurring tasks only execute if the job worker is running:

```bash
# Check if job worker process is running
ps aux | grep "bin/jobs" | grep -v grep

# Or check if Solid Queue is running in Puma (if SOLID_QUEUE_IN_PUMA=true)
# The job worker should be part of your ./bin/dev process
```

## Troubleshooting

### Job Not Scheduled

1. **Check recurring.yml syntax**:
   ```bash
   cat config/recurring.yml
   ```

2. **Restart job worker**:
   ```bash
   # Stop current worker (Ctrl+C)
   # Then restart
   bin/jobs
   ```

3. **Load tasks manually**:
   ```ruby
   # In Rails console
   SolidQueue::RecurringTask.load_from_config
   ```

### Job Not Running

1. **Check if job worker is running**:
   ```bash
   bin/jobs
   ```

2. **Check for errors in logs**:
   ```bash
   tail -f log/development.log | grep SensexOptionAnalysisJob
   ```

3. **Check job queue**:
   ```ruby
   # In Rails console
   SolidQueue::Job.where(class_name: 'SensexOptionAnalysisJob').count
   ```

### Database Tables Missing

If you see "relation does not exist" errors:

```bash
# Run migrations
bin/rails db:migrate

# If using separate queue database
bin/rails db:migrate:queue
```

## Quick Status Check Script

Create a simple rake task to check status:

```ruby
# lib/tasks/job_status.rake
namespace :jobs do
  desc "Check status of scheduled jobs"
  task status: :environment do
    puts "=== Recurring Tasks ==="
    SolidQueue::RecurringTask.all.each do |task|
      puts "#{task.key}: #{task.schedule} (#{task.class_name})"
    end

    puts "\n=== SENSEX Job Status ==="
    task = SolidQueue::RecurringTask.find_by(key: 'sensex_option_analysis')
    if task
      puts "✅ Scheduled: #{task.schedule}"
      next_run = SolidQueue::RecurringExecution
        .where(task_key: 'sensex_option_analysis')
        .order(run_at: :asc)
        .first
      if next_run
        puts "Next run: #{next_run.run_at}"
      else
        puts "Next run: Will be scheduled when job worker starts"
      end
    else
      puts "❌ Not found - run: SolidQueue::RecurringTask.load_from_config"
    end
  end
end
```

Then run:
```bash
bundle exec rake jobs:status
```

