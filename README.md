# Ollama UI - Local AI Console

A clean, modern Rails app for chatting with local AI models via Ollama.

## Features

- ✨ Modern Tailwind CSS UI
- ⚡ Hotwire (Turbo + Stimulus) for fast, reactive interactions
- 🔄 Live model fetching from your local Ollama instance
- 💬 Simple chat interface for interacting with AI models
- 🎨 Responsive design that works on desktop and mobile

## Prerequisites

- Ruby 3.2+ and Rails 8.0+
- Node.js and npm
- PostgreSQL
- **Ollama running locally** on `http://localhost:11434` (default)

## Setup

1. **Install dependencies**:
   ```bash
   bundle install
   npm install
   ```

2. **Create the database**:
   ```bash
   bin/rails db:create
   ```

3. **Build assets**:
   ```bash
   npm run build
   ```

4. **Start Ollama locally**:
   ```bash
   # Install from https://ollama.ai if you haven't
   ollama serve
   ```

5. **Run the app**:
   ```bash
   bin/dev
   ```

Visit `http://localhost:3000` and start chatting with your local AI models!

## How it works

1. **Model Selection**: The app fetches available models from your local Ollama instance via `/api/tags`
2. **Prompt Entry**: Type your question or prompt in the textarea
3. **Send**: Submit to get a response from the selected model
4. **Response**: View the AI's response below

## Configuration

Default Ollama host is `http://localhost:11434`. To change it, update `.env`:

```
OLLAMA_HOST=http://localhost:11434
```

## Stack

- **Backend**: Rails 8.0 with PostgreSQL
- **Frontend**: Tailwind CSS + Hotwire (Turbo + Stimulus)
- **AI Integration**: Ollama via HTTP client
- **Styling**: Tailwind CSS
- **Linting**: RuboCop

## Development

Build assets in watch mode:
```bash
bin/dev
```

This runs:
- Rails server on port 3000
- JS bundler (esbuild) in watch mode
- CSS compiler (Tailwind) in watch mode

## Next Steps

- [ ] Streaming responses (SSE)
- [ ] Chat history with PostgreSQL
- [ ] System prompts support
- [ ] Model metadata display
- [ ] Multi-turn conversations

## License

MIT
