// REST API (contracts §6) + static files (/assets, built phone site).
import { existsSync, statSync } from "node:fs";
import { join, normalize, sep } from "node:path";
import {
  mergeConfig,
  NicknameBodySchema,
  RENDER_KEYS,
  SessionStartBodySchema,
} from "@bebbikart/shared";
import { ApiError } from "./errors.js";

const COOKIE = "bk_device";

function readCookie(req, name) {
  const header = req.headers.get("cookie") ?? "";
  for (const part of header.split(";")) {
    const [k, ...v] = part.trim().split("=");
    if (k === name) return decodeURIComponent(v.join("="));
  }
  return undefined;
}
export const deviceIdOf = (req) => readCookie(req, COOKIE);

const json = (data, status = 200, headers = {}) => Response.json(data, { status, headers });
const errorResponse = (code, message, status) => json({ error: { code, message } }, status);

async function body(req, schema) {
  let data;
  try {
    data = await req.json();
  } catch {
    data = {};
  }
  if (!schema) return data;
  const r = schema.safeParse(data);
  if (!r.success)
    throw new ApiError("bad_request", r.error.issues.map((i) => i.message).join("; "), 400);
  return r.data;
}

/** Serves a file from `root`, refusing paths that escape it. */
function serveFile(root, rel) {
  const path = normalize(join(root, rel));
  if (!path.startsWith(root + sep) && path !== root) return null;
  if (!existsSync(path) || !statSync(path).isFile()) return null;
  return new Response(Bun.file(path), { headers: { "cache-control": "no-cache" } });
}

