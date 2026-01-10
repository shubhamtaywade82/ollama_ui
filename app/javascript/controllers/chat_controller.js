import { Controller } from "@hotwired/stimulus";
import { marked } from "marked";

// Configure marked for better markdown rendering
marked.setOptions({
  breaks: true,
  gfm: true,
});

export default class extends Controller {
  static targets = [
    "model",
    "prompt",
    "promptCentered",
    "output",
    "sendBtn",
    "sendBtnCentered",
    "loading",
    "messages",
    "messagesContainer",
    "modelName",
    "deepModeToggle",
    "welcomeScreen",
    "bottomInput",
  ];

  connect() {
    this.conversationHistory = [];
    this.hasMessages = false;
    this.isUserScrolling = false;
    this.isNearBottom = true;
    this.loadModels();
    this.setupTextareaEnterHandler();
    this.setupTextareaAutoResize();
    this.setupCenteredTextareaAutoResize();
    this.setupScrollDetection();
  }

  setupScrollDetection() {
    if (!this.hasMessagesContainerTarget) return;

    const container = this.messagesContainerTarget;
    let scrollTimeout;

    container.addEventListener("scroll", () => {
      // Clear any existing timeout
      clearTimeout(scrollTimeout);

      // Check if user is near bottom (within 100px)
      const scrollBottom = container.scrollHeight - container.scrollTop - container.clientHeight;
      this.isNearBottom = scrollBottom < 100;

      // Set a timeout to reset isUserScrolling flag after scrolling stops
      scrollTimeout = setTimeout(() => {
        this.isUserScrolling = false;
      }, 150);
    });
  }

  setupTextareaEnterHandler() {
    // Handle Enter key for both textareas - submit, Shift+Enter for new line
    const setupHandler = (textarea) => {
      textarea.addEventListener("keydown", (e) => {
        if (e.key === "Enter" && !e.shiftKey) {
          e.preventDefault();
          // Find the form and trigger submit
          const form = textarea.closest("form");
          if (form) {
            form.dispatchEvent(
              new Event("submit", { bubbles: true, cancelable: true })
            );
          }
        }
      });
    };

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
    this.resizeTextarea(textarea, 32, 128); // min: 2rem, max: 8rem

    // Auto-resize on input
    textarea.addEventListener("input", () => {
      this.resizeTextarea(textarea, 32, 128);
    });
  }

