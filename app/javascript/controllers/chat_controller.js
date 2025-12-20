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
    this.loadModels();
    this.setupTextareaEnterHandler();
    this.setupTextareaAutoResize();
    this.setupCenteredTextareaAutoResize();
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
    const prompt = promptTextarea.value;

    if (!model || !prompt.trim()) {
      alert("Please choose a model and enter a prompt.");
      return;
    }

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

    // Add user message
    const userMessage = this.addMessage("user", prompt);

    // Add empty AI message for streaming
    const aiMessage = this.addMessage("assistant", "");
    this.currentMessageElement = aiMessage;

    // Scroll to bottom
    this.scrollToBottom();

    // Store in history
    this.conversationHistory.push({ role: "user", content: prompt });

    // Get deep mode state
    const deepMode =
      this.hasDeepModeToggleTarget && this.deepModeToggleTarget.checked;

    try {
      const res = await fetch("/chats/stream", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrf(),
        },
        body: JSON.stringify({ model, prompt, deep_mode: deepMode }),
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

                // Update the current AI message
                const html = marked.parse(this.accumulatedText);
                if (this.currentMessageElement) {
                  this.currentMessageElement.querySelector(
                    ".message-content"
                  ).innerHTML = html;
                  this.scrollToBottom();
                }
              } else if (data.type === "result" && data.text) {
                // Result event - ensure all content is displayed
                if (!this.accumulatedText) this.accumulatedText = "";
                // Only append if result text is different from accumulated
                if (!this.accumulatedText.includes(data.text)) {
                  this.accumulatedText += data.text;
                } else {
                  this.accumulatedText = data.text;
                }

                // Update the current AI message
                const html = marked.parse(this.accumulatedText);
                if (this.currentMessageElement) {
                  this.currentMessageElement.querySelector(
                    ".message-content"
                  ).innerHTML = html;
                  this.scrollToBottom();
                }
              } else if (data.type === "info" && data.text) {
                // Info messages (progress updates from agents)
                // Show as a temporary status message
                this.showInfoMessage(data.text);
              } else if (data.error) {
                throw new Error(data.error);
              }
            } catch (e) {
              console.error("Parse error:", e);
            }
          }
        }
      }
    } catch (e) {
      console.error(e);
      const errorHtml = `<span class="text-red-400">Error: ${e.message}</span>`;
      if (this.currentMessageElement) {
        this.currentMessageElement.querySelector(".message-content").innerHTML =
          errorHtml;
      } else {
        this.addMessage("assistant", errorHtml);
      }
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
        promptTextarea.value = "";

        // Reset textarea height after clearing
        this.resizeTextarea(
          promptTextarea,
          promptTextarea === this.promptCenteredTarget ? 24 : 32,
          promptTextarea === this.promptCenteredTarget ? 192 : 128
        );
      }

      // Store response in history
      if (this.accumulatedText) {
        this.conversationHistory.push({
          role: "assistant",
          content: this.accumulatedText,
        });
      }
    }
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
      "mb-4 flex " + (role === "user" ? "justify-end" : "justify-start");

    const isAI = role === "assistant";
    const avatarBg = isAI
      ? 'style="background-color: var(--accent-primary);"'
      : 'style="background: linear-gradient(to right, var(--accent-primary), var(--accent-secondary));"';
    const messageBg = isAI
      ? `style="background-color: var(--bg-secondary); color: var(--text-primary);"`
      : `style="background: linear-gradient(to right, var(--accent-primary), var(--accent-secondary)); color: white;"`;

    messageDiv.innerHTML = `
      <div class="flex gap-3 max-w-[85%] ${
        role === "user" ? "flex-row-reverse" : ""
      }">
        <div class="flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center" ${avatarBg}>
          ${isAI ? "🤖" : "👤"}
        </div>
        <div class="rounded-2xl px-4 py-3 shadow-sm ${
          isAI ? "prose prose-sm max-w-none" : ""
        }" ${messageBg}>
          <div class="message-content ${
            isAI ? "" : "whitespace-pre-wrap"
          }" style="color: var(--text-primary);">
            ${content}
          </div>
        </div>
      </div>
    `;

    if (this.hasMessagesTarget) {
      this.messagesTarget.appendChild(messageDiv);
    }
    return messageDiv;
  }

  scrollToBottom() {
    setTimeout(() => {
      this.messagesContainerTarget.scrollTop =
        this.messagesContainerTarget.scrollHeight;
    }, 1000);
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
        this.scrollToBottom();
      }
    }
  }

  csrf() {
    const meta = document.querySelector("meta[name='csrf-token']");
    return meta ? meta.content : "";
  }
}
