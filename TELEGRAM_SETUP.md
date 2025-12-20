# Telegram Notification Setup

## Overview

The application can send automated notifications to Telegram for:
- SENSEX option buying analysis (every 5 minutes)
- DhanHQ token expiry alerts
- Other trading signals

## Setup Instructions

### 1. Create a Telegram Bot

1. Open Telegram and search for **@BotFather**
2. Send `/newbot` command
3. Follow the instructions to create your bot
4. BotFather will give you a **Bot Token** (looks like: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

### 2. Get Your Chat ID

1. Start a chat with your new bot
2. Send any message to the bot
3. Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
4. Look for `"chat":{"id":123456789}` - this is your Chat ID

### 3. Configure Environment Variables

Add these to your `.env` file (or set them in your environment):

```bash
# Telegram Bot Configuration
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here

# Optional: Specify model for SENSEX analysis (defaults to auto-select)
# SENSEX_ANALYSIS_MODEL=llama3.1:8b
# Or use a faster model for scheduled jobs:
# SENSEX_ANALYSIS_MODEL=qwen2.5:1.5b-instruct
```

### 4. Restart the Application

After setting the environment variables, restart your Rails server and job workers:

```bash
# Restart the server
./bin/dev

# Or if running jobs separately
bin/jobs
```

## Scheduled Jobs

### SENSEX Option Analysis

The `SensexOptionAnalysisJob` runs every 5 minutes and:
- Analyzes SENSEX using the Technical Analysis Agent
- Focuses on option buying opportunities (CALL for bullish, PUT for bearish)
- Sends notifications only when:
  - Verdict is not `NO_TRADE`
  - Confidence is above 50%

### Configuration

The job is configured in `config/recurring.yml`:

```yaml
sensex_option_analysis:
  class: SensexOptionAnalysisJob
  queue: default
  schedule: every 5 minutes
```

To change the schedule, modify the `schedule` field. Examples:
- `every 5 minutes`
- `every 15 minutes`
- `every hour`
- `at 9:30am every day`

## Testing

### Test Telegram Connection

In Rails console:

```ruby
# Check if configured
TelegramNotifier.enabled?
# => true

# Send a test message
TelegramNotifier.send_message("🧪 Test message from Rails app")
# => true (if successful)
```

### Test SENSEX Analysis Job

In Rails console:

```ruby
# Run the job manually
SensexOptionAnalysisJob.perform_now
```

## Troubleshooting

### Notifications Not Sending

1. **Check environment variables**:
   ```bash
   echo $TELEGRAM_BOT_TOKEN
   echo $TELEGRAM_CHAT_ID
   ```

2. **Check logs**:
   ```bash
   tail -f log/development.log | grep TelegramNotifier
   ```

3. **Verify bot token and chat ID**:
   - Make sure bot token starts with numbers and has a colon
   - Make sure chat ID is a number (can be negative for groups)

### Job Not Running

1. **Check if Solid Queue is running**:
   ```bash
   bin/jobs
   ```

2. **Check recurring tasks**:
   ```ruby
   # In Rails console
   SolidQueue::RecurringTask.all
   ```

3. **Manually trigger a recurring task**:
   ```ruby
   # In Rails console
   SolidQueue::RecurringTask.find_by(key: 'sensex_option_analysis').enqueue
   ```

## Security Notes

- **Never commit** `.env` file with real tokens
- Keep your bot token secret
- Consider using Rails credentials for production:
  ```ruby
  # config/credentials.yml.enc
  telegram:
    bot_token: your_token
    chat_id: your_chat_id
  ```