  setupCenteredTextareaAutoResize() {
    if (!this.hasPromptCenteredTarget) return;

    const textarea = this.promptCenteredTarget;

    // Initial resize
    this.resizeTextarea(textarea, 24, 192); // min: 1.5rem, max: 12rem

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
    this.modelTarget.innerHTML = "";
    this.loadingTarget.classList.remove("hidden");

    try {
      const res = await fetch("/models");
      const json = await res.json();
      if (json.error) throw new Error(json.error);

      if (json.models.length === 0) {
        const opt = document.createElement("option");
        opt.value = "";
        opt.textContent =
          "No models installed - Install one with: ollama pull llama3.2";
        opt.disabled = true;
        this.modelTarget.appendChild(opt);
      } else {
        json.models.forEach((m) => {
          const opt = document.createElement("option");
          opt.value = m;
          opt.textContent = m;
          this.modelTarget.appendChild(opt);
        });

        // Set default to qwen model
        const qwenModel =
          json.models.find((m) => m.includes("qwen")) || json.models[0];
        this.modelTarget.value = qwenModel;

        // Update model name display
        if (this.modelNameTarget) {
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
      this.loadingTarget.classList.add("hidden");
    }
  }

  useExample(event) {
    const example = event.currentTarget.dataset.example;
    if (!example) return;

    // Determine which textarea to use
    const textarea =
      this.hasMessages && this.hasPromptTarget
        ? this.promptTarget
        : this.hasPromptCenteredTarget
        ? this.promptCenteredTarget
        : null;

    if (textarea) {
      textarea.value = example;
      textarea.focus();
      this.resizeTextarea(
        textarea,
        textarea === this.promptCenteredTarget ? 24 : 32,
        textarea === this.promptCenteredTarget ? 192 : 128
      );
    }
  }

  async submit(event) {
    event.preventDefault();
    this.accumulatedText = "";

    // Determine which textarea and button to use
    const isWelcomeScreen =
      !this.hasMessages &&
      this.hasWelcomeScreenTarget &&
      !this.welcomeScreenTarget.classList.contains("hidden");
    const promptTextarea =
      isWelcomeScreen && this.hasPromptCenteredTarget
        ? this.promptCenteredTarget
        : this.hasPromptTarget
        ? this.promptTarget
        : null;
    const sendBtn =
      isWelcomeScreen && this.hasSendBtnCenteredTarget
        ? this.sendBtnCenteredTarget
        : this.hasSendBtnTarget
        ? this.sendBtnTarget
        : null;

    if (!promptTextarea) {
      console.error("No prompt textarea found");
      return;
    }

    const model = this.modelTarget.value;
    const prompt = promptTextarea.value.trim(); // Trim spaces from start and end

    if (!model || !prompt) {
      alert("Please choose a model and enter a prompt.");
      return;
    }

    // Clear the textarea
    promptTextarea.value = "";
    this.resizeTextarea(
      promptTextarea,
      promptTextarea === this.promptCenteredTarget ? 24 : 32,
      promptTextarea === this.promptCenteredTarget ? 192 : 128
    );

    // Hide welcome screen and show messages/bottom input on first submission
    if (!this.hasMessages && this.hasWelcomeScreenTarget) {
      this.welcomeScreenTarget.classList.add("hidden");
      if (this.hasMessagesTarget) {
        this.messagesTarget.classList.remove("hidden");
      }
      if (this.hasBottomInputTarget) {
        this.bottomInputTarget.classList.remove("hidden");
      }
      this.hasMessages = true;
    }

    if (sendBtn) sendBtn.disabled = true;
    promptTextarea.disabled = true;

    // Add user message (store raw content for copying)
    const userMessage = this.addMessage("user", prompt);
    userMessage.dataset.rawContent = prompt;

    // Add empty AI message for streaming
    const aiMessage = this.addMessage("assistant", "");
    this.currentMessageElement = aiMessage;

    // Scroll to bottom (force scroll for new messages)
    this.scrollToBottom(true);

    // Get deep mode state
    const deepMode =
      this.hasDeepModeToggleTarget && this.deepModeToggleTarget.checked;

    try {
      // Send conversation history WITHOUT the current prompt
      // The backend will add the prompt to the conversation
      const res = await fetch("/chats/stream", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrf(),
        },
        body: JSON.stringify({
          model,
          prompt,
          deep_mode: deepMode,
          messages: this.conversationHistory, // Previous messages only (without current prompt)
        }),
      });

      if (!res.ok) {
        const json = await res.json();
        throw new Error(json.error || "Request failed");
      }

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
            try {
              const data = JSON.parse(line.slice(6));
              if (data.type === "content" && data.text) {
                // Append to the accumulated text
                if (!this.accumulatedText) this.accumulatedText = "";
                this.accumulatedText += data.text;

                // Clean artifacts from accumulated text
                const cleanedAccumulated = this.cleanModelArtifacts(this.accumulatedText);

                // Format and update the current AI message
                const formattedContent = this.formatMessageContent(
                  cleanedAccumulated
                );
                if (this.currentMessageElement) {
                  this.currentMessageElement.querySelector(
                    ".message-content"
                  ).innerHTML = formattedContent;
                  // Update raw content for copying
                  this.currentMessageElement.dataset.rawContent =
                    this.accumulatedText;
                  // Only auto-scroll if user is near bottom
                  this.scrollToBottom();
                }
              } else if (data.type === "result" && data.text) {
                // Result event - use the complete result text (it should contain all content)
                // Clean artifacts first
                this.accumulatedText = this.cleanModelArtifacts(data.text);

                // Format and render the final result (with tool call formatting)
                const formattedText = this.formatMessageContent(
                  this.accumulatedText
                );
                if (this.currentMessageElement) {
                  this.currentMessageElement.querySelector(
                    ".message-content"
                  ).innerHTML = formattedText;
                  // Update raw content for copying
                  this.currentMessageElement.dataset.rawContent =
                    this.accumulatedText;
                  // Only auto-scroll if user is near bottom
                  this.scrollToBottom();
                }
              } else if (data.type === "info" && data.text) {
                // Info messages (progress updates from agents)
                // Show as a temporary status message
                this.showInfoMessage(data.text);
              } else if (data.type === "error") {
                // Error event from stream
                const errorText =
                  data.text || data.message || "An error occurred";
                this.displayError(errorText);
                break; // Stop processing stream on error
              } else if (data.error) {
                // Error field in response
                this.displayError(data.error);
                break; // Stop processing stream on error
              }
            } catch (e) {
              console.error("Parse error:", e);
            }
          }
        }
      }
    } catch (e) {
      console.error(e);
      this.displayError(e.message);
    } finally {
      // Determine which textarea and button to use
      const isWelcomeScreen =
        !this.hasMessages &&
        this.hasWelcomeScreenTarget &&
        !this.welcomeScreenTarget.classList.contains("hidden");
      const promptTextarea =
        isWelcomeScreen && this.hasPromptCenteredTarget
          ? this.promptCenteredTarget
          : this.hasPromptTarget
          ? this.promptTarget
          : null;
      const sendBtn =
        isWelcomeScreen && this.hasSendBtnCenteredTarget
          ? this.sendBtnCenteredTarget
          : this.hasSendBtnTarget
          ? this.sendBtnTarget
          : null;

      if (sendBtn) sendBtn.disabled = false;
      if (promptTextarea) {
        promptTextarea.disabled = false;
        // Textarea is already cleared in submit() before sending
      }

      // Store user message and assistant response in history after successful response
      // Add user message to history
      this.conversationHistory.push({ role: "user", content: prompt });

      // Store assistant response
      if (this.accumulatedText) {
        // Clean artifacts and remove tool call JSON patterns from content before storing
        let cleanContent = this.cleanModelArtifacts(this.accumulatedText).trim();

        // Only store if there's actual content (not just tool call JSON)
        if (cleanContent) {
          this.conversationHistory.push({
            role: "assistant",
            content: cleanContent,
          });
        }
      }
    }
  }

  cleanModelArtifacts(text) {
    if (!text) return "";

    let cleaned = text;

    // Remove model-specific tokens
    cleaned = cleaned.replace(/<\|end_of_text\|>/g, "");
    cleaned = cleaned.replace(/<file_sep>/g, "\n\n");
    cleaned = cleaned.replace(/<\|endoftext\|>/gi, "");
    cleaned = cleaned.replace(/<\|end\|>/gi, "");

    // Remove repeated question-answer patterns
    // Pattern: "Question?<|end_of_text|>Question?Answer" -> "Question?Answer"
    const questionPattern = /([^?]+?\?)\s*<\|end_of_text\|>\s*\1\s*/gi;
    cleaned = cleaned.replace(questionPattern, "$1\n\n");

    // Remove duplicate consecutive sentences (more than 2 in a row)
    // But preserve line breaks for markdown formatting
    const lines = cleaned.split("\n");
    const uniqueLines = [];
    let lastLine = "";
    let repeatCount = 0;

    for (const line of lines) {
      const trimmed = line.trim();

      // Preserve empty lines (important for markdown)
      if (!trimmed) {
        uniqueLines.push("");
        continue;
      }

      const normalized = trimmed.toLowerCase();

      // If this line is the same as the last one, count repeats
      if (normalized === lastLine.toLowerCase() && normalized.length > 20) {
        repeatCount++;
        // Only keep if it's the first or second occurrence
        if (repeatCount <= 1) {
          uniqueLines.push(line);
        }
      } else {
        // New line, reset counter
        repeatCount = 0;
        lastLine = trimmed;
        uniqueLines.push(line);
      }
    }

    cleaned = uniqueLines.join("\n");

    // Clean up excessive blank lines (more than 2 consecutive)
    cleaned = cleaned.replace(/\n{3,}/g, "\n\n");

    // Clean up excessive spaces within lines (but preserve markdown structure)
    cleaned = cleaned.replace(/[ \t]+/g, " ");

    cleaned = cleaned.trim();

    return cleaned;
  }

  formatMessageContent(text) {
    if (!text) return "";

    // Clean model artifacts first
    let cleanedText = this.cleanModelArtifacts(text);

    // Extract and format tool calls - handle nested JSON objects properly
    // Pattern: {"name": "tool_name", "arguments": {...}}
    let formattedText = cleanedText;
    const matches = [];

    // Find tool call patterns by looking for the structure and parsing the full JSON
    // This approach finds the start of a tool call and then tries to parse the complete JSON
    const toolCallStartPattern =
      /\{\s*"name"\s*:\s*"(\w+)"\s*,\s*"arguments"\s*:\s*\{/g;
    let match;

    while ((match = toolCallStartPattern.exec(text)) !== null) {
      const startIndex = match.index;
      const toolName = match[1];

      // Try to find the complete JSON object by finding matching braces
      let braceCount = 0;
      let inString = false;
      let escapeNext = false;
      let endIndex = startIndex;

      for (let i = startIndex; i < text.length; i++) {
        const char = text[i];

        if (escapeNext) {
          escapeNext = false;
          continue;
        }

        if (char === "\\") {
          escapeNext = true;
          continue;
        }

        if (char === '"' && !escapeNext) {
          inString = !inString;
          continue;
        }

        if (!inString) {
          if (char === "{") braceCount++;
          if (char === "}") {
            braceCount--;
            if (braceCount === 0) {
              endIndex = i + 1;
              break;
            }
          }
        }
      }

      if (endIndex > startIndex) {
        const fullMatch = text.substring(startIndex, endIndex);
        try {
          const parsed = JSON.parse(fullMatch);
          if (parsed.name && parsed.arguments) {
            matches.push({
              fullMatch: fullMatch,
              name: toolName,
              arguments: parsed.arguments,
              index: startIndex,
            });
          }
        } catch (e) {
          // If parsing fails, skip this match
        }
      }
    }

    // Replace tool calls with formatted components (in reverse order to preserve indices)
    matches.reverse().forEach((toolCall) => {
      try {
        const args = JSON.parse(toolCall.arguments);
        const formattedToolCall = this.createToolCallComponent(
          toolCall.name,
          args
        );
        formattedText =
          formattedText.substring(0, toolCall.index) +
          formattedToolCall +
          formattedText.substring(toolCall.index + toolCall.fullMatch.length);
      } catch (e) {
        // If JSON parsing fails, just remove the tool call
        formattedText = formattedText.replace(toolCall.fullMatch, "");
      }
    });

    // Process markdown for the remaining content
    return marked.parse(formattedText);
  }

  createToolCallComponent(toolName, args) {
    const toolIcons = {
      get_quote: "📊",
      get_ohlc: "📈",
      search_instrument: "🔎",
      get_historical: "📉",
      get_option_chain: "⚡",
    };
    const icon = toolIcons[toolName] || "🔧";
    const argsStr = JSON.stringify(args, null, 2);
    const uniqueId = `tool-call-${Date.now()}-${Math.random()
      .toString(36)
      .substr(2, 9)}`;

    return `
      <div class="tool-call-display my-2 rounded-lg overflow-hidden transition-all duration-200"
           style="border: 1px solid var(--border-color); background-color: var(--bg-tertiary);">
        <button type="button" class="tool-call-header w-full px-3 py-2 flex items-center justify-between text-left hover:opacity-80 transition-opacity cursor-pointer"
                onclick="const content = this.nextElementSibling; const arrow = this.querySelector('.tool-call-arrow'); content.classList.toggle('hidden'); arrow.classList.toggle('rotate-180');"
                style="background-color: var(--bg-secondary); border: none;">
          <div class="flex items-center gap-2">
            <span class="text-base">${icon}</span>
            <span class="text-xs font-semibold" style="color: var(--text-primary);">Calling: <code style="background-color: var(--bg-tertiary); padding: 0.125rem 0.25rem; border-radius: 0.25rem;">${this.escapeHtml(
              toolName
            )}</code></span>
          </div>
          <svg class="tool-call-arrow w-4 h-4 transition-transform duration-200" style="color: var(--text-secondary);" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
          </svg>
        </button>
        <div class="tool-call-content hidden px-3 py-2">
          <div class="text-xs" style="color: var(--text-secondary);">
            <div class="text-xs font-medium mb-1" style="color: var(--text-primary);">Arguments:</div>
            <pre class="whitespace-pre-wrap text-xs overflow-x-auto" style="color: var(--text-primary); background-color: var(--bg-primary); padding: 0.5rem; border-radius: 0.25rem; border: 1px solid var(--border-color);">${this.escapeHtml(
              argsStr
            )}</pre>
          </div>
        </div>
      </div>
    `;
  }

  escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }

  addMessage(role, content) {
    // Show messages container and hide welcome screen if this is the first message
    if (!this.hasMessages && this.hasWelcomeScreenTarget) {
      this.welcomeScreenTarget.classList.add("hidden");
      if (this.hasMessagesTarget) {
        this.messagesTarget.classList.remove("hidden");
      }
      if (this.hasBottomInputTarget) {
        this.bottomInputTarget.classList.remove("hidden");
      }
      this.hasMessages = true;
    }

    const messageDiv = document.createElement("div");
    messageDiv.className =
      "mb-4 flex animate-fade-in " +
      (role === "user" ? "justify-end" : "justify-start");

    const isAI = role === "assistant";

    const messageId = `message-${Date.now()}-${Math.random()
      .toString(36)
      .substr(2, 9)}`;

    messageDiv.innerHTML = `
      <div class="flex gap-3 max-w-[90%] sm:max-w-[80%] lg:max-w-[75%] ${
        role === "user" ? "flex-row-reverse ml-auto" : ""
      }">
        <div class="avatar flex-shrink-0 ${isAI ? 'style="background: rgba(var(--accent-primary-rgb), 0.15); backdrop-filter: blur(8px);"' : 'style="background: var(--accent-primary);"'}">
          <span class="text-sm">${isAI ? "🤖" : "👤"}</span>
        </div>
        <div class="${isAI ? "flex-1" : ""} relative group">
          <div class="message-bubble ${
            isAI ? "message-bubble-assistant prose prose-sm max-w-none" : "message-bubble-user"
          }">
            <div class="message-content ${
              isAI
                ? "text-body"
                : "text-body"
            }" style="${
      isAI ? "color: var(--text-primary) !important;" : "color: white; font-weight: 400;"
    }">
              ${
                isAI
                  ? this.formatMessageContent(content)
                  : this.escapeHtml(content)
              }
            </div>
          </div>
          <!-- Copy Button -->
          <button
            type="button"
            class="copy-button absolute top-2.5 ${
              role === "user" ? "left-2.5" : "right-2.5"
            } opacity-0 group-hover:opacity-100 transition-all duration-200 p-2 rounded-lg hover:scale-110 active:scale-95 focus-visible-ring"
            style="background-color: rgba(var(--bg-secondary-rgb), 0.9); backdrop-filter: blur(8px); border: 1px solid var(--border-color); box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);"
            data-message-id="${messageId}"
            title="Copy to clipboard"
            aria-label="Copy message">
            <svg class="w-4 h-4" style="color: var(--text-primary);" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
            </svg>
          </button>
        </div>
      </div>
    `;

    // Store the raw content for copying (before formatting)
    messageDiv.dataset.rawContent = content;

    if (this.hasMessagesTarget) {
      this.messagesTarget.appendChild(messageDiv);
    }

    // Attach copy functionality to the button
    const copyButton = messageDiv.querySelector(".copy-button");
    if (copyButton) {
      copyButton.addEventListener("click", () => {
        this.copyMessageToClipboard(messageDiv);
      });
    }

    return messageDiv;
  }

  async copyMessageToClipboard(messageElement) {
    try {
      // Get the raw content (before formatting)
      const rawContent =
        messageElement.dataset.rawContent ||
        messageElement.querySelector(".message-content")?.textContent ||
        messageElement.querySelector(".message-content")?.innerText ||
        "";

      // Remove any tool call components from the text (get clean text)
      const cleanContent = rawContent.trim();

      if (!cleanContent) {
        // If no clean content, try to get the formatted text
        const formattedText =
          messageElement.querySelector(".message-content")?.textContent ||
          messageElement.querySelector(".message-content")?.innerText ||
          "";
        await navigator.clipboard.writeText(formattedText.trim());
      } else {
        await navigator.clipboard.writeText(cleanContent);
      }

      // Show feedback
      const copyButton = messageElement.querySelector(".copy-button");
      if (copyButton) {
        const originalHTML = copyButton.innerHTML;
        copyButton.innerHTML = `
          <svg class="w-3.5 h-3.5" style="color: var(--accent-primary);" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
          </svg>
        `;
        copyButton.style.color = "var(--accent-primary)";

        setTimeout(() => {
          copyButton.innerHTML = originalHTML;
          copyButton.style.color = "";
        }, 2000);
      }
    } catch (err) {
      console.error("Failed to copy:", err);
      // Fallback for older browsers
      const textArea = document.createElement("textarea");
      textArea.value =
        messageElement.querySelector(".message-content")?.textContent || "";
      textArea.style.position = "fixed";
      textArea.style.opacity = "0";
      document.body.appendChild(textArea);
      textArea.select();
      document.execCommand("copy");
      document.body.removeChild(textArea);
    }
  }

  scrollToBottom(force = false) {
    if (!this.hasMessagesContainerTarget) return;

    // Only auto-scroll if user is near bottom or if forced (e.g., new message sent)
    if (!force && !this.isNearBottom) {
      return;
    }

    // Use requestAnimationFrame for smoother scrolling
    requestAnimationFrame(() => {
      const container = this.messagesContainerTarget;
      container.scrollTop = container.scrollHeight;
      this.isNearBottom = true;
    });
  }

  showInfoMessage(text) {
    // Show temporary info message in the AI response
    if (this.currentMessageElement) {
      const infoDiv = document.createElement("div");
      infoDiv.className = "text-sm opacity-70 mb-2";
      infoDiv.textContent = text;
      const contentDiv =
        this.currentMessageElement.querySelector(".message-content");
      if (contentDiv && !contentDiv.querySelector(".info-message")) {
        infoDiv.classList.add("info-message");
        contentDiv.insertBefore(infoDiv, contentDiv.firstChild);
        // Only auto-scroll if user is near bottom
        this.scrollToBottom();
      }
    }
  }

  displayError(errorMessage) {
    // Display error message with proper formatting
    const escapedMessage = this.escapeHtml(errorMessage);
    const errorHtml = `
      <div class="error-message flex items-start gap-2 p-3 rounded-lg border" style="background-color: rgba(239, 68, 68, 0.1); border-color: rgba(239, 68, 68, 0.3);">
        <svg class="w-5 h-5 flex-shrink-0 mt-0.5" style="color: rgb(239, 68, 68);" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
        </svg>
        <div class="flex-1">
          <div class="font-semibold mb-1" style="color: rgb(239, 68, 68);">Error</div>
          <div class="text-sm leading-relaxed" style="color: var(--text-primary);">${escapedMessage}</div>
        </div>
      </div>
    `;

    if (this.currentMessageElement) {
      this.currentMessageElement.querySelector(".message-content").innerHTML =
        errorHtml;
      // Store raw content for copying
      this.currentMessageElement.dataset.rawContent = errorMessage;
    } else {
      const errorMessageElement = this.addMessage("assistant", errorHtml);
      errorMessageElement.dataset.rawContent = errorMessage;
    }

    // Force scroll for errors
    this.scrollToBottom(true);
  }

  csrf() {
    const meta = document.querySelector("meta[name='csrf-token']");
    return meta ? meta.content : "";
  }
}
