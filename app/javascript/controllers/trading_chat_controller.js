import { Controller } from "@hotwired/stimulus";
import { marked } from "marked";

marked.setOptions({
  breaks: true,
  gfm: true,
});

export default class extends Controller {
  static targets = [
    "prompt",
    "sendBtn",
    "messages",
    "messagesContainer",
    "accountInfo",
    "accountValue",
  ];

  connect() {
    this.loadAccountInfo();
    this.setupTextareaEnterHandler();
  }

  setupTextareaEnterHandler() {
    // Handle Enter key - submit, Shift+Enter for new line
    this.promptTarget.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        // Find the form and trigger submit
        const form = this.element.querySelector("form");
        if (form) {
          form.dispatchEvent(
            new Event("submit", { bubbles: true, cancelable: true })
          );
        }
      }
    });
  }

  async loadAccountInfo() {
    try {
      const res = await fetch("/trading/account");
      const data = await res.json();

      if (data.error) {
        this.accountInfoTarget.textContent = "Demo Mode (No API Keys)";
        this.accountValueTarget.textContent = "$0.00";
      } else {
        this.accountInfoTarget.textContent = `${
          data.account_status || "Demo"
        } Account`;
        this.accountValueTarget.textContent = `$${parseFloat(
          data.equity || 0
        ).toLocaleString("en-US", {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2,
        })}`;
      }
    } catch (e) {
      this.accountInfoTarget.textContent = "Offline";
      this.accountValueTarget.textContent = "$0.00";
    }
  }

  async submit(event) {
    event.preventDefault();
    this.accumulatedText = "";
    const prompt = this.promptTarget.value;

    if (!prompt.trim()) {
      alert("Please enter a message.");
      return;
    }

    this.sendBtnTarget.disabled = true;
    this.promptTarget.disabled = true;

    const userMessage = this.addMessage("user", prompt);
    const aiMessage = this.addMessage("assistant", "");
    this.currentMessageElement = aiMessage;

    this.scrollToBottom();

    try {
      // Try agent first (smart LLM-based routing)
      const agentResponse = await this.tryAgent(prompt);

      if (agentResponse) {
        this.currentMessageElement.querySelector(".message-content").innerHTML =
          agentResponse.formatted || agentResponse;
        this.scrollToBottom();
        return;
      }

      // Fallback to pattern matching
      const tradingResponse = await this.handleTradingCommand(prompt);

      if (tradingResponse) {
        this.currentMessageElement.querySelector(".message-content").innerHTML =
          tradingResponse;
        this.scrollToBottom();
      } else {
        // Send to AI for general chat
        const res = await fetch("/chats/stream", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": this.csrf(),
          },
          body: JSON.stringify({
            model: "qwen2.5:1.5b-instruct",
            prompt: `You are a trading assistant. Help with stock market questions. User asked: ${prompt}`,
          }),
        });

        if (!res.ok) throw new Error("AI chat failed");

        const reader = res.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split("\n");
          buffer = lines.pop() || "";

          for (const line of lines) {
            if (line.startsWith("data: ")) {
              const data = JSON.parse(line.slice(6));
              if (data.type === "content" && data.text) {
                if (!this.accumulatedText) this.accumulatedText = "";
                this.accumulatedText += data.text;
                const html = marked.parse(this.accumulatedText);
                this.currentMessageElement.querySelector(
                  ".message-content"
                ).innerHTML = html;
                this.scrollToBottom();
              }
            }
          }
        }
      }
    } catch (e) {
      const errorHtml = `<span class="text-red-400">Error: ${e.message}</span>`;
      if (this.currentMessageElement) {
        this.currentMessageElement.querySelector(".message-content").innerHTML =
          errorHtml;
      }
    } finally {
      this.sendBtnTarget.disabled = false;
      this.promptTarget.disabled = false;
      this.promptTarget.value = "";
      this.promptTarget.style.height = "auto"; // Reset textarea height
    }
  }

  async tryAgent(prompt) {
    // Try the intelligent agent endpoint
    try {
      const res = await fetch("/trading/agent", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrf(),
        },
        body: JSON.stringify({ prompt: prompt }),
      });

      if (res.ok) {
        const data = await res.json();
        return data;
      }
    } catch (e) {
      console.log("Agent not available, falling back to pattern matching");
    }

    return null;
  }

  async handleTradingCommand(prompt) {
    const lowerPrompt = prompt.toLowerCase();

    // Check account info
    if (lowerPrompt.includes("account") || lowerPrompt.includes("balance")) {
      const res = await fetch("/trading/account");
      const data = await res.json();
      return this.formatAccountInfo(data);
    }

    // Check positions
    if (lowerPrompt.includes("position")) {
      const res = await fetch("/trading/positions");
      const data = await res.json();
      return this.formatPositions(data.positions || []);
    }

    // Check holdings
    if (lowerPrompt.includes("holding") || lowerPrompt.includes("portfolio")) {
      const res = await fetch("/trading/holdings");
      const data = await res.json();
      return this.formatHoldings(data.holdings || []);
    }

    // Get quote - handle multiple patterns
    if (
      lowerPrompt.includes("quote") ||
      lowerPrompt.includes("price") ||
      lowerPrompt.includes("current price") ||
      lowerPrompt.includes("ltp") ||
      lowerPrompt.includes("show me") ||
      lowerPrompt.includes("what is the price")
    ) {
      // Try to extract symbol from prompt
      const patterns = [
        // Pattern 1: "show me current price of TCS" or "price of TCS"
        /(?:show\s+me\s+)?(?:current\s+)?(?:price|quote|ltp)\s+of\s+(\w+)/i,
        // Pattern 2: "what is the price of TCS"
        /what\s+is\s+(?:the\s+)?(?:current\s+)?(?:price|quote)\s+of\s+(\w+)/i,
        // Pattern 3: "TCS price"
        /(\w+)\s+(?:price|quote|ltp)/i,
        // Pattern 4: Any uppercase word in the prompt
        /\b([A-Z]{3,})\b/g,
      ];

      let symbol = null;

      // Try first 3 patterns (specific)
      for (let i = 0; i < 3; i++) {
        const match = prompt.match(patterns[i]);
        if (match && match[1]) {
          symbol = match[1].toUpperCase();
          break;
        }
      }

      // If no symbol found, extract last uppercase word
      if (!symbol) {
        const allMatches = prompt.match(patterns[3]);
        if (allMatches && allMatches.length > 0) {
          // Get the last uppercase word (most likely the symbol)
          symbol = allMatches[allMatches.length - 1].toUpperCase();
        }
      }

      if (symbol) {
        const res = await fetch(`/trading/quote?symbol=${symbol}`);
        const data = await res.json();
        return this.formatQuote(symbol, data);
      }
    }

    // Get historical data - handle multiple patterns
    if (
      lowerPrompt.includes("historical") ||
      lowerPrompt.includes("ohlc") ||
      lowerPrompt.includes("candle") ||
      lowerPrompt.includes("chart")
    ) {
      const symbolPattern =
        /(?:historical|ohlc|candle|chart).*(?:for|of)\s+(\w+)/i;
      const match = prompt.match(symbolPattern);

      if (match) {
        const symbol = match[1].toUpperCase();
        const timeframe = lowerPrompt.includes("daily") ? "daily" : "intraday";
        const res = await fetch(
          `/trading/historical?symbol=${symbol}&timeframe=${timeframe}&interval=15`
        );
        const data = await res.json();
        return this.formatHistoricalData(symbol, data);
      }
    }

    return null;
  }

  formatAccountInfo(data) {
    if (data.error) {
      return `<p>⚠️ <strong>No API credentials configured.</strong></p><p>To enable real trading, add your DhanHQ credentials to <code>.env</code>:</p><pre class="bg-gray-100 p-2 rounded text-xs mt-2">CLIENT_ID=your_client_id
ACCESS_TOKEN=your_access_token</pre><p class="text-xs text-gray-500 mt-2">Get API access from <a href="https://dhan.co" target="_blank">dhan.co</a></p>`;
    }

    return `
      <div class="grid grid-cols-2 gap-4">
        <div class="bg-blue-50 p-3 rounded-lg">
          <div class="text-xs text-blue-600">Portfolio Value</div>
          <div class="text-2xl font-bold text-blue-900">$${parseFloat(
            data.equity || 0
          ).toLocaleString("en-US", { minimumFractionDigits: 2 })}</div>
        </div>
        <div class="bg-green-50 p-3 rounded-lg">
          <div class="text-xs text-green-600">Buying Power</div>
          <div class="text-2xl font-bold text-green-900">$${parseFloat(
            data.buying_power || 0
          ).toLocaleString("en-US", { minimumFractionDigits: 2 })}</div>
        </div>
      </div>
      <p class="mt-3 text-sm text-gray-600">💰 Cash: $${parseFloat(
        data.cash || 0
      ).toLocaleString("en-US", { minimumFractionDigits: 2 })}</p>
    `;
  }

  formatPositions(positions) {
    if (!positions || positions.length === 0) {
      return "<p>📊 You have no open positions.</p>";
    }

    let html = `<table class="w-full text-sm">
      <thead><tr class="border-b"><th class="text-left p-2">Symbol</th><th class="text-left p-2">Qty</th><th class="text-right p-2">Value</th><th class="text-right p-2">P/L</th></tr></thead>
      <tbody>`;

    positions.forEach((pos) => {
      const plColor =
        pos.unrealized_pl >= 0 ? "text-green-600" : "text-red-600";
      html += `<tr class="border-b">
        <td class="p-2 font-semibold">${pos.symbol}</td>
        <td class="p-2">${pos.qty}</td>
        <td class="text-right p-2">$${parseFloat(
          pos.market_value
        ).toLocaleString("en-US", { minimumFractionDigits: 2 })}</td>
        <td class="text-right p-2 ${plColor} font-semibold">$${parseFloat(
        pos.unrealized_pl
      ).toLocaleString("en-US", { minimumFractionDigits: 2 })}</td>
      </tr>`;
    });

    html += `</tbody></table>`;
    return html;
  }

  formatHoldings(holdings) {
    if (!holdings || holdings.length === 0) {
      return "<p>📊 You have no holdings.</p>";
    }

    let html = `<table class="w-full text-sm">
      <thead><tr class="border-b"><th class="text-left p-2">Symbol</th><th class="text-left p-2">Qty</th><th class="text-right p-2">Invested</th><th class="text-right p-2">Current</th><th class="text-right p-2">P/L</th></tr></thead>
      <tbody>`;

    holdings.forEach((hold) => {
      const pl = ((hold.current_price - hold.invested) * hold.qty).toFixed(2);
      const plColor = pl >= 0 ? "text-green-600" : "text-red-600";
      html += `<tr class="border-b">
        <td class="p-2 font-semibold">${hold.symbol}</td>
        <td class="p-2">${hold.qty}</td>
        <td class="text-right p-2">₹${parseFloat(hold.invested).toLocaleString(
          "en-US",
          { minimumFractionDigits: 2 }
        )}</td>
        <td class="text-right p-2">₹${parseFloat(
          hold.current_price
        ).toLocaleString("en-US", { minimumFractionDigits: 2 })}</td>
        <td class="text-right p-2 ${plColor} font-semibold">₹${parseFloat(
        pl
      ).toLocaleString("en-US", { minimumFractionDigits: 2 })}</td>
      </tr>`;
    });

    html += `</tbody></table>`;
    return html;
  }

  formatQuote(symbol, data) {
    if (data.error) {
      return `<p class="text-red-600">❌ Could not fetch quote for ${symbol}: ${data.error}</p>`;
    }

    const lastPrice = data.last_price || 0;
    const volume = data.volume || 0;
    const ohlc = data.ohlc || {};
    const high52w = data.fifty_two_week_high || 0;
    const low52w = data.fifty_two_week_low || 0;

    return `
      <div class="bg-gradient-to-r from-purple-50 to-blue-50 p-4 rounded-lg">
        <h3 class="font-bold text-lg mb-3">${symbol}${
      data.name ? " - " + data.name : ""
    }</h3>

        <div class="text-center mb-4">
          <div class="text-xs text-gray-600 mb-1">Last Traded Price</div>
          <div class="text-4xl font-bold">₹${parseFloat(
            lastPrice
          ).toLocaleString("en-US", {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2,
          })}</div>
        </div>

        <div class="grid grid-cols-2 gap-3 text-sm">
          ${
            ohlc.open
              ? `
          <div>
            <div class="text-xs text-gray-500">Open</div>
            <div class="font-semibold">₹${parseFloat(ohlc.open).toFixed(
              2
            )}</div>
          </div>
          <div>
            <div class="text-xs text-gray-500">High</div>
            <div class="font-semibold text-green-600">₹${parseFloat(
              ohlc.high
            ).toFixed(2)}</div>
          </div>
          <div>
            <div class="text-xs text-gray-500">Low</div>
            <div class="font-semibold text-red-600">₹${parseFloat(
              ohlc.low
            ).toFixed(2)}</div>
          </div>
          <div>
            <div class="text-xs text-gray-500">Close</div>
            <div class="font-semibold">₹${parseFloat(ohlc.close).toFixed(
              2
            )}</div>
          </div>
          `
              : ""
          }
          <div>
            <div class="text-xs text-gray-500">52W High</div>
            <div class="text-green-600">₹${parseFloat(high52w).toFixed(2)}</div>
          </div>
          <div>
            <div class="text-xs text-gray-500">52W Low</div>
            <div class="text-red-600">₹${parseFloat(low52w).toFixed(2)}</div>
          </div>
        </div>

        <div class="mt-3 text-xs text-gray-500">
          Volume: ${volume.toLocaleString()}
        </div>
      </div>
    `;
  }

  formatHistoricalData(symbol, data) {
    if (data.error) {
      return `<p class="text-red-600">❌ Could not fetch historical data for ${symbol}: ${data.error}</p>`;
    }

    if (!data.data || !data.data.close || data.data.close.length === 0) {
      return `<p>📊 No historical data available for ${symbol}</p>`;
    }

    const closes = data.data.close || [];
    const opens = data.data.open || [];
    const highs = data.data.high || [];
    const lows = data.data.low || [];
    const volumes = data.data.volume || [];
    const timestamps = data.data.timestamp || [];

    let html = `
      <div class="bg-gradient-to-r from-blue-50 to-purple-50 p-4 rounded-lg">
        <h3 class="font-bold text-lg mb-3">${symbol} - ${data.timeframe.toUpperCase()} Data</h3>
        <p class="text-sm text-gray-600 mb-2">Security ID: ${
          data.security_id
        }</p>
        <div class="overflow-x-auto">
          <table class="w-full text-xs">
            <thead>
              <tr class="border-b">
                <th class="text-left p-1">Time</th>
                <th class="text-right p-1">Open</th>
                <th class="text-right p-1">High</th>
                <th class="text-right p-1">Low</th>
                <th class="text-right p-1">Close</th>
                <th class="text-right p-1">Volume</th>
              </tr>
            </thead>
            <tbody>
    `;

    // Show last 5 candles
    const candlesToShow = Math.min(5, closes.length);
    for (let i = closes.length - candlesToShow; i < closes.length; i++) {
      const timestamp = timestamps[i]
        ? new Date(timestamps[i] * 1000).toLocaleTimeString()
        : "-";
      html += `
        <tr class="border-b">
          <td class="p-1">${timestamp}</td>
          <td class="text-right p-1">₹${opens[i]?.toFixed(2) || "-"}</td>
          <td class="text-right p-1">₹${highs[i]?.toFixed(2) || "-"}</td>
          <td class="text-right p-1">₹${lows[i]?.toFixed(2) || "-"}</td>
          <td class="text-right p-1 font-semibold">₹${
            closes[i]?.toFixed(2) || "-"
          }</td>
          <td class="text-right p-1">${volumes[i]?.toLocaleString() || "-"}</td>
        </tr>
      `;
    }

    html += `
            </tbody>
          </table>
          <p class="text-xs text-gray-500 mt-2">Showing last ${candlesToShow} of ${closes.length} candles</p>
        </div>
      </div>
    `;

    return html;
  }

  addMessage(role, content) {
    const messageDiv = document.createElement("div");
    messageDiv.className =
      "mb-4 flex " + (role === "user" ? "justify-end" : "justify-start");

    const isAI = role === "assistant";
    messageDiv.innerHTML = `
      <div class="flex gap-3 max-w-[85%] ${
        role === "user" ? "flex-row-reverse" : ""
      }">
        <div class="flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center ${
          isAI ? "bg-green-500" : "bg-blue-500"
        }">
          ${isAI ? "💰" : "👤"}
        </div>
        <div class="${isAI ? "bg-white" : "bg-blue-500"} ${
      isAI ? "text-gray-900" : "text-white"
    } rounded-2xl px-4 py-3 shadow-sm ${
      isAI ? "prose prose-sm max-w-none" : ""
    }">
          <div class="message-content ${
            isAI ? "" : "whitespace-pre-wrap"
          }">${content}</div>
        </div>
      </div>
    `;

    this.messagesTarget.appendChild(messageDiv);
    return messageDiv;
  }

  scrollToBottom() {
    setTimeout(() => {
      this.messagesContainerTarget.scrollTop =
        this.messagesContainerTarget.scrollHeight;
    }, 100);
  }

  csrf() {
    const meta = document.querySelector("meta[name='csrf-token']");
    return meta ? meta.content : "";
  }
}
