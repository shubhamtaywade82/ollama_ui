import { Controller } from "@hotwired/stimulus";
import { marked } from "marked";
import { createConsumer } from "@rails/actioncable";

marked.setOptions({
  breaks: true,
  gfm: true,
});

export default class extends Controller {
  static targets = [
    "model",
    "prompt",
    "promptCentered",
    "sendBtn",
    "sendBtnCentered",
    "messages",
    "messagesContainer",
    "accountInfo",
    "accountValue",
    "modeSelector",
    "tradingModeBtn",
    "technicalAnalysisModeBtn",
    "progressSidebar",
    "progressContainer",
    "progressLog",
    "sidebarOverlay",
    "progressBadge",
    "welcomeScreen",
    "bottomInput",
    "progressToggleBtn",
    "expandProgressBtn",
    "loading",
    "modelName",
  ];

  connect() {
    this.agentMode = "technical_analysis"; // Default to Analysis mode
    this.currentProgressLog = null;
    this.progressEntries = [];
    this.cable = null; // ActionCable consumer
    this.channel = null; // Current channel subscription
    this.sidebarOpen = false;
    this.progressSidebarOpen = true; // Expanded by default
    this.hasMessages = false;
    this.loadAccountInfo();
    this.loadModels();
    this.setupTextareaEnterHandler();
    this.setupTextareaAutoResize();
    this.setupCenteredTextareaAutoResize();
    this.updateModeButtons();
    this.initializeProgressSidebar();
    this.setupResponsiveHandlers();
  }

  disconnect() {
    // Clean up ActionCable connection
    if (this.channel) {
      this.channel.unsubscribe();
      this.channel = null;
    }
    if (this.cable) {
      this.cable.disconnect();
      this.cable = null;
    }
    // Clean up responsive handlers
    if (this.resizeHandler) {
      window.removeEventListener("resize", this.resizeHandler);
    }
  }

  setupResponsiveHandlers() {
    // Handle window resize to close sidebar on mobile when switching to desktop
    this.resizeHandler = () => {
      if (window.innerWidth >= 1024 && this.sidebarOpen) {
        this.closeSidebar();
      }
    };
    window.addEventListener("resize", this.resizeHandler);
  }

  toggleProgressSidebar(event) {
    if (event) {
      event.preventDefault();
    }
    if (this.progressSidebarOpen) {
      this.closeProgressSidebar();
    } else {
      this.openProgressSidebar();
    }
  }

  openProgressSidebar() {
    if (!this.hasProgressSidebarTarget) return;

    this.progressSidebarOpen = true;
    const sidebar = this.progressSidebarTarget;

    // Remove collapse classes
    sidebar.classList.remove(
      "-translate-x-full",
      "w-0",
      "overflow-hidden",
      "border-0"
    );
    sidebar.classList.add("w-72");

    // Hide floating expand button
    if (this.hasExpandProgressBtnTarget) {
      this.expandProgressBtnTarget.classList.add("hidden");
    }

    // Update button icon to show collapse (left arrow pointing left)
    if (this.hasProgressToggleBtnTarget) {
      const svg = this.progressToggleBtnTarget.querySelector("svg");
      if (svg) {
        svg.innerHTML =
          '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 19l-7-7 7-7m8 14l-7-7 7-7"/>';
      }
    }
  }

  closeProgressSidebar(event) {
    if (event) {
      event.preventDefault();
    }

    if (!this.hasProgressSidebarTarget) return;

    this.progressSidebarOpen = false;
    const sidebar = this.progressSidebarTarget;

    // Collapse to left (-translate-x-full moves it off-screen to the left)
    sidebar.classList.remove("w-72");
    sidebar.classList.add(
      "-translate-x-full",
      "w-0",
      "overflow-hidden",
      "border-0"
    );

    // Show floating expand button
    if (this.hasExpandProgressBtnTarget) {
      this.expandProgressBtnTarget.classList.remove("hidden");
    }

    // Update button icon to show expand (right arrow pointing right)
    if (this.hasProgressToggleBtnTarget) {
      const svg = this.progressToggleBtnTarget.querySelector("svg");
      if (svg) {
        svg.innerHTML =
          '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 5l7 7-7 7M5 5l7 7-7 7"/>';
      }
    }
  }

