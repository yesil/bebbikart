// Server settings: bebbikart.config.json (repo root or cwd) + env vars (game-server.md "Networking").
import { existsSync, readFileSync } from "node:fs";
import { networkInterfaces } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { DEFAULT_CONFIG, mergeConfig } from "@bebbikart/shared";

const here = dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = resolve(here, "../../..");

/** First non-internal IPv4 address, preferring en0/en1 (Wi-Fi on a Mac). */
export function lanIp() {
  const nets = networkInterfaces();
  const names = Object.keys(nets).sort((a, b) => rank(a) - rank(b));
  for (const name of names) {
    for (const n of nets[name] ?? []) {
      if (n.family === "IPv4" && !n.internal) return n.address;
    }
  }
  return "localhost";
}
const rank = (name) => (name === "en0" ? 0 : name === "en1" ? 1 : name.startsWith("en") ? 2 : 3);

function fileConfig() {
  for (const p of [
    join(process.cwd(), "bebbikart.config.json"),
    join(REPO_ROOT, "bebbikart.config.json"),
  ]) {
    if (existsSync(p)) return JSON.parse(readFileSync(p, "utf8"));
  }
  return {};
}

export function loadSettings(env = process.env) {
  const port = Number(env.PORT ?? 8080);
  let config = mergeConfig(DEFAULT_CONFIG, fileConfig());
  if (env.BK_MAX_PLAYERS) config = mergeConfig(config, { maxPlayers: Number(env.BK_MAX_PLAYERS) });
  if (env.BK_SESSION_MINUTES)
    config = mergeConfig(config, { sessionMinutes: Number(env.BK_SESSION_MINUTES) });
  const pipeline = env.BK_PIPELINE ?? (env.DEEPSEEK_API_KEY ? "deepseek" : "mock");
  return {
    port,
    config,
    publicUrl: (env.PUBLIC_URL ?? `http://${lanIp()}:${port}`).replace(/\/$/, ""),
    adminPin: env.BK_ADMIN_PIN ?? "1234",
    gameKey: env.BK_GAME_KEY ?? "bebbikart-dev",
    dataDir: resolve(env.BK_DATA_DIR ?? join(REPO_ROOT, "apps/server/data")),
    webDist: resolve(env.BK_WEB_DIST ?? join(REPO_ROOT, "apps/web/dist")),
    pipeline, // "mock" | "deepseek"
    // Dev convenience: start a session at boot so phones can race straight away.
    autoStart: (env.BK_AUTOSTART ?? "1") !== "0",
    jobTimeoutMs: Number(env.BK_JOB_TIMEOUT_MS ?? 60_000),
  };
}
