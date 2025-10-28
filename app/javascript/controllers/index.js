import { Application } from "@hotwired/stimulus";
import ChatController from "./chat_controller";
import TradingChatController from "./trading_chat_controller";

window.Stimulus = Application.start();
Stimulus.register("chat", ChatController);
Stimulus.register("trading-chat", TradingChatController);