  // Legacy methods for mobile (kept for compatibility)
  toggleSidebar(event) {
    this.toggleProgressSidebar(event);
  }

  openSidebar() {
    this.openProgressSidebar();
  }

  closeSidebar(event) {
    this.closeProgressSidebar(event);
  }

  initializeProgressSidebar() {
    if (this.hasProgressLogTarget) {
      this.currentProgressLog = this.progressLogTarget;
    }
  }

  switchMode(event) {
    event.preventDefault();
    const mode = event.currentTarget.dataset.mode;
    if (mode === "trading" || mode === "technical_analysis") {
      this.agentMode = mode;
      this.updateModeButtons();
    }
  }

  updateModeButtons() {
    if (
      this.hasTradingModeBtnTarget &&
      this.hasTechnicalAnalysisModeBtnTarget
    ) {
      if (this.agentMode === "technical_analysis") {
        // Analysis is active
        this.technicalAnalysisModeBtnTarget.style.backgroundColor =
          "var(--accent-primary)";
        this.technicalAnalysisModeBtnTarget.style.color = "white";
        this.technicalAnalysisModeBtnTarget.classList.remove("opacity-60");

        this.tradingModeBtnTarget.style.backgroundColor = "var(--bg-tertiary)";
        this.tradingModeBtnTarget.style.color = "var(--text-primary)";
        this.tradingModeBtnTarget.classList.add("opacity-60");
      } else {
        // Trading is active
        this.tradingModeBtnTarget.style.backgroundColor =
          "var(--accent-primary)";
        this.tradingModeBtnTarget.style.color = "white";
        this.tradingModeBtnTarget.classList.remove("opacity-60");

        this.technicalAnalysisModeBtnTarget.style.backgroundColor =
          "var(--bg-tertiary)";
        this.technicalAnalysisModeBtnTarget.style.color = "var(--text-primary)";
        this.technicalAnalysisModeBtnTarget.classList.add("opacity-60");
      }
    }
  }

