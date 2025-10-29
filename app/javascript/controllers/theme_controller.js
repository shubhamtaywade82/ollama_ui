import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["switcher", "themeIcon"];

  static values = {
    themes: {
      type: Array,
      default: ["light", "dark", "blue", "green", "purple", "orange", "red"],
    },
    current: { type: String, default: "light" },
  };

  connect() {
    // Load saved theme from localStorage
    const savedTheme = localStorage.getItem("theme") || "light";
    this.applyTheme(savedTheme);
  }

  switch(event) {
    const theme = event.currentTarget.dataset.theme;
    this.applyTheme(theme);
    localStorage.setItem("theme", theme);

    // Close dropdown if it exists
    const dropdown = this.element.querySelector("[data-theme-dropdown]");
    if (dropdown) {
      dropdown.classList.add("hidden");
    }
  }

  applyTheme(theme) {
    // Remove all theme classes
    const body = document.body;
    const html = document.documentElement;

    const themeClasses = [
      "theme-light",
      "theme-dark",
      "theme-blue",
      "theme-green",
      "theme-purple",
      "theme-orange",
      "theme-red",
    ];

    themeClasses.forEach((cls) => {
      body.classList.remove(cls);
      html.classList.remove(cls);
    });

    // Add current theme class
    body.classList.add(`theme-${theme}`);
    html.classList.add(`theme-${theme}`);

    this.currentValue = theme;

    // Update theme icon if available
    this.updateThemeIcon(theme);
  }

  updateThemeIcon(theme) {
    if (!this.hasThemeIconTarget) return;

    const icons = {
      light:
        '<svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20"><path d="M10 2a1 1 0 011 1v1a1 1 0 11-2 0V3a1 1 0 011-1zm4 8a4 4 0 11-8 0 4 4 0 018 0zm-.464 4.95l.707.707a1 1 0 001.414-1.414l-.707-.707a1 1 0 00-1.414 1.414zm2.12-10.607a1 1 0 010 1.414l-.706.707a1 1 0 11-1.414-1.414l.707-.707a1 1 0 011.414 0zM17 11a1 1 0 100-2h-1a1 1 0 100 2h1zm-7 4a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zM5.05 6.464A1 1 0 106.465 5.05l-.708-.707a1 1 0 00-1.414 1.414l.707.707zm1.414 8.486l-.707.707a1 1 0 01-1.414-1.414l.707-.707a1 1 0 011.414 1.414zM4 11a1 1 0 100-2H3a1 1 0 000 2h1z"/></svg>',
      dark: '<svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20"><path d="M17.293 13.293A8 8 0 016.707 2.707a8.001 8.001 0 1010.586 10.586z"/></svg>',
      blue: '<svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"/></svg>',
      green:
        '<svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"/></svg>',
      purple:
        '<svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"/></svg>',
      orange:
        '<svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20"><path d="M10 2a6 6 0 00-1.83 11.83l.01.01a2 2 0 11-.83 3.83l-.01-.01A8 8 0 0110 2z"/></svg>',
      red: '<svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"/></svg>',
    };

    this.themeIconTarget.innerHTML = icons[theme] || icons.light;
  }

  toggleDropdown(event) {
    event.stopPropagation();
    const dropdown = this.element.querySelector("[data-theme-dropdown]");
    if (dropdown) {
      dropdown.classList.toggle("hidden");

      // Close on outside click
      if (!dropdown.classList.contains("hidden")) {
        setTimeout(() => {
          const closeOnClick = (e) => {
            if (!this.element.contains(e.target)) {
              dropdown.classList.add("hidden");
              document.removeEventListener("click", closeOnClick);
            }
          };
          document.addEventListener("click", closeOnClick);
        }, 0);
      }
    }
  }
}
