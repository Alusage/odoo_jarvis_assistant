import { mount } from "@odoo/owl";
import { App } from "./components/App.js";

// Mount the application directly
mount(App, document.getElementById("app"), {
  name: "Odoo Client Dashboard",
  dev: true
});