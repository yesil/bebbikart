import { defineConfig } from "vite";

// In dev, the phone site runs on Vite and forwards API, WebSocket and asset calls to the Bun server.
// Built files go to dist/static (not dist/assets): the server's /assets/* is racer packages.
export default defineConfig({
  build: { assetsDir: "static" },
  server: {
    host: "0.0.0.0",
    port: 5173,
    // Never move to another port silently: bun run dev frees 5173 or says what holds it.
    strictPort: true,
    // xfwd: the server sees which phone a call came from (network.js), not just Vite.
    proxy: {
      "/api": { target: "http://localhost:8080", xfwd: true },
      "/assets": { target: "http://localhost:8080", xfwd: true },
      "/ws": { target: "ws://localhost:8080", ws: true, xfwd: true },
    },
  },
});
