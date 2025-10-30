# Testing Trading Prompts

Quick reference for testing all available prompts. Use these to verify everything is working.

## ✅ Working Prompts (Test These)

### Account & Balance
```
Show my account balance
Check my account
What's my buying power?
Show available funds
```

### Positions
```
Show my positions
Display my open positions
What are my current positions?
List my positions
```

### Holdings
```
Show my holdings
Display my portfolio
What are my holdings?
Show my investments
```

### Quotes & Prices ✅ (Working)
```
Get quote for RELIANCE
Show me current price of TCS
What's the price of INFY?
Get LTP for HDFC
TCS price
RELIANCE quote
```

### Historical Data
```
Get historical data for RELIANCE
Show me daily chart for TCS
Find intraday data for INFY
Get OHLC for RELIANCE
Show historical for TCS
Get candles for HDFC
Get daily data for NIFTY
```

### Instrument Search
```
Find RELIANCE
Search for TCS
Lookup NIFTY
Find instrument for RELIANCE
Search TCS stock
```

### Option Chains (Complex - May Use Iterative Agent)
```
Get option chain for NIFTY
Show me option chain for RELIANCE
Find option contracts for BANKNIFTY
```

---

## 🧪 Quick Test Checklist

Use this checklist to verify all features:

- [ ] **Account Balance** - "Show my account balance"
- [ ] **Positions** - "Show my positions"
- [ ] **Holdings** - "Show my holdings"
- [ ] **Quote (Simple)** - "Get quote for RELIANCE" ✅ (Known working)
- [ ] **Quote (Variation)** - "What's the price of TCS?"
- [ ] **Historical (Intraday)** - "Get historical data for RELIANCE"
- [ ] **Historical (Daily)** - "Get daily chart for TCS"
- [ ] **Instrument Search** - "Find INFY"
- [ ] **Option Chain** - "Get option chain for NIFTY"

---

## 🔍 What to Check For Each Prompt

### Account/Positions/Holdings
- ✅ Should return account data without errors
- ✅ Should format nicely in the UI
- ✅ Should handle demo mode (no API keys) gracefully

### Quotes
- ✅ Should find the symbol
- ✅ Should return price, volume, OHLC data
- ✅ Should format nicely with proper currency symbols

### Historical Data
- ✅ Should find the symbol
- ✅ Should return candle data (OHLC arrays)
- ✅ Should handle both intraday and daily timeframes
- ✅ Should format with number of candles

### Instrument Search
- ✅ Should find matching instruments
- ✅ Should show security_id, exchange, instrument type
- ✅ Should handle partial matches

### Option Chain
- ✅ Should find underlying instrument
- ✅ Should return option chain data
- ⚠️ May require expiry date specification

---

## 🐛 Common Issues to Watch For

1. **"Symbol not found"** - Check if symbol is correct, try uppercase
2. **"Wrong number of arguments"** - Should be fixed now, but report if still happens
3. **Empty responses** - Check DhanHQ API credentials in `.env`
4. **Timeout errors** - API might be slow, check network
5. **Formatting issues** - UI might not render correctly

---

## 📝 Testing Notes

- **Symbols to Test:** RELIANCE, TCS, INFY, HDFC, WIPRO, NIFTY, BANKNIFTY
- **Exchange:** Most symbols are on NSE
- **Demo Mode:** If no API keys, some features will show demo/error messages

---

## 🚀 Next Steps After Testing

1. Report any prompts that don't work
2. Note any formatting issues
3. Check response times
4. Verify error messages are helpful

