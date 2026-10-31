// BebbiKart game server (WS2): REST API, WebSocket hub, asset jobs, static files.
//   bun run dev:server            (from the repo root)
// Env: PORT (8080), PUBLIC_URL, BK_ADMIN_PIN (1234), BK_GAME_KEY (bebbikart-dev),
//      DEEPSEEK_API_KEY (required; read from env, apps/server/.env, .env or packages/asset-pipeline/.env),
//      BK_AUTOSTART=0|1,
//      BK_DATA_DIR (apps/server/data), BK_SESSION_MINUTES, BK_MAX_PLAYERS
import { join } from "node:path";
import { openDb } from "./db.js";
import { DOTENV_FILES, loadDotEnvs, loadSettings, REPO_ROOT } from "./env.js";

const DOTENV_FILES_HINT = DOTENV_FILES.map((f) => `    ${f}`).join("\n");

import { createGame } from "./game.js";
import { createHttp, deviceIdOf } from "./http.js";
import { createHub } from "./hub.js";
import { createJobs } from "./jobs.js";

export function startServer(settings = loadSettings(), { log = console.log } = {}) {
  const db = openDb(settings.dbFile ?? join(settings.dataDir, "bebbikart.sqlite"));
  const hub = createHub({ settings, log });
  const game = createGame({ db, settings, hub, log });
  hub.attach(game);
  const jobs = createJobs({
    game,
    settings,
    log,
    logError: log === console.log ? console.error : log,
  });
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
  const envFiles = loadDotEnvs();
  const settings = loadSettings();
  if (!settings.hasDeepSeekKey) {
    console.error(`
  BebbiKart server: DEEPSEEK_API_KEY is not set, so racers can't be designed from drawings.
  Put DEEPSEEK_API_KEY=... in one of:
${DOTENV_FILES_HINT}
`);
    process.exit(1);
  }
  const { server } = startServer(settings);
  console.log(`
  BebbiKart server on port ${server.port}
    Phones:   ${settings.publicUrl}   (built site: bun run build:web)
              ${settings.publicUrl.replace(/:\d+$/, ":5173")}   (Vite, with bun run dev)
    Game:     ws://localhost:${server.port}/ws  (game key "${settings.gameKey}")
    Admin PIN ${settings.adminPin} · data ${settings.dataDir}
    Pipeline: DeepSeek (key from ${envFiles.length ? envFiles.map((f) => f.replace(`${REPO_ROOT}/`, "")).join(", ") : "the environment"})
`);
}
