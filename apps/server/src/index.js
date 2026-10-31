// BebbiKart game server (WS2): REST API, WebSocket hub, asset jobs, static files.
//   bun run dev:server            (from the repo root)
// Env: PORT (8080), PUBLIC_URL, BK_ADMIN_PIN (1234), BK_GAME_KEY (bebbikart-dev),
//      BK_PIPELINE=mock|deepseek (deepseek when DEEPSEEK_API_KEY is set), BK_AUTOSTART=0|1,
//      BK_DATA_DIR (apps/server/data), BK_SESSION_MINUTES, BK_MAX_PLAYERS
import { join } from "node:path";
import { openDb } from "./db.js";
import { loadSettings } from "./env.js";
import { createGame } from "./game.js";
import { createHttp, deviceIdOf } from "./http.js";
import { createHub } from "./hub.js";
import { createJobs } from "./jobs.js";

export function startServer(settings = loadSettings(), { log = console.log } = {}) {
  const db = openDb(settings.dbFile ?? join(settings.dataDir, "bebbikart.sqlite"));
  const hub = createHub({ settings, log });
  const game = createGame({ db, settings, hub, log });
  hub.attach(game);
  const jobs = createJobs({ game, settings, log });
  const handle = createHttp({ game, jobs, settings });

  const server = Bun.serve({
    port: settings.port,
    hostname: "0.0.0.0",
    maxRequestBodySize: 40 * 1024 * 1024,
    fetch(req, srv) {
      const url = new URL(req.url);
      if (url.pathname === "/ws") {
        if (srv.upgrade(req, { data: { deviceId: deviceIdOf(req) } })) return;
        return new Response("Expected a WebSocket upgrade", { status: 400 });
      }
      return handle(req, url);
    },
    websocket: hub.websocket,
  });

  return {
    server,
    game,
    jobs,
    hub,
    stop() {
      game.close();
      server.stop(true);
      db.close();
    },
  };
}

if (import.meta.main) {
  const settings = loadSettings();
  const { server } = startServer(settings);
  console.log(`
  BebbiKart server on port ${server.port}
    Phones:   ${settings.publicUrl}   (built site: bun run build:web)
              ${settings.publicUrl.replace(/:\d+$/, ":5173")}   (Vite, with bun run dev)
    Game:     ws://localhost:${server.port}/ws  (game key "${settings.gameKey}")
    Admin PIN ${settings.adminPin} · pipeline ${settings.pipeline} · data ${settings.dataDir}
`);
}
