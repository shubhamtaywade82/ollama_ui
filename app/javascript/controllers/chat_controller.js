import { Controller } from "@hotwired/stimulus";
import { marked } from "marked";

// Configure marked for better markdown rendering
marked.setOptions({
  breaks: true,
  gfm: true,
});

export default class extends Controller {
  static targets = ["model", "prompt", "output", "sendBtn", "loading"];

  connect() {
    this.loadModels();
  }

  async loadModels() {
    this.modelTarget.innerHTML = "";
    this.loadingTarget.classList.remove("hidden");

    try {
      const res = await fetch("/models");
      const json = await res.json();
      if (json.error) throw new Error(json.error);

      const placeholder = document.createElement("option");
      placeholder.value = "";
      placeholder.textContent = "Select a model…";
      this.modelTarget.appendChild(placeholder);

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
    this.outputTarget.innerHTML = "";
    this.accumulatedText = "";
    const model = this.modelTarget.value;
    const prompt = this.promptTarget.value;

    if (!model || !prompt.trim()) {
      alert("Please choose a model and enter a prompt.");
      return;
    }

    this.sendBtnTarget.disabled = true;
    const sendText = this.sendBtnTarget.querySelector(".send-text");
    if (sendText) sendText.textContent = "Thinking…";
    this.sendBtnTarget.classList.add("cursor-wait");

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

                // Render markdown
                const html = marked.parse(this.accumulatedText);
                this.outputTarget.innerHTML = html;
                this.outputTarget.scrollTop = this.outputTarget.scrollHeight;
              } else if (data.error) {
                throw new Error(data.error);
              }
            } catch (e) {
              console.error("Parse error:", e);
            }
          }
        }
      }

      if (sendText) sendText.textContent = "Send";
    } catch (e) {
      console.error(e);
      this.outputTarget.innerHTML = `<span class="text-red-400">Error: ${e.message}</span>`;
      this.outputTarget.classList.add("text-red-300");
    } finally {
      this.sendBtnTarget.disabled = false;
      this.sendBtnTarget.classList.remove("cursor-wait");
    }
  }

  csrf() {
    const meta = document.querySelector("meta[name='csrf-token']");
    return meta ? meta.content : "";
  }
}
