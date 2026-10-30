// Hello-world server (M0). WS2 replaces this with the real REST API and WS hub.
import { DEFAULT_CONFIG, makeMsg, parseMsg, WS_CLOSE_UNAUTHORIZED } from "@bebbikart/shared";

const port = Number(process.env.PORT ?? 8080);

const server = Bun.serve({
  port,
  hostname: "0.0.0.0",
  fetch(req, srv) {
    const url = new URL(req.url);
    if (url.pathname === "/ws") {
      if (srv.upgrade(req)) return;
      return new Response("Expected a WebSocket upgrade", { status: 400 });
    }
    if (url.pathname === "/api/health") {
      return Response.json({ ok: true, config: DEFAULT_CONFIG });
    }
    return Response.json({ error: { code: "not_found", message: "Not found" } }, { status: 404 });
  },
  websocket: {
    message(ws, raw) {
      const parsed = parseMsg("gameToServer", String(raw));
      if (!parsed.ok) {
        ws.send(JSON.stringify(makeMsg("serverToGame", "error", parsed.error)));
        ws.close(WS_CLOSE_UNAUTHORIZED, parsed.error.message);
        return;
      }
      console.log(`[ws] ${parsed.msg.type}`, parsed.msg.payload);
    },
  },
});

console.log(`BebbiKart server on http://localhost:${server.port}`);