export function createHttp({ game, jobs, settings }) {
  const assetsDir = join(settings.dataDir, "assets");

  const me = (req) => game.mustPlayer(deviceIdOf(req));
  /** Go: a free race answers 201 with the run; a duel joins the line, 202 with the line. */
  const go = (playerId) => {
    const out = game.launch(playerId);
    return json(out, game.config.mode === "duel" ? 202 : 201);
  };
  const admin = (req) => {
    if (req.headers.get("x-admin-pin") !== settings.adminPin)
      throw new ApiError("unauthorized", "Wrong PIN", 401);
  };
  const adminPlayer = (id) => {
    const p = game.players.get(id);
    if (!p) throw new ApiError("not_found", "No such racer", 404);
    return p;
  };

  /** [method, pattern, handler(req, params, url)] */
  const routes = [
    ["GET", "/api/health", () => json({ ok: true, gameOnline: null })],
    ["GET", "/api/join", () => json({ url: settings.publicUrl })],
    [
      "POST",
      "/api/device",
      (req) => {
        const existing = deviceIdOf(req);
        const d = game.ensureDevice(existing);
        const headers =
          d.id === existing
            ? {}
            : {
                "set-cookie": `${COOKIE}=${d.id}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${60 * 60 * 24 * 30}`,
              };
        return json({ deviceId: d.id }, 200, headers);
      },
    ],
    [
      "GET",
      "/api/state",
      (req) => {
        const p = game.playerForDevice(deviceIdOf(req));
        return json({
          session: game.session,
          config: game.config,
          ...(p ? { me: game.playerView(p.id) } : {}),
        });
      },
    ],
    [
      "POST",
      "/api/players",
      async (req) => {
        const deviceId = deviceIdOf(req);
        if (!deviceId || game.ensureDevice(deviceId).id !== deviceId)
          throw new ApiError("unauthorized", "Call POST /api/device first", 401);
        const { nickname } = await body(req, NicknameBodySchema);
        return json(game.createPlayer(deviceId, nickname), 201);
      },
    ],
    [
      "PATCH",
      "/api/players/me",
      async (req) => {
        const p = me(req);
        const { nickname } = await body(req, NicknameBodySchema);
        return json(game.rename(p.id, nickname));
      },
    ],
    [
      "DELETE",
      "/api/players/me",
      (req) => {
        game.removePlayer(me(req).id, "player_quit");
        return new Response(null, { status: 204 });
      },
    ],
    ["POST", "/api/players/me/reroll", (req) => json(jobs.reroll(me(req).id))],
    [
      "POST",
      "/api/players/me/drawings",
      async (req) => json(await jobs.upload(me(req).id, await formOf(req)), 202),
    ],
    [
      "PUT",
      "/api/players/me/build",
      async (req) => json(game.setBuild(me(req).id, await body(req))),
    ],
    // Duel mode (contracts §2i): Go joins the line, 202 with the line.
    ["POST", "/api/players/me/runs", (req) => go(me(req).id)],
    ["DELETE", "/api/players/me/queue", (req) => json(game.leaveLine(me(req).id))],
    ["POST", "/api/players/me/runs/current/boost", (req) => json({ ok: game.boost(me(req).id) })],
    [
      "GET",
      "/api/players/me/runs",
      (req, _p, url) => {
        const limit = Math.min(50, Number(url.searchParams.get("limit") ?? 10) || 10);
        return json(game.playerRuns(me(req).id).slice(0, limit));
      },
    ],
    ["GET", "/api/leaderboard", () => json(game.leaderboard())],

    // ---- admin
    [
      "POST",
      "/api/admin/session/start",
      async (req) => {
        const { durationMs } = await body(req, SessionStartBodySchema);
        return json(game.startSession(durationMs ?? game.config.sessionMinutes * 60_000));
      },
    ],
    ["POST", "/api/admin/session/end", (_req) => json(game.endSession())],
    [
      "POST",
      "/api/admin/session/reset",
      async (_req) => {
        const s = game.resetSession();
        if (game.config.deleteUploadsOnReset) await jobs.deleteAll();
        return json(s);
      },
    ],
    ["GET", "/api/admin/players", (_req) => json(game.allPlayerViews())],
    [
      "POST",
      "/api/admin/players",
      async (req) => {
        const { nickname } = await body(req, NicknameBodySchema);
        return json(game.createPlayer(undefined, nickname), 201);
      },
    ],
    [
      "POST",
      "/api/admin/players/:id/drawings",
      async (req, p) => json(await jobs.upload(adminPlayer(p.id).id, await formOf(req)), 202),
    ],
    [
      "POST",
      "/api/admin/players/:id/build",
      async (req, p) => json(game.setBuild(adminPlayer(p.id).id, await body(req))),
    ],
    [
      "PUT",
      "/api/admin/players/:id/build",
      async (req, p) => json(game.setBuild(adminPlayer(p.id).id, await body(req))),
    ],
    ["POST", "/api/admin/players/:id/runs", (_req, p) => go(adminPlayer(p.id).id)],
    [
      "POST",
      "/api/admin/players/:id/approve",
      (_req, p) => {
        jobs.approve(adminPlayer(p.id).id);
        return json(game.playerView(p.id));
      },
    ],
    [
      "DELETE",
      "/api/admin/players/:id",
      (_req, p) => {
        game.removePlayer(adminPlayer(p.id).id);
        return new Response(null, { status: 204 });
      },
    ],
    [
      "PATCH",
      "/api/admin/config",
      async (req) => {
        let next;
        try {
          next = mergeConfig(game.config, await body(req));
        } catch (err) {
          throw new ApiError("bad_request", err.message, 400);
        }
        return json(game.patchConfig(next));
      },
    ],

    // ---- game
    [
      "PUT",
      "/api/game/renders/:playerId/:key",
      async (req, p) => {
        if (req.headers.get("x-game-key") !== settings.gameKey)
          throw new ApiError("unauthorized", "Bad game key", 401);
        if (!RENDER_KEYS.includes(p.key))
          throw new ApiError("bad_request", "Unknown render key", 400);
        const pl = adminPlayer(p.playerId);
        const pkg = game.manifests.get(pl.id)?.packageId;
        if (!pkg) throw new ApiError("not_found", "Racer has no asset package yet", 404);
        const bytes = new Uint8Array(await req.arrayBuffer());
        if (bytes.length < 8 || bytes[0] !== 0x89 || bytes[1] !== 0x50)
          throw new ApiError("bad_request", "Expected a PNG body", 400);
        await Bun.write(join(assetsDir, pkg, `${p.key}.png`), bytes);
        game.setRender(pl.id, p.key, `/assets/${pkg}/${p.key}.png?v=${Date.now()}`);
        return new Response(null, { status: 204 });
      },
    ],
  ].map(([method, pattern, handler]) => {
    const names = [];
    const re = new RegExp(
      `^${pattern.replace(/:([a-zA-Z]+)/g, (_, n) => {
        names.push(n);
        return "([^/]+)";
      })}$`,
    );
    return { method, re, names, handler };
  });

  async function formOf(req) {
    try {
      return await req.formData();
    } catch {
      throw new ApiError("bad_request", "Expected multipart form data", 400);
    }
  }

  return async function handle(req, url) {
    const path = url.pathname;
    if (path.startsWith("/api/")) {
      let methodMismatch = false;
      for (const r of routes) {
        const m = r.re.exec(path);
        if (!m) continue;
        if (r.method !== req.method) {
          methodMismatch = true;
          continue;
        }
        const params = Object.fromEntries(r.names.map((n, i) => [n, decodeURIComponent(m[i + 1])]));
        try {
          if (path.startsWith("/api/admin/")) admin(req);
          return await r.handler(req, params, url);
        } catch (err) {
          if (err instanceof ApiError) return errorResponse(err.code, err.message, err.status);
          console.error(err);
          return errorResponse("bad_request", err.message ?? "Something went wrong", 500);
        }
      }
      return errorResponse(
        "not_found",
        methodMismatch ? "Method not allowed" : "Not found",
        methodMismatch ? 405 : 404,
      );
    }
    if (path.startsWith("/assets/")) {
      // Never serve uploads: only packages (spec, downscaled drawings, game renders).
      return (
        serveFile(assetsDir, decodeURIComponent(path.slice("/assets/".length))) ??
        new Response("Not found", { status: 404 })
      );
    }
    // Built phone site, with SPA fallback.
    if (existsSync(settings.webDist)) {
      const file = path !== "/" && serveFile(settings.webDist, decodeURIComponent(path.slice(1)));
      if (file) return file;
      const index = serveFile(settings.webDist, "index.html");
      if (index) return index;
    }
    return new Response(
      `<h1>BebbiKart server</h1><p>The phone site isn't built yet. Run <code>bun run --cwd apps/web build</code>, or use the Vite dev server on port 5173.</p>`,
      { headers: { "content-type": "text/html" } },
    );
  };
}
