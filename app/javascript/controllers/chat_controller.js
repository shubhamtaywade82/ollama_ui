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
    "output",
    "sendBtn",
    "loading",
    "messages",
    "messagesContainer",
    "modelName",
  ];

  connect() {
    this.conversationHistory = [];
    this.loadModels();
    this.setupTextareaEnterHandler();
    this.setupTextareaAutoResize();
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

  setupTextareaAutoResize() {
    const textarea = this.promptTarget;

    // Initial resize
    this.resizeTextarea();

    // Auto-resize on input
    textarea.addEventListener("input", () => {
      this.resizeTextarea();
    });
  }

  resizeTextarea() {
    const textarea = this.promptTarget;
    // Reset height to auto to get the correct scrollHeight
    textarea.style.height = "auto";

    // Calculate the new height based on scrollHeight
    const scrollHeight = textarea.scrollHeight;
    const minHeight = 48; // 3rem = 48px
    const maxHeight = 192; // 12rem = 192px

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

  async submit(event) {
    event.preventDefault();
    this.accumulatedText = "";
    const model = this.modelTarget.value;
    const prompt = this.promptTarget.value;

    if (!model || !prompt.trim()) {
      alert("Please choose a model and enter a prompt.");
      return;
    }

    this.sendBtnTarget.disabled = true;
    this.promptTarget.disabled = true;

    // Add user message
    const userMessage = this.addMessage("user", prompt);

    // Add empty AI message for streaming
    const aiMessage = this.addMessage("assistant", "");
    this.currentMessageElement = aiMessage;

    // Scroll to bottom
    this.scrollToBottom();

    // Store in history
    this.conversationHistory.push({ role: "user", content: prompt });

    try {
      const res = await fetch("/chats/stream", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrf(),
        },
        body: JSON.stringify({ model, prompt }),
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
                this.currentMessageElement.querySelector(
                  ".message-content"
                ).innerHTML = html;
                this.scrollToBottom();
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
      this.sendBtnTarget.disabled = false;
      this.promptTarget.disabled = false;
      this.promptTarget.value = "";

      // Reset textarea height after clearing
      this.resizeTextarea();

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
    }, 1000);
  }

  csrf() {
    const meta = document.querySelector("meta[name='csrf-token']");
    return meta ? meta.content : "";
  }
}
