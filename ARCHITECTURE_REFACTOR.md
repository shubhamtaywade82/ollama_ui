# Technical Analysis Agent - ReAct Architecture Refactor

## Summary

The Technical Analysis Agent has been refactored to follow a strict **tool-augmented ReAct (Reasoning + Acting) architecture** where:

- **Rails owns**: All market data fetching, indicator computation, tool execution, loop control
- **LLM owns**: Planning which tools to call, reasoning over facts, conflict resolution, final synthesis

## Key Changes

### 1. AgentContext (`lib/services/ai/technical_analysis_agent/agent_context.rb`)
- Rails-owned fact accumulator
- Stores only deterministic tool results (no LLM reasoning)
- Tracks instrument resolution, observations, termination conditions
- Provides facts summary for LLM reasoning

### 2. ReactRunner (`lib/services/ai/technical_analysis_agent/react_runner.rb`)
- Rails-controlled ReAct loop
- LLM only plans next step (which tool to call)
- Rails executes tools and accumulates facts
- Explicit termination conditions (max iterations, max time, sufficient data)
- Full auditability with logging

### 3. StructuredOutput (`lib/services/ai/technical_analysis_agent/structured_output.rb`)
- Validates final analysis JSON
- Enforces NO_TRADE when confidence < 0.6
- Validates required fields and verdict values
- Normalizes output format

### 4. Tool Registry Updates
- `get_comprehensive_analysis` marked as DEPRECATED (violates no-prefetching rule)
- Tools now explicitly documented with clear boundaries
- All tools return pure JSON (no reasoning embedded)

### 5. Main Agent Updates
- Default mode changed from `use_planning` to `use_react`
- ReAct loop is now the primary execution path
- Legacy planning executor kept as fallback

## Architecture Principles Enforced

✅ **LLM NEVER fetches market data directly** - All data comes from tools
✅ **LLM NEVER computes indicators** - Indicators computed by Rails tools
✅ **Rails is single source of truth** - All facts from tool results
✅ **LLM only reasons over tool-returned facts** - No assumptions or guesses
✅ **Every analysis supports NO_TRADE** - Structured output enforces this
✅ **Every tool call is explicit, logged, replayable** - Full audit trail
✅ **User intent determines tool usage** - No prefetching

## Usage

```ruby
# Default: ReAct mode (Rails-controlled loop)
result = Services::Ai::TechnicalAnalysisAgent.analyze(
  query: "Analyze NIFTY with technical indicators",
  stream: true
) do |chunk|
  # Stream progress messages and final analysis
  puts chunk
end

# Result structure:
# {
#   analysis: { ... structured JSON ... },
#   analysis_valid: true/false,
#   analysis_errors: [...],
#   context: { ... full context ... },
#   iterations: 5,
#   generated_at: Time,
#   provider: :ollama
# }
```

## Migration Notes

- Old `use_planning` parameter renamed to `use_react`
- `TechnicalAnalysisJob` updated to use `use_react`
- Controller updated to pass `use_react` parameter
- Backward compatibility: Legacy planning executor still available as fallback

## Next Steps

1. ✅ AgentContext created
2. ✅ ReactRunner implemented
3. ✅ StructuredOutput parser added
4. ✅ Tool registry updated
5. ✅ Prompts updated to remove indicator logic
6. ✅ Tool call logging added
7. ⏳ Test with real queries
8. ⏳ Monitor performance and adjust termination conditions
9. ⏳ Add more tool validation
10. ⏳ Consider removing comprehensive_analysis tool entirely

