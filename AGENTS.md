# Repository Guidelines

## Project Structure & Module Organization
- Rails domain code stays in `app/`: controllers orchestrate chat and trading flows, service objects live in `app/services`, and Stimulus logic sits in `app/javascript`.
- Assets ship from `app/assets/stylesheets` (source) and `app/assets/builds` (compiled). Shared Ruby helpers belong in `lib/`, while configuration files live under `config/`.
- Prompt and agent references live in `docs/`. Add new automated coverage under a mirrored tree in `test/`, and keep schema work in `db/migrate`.

## Build, Test, and Development Commands
- `bin/setup` installs gems, pulls JS packages, prepares the database, and can launch the dev stack.
- Day-to-day workflow uses `bin/dev`, which runs Rails, esbuild, and Tailwind watchers together. Apply schema updates with `bin/rails db:migrate`; run `bin/rails db:prepare` before CI.
- Build assets with `npm run build` (`npm run build:css` for CSS only). Lint and scan with `bin/rubocop` and `bundle exec brakeman`.

## Coding Style & Naming Conventions
- RuboCop enforces Ruby 3.3, two-space indentation, ≤120 columns, and ≤25-line methods.
- Match module paths to filenames (`Trading::QuoteFetcher` in `app/services/trading/quote_fetcher.rb`) and keep controller/service names action-oriented.
- Stimulus controllers end in `_controller.js` with camelCase targets/actions. Prefer Tailwind utilities; extract repeated fragments into partials under `app/views/shared`.

## Testing Guidelines
- Use Rails Minitest: place controller tests in `test/controllers`, service coverage in `test/services`, and run suites with `bin/rails test`.
- Document manual Ollama or trading checks and cross-reference scenarios in `docs/TESTING_PROMPTS.md` when automation is not feasible.

## Commit & Pull Request Guidelines
- Mirror the existing imperative, present-tense commit style (e.g., `Update application layout to apply light theme styling`). Keep commits focused and explain schema or integration changes in the body.
- Rebase on `main` before opening a PR, summarize intent, list validation commands, link issues, and provide UI screenshots or screencasts when behavior changes.

## Security & Configuration Tips
- Keep secrets out of git; use `.env` for local overrides (e.g., `OLLAMA_HOST`) and Rails credentials for production values.
- When upgrading dependencies, record `bin/rubocop`, `bundle exec brakeman`, and `npm audit --production` results in the PR to highlight risk assessments.
