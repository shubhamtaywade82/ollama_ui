# Trading Assistant - Prompts That Work Now

This guide shows all the prompts/commands that work with your ollama-ui trading assistant, including the new reliable DhanHQ wrapper endpoints.

---

## 🎯 Quick Reference: What Works Now

### ✅ **Fully Working Prompts (via Trading Chat)**

These work through the trading chat interface at `/trading`:

#### **Account & Portfolio**
```
Show my account balance
Check my account
What's my buying power?
Show my positions
Display my holdings
Show my portfolio
```

#### **Stock Quotes & Prices**
```
Get quote for RELIANCE
Show me current price of TCS
What's the price of INFY?
Get LTP for HDFC
TCS price
Show me quote for RELIANCE
What is the price of TCS
```

#### **Historical Data & Charts**
```
Get historical data for RELIANCE
Show me daily chart for TCS
Find intraday data for INFY
Get OHLC for RELIANCE
Show historical for TCS
Get candles for HDFC
```

#### **Instrument Search**
```
Find RELIANCE
Search for TCS
Lookup NIFTY
Find instrument for RELIANCE
```

---

## 🆕 New API Endpoints (Direct Access)

The new `/dhan/*` endpoints provide reliable, cached access to market data. You can use these directly from your frontend or integrate them into new features:

### **1. Search Instruments**
```javascript
// GET /dhan/search_instruments?q=NIFTY&exchange=NSE
fetch('/dhan/search_instruments?q=RELIANCE&exchange=NSE')
  .then(r => r.json())
  .then(data => console.log(data.instruments))
```

**What it does:** Searches for instruments by symbol/name
**Response:** Array of matching instruments with security_id, symbol, exchange_segment

**Example prompts that could trigger this:**
- "Search for NIFTY stocks"
- "Find all RELIANCE instruments"
- "Lookup securities starting with TCS"

### **2. Get Quote (with symbol or security_id)**
```javascript
// By symbol (recommended)
fetch('/dhan/quote?symbol=RELIANCE&segment=NSE')

// By security_id (if you have it)
fetch('/dhan/quote?security_id=1234567890123456&segment=NSE')
```

**What it does:** Gets live quote/LTP with OHLC data
**Response:** Quote data with last_price, volume, OHLC, 52-week highs/lows

**Example prompts:**
- "Get quote for RELIANCE" ✅ (already works)
- "What's the current price of TCS?" ✅ (already works)
- "Show me LTP for NIFTY 50"

### **3. Get Intraday OHLC**
```javascript
// GET /dhan/ohlc?symbol=RELIANCE&segment=NSE&timeframe=15&count=120
fetch('/dhan/ohlc?symbol=RELIANCE&segment=NSE&timeframe=15&count=120')
```

**What it does:** Gets intraday OHLC candles (1m, 5m, 15m, etc.)
**Response:** OHLC data with open, high, low, close arrays

**Timeframes:** `1`, `5`, `15`, `30`, `60` (minutes)
**Count:** Number of candles to fetch (default: 50, max depends on timeframe)

**Example prompts that could trigger this:**
- "Get 15 minute candles for RELIANCE"
- "Show me intraday OHLC for TCS"
- "Get 1 hour chart data for NIFTY"

### **4. Get Historical Data (Daily)**
```javascript
// GET /dhan/historical?symbol=RELIANCE&segment=NSE&from=2025-09-01&to=2025-10-29
fetch('/dhan/historical?symbol=RELIANCE&segment=NSE&from=2025-09-01&to=2025-10-29')
```

**What it does:** Gets daily historical OHLC data for a date range
**Response:** Historical OHLC data with timestamps

**Dates:** Format `YYYY-MM-DD`
**Default:** Last 30 days if not specified

**Example prompts:**
- "Get historical data for RELIANCE from September to October"
- "Show me daily candles for TCS for the last month"
- "Historical OHLC for NIFTY from 2025-09-01 to 2025-10-29"