  setupTextareaEnterHandler() {
    // Handle Enter key - submit, Shift+Enter for new line
    const setupHandler = (textarea) => {
      if (!textarea) return;
      textarea.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
          // Find the closest form and trigger submit
          const form = textarea.closest("form");
        if (form) {
          form.dispatchEvent(
            new Event("submit", { bubbles: true, cancelable: true })
          );
        }
      }
    });
    };

    // Setup for both textareas
    if (this.hasPromptTarget) {
      setupHandler(this.promptTarget);
    }
    if (this.hasPromptCenteredTarget) {
      setupHandler(this.promptCenteredTarget);
    }
  }

  setupTextareaAutoResize() {
    if (!this.hasPromptTarget) return;

    const textarea = this.promptTarget;

    // Initial resize
    this.resizeTextarea(textarea);

    // Auto-resize on input
    textarea.addEventListener("input", () => {
      this.resizeTextarea(textarea);
    });
  }

  setupCenteredTextareaAutoResize() {
    if (!this.hasPromptCenteredTarget) return;

    const textarea = this.promptCenteredTarget;

    // Initial resize
    this.resizeTextarea(textarea, 24, 192); // min 24px, max 192px

    // Auto-resize on input
    textarea.addEventListener("input", () => {
      this.resizeTextarea(textarea, 24, 192);
    });
  }

  resizeTextarea(textarea, minHeight = 32, maxHeight = 128) {
    if (!textarea) return;

    // Reset height to auto to get the correct scrollHeight
    textarea.style.height = "auto";

    // Calculate the new height based on scrollHeight
    const scrollHeight = textarea.scrollHeight;

    // Set the height, but limit to max-height
    const newHeight = Math.min(Math.max(scrollHeight, minHeight), maxHeight);
    textarea.style.height = `${newHeight}px`;

    // Show scrollbar if content exceeds max height
    if (scrollHeight > maxHeight) {
      textarea.style.overflowY = "auto";
    } else {
      textarea.style.overflowY = "hidden";
    }
  }

  async loadModels() {
    if (!this.hasModelTarget) return;

    this.modelTarget.innerHTML = "";
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.remove("hidden");
    }

    try {
      const res = await fetch("/models");
      const json = await res.json();
      if (json.error) throw new Error(json.error);

      if (json.models.length === 0) {
        const opt = document.createElement("option");
        opt.value = "";
        opt.textContent =
          "No models installed - Install one with: ollama pull llama3.1:8b";
        opt.disabled = true;
        this.modelTarget.appendChild(opt);
      } else {
        json.models.forEach((m) => {
          const opt = document.createElement("option");
          opt.value = m;
          opt.textContent = m;
          this.modelTarget.appendChild(opt);
        });

        // Set default to qwen model or first available
        const qwenModel =
          json.models.find((m) => m.includes("qwen")) || json.models[0];
        this.modelTarget.value = qwenModel;

        // Update model name display
        if (this.hasModelNameTarget) {
          this.modelNameTarget.textContent = `${qwenModel} • Ready`;
        }
      }
    } catch (e) {
      console.error(e);
      const opt = document.createElement("option");
      opt.value = "";
      opt.textContent = `Error: ${e.message}`;
      opt.disabled = true;
      this.modelTarget.appendChild(opt);
    } finally {
      if (this.hasLoadingTarget) {
        this.loadingTarget.classList.add("hidden");
      }
    }
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

  useExample(event) {
    event.preventDefault();
    const example = event.currentTarget.dataset.example;
    if (example) {
      // Use centered prompt if welcome screen is visible, otherwise use bottom prompt
      const prompt =
        this.hasPromptCenteredTarget && !this.hasMessages
          ? this.promptCenteredTarget
          : this.promptTarget;

      if (prompt) {
        prompt.value = example;
        prompt.focus();
        this.resizeTextarea(
          prompt,
          prompt === this.promptCenteredTarget ? 24 : 32
        );
        // Auto-submit the example
        const form = prompt.closest("form");
        if (form) {
          form.dispatchEvent(
            new Event("submit", { bubbles: true, cancelable: true })
          );
        }
      }
    }
  }

  async submit(event) {
    event.preventDefault();

    // Get prompt from the appropriate textarea
    this.currentPromptTextarea =
      this.hasPromptCenteredTarget && !this.hasMessages
        ? this.promptCenteredTarget
        : this.promptTarget;

    if (!this.currentPromptTextarea) return;

    // Hide welcome screen and show messages on first submission
    if (!this.hasMessages) {
      if (this.hasWelcomeScreenTarget) {
        this.welcomeScreenTarget.classList.add("hidden");
      }
      if (this.hasMessagesTarget) {
        this.messagesTarget.classList.remove("hidden");
      }
      if (this.hasBottomInputTarget) {
        this.bottomInputTarget.classList.remove("hidden");
      }
      this.hasMessages = true;
    }

    this.accumulatedText = "";
    this.accumulatedContent = ""; // Reset for technical analysis mode
    this.progressEntries = []; // Reset progress entries
    const prompt = this.currentPromptTextarea.value;

    // Clear progress sidebar and show placeholder
    if (this.hasProgressLogTarget) {
      this.progressLogTarget.innerHTML = "";
      this.currentProgressLog = this.progressLogTarget;
      // Show placeholder again
      const placeholder =
        this.progressContainerTarget?.querySelector(".text-center");
      if (placeholder) {
        placeholder.style.display = "block";
      }
    }

    if (!prompt.trim()) {
      alert("Please enter a message.");
      return;
    }

    // Disable the appropriate button and textarea
    this.currentSendBtn =
      this.hasSendBtnCenteredTarget && !this.hasMessages
        ? this.sendBtnCenteredTarget
        : this.sendBtnTarget;

    if (this.currentSendBtn) {
      this.currentSendBtn.disabled = true;
    }
    if (this.currentPromptTextarea) {
      this.currentPromptTextarea.disabled = true;
    }

    const userMessage = this.addMessage("user", prompt);
    const aiMessage = this.addMessage("assistant", "");
    this.currentMessageElement = aiMessage;

    this.scrollToBottom();

    try {
      this.resetProgressState();
      this.setAssistantMessage("⏳ Working on it…");

      let streamed = false;
      try {
        streamed = await this.streamAgent(prompt);
      } catch (streamError) {
        console.warn("Streaming agent failed", streamError);
        if (streamError?.message) {
          this.appendProgressLog(
            `Streaming error: ${streamError.message}`,
            "error"
          );
        }
      }

      if (streamed) {
        return;
      }

      this.appendProgressLog("Switching to fallback agent…", "warning");

      const agentResponse = await this.tryAgent(prompt);

      if (this.handleAgentResponse(agentResponse)) {
        return;
      }

      // Fallback to pattern matching
      const tradingResponse = await this.handleTradingCommand(prompt);

      if (tradingResponse) {
        this.setAssistantMessage(tradingResponse);
        return;
      }

      this.setAssistantMessage(
        "I wasn't able to process that request. Please try rephrasing.",
        true
      );
    } catch (e) {
      console.error("Trading chat error", e);
      const errorHtml = `<span class="text-red-400">Error: ${this.escapeHtml(
        e.message
      )}</span>`;
      if (this.currentMessageElement) {
        this.currentMessageElement.querySelector(".message-content").innerHTML =
          errorHtml;
      }
    } finally {
      // Enable the appropriate buttons
      if (this.currentSendBtn) {
        this.currentSendBtn.disabled = false;
      }

      if (this.currentPromptTextarea) {
        this.currentPromptTextarea.disabled = false;
        this.currentPromptTextarea.value = "";
      // Reset textarea height after clearing
        const minHeight =
          this.currentPromptTextarea === this.promptCenteredTarget ? 24 : 32;
        this.resizeTextarea(this.currentPromptTextarea, minHeight);
      }
    }
  }

  resetProgressState() {
    this.progressEntries = [];
    // Clear progress sidebar and show placeholder
    if (this.hasProgressLogTarget) {
      this.progressLogTarget.innerHTML = "";
      this.currentProgressLog = this.progressLogTarget;
      // Show placeholder again
      const placeholder =
        this.progressContainerTarget?.querySelector(".text-center");
      if (placeholder) {
        placeholder.style.display = "block";
      }
    }
  }

  setAssistantMessage(content, treatAsMarkdown = true) {
    if (!this.currentMessageElement) return;
    const target = this.currentMessageElement.querySelector(".message-content");
    if (!target) return;

    if (treatAsMarkdown) {
      target.innerHTML = this.renderMarkdown(content);
    } else {
      target.innerHTML = content;
    }
    this.scrollToBottom();
  }

  async streamAgent(prompt) {
    // For technical analysis, use background jobs by default
    if (this.agentMode === "technical_analysis") {
      return this.streamTechnicalAnalysisBackground(prompt);
    }

    // For trading agent, use direct streaming
    const endpoint = "/trading/agent_stream";

    const res = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrf(),
      },
      body: JSON.stringify({ prompt, mode: this.agentMode }),
    });

    if (!res.ok) {
      return false;
    }

    if (!res.body || !res.body.getReader) {
      return false;
    }

    this.appendProgressLog("Agent connected. Waiting for plan…", "muted");

    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let completed = false;

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() || "";

      for (const line of lines) {
        if (!line.startsWith("data: ")) continue;

        const payloadRaw = line.slice(6);
        if (!payloadRaw.trim()) continue;

        try {
          const payload = JSON.parse(payloadRaw);
          const outcome = this.handleAgentEvent(payload);
          if (outcome === "done") {
            completed = true;
            break;
          }
          if (outcome === "error") {
            throw new Error(
              payload?.data?.message || payload?.message || "Agent error"
            );
          }
        } catch (err) {
          console.error("Failed to parse agent stream payload", err, line);
        }
      }

      if (completed) {
        break;
      }
    }

    return completed;
  }

  async streamTechnicalAnalysisBackground(prompt) {
    // Get selected model
    const model = this.hasModelTarget ? this.modelTarget.value : null;

    // Use direct streaming for immediate execution (no background job)
    const res = await fetch("/trading/technical_analysis_stream", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrf(),
      },
      body: JSON.stringify({
        prompt,
        mode: this.agentMode,
        background: false, // Use direct streaming for immediate execution
        model: model,
      }),
    });

    if (!res.ok) {
      const error = await res
        .json()
        .catch(() => ({ error: "Failed to start analysis" }));
      this.appendProgressLog(
        `Error: ${error.error || "Failed to start analysis"}`,
        "error"
      );
      return false;
    }

    // Check if response is SSE stream (direct streaming) or JSON (background job)
    const contentType = res.headers.get("content-type") || "";
    if (contentType.includes("text/event-stream")) {
      // Direct streaming - handle SSE events
      return this.handleDirectStream(res);
    } else {
      // Background job - use ActionCable
    const data = await res.json();
    const jobId = data.job_id;
    const channelName = data.channel || `technical_analysis_${jobId}`;

      this.appendProgressLog(
        "Analysis queued. Connecting to updates...",
        "info"
      );

    // Connect to ActionCable channel (with polling fallback)
    try {
      return this.connectToActionCable(channelName, jobId);
    } catch (err) {
      console.warn("ActionCable not available, using polling fallback:", err);
      return this.pollForUpdates(jobId);
      }
    }
  }

  async handleDirectStream(res) {
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    // Initialize progress log if not already done
    if (!this.currentProgressLog && this.hasProgressLogTarget) {
      this.currentProgressLog = this.progressLogTarget;
    }
    // Hide placeholder when starting
    const placeholder =
      this.progressContainerTarget?.querySelector(".text-center");
    if (placeholder) {
      placeholder.style.display = "none";
    }

    this.appendProgressLog("Analysis started...", "info");

    try {
      // Process stream continuously for real-time updates
      const processStream = async () => {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          if (value) {
            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split("\n");
            buffer = lines.pop() || "";

            // Process all complete lines immediately
            for (const line of lines) {
              if (!line.trim()) continue; // Skip empty lines
              if (!line.startsWith("data: ")) continue;

              const payloadRaw = line.slice(6).trim();
              if (!payloadRaw) continue;

              try {
                const payload = JSON.parse(payloadRaw);
                // Debug: log all events to see what we're receiving
                if (
                  payload.type === "progress" ||
                  payload.type === "content" ||
                  payload.type === "start"
                ) {
                  console.log("Received event:", payload.type, payload.data);
                }
                const outcome = this.handleAgentEvent(payload);
                if (outcome === "done" || outcome === "error") {
                  return outcome === "done";
                }
              } catch (err) {
                console.error("Failed to parse stream payload", err, line);
              }
            }
          }
        }
        return true;
      };

      return await processStream();
    } catch (err) {
      console.error("Stream error:", err);
      this.appendProgressLog(`Error: ${err.message}`, "error");
      return false;
    }
  }

  connectToActionCable(channelName, jobId) {
    return new Promise((resolve, reject) => {
      try {
        // Create consumer if not exists
        if (!this.cable) {
          this.cable = createConsumer();
        }

        // Subscribe to channel
        this.channel = this.cable.subscriptions.create(
          {
            channel: "TechnicalAnalysisChannel",
            job_id: jobId,
          },
          {
            connected: () => {
              this.appendProgressLog("Connected to analysis stream", "success");
            },
            received: (data) => {
              const outcome = this.handleAgentEvent(data);
              if (outcome === "done") {
                if (this.channel) {
                  this.channel.unsubscribe();
                  this.channel = null;
                }
                resolve(true);
              } else if (outcome === "error") {
                if (this.channel) {
                  this.channel.unsubscribe();
                  this.channel = null;
                }
                reject(new Error(data?.data?.message || "Analysis failed"));
              }
            },
            disconnected: () => {
              this.appendProgressLog(
                "Disconnected from analysis stream",
                "muted"
              );
            },
          }
        );
      } catch (err) {
        console.error("ActionCable connection error:", err);
        // Fallback to polling
        this.pollForUpdates(jobId).then(resolve).catch(reject);
      }
    });
  }

  async pollForUpdates(jobId) {
    // Fallback polling mechanism if ActionCable not available
    this.appendProgressLog(
      "Using polling mode (ActionCable not available)",
      "muted"
    );

    const maxAttempts = 300; // 5 minutes max (1 second intervals)
    let attempts = 0;
    let lastEventId = 0;

    while (attempts < maxAttempts) {
      await new Promise((resolve) => setTimeout(resolve, 1000)); // Poll every second
      attempts++;

      try {
        const res = await fetch(
          `/trading/technical_analysis_status/${jobId}?last_event=${lastEventId}`,
          {
          headers: {
            "X-CSRF-Token": this.csrf(),
          },
          }
        );

        if (res.ok) {
          const data = await res.json();
          if (data.events && data.events.length > 0) {
            for (const event of data.events) {
              const outcome = this.handleAgentEvent(event);
              if (outcome === "done") {
                return true;
              }
              if (outcome === "error") {
                throw new Error(event?.data?.message || "Analysis failed");
              }
            }
            lastEventId = data.last_event_id || lastEventId;
          }

          if (data.status === "completed" || data.status === "failed") {
            return data.status === "completed";
          }
        }
      } catch (err) {
        console.error("Polling error:", err);
      }
    }

    this.appendProgressLog(
      "Polling timeout - analysis may still be running",
      "warning"
    );
    return false;
  }

  appendProgressLog(message, variant = "muted") {
    if (!message) return;

    // Use sidebar progress log instead of inline
    if (!this.currentProgressLog && this.hasProgressLogTarget) {
      this.currentProgressLog = this.progressLogTarget;
    }

    if (!this.currentProgressLog) return;

    // Auto-expand sidebar if collapsed when progress appears
    if (!this.progressSidebarOpen) {
      this.openProgressSidebar();
    }

    // Hide placeholder text when first progress entry is added
    const placeholder =
      this.progressContainerTarget?.querySelector(".text-center");
    if (placeholder && this.progressEntries.length === 0) {
      placeholder.style.display = "none";
    }

    const entry = document.createElement("div");
    entry.className = `${this.progressVariantClass(
      variant
    )} flex items-start gap-1.5 py-1 px-2 rounded transition-colors duration-150 hover:bg-opacity-10 animate-fade-in`;
    entry.style.whiteSpace = "pre-line";
    entry.style.wordBreak = "break-word";

    const messageSpan = document.createElement("span");
    messageSpan.className = "flex-1 text-xs leading-relaxed";
    messageSpan.textContent = message;

    entry.appendChild(messageSpan);
    this.currentProgressLog.appendChild(entry);

    // Scroll progress sidebar to bottom
    if (this.hasProgressContainerTarget) {
      this.progressContainerTarget.scrollTop =
        this.progressContainerTarget.scrollHeight;
    }

    // Also scroll chat to bottom
    this.scrollToBottom();

    if (!this.progressEntries) this.progressEntries = [];
    this.progressEntries.push({ message, variant, timestamp: new Date() });
    if (this.progressEntries.length > 100) {
      // Keep last 100 entries, remove oldest
      const oldestEntry = this.currentProgressLog.firstElementChild;
      if (oldestEntry) {
        oldestEntry.remove();
      }
      this.progressEntries.shift();
    }
  }

  progressVariantClass(variant) {
    const base = "text-xs sm:text-sm leading-relaxed";
    switch (variant) {
      case "info":
        return `${base} text-blue-600 dark:text-blue-400`;
      case "success":
        return `${base} text-green-600 dark:text-green-400`;
      case "error":
        return `${base} text-red-500 dark:text-red-400`;
      case "warning":
        return `${base} text-yellow-600 dark:text-yellow-400`;
      default:
        return `${base} text-gray-600 dark:text-gray-400`;
    }
  }

  // Progress panel methods are no longer needed - using sidebar instead

  handleAgentEvent(event) {
    if (!event || !event.type) return null;

    const type = event.type;
    const data = event.data || {};

    switch (type) {
      case "start":
        this.appendProgressLog("Agent started.", "info");
        break;
      case "mode":
        if (data.mode === "iterative") {
          this.appendProgressLog("Using multi-step workflow.", "info");
        } else if (data.mode === "direct") {
          this.appendProgressLog("Using direct workflow.", "info");
        }
        break;
      case "thinking":
        if (data.message) {
          this.appendProgressLog(data.message, "muted");
        }
        break;
      case "intent":
        if (data.tool || data.action) {
          const intentLabel = this.humanizeTool(data.tool || data.action);
          const symbol = data.symbol ? ` for ${data.symbol}` : "";
          this.appendProgressLog(`Intent: ${intentLabel}${symbol}.`, "info");
        }
        break;
      case "plan":
        if (Array.isArray(data.plan) && data.plan.length > 0) {
          data.plan.forEach((step) => {
            const label = this.stepLabel(step);
            this.appendProgressLog(`Plan: ${label}`, "muted");
          });
        }
        break;
      case "step_started":
        if (data.step) {
          this.appendProgressLog(
            `▶ ${this.stepLabel(data.step)} — started`,
            "info"
          );
        }
        break;
      case "step_completed":
        if (data.step) {
          const summary = data.result?.summary;
          const label = this.stepLabel(data.step);
          const message = summary
            ? `${label} — ✅ ${summary}`
            : `${label} — ✅ Completed`;
          this.appendProgressLog(message, "success");
        }
        break;
      case "step_failed":
        if (data.step) {
          const label = this.stepLabel(data.step);
          const errorText = data.error || "Step failed";
          this.appendProgressLog(`${label} — ❌ ${errorText}`, "error");
        }
        break;
      case "reasoning_complete":
        if (data.reasoning) {
          this.appendProgressLog("Reasoning complete.", "info");
        }
        break;
      case "summary_ready":
        if (data.message) {
          this.appendProgressLog(`Summary ready: ${data.message}`, "info");
        }
        break;
      case "content":
        // For technical analysis, accumulate content chunks
        if (data.content) {
          if (!this.accumulatedContent) this.accumulatedContent = "";
          this.accumulatedContent += data.content;
          this.setAssistantMessage(this.accumulatedContent);
        } else if (data.message) {
          this.appendProgressLog(data.message, "muted");
        }
        break;
      case "progress":
        // Progress messages from technical analysis agent (goes to sidebar)
        if (data.message) {
          // Determine variant based on message content
          let variant = "muted";
          if (
            data.message.includes("✅") ||
            data.message.includes("Completed")
          ) {
            variant = "success";
          } else if (
            data.message.includes("❌") ||
            data.message.includes("Error")
          ) {
            variant = "error";
          } else if (
            data.message.includes("⚠️") ||
            data.message.includes("Warning")
          ) {
            variant = "warning";
          } else if (
            data.message.includes("🔍") ||
            data.message.includes("🔧") ||
            data.message.includes("⚙️")
          ) {
            variant = "info";
          }
          this.appendProgressLog(data.message, variant);
        }
        break;
      case "error":
        const errorMessage = data.message || data.error || "Agent error";
        this.appendProgressLog(`Error: ${errorMessage}`, "error");
        this.setAssistantMessage(
          `<span class="text-red-500">❌ ${this.escapeHtml(
            errorMessage
          )}</span>`,
          false
        );
        return "done";
      case "result":
        // Reset accumulated content and show final result
        if (this.accumulatedContent) {
          this.accumulatedContent = "";
        }
        this.setAssistantMessage(data.formatted || data.message || "");
        this.appendProgressLog("Final response ready.", "success");
        return "done";
      default:
        if (data.message) {
          this.appendProgressLog(data.message, "muted");
        }
    }

    return null;
  }

  handleAgentResponse(agentResponse) {
    if (!agentResponse) return false;

    let content = "";
    if (agentResponse.formatted) {
      content = agentResponse.formatted;
    } else if (agentResponse.data) {
      if (typeof agentResponse.data === "object") {
        content = `<pre class="text-xs overflow-auto">${JSON.stringify(
          agentResponse.data,
          null,
          2
        )}</pre>`;
      } else {
        content = String(agentResponse.data);
      }
    } else if (agentResponse.message) {
      content = agentResponse.message;
    } else if (typeof agentResponse === "string") {
      content = agentResponse;
    } else {
      content = `<div class="text-yellow-600">⚠️ Response received but format unexpected</div><pre class="text-xs overflow-auto">${JSON.stringify(
        agentResponse,
        null,
        2
      )}</pre>`;
    }

    this.setAssistantMessage(content);
    this.appendProgressLog("Fallback agent responded.", "success");
    return true;
  }

  stepLabel(step = {}) {
    const number = step.number || step.id;
    const description =
      step.description || this.humanizeTool(step.tool) || "Step";
    const symbol = step.symbol ? ` (${step.symbol})` : "";
    return number
      ? `Step ${number}: ${description}${symbol}`
      : `${description}${symbol}`;
  }

  humanizeTool(tool) {
    if (!tool) return "";
    return tool
      .toString()
      .split("_")
      .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
      .join(" ");
  }

  escapeHtml(str) {
    if (!str) return "";
    return str
      .toString()
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
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

  renderMarkdown(content) {
    if (!content) {
      return "";
    }

    return marked.parse(content);
  }

  addMessage(role, content) {
    // Hide welcome screen and show messages on first message
    if (!this.hasMessages) {
      if (this.hasWelcomeScreenTarget) {
        this.welcomeScreenTarget.classList.add("hidden");
      }
      if (this.hasMessagesTarget) {
        this.messagesTarget.classList.remove("hidden");
      }
      this.hasMessages = true;
    }

    const messageDiv = document.createElement("div");
    messageDiv.className =
      "mb-2 flex animate-fade-in " +
      (role === "user" ? "justify-end" : "justify-start");

    const isAI = role === "assistant";
    const avatarStyle = isAI
      ? 'style="background: rgba(var(--accent-primary-rgb), 0.2); backdrop-filter: blur(8px);"'
      : 'style="background: linear-gradient(to right, var(--accent-primary), var(--accent-secondary));"';
    const messageStyle = isAI
      ? `style="background: rgba(var(--bg-secondary-rgb), 0.6); backdrop-filter: blur(8px); color: var(--text-primary); border: 1px solid var(--border-color);"`
      : `style="background: linear-gradient(to right, var(--accent-primary), var(--accent-secondary)); color: white;"`;

    messageDiv.innerHTML = `
      <div class="flex gap-2 max-w-[75%] ${
        role === "user" ? "flex-row-reverse" : ""
      }">
        <div class="flex-shrink-0 w-6 h-6 rounded-full flex items-center justify-center transition-transform duration-200 hover:scale-110" ${avatarStyle}>
          <span class="text-xs">${isAI ? "🤖" : "👤"}</span>
        </div>
        <div class="glass-card rounded-xl px-3 py-2 shadow-sm transition-all duration-200 hover:shadow-md ${
          isAI ? "prose prose-sm max-w-none" : ""
        }" ${messageStyle}>
          <div class="message-content text-xs leading-relaxed ${
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
