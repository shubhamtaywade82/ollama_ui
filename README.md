# Ollama UI - AI-Powered Trading & Chat Assistant

A modern Rails application that provides an intelligent chat interface for interacting with local AI models (via Ollama) and a comprehensive trading assistant with technical analysis capabilities for Indian stock markets.

## 📋 Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Usage Guide](#usage-guide)
- [Architecture](#architecture)
- [Development](#development)
- [Contributing](#contributing)
- [Testing](#testing)
- [Deployment](#deployment)
- [Troubleshooting](#troubleshooting)
- [Additional Resources](#additional-resources)

---

## ✨ Features

### Core Features

- **🤖 AI Chat Interface**: Chat with local AI models via Ollama with streaming responses
- **📊 Trading Assistant**: Intelligent trading assistant with technical analysis capabilities
- **💹 Market Data Integration**: Real-time quotes, historical data, and option chains via DhanHQ API
- **🔍 Web Search Integration**: AI-powered web search for up-to-date information
- **📈 Technical Analysis Agent**: ReAct-based agent for comprehensive market analysis
- **🎨 Modern UI**: Responsive design with dark/light themes, glassmorphism effects, and smooth animations
- **📱 Real-time Updates**: Server-Sent Events (SSE) for live streaming responses
- **📋 Copy to Clipboard**: Easy message copying functionality
- **🔔 Telegram Notifications**: Optional Telegram bot integration for trading alerts

### Technical Features

- **Rails 8.0** with PostgreSQL
- **Hotwire** (Turbo + Stimulus) for reactive UI
- **Tailwind CSS** for modern styling
- **SolidQueue** for background job processing
- **ActionCable** for real-time communication
- **Ollama Integration** for local AI model inference
- **DhanHQ API** for Indian market data

---

## 🛠 Prerequisites

### Required

- **Ruby 3.2+** and **Rails 8.0+**
- **Node.js** (v18+) and **npm**
- **PostgreSQL** (v12+)
- **Ollama** running locally (default: `http://localhost:11434`)

### Optional

- **DhanHQ API credentials** (for trading features)
- **Telegram Bot Token** (for notifications)
- **Google Search API Key** (for enhanced web search, optional)

---

## 🚀 Quick Start

### 1. Clone and Install

```bash
# Clone the repository
git clone <repository-url>
cd ollama_ui

# Install Ruby dependencies
bundle install

# Install JavaScript dependencies
npm install
```

### 2. Database Setup

```bash
# Create and setup database
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed  # Optional: seed initial data
```

### 3. Build Assets

```bash
# Build CSS and JavaScript assets
npm run build
```

### 4. Configure Environment

Create a `.env` file in the project root:

```bash
# Ollama Configuration
OLLAMA_HOST=http://localhost:11434
OLLAMA_MODEL=llama3.2:3b  # Optional: specify default model

# DhanHQ Trading API (Optional - for trading features)
DHAN_CLIENT_ID=your_client_id
DHAN_ACCESS_TOKEN=your_access_token

# Telegram Notifications (Optional)
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_CHAT_ID=your_chat_id

# Web Search (Optional - for enhanced search)
GOOGLE_SEARCH_API_KEY=your_api_key
GOOGLE_SEARCH_ENGINE_ID=your_engine_id
```

### 5. Start Ollama

```bash
# Install Ollama from https://ollama.ai if you haven't
ollama serve

# Pull a model (e.g., llama3.2:3b)
ollama pull llama3.2:3b
```

### 6. Run the Application

```bash
# Start Rails server, asset watchers, and job workers
bin/dev
```

This command runs:
- Rails server on `http://localhost:3000`
- esbuild watcher for JavaScript
- Tailwind CSS watcher
- SolidQueue worker for background jobs

### 7. Access the Application

- **General Chat**: `http://localhost:3000/`
- **Trading Assistant**: `http://localhost:3000/trading`

---

## ⚙️ Configuration

### Environment Variables

| Variable                         | Description                | Default                  | Required          |
| -------------------------------- | -------------------------- | ------------------------ | ----------------- |
| `OLLAMA_HOST`                    | Ollama server URL          | `http://localhost:11434` | No                |
| `OLLAMA_MODEL`                   | Default Ollama model       | Auto-detected            | No                |
| `OLLAMA_TIMEOUT`                 | Request timeout (seconds)  | `300`                    | No                |
| `DHAN_CLIENT_ID`                 | DhanHQ client ID           | -                        | For trading       |
| `DHAN_ACCESS_TOKEN`              | DhanHQ access token        | -                        | For trading       |
| `TELEGRAM_BOT_TOKEN`             | Telegram bot token         | -                        | For notifications |
| `TELEGRAM_CHAT_ID`               | Telegram chat ID           | -                        | For notifications |
| `GOOGLE_SEARCH_API_KEY`          | Google Search API key      | -                        | For web search    |
| `GOOGLE_SEARCH_ENGINE_ID`        | Google Search Engine ID    | -                        | For web search    |
| `AI_AGENT_MAX_ITERATIONS`        | Max agent iterations       | `15`                     | No                |
| `AI_AGENT_MAX_CONSECUTIVE_TOOLS` | Max consecutive tool calls | `8`                      | No                |
| `AI_AGENT_STREAM_TIMEOUT`        | Stream timeout (seconds)   | `60`                     | No                |

### Rails Credentials (Production)

For production, use Rails encrypted credentials:

```bash
# Edit credentials
EDITOR="code --wait" bin/rails credentials:edit

# Add secrets
dhan:
  client_id: your_client_id
  access_token: your_access_token
telegram:
  bot_token: your_bot_token
  chat_id: your_chat_id
```

---

## 📖 Usage Guide

### General Chat (`/`)

The general chat interface allows you to:

- **Select AI Models**: Choose from available Ollama models
- **Ask Questions**: Get answers with web search integration
- **Multi-turn Conversations**: Maintain conversation history
- **Tool Calling**: Automatic tool execution (web search, etc.)

#### Example Prompts

```
What are the latest trends in AI?
Explain how RSI indicator works
What is the current weather in Mumbai?
```

### Trading Assistant (`/trading`)

The trading assistant provides:

- **Account Information**: View balance, positions, holdings
- **Market Data**: Real-time quotes, historical data, option chains
- **Technical Analysis**: AI-powered market analysis
- **Agent Progress**: Real-time analysis progress tracking

#### Example Prompts

**Account & Portfolio:**
```
Show my account balance
Display my positions
What are my holdings?
```

**Market Data:**
```
Get quote for RELIANCE
Show me current price of TCS
Get historical data for NIFTY
Get option chain for BANKNIFTY
```

**Technical Analysis:**
```
Analyze NIFTY with technical indicators
What's the trend for RELIANCE?
Calculate RSI for TCS
Show me support and resistance for INFY
```

> ⚠️ **Warning**: Trading commands (buy/sell orders) are available but will execute real trades. Use with caution!

### Agent Modes

The trading assistant supports two modes:

1. **Analysis Mode** (Default): Uses Technical Analysis Agent for comprehensive market analysis
2. **Trading Mode**: Direct trading commands and market data queries

---

## 🏗 Architecture

### Project Structure

```
ollama_ui/
├── app/
│   ├── controllers/          # Rails controllers
│   │   ├── chats_controller.rb
│   │   └── trading_controller.rb
│   ├── javascript/
│   │   └── controllers/      # Stimulus controllers
│   │       ├── chat_controller.js
│   │       └── trading_chat_controller.js
│   ├── models/               # ActiveRecord models
│   ├── services/             # Service objects
│   │   ├── web_search_service.rb
│   │   ├── agent_router.rb
│   │   └── dhan_trading_agent.rb
│   └── views/                # ERB templates
├── lib/
│   └── services/
│       └── ai/               # AI services
│           ├── technical_analysis_agent.rb
│           ├── ollama_client.rb
│           └── technical_analysis_agent/
│               ├── agent_context.rb
│               ├── react_runner.rb
│               └── tool_registry.rb
├── config/                   # Configuration files
├── db/                       # Database migrations
└── docs/                     # Documentation
```

### Key Components

#### 1. AI Services (`lib/services/ai/`)

- **`OllamaClient`**: Handles Ollama API communication
- **`TechnicalAnalysisAgent`**: ReAct-based agent for market analysis
- **`AgentContext`**: Manages agent state and facts
- **`ReactRunner`**: Orchestrates ReAct loop execution
- **`ToolRegistry`**: Defines available tools for the agent

#### 2. Controllers

- **`ChatsController`**: General chat interface with web search
- **`TradingController`**: Trading assistant with market data integration

#### 3. Services

- **`WebSearchService`**: Web search with DuckDuckGo and Google fallback
- **`AgentRouter`**: Routes queries to appropriate agent or direct LLM
- **`DhanTradingAgent`**: Trading-specific agent with DhanHQ integration

#### 4. Frontend (Stimulus Controllers)

- **`ChatController`**: General chat UI logic
- **`TradingChatController`**: Trading assistant UI logic
- **`ThemeController`**: Dark/light theme switching

### Data Flow

```
User Query
    ↓
AgentRouter (routes to agent or direct LLM)
    ↓
TechnicalAnalysisAgent / Direct LLM
    ↓
OllamaClient (streams to Ollama)
    ↓
Tool Calls (if needed)
    ↓
Tool Execution (market data, web search, etc.)
    ↓
Response Streaming (SSE)
    ↓
Frontend (Stimulus controllers)
    ↓
UI Update
```

### ReAct Architecture

The Technical Analysis Agent follows a strict ReAct (Reasoning + Acting) pattern:

- **Rails owns**: Data fetching, indicator computation, tool execution, loop control
- **LLM owns**: Planning which tools to call, reasoning over facts, final synthesis
- **No prefetching**: Tools are called only when needed based on user intent
- **Full auditability**: Every tool call is logged and replayable

See [ARCHITECTURE_REFACTOR.md](./ARCHITECTURE_REFACTOR.md) for detailed architecture documentation.

---

## 💻 Development

### Development Workflow

```bash
# Start development server with watchers
bin/dev

# Run in separate terminals if needed:
bin/rails server          # Rails server
npm run build -- --watch  # JavaScript watcher
npm run build:css -- --watch  # CSS watcher
bin/jobs                  # Background job worker
```

### Code Style

The project follows Rails Omakase conventions:

- **Ruby**: RuboCop enforces Ruby 3.3, two-space indentation, ≤120 columns, ≤25-line methods
- **JavaScript**: Standard JavaScript with Stimulus conventions
- **CSS**: Tailwind CSS utility classes

#### Linting

```bash
# Ruby linting
bin/rubocop

# Security scanning
bundle exec brakeman

# JavaScript (if configured)
npm run lint
```

### Project Guidelines

See [AGENTS.md](./AGENTS.md) for detailed project structure and coding guidelines.

### Key Development Commands

```bash
# Database
bin/rails db:migrate              # Run migrations
bin/rails db:rollback             # Rollback last migration
bin/rails db:reset                # Reset database
bin/rails db:seed                 # Seed database

# Assets
npm run build                     # Build assets once
npm run build:css                 # Build CSS only
npm run build -- --watch         # Watch mode

# Testing
bin/rails test                    # Run all tests
bin/rails test:controllers        # Test controllers
bin/rails test:services           # Test services

# Rake Tasks
bundle exec rake ai:technical_analysis["query"]  # Test technical analysis
bundle exec rake ai:list_models                  # List Ollama models
```

### Adding New Features

1. **New AI Tool**: Add to `lib/services/ai/technical_analysis_agent/tool_registry.rb`
2. **New Service**: Create in `app/services/` or `lib/services/`
3. **New Controller Action**: Add route in `config/routes.rb` and action in controller
4. **New UI Component**: Create Stimulus controller in `app/javascript/controllers/`

---

## 🤝 Contributing

### Contribution Guidelines

1. **Fork and Branch**: Create a feature branch from `main`
2. **Follow Conventions**: Adhere to coding style and project structure
3. **Write Tests**: Add tests for new features
4. **Update Documentation**: Update relevant docs and README
5. **Commit Messages**: Use imperative, present-tense style
   ```
   Update trading UI to add copy button
   Fix agent routing for explanation queries
   ```

### Commit Style

- Use imperative, present-tense: `Add feature` not `Added feature`
- Keep commits focused and atomic
- Explain schema or integration changes in commit body

### Pull Request Process

1. **Rebase on main**: `git rebase origin/main`
2. **Run checks**: Ensure `bin/rubocop` and tests pass
3. **Write PR description**: Summarize changes, list validation commands
4. **Link issues**: Reference related issues
5. **Add screenshots**: For UI changes

### Code Review Checklist

- [ ] Code follows project conventions
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] No security vulnerabilities
- [ ] Performance considerations addressed
- [ ] Error handling implemented

---

## 🧪 Testing

### Running Tests

```bash
# All tests
bin/rails test

# Specific test file
bin/rails test test/controllers/chats_controller_test.rb

# With verbose output
bin/rails test --verbose
```

### Test Structure

- **Unit Tests**: `test/unit/` - Model and service tests
- **Functional Tests**: `test/functional/` - Controller tests
- **Integration Tests**: `test/integration/` - End-to-end tests

### Manual Testing

For features that require Ollama or trading APIs, use manual testing prompts documented in:

- [docs/TESTING_PROMPTS.md](./docs/TESTING_PROMPTS.md) - Trading prompt testing
- [docs/PROMPTS_REFERENCE.md](./docs/PROMPTS_REFERENCE.md) - Available prompts

### Testing AI Features

```bash
# Test technical analysis agent
bundle exec rake 'ai:technical_analysis["Analyze NIFTY"]'

# Test with streaming
STREAM=true bundle exec rake 'ai:technical_analysis["query"]'

# List available models
bundle exec rake ai:list_models
```

---

## 🚀 Deployment

### Production Setup

1. **Set Environment Variables**: Use Rails credentials or environment variables
2. **Precompile Assets**: `RAILS_ENV=production npm run build`
3. **Database Migration**: `RAILS_ENV=production bin/rails db:migrate`
4. **Start Workers**: Ensure SolidQueue workers are running

### Docker Deployment

The project includes Docker support via Kamal:

```bash
# Deploy with Kamal
bin/kamal setup
bin/kamal deploy
```

### Background Jobs

Ensure SolidQueue workers are running in production:

```bash
# Start job workers
bin/jobs

# Or via systemd/process manager
```

### Scheduled Jobs

Configure recurring jobs in `config/recurring.yml`:

```yaml
sensex_option_analysis:
  class: SensexOptionAnalysisJob
  queue: default
  schedule: every 5 minutes
```

---

## 🔧 Troubleshooting

### Common Issues

#### Ollama Connection Issues

```bash
# Check Ollama is running
curl http://localhost:11434/api/tags

# Check environment variable
echo $OLLAMA_HOST

# Test model availability
bundle exec rake ai:list_models
```

#### Database Issues

```bash
# Reset database
bin/rails db:reset

# Check migrations
bin/rails db:migrate:status
```

#### Asset Build Issues

```bash
# Clean and rebuild
rm -rf app/assets/builds/*
npm run build
```

#### Streaming Not Working

- Check `ActionController::Live` is included in controller
- Verify SSE headers are set correctly
- Check browser console for errors
- Ensure no proxy/buffer issues

#### Trading API Issues

- Verify DhanHQ credentials in `.env`
- Check API token expiration
- Review logs: `tail -f log/development.log | grep Dhan`

### Getting Help

1. Check logs: `tail -f log/development.log`
2. Review documentation in `docs/` directory
3. Check GitHub issues
4. Review [AGENTS.md](./AGENTS.md) for project guidelines

---

## 📚 Additional Resources

### Documentation Files

- **[AGENTS.md](./AGENTS.md)**: Repository guidelines and coding standards
- **[ARCHITECTURE_REFACTOR.md](./ARCHITECTURE_REFACTOR.md)**: Technical Analysis Agent architecture
- **[docs/AI_IMPLEMENTATION_FILES.md](./docs/AI_IMPLEMENTATION_FILES.md)**: Complete AI service reference
- **[docs/PROMPTS_REFERENCE.md](./docs/PROMPTS_REFERENCE.md)**: Available prompts and commands
- **[docs/TESTING_PROMPTS.md](./docs/TESTING_PROMPTS.md)**: Testing guide
- **[docs/TRADING_AGENT_PROMPTS.md](./docs/TRADING_AGENT_PROMPTS.md)**: Trading agent commands (⚠️ includes risky commands)
- **[TELEGRAM_SETUP.md](./TELEGRAM_SETUP.md)**: Telegram notification setup

### External Resources

- [Ollama Documentation](https://ollama.ai/docs)
- [Rails Guides](https://guides.rubyonrails.org/)
- [Stimulus Handbook](https://stimulus.hotwired.dev/)
- [Tailwind CSS Documentation](https://tailwindcss.com/docs)
- [DhanHQ API Documentation](https://dhanhq.co/api-docs/)

### Key Concepts

- **ReAct Pattern**: Reasoning + Acting loop for AI agents
- **Tool Calling**: LLM function calling for external integrations
- **SSE Streaming**: Server-Sent Events for real-time updates
- **Agent Routing**: Intelligent routing between agents and direct LLM

---

## 📝 License

MIT License - see LICENSE file for details

---

## 🙏 Acknowledgments

- **Ollama** for local AI inference
- **DhanHQ** for Indian market data API
- **Rails** team for the amazing framework
- **Hotwire** for reactive UI patterns

---

## 📧 Support

For issues, questions, or contributions:

1. Check existing documentation
2. Review GitHub issues
3. Create a new issue with detailed information
4. Follow contribution guidelines for PRs

---

**Last Updated**: 2025-01-XX

**Version**: 1.0.0
