import { Controller } from "@hotwired/stimulus";

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
    this.outputTarget.textContent = "";
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
      const res = await fetch("/chats", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrf(),
        },
        body: JSON.stringify({ model, prompt }),
      });
      const json = await res.json();
      if (!res.ok) throw new Error(json.error || "Request failed");
      this.outputTarget.textContent = json.text;
    } catch (e) {
      console.error(e);
      this.outputTarget.textContent = `Error: ${e.message}`;
      this.outputTarget.classList.add("text-red-300");
    } finally {
      this.sendBtnTarget.disabled = false;
      if (sendText) sendText.textContent = "Send";
      this.sendBtnTarget.classList.remove("cursor-wait");
      this.outputTarget.classList.remove("text-red-300");
    }
  }

  csrf() {
    const meta = document.querySelector("meta[name='csrf-token']");
    return meta ? meta.content : "";
  }
}
