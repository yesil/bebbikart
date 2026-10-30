import { defineConfig } from "vite";

// In dev, the phone site runs on Vite and forwards API and WebSocket calls to the Bun server.
export default defineConfig({
  server: {
    host: "0.0.0.0",
    port: 5173,
    proxy: {
      "/api": "http://localhost:8080",
      "/ws": { target: "ws://localhost:8080", ws: true },
    },
  },
});