### **5. Get Option Chain**
```javascript
// GET /dhan/option_chain?underlying_symbol=NIFTY 50&segment=NSE&expiry=2025-11-06
fetch('/dhan/option_chain?underlying_symbol=NIFTY 50&segment=NSE&expiry=2025-11-06')
```

**What it does:** Gets option chain (calls & puts) for an underlying
**Response:** Option chain data with strikes, premiums, OI

**Expiry:** Format `YYYY-MM-DD`

**Example prompts:**
- "Get option chain for NIFTY 50 expiring 2025-11-06"
- "Show me RELIANCE option chain for next expiry"
- "What are the option strikes for BANKNIFTY?"

---

## 🔄 Integration Examples

### Example 1: Enhanced Quote with Historical Context

You could create a new prompt handler that fetches both quote and recent historical:

```ruby
# In your agent or controller
quote = Dhan::MarketData.quote(symbol: "RELIANCE", segment: "NSE")
historical = Dhan::MarketData.historical(
  symbol: "RELIANCE",
  segment: "NSE",
  from: 30.days.ago.to_s,
  to: Date.today.to_s
)
# Combine both for richer analysis
```

**Prompt:** "Get quote and 30-day trend for RELIANCE"

### Example 2: Multi-Timeframe Analysis

```ruby
# Get multiple timeframes
data_1m = Dhan::MarketData.ohlc(symbol: "RELIANCE", timeframe: "1", count: 240)
data_5m = Dhan::MarketData.ohlc(symbol: "RELIANCE", timeframe: "5", count: 48)
data_15m = Dhan::MarketData.ohlc(symbol: "RELIANCE", timeframe: "15", count: 96)
```

**Prompt:** "Analyze RELIANCE across multiple timeframes"

### Example 3: Option Chain Analysis

```ruby
# Get current price first
quote = Dhan::MarketData.quote(symbol: "NIFTY 50", segment: "NSE_IDX")
current_price = quote[:last_price]

# Get option chain
next_expiry = Date.today + 7.days # or fetch available expiries
chain = Dhan::MarketData.option_chain(
  underlying_symbol: "NIFTY 50",
  segment: "NSE",
  expiry: next_expiry.to_s
)
```

**Prompt:** "Show me NIFTY 50 option chain for next expiry with current price"

---

## 📝 Current Prompt Patterns (Already Working)

### Pattern Matching (trading_chat_controller.js)

The frontend automatically recognizes these patterns:

#### Account/Balance
- Contains: `"account"` OR `"balance"`
- → Calls `/trading/account`

#### Positions
- Contains: `"position"`
- → Calls `/trading/positions`

#### Holdings
- Contains: `"holding"` OR `"portfolio"`
- → Calls `/trading/holdings`

#### Quotes
- Contains: `"quote"`, `"price"`, `"current price"`, `"ltp"`, `"show me"`, `"what is the price"`
- Extracts symbol via regex patterns
- → Calls `/trading/quote?symbol=...`

#### Historical
- Contains: `"historical"`, `"ohlc"`, `"candle"`, `"chart"`
- Extracts symbol
- → Calls `/trading/historical?symbol=...&timeframe=...`

### AI Agent Routing (DhanTradingAgent)

For complex prompts, the AI agent (`/trading/agent`) handles:

#### Simple Actions
- Account balance requests
- Position queries
- Holdings queries
- Quote requests
- Historical data requests
- Instrument search

#### Complex Actions (requires iteration)
- Option chain requests
- Multi-step analysis
- Chart generation requests
- Comparative analysis
- Order placement (disabled for safety)

---

## 🚀 New Prompts You Can Add

With the new reliable endpoints, you can support these additional prompt patterns:

### 1. Symbol-Agnostic Quotes
```
Get quote for any symbol
What's the price of [ANY_STOCK]?
Show me LTP for [ANY_SYMBOL]
```

