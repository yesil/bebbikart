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

/**
 * Loads KEY=value lines from .env files into `env` without overriding what is already set.
 * Bun only reads the .env in the current directory (apps/server when started via the scripts),
 * so the server also reads the repo root and packages/asset-pipeline ones (where the CLI's key lives).
 * @returns {string[]} the files that were read
 */
export function loadDotEnvs(env = process.env, files = DOTENV_FILES) {
  const read = [];
  for (const file of files) {
    if (!existsSync(file)) continue;
    read.push(file);
    for (const line of readFileSync(file, "utf8").split(/\r?\n/)) {
      const m = line.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
      if (!m || m[1] in env) continue;
      env[m[1]] = m[2].replace(/^(['"])(.*)\1$/, "$2");
    }
  }
  return read;
}
export const DOTENV_FILES = [
  join(REPO_ROOT, "apps/server/.env"),
  join(REPO_ROOT, ".env"),
  join(REPO_ROOT, "packages/asset-pipeline/.env"),
];

export function loadSettings(env = process.env) {
  const port = Number(env.PORT ?? 8080);
  let config = mergeConfig(DEFAULT_CONFIG, fileConfig());
  if (env.BK_MAX_PLAYERS) config = mergeConfig(config, { maxPlayers: Number(env.BK_MAX_PLAYERS) });
  if (env.BK_SESSION_MINUTES)
    config = mergeConfig(config, { sessionMinutes: Number(env.BK_SESSION_MINUTES) });
  return {
    port,
    config,
    publicUrl: (env.PUBLIC_URL ?? `http://${lanIp()}:${port}`).replace(/\/$/, ""),
    adminPin: env.BK_ADMIN_PIN ?? "1234",
    gameKey: env.BK_GAME_KEY ?? "bebbikart-dev",
    dataDir: resolve(env.BK_DATA_DIR ?? join(REPO_ROOT, "apps/server/data")),
    webDist: resolve(env.BK_WEB_DIST ?? join(REPO_ROOT, "apps/web/dist")),
    // Dev convenience: start a session at boot so phones can race straight away.
    autoStart: (env.BK_AUTOSTART ?? "1") !== "0",
    hasAnthropicKey: !!env.ANTHROPIC_API_KEY,
    // Four Claude passes (look, design, critique, refine) plus retries for invalid replies.
    jobTimeoutMs: Number(env.BK_JOB_TIMEOUT_MS ?? 300_000),
    // Racers designed at once. A group of 8 joining together all start right away (3 made the
    // 8th kid wait ~4 min); more wait in line, and the SDK backs off on rate limits.
    designConcurrency: Number(env.BK_DESIGN_CONCURRENCY ?? 8),
  };
}
