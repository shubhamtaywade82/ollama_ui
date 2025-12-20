# Quick Guide: Check if SENSEX Job is Scheduled

## ✅ Job is Scheduled!

The job is already configured and scheduled. Here's how to verify:

## Method 1: Rake Task (Easiest)

```bash
bundle exec rake jobs:status
```

This shows:
- ✅ If tables exist
- ✅ All recurring tasks
- ✅ SENSEX job details
- ⚠️ Next execution (will be `nil` until job worker starts)

## Method 2: Rails Console

```ruby
# Check if task exists
task = SolidQueue::RecurringTask.find_by(key: 'sensex_option_analysis')
task.schedule  # => "every 5 minutes"

# Check next execution (will be nil until job worker starts)
SolidQueue::RecurringExecution
  .where(task_key: 'sensex_option_analysis')
  .order(run_at: :asc)
  .first
# => nil (until job worker creates the execution)
```

## Why is Next Execution `nil`?

**This is normal!** The `RecurringExecution` records are created automatically by the **job worker** when it starts. The recurring task is scheduled, but the actual execution records are created dynamically.

## To Start the Job Worker

```bash
# In a separate terminal
bin/jobs
```

Once the job worker starts:
1. It loads recurring tasks from `config/recurring.yml`
2. Creates execution records for each task
3. Schedules them according to their schedule
4. Runs them automatically

## Test the Job Manually

```bash
# Run the job immediately (for testing)
bundle exec rake jobs:sensex

# Or in Rails console:
SensexOptionAnalysisJob.perform_now
```

## Verify Job Ran

```ruby
# In Rails console - check recent job executions
SolidQueue::Job
  .where(class_name: 'SensexOptionAnalysisJob')
  .order(created_at: :desc)
  .limit(5)
  .each do |job|
    puts "#{job.created_at}: #{job.finished_at ? 'Completed' : 'Running'}"
  end
```

## Summary

- ✅ **Job is scheduled** (check with `rake jobs:status`)
- ⚠️ **Next execution is `nil`** until job worker starts (this is normal!)
- 🚀 **Start job worker** with `bin/jobs` to begin automatic execution
- 🧪 **Test manually** with `rake jobs:sensex`