### 2. Specific Timeframe Requests
```
Get 5 minute candles for RELIANCE
Show me 1 hour chart for TCS
Get 15 minute OHLC for NIFTY
```

### 3. Date Range Queries
```
Get RELIANCE data from September 1 to October 29
Show me TCS historical from last month
Get NIFTY candles between two dates
```

### 4. Option Chain Queries
```
Show option chain for NIFTY 50
Get RELIANCE options for November 6
What are the strikes for BANKNIFTY?
```

### 5. Instrument Discovery
```
Find all stocks with NIFTY in name
Search for all RELIANCE securities
Lookup instruments matching TCS
```

---

## 🔧 Adding New Prompt Handlers

To add support for new prompts, you can:

### Option 1: Update Frontend Pattern Matching

Add to `trading_chat_controller.js` in `handleTradingCommand`:

```javascript
// Example: Add option chain detection
if (lowerPrompt.includes("option") && lowerPrompt.includes("chain")) {
  // Extract underlying and expiry
  const underlying = extractSymbol(prompt);
  const expiry = extractDate(prompt);

  const res = await fetch(
    `/dhan/option_chain?underlying_symbol=${underlying}&expiry=${expiry}`
  );
  const data = await res.json();
  return formatOptionChain(data);
}
```

### Option 2: Extend AI Agent

The agent already handles complex prompts. To add new capabilities, extend `DhanTradingAgent`:

```ruby
# In app/services/dhan_trading_agent.rb
def get_option_chain(symbol = nil, expiry = nil)
  symbol ||= extract_symbol_from_prompt
  expiry ||= extract_expiry_from_prompt

  # Use the new reliable wrapper
  data = Dhan::MarketData.option_chain(
    underlying_symbol: symbol,
    segment: "NSE",
    expiry: expiry
  )

  {
    type: :option_chain,
    message: "📊 Option Chain for #{symbol}",
    data: data,
    formatted: format_option_chain(data)
  }
end
```

### Option 3: Use Direct Service Calls

For custom logic, call services directly:

```ruby
# In any controller or service
quote = Dhan::MarketData.quote(symbol: "RELIANCE", segment: "NSE")
security_id = Dhan::InstrumentIndex.security_id_for("RELIANCE", exchange: "NSE")
ohlc_data = Dhan::MarketData.ohlc(
  security_id: security_id,
  segment: "NSE",
  timeframe: "15",
  count: 100
)
```

---

## ⚡ Performance & Caching

The new integration includes automatic caching:

- **Instrument Master:** Cached for 24 hours
- **Symbol → Security ID:** Cached for 6 hours
- **Full Instrument Details:** Cached for 6 hours

This means repeated queries for the same symbol are lightning fast!

---

## ✅ Summary: What Works Right Now

| Feature           | Works Via            | Example Prompt                          |
| ----------------- | -------------------- | --------------------------------------- |
| Account Balance   | ✅ Trading Chat       | "Show my account balance"               |
| Positions         | ✅ Trading Chat       | "Show my positions"                     |
| Holdings          | ✅ Trading Chat       | "Show my holdings"                      |
| Quotes            | ✅ Trading Chat       | "Get quote for RELIANCE"                |
| Historical Data   | ✅ Trading Chat       | "Get historical for TCS"                |
| Instrument Search | ✅ AI Agent           | "Find RELIANCE"                         |
| Option Chain      | ⚠️ AI Agent (complex) | "Get option chain for NIFTY"            |
| OHLC (New)        | 🆕 Direct API         | Use `/dhan/ohlc` endpoint               |
| Historical (New)  | 🆕 Direct API         | Use `/dhan/historical` endpoint         |
| Search (New)      | 🆕 Direct API         | Use `/dhan/search_instruments` endpoint |

---

**Note:** All existing prompts continue to work. The new endpoints provide additional reliability, caching, and direct access for building custom features!

