import { Application } from "@hotwired/stimulus"
import ChatController from "./chat_controller"

window.Stimulus = Application.start()
Stimulus.register("chat", ChatController)

