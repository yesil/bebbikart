// MSW handlers covering every REST route in contracts.md §6, so the phone site and admin
// console can be built before the server exists. In-memory state, seeded from fixtures.
import { delay, HttpResponse, http } from "msw";
import { parseBuildInput } from "../src/build.js";
import { DEFAULT_CONFIG, mergeConfig } from "../src/config.js";
import { newId } from "../src/ids.js";
import { NicknameBodySchema, SessionStartBodySchema } from "../src/schemas.js";
import { BUILDS, LEADERBOARD, playerView, RUNS, SESSION_RUNNING } from "./fixtures.js";

const fail = (status, code, message) => HttpResponse.json({ error: { code, message } }, { status });

/**
 * @param {object} [opts]
 * @param {number} [opts.delayMs]    simulated network latency (default 150)
 * @param {boolean} [opts.withPlayer] start with a ready racer for this device (default true)
 * @param {string} [opts.adminPin]   PIN the admin routes accept (default "1234")
 * @param {string} [opts.baseUrl]    origin to match, e.g. "http://localhost" in Node tests (default: same origin)
 */
export function mockHandlers({
  delayMs = 150,
  withPlayer = true,
  adminPin = "1234",
  baseUrl = "",
} = {}) {
  const now = () => new Date().toISOString();
  const state = {
    config: structuredClone(DEFAULT_CONFIG),
    session: structuredClone(SESSION_RUNNING),
    me: withPlayer ? structuredClone(playerView(0)) : undefined,
    others: [1, 2, 3, 4].map((i) => structuredClone(playerView(i))),
    runs: structuredClone(RUNS.filter((r) => r.playerId === playerView(0).id)),
    leaderboard: structuredClone(LEADERBOARD),
    rerolls: 0,
  };
  const allPlayers = () => (state.me ? [state.me, ...state.others] : state.others);
  const wait = () => delay(delayMs);

  const newPlayer = (nickname, deviceId) => ({
    id: newId("player"),
    sessionId: state.session.id,
    deviceId,
    nickname,
    status: "draft",
    connected: true,
    createdAt: now(),
    build: { ...structuredClone(BUILDS[0]), id: newId("build"), createdAt: now() },
  });

  const startJob = (player) => {
    player.status = "processing";
    player.job = {
      id: newId("job"),
      playerId: player.id,
      status: "queued",
      createdAt: now(),
      updatedAt: now(),
    };
    // The real job takes ~10–20 s; here it finishes after 3 s.
    setTimeout(() => {
      player.status = "ready";
      player.job = { ...player.job, status: "ready", updatedAt: now() };
      player.asset = structuredClone(playerView(0).asset);
    }, 3_000);
    return player.job;
  };

  const putBuild = async (request, player) => {
    const result = parseBuildInput(await request.json(), state.config);
    if (!result.ok) return fail(400, "invalid_build", result.errors.join("; "));
    player.build = { id: newId("build"), playerId: player.id, ...result.build, createdAt: now() };
    return HttpResponse.json(player.build);
  };

  const launch = (player) => {
    if (state.session.status !== "running")
      return fail(409, "session_not_running", "Session is not running");
    if (player.status !== "ready") return fail(409, "not_ready", "Racer is not ready yet");
    if (player.currentRun) return fail(409, "run_in_progress", "Racer is still on the track");
    // Go joins the line (contracts §2i); here nobody else waits, so the left half takes it now.
    const run = {
      id: newId("run"),
      playerId: player.id,
      buildId: player.build.id,
      status: "queued",
      queuedAt: now(),
      side: "left",
    };
    player.currentRun = run;
    // Finish the run after ~30 s so the phone can be built against the full loop.
    setTimeout(() => {
      const elapsedMs = 28_000 + Math.round(Math.random() * 6_000);
      const done = {
        ...run,
        status: "done",
        outcome: "finished",
        startedAt: run.queuedAt,
        endedAt: now(),
        elapsedMs,
        splits: { hills: 7_500, pond: elapsedMs - 22_500, crossing: 7_400, bends: 7_600 },
        events: [],
        boostsUsed: state.config.boostsPerRun,
        weatherSeen: [],
      };
      player.currentRun = undefined;
      player.lastRun = done;
      state.runs.push(done);
      if (player.bestTimeMs === undefined || elapsedMs < player.bestTimeMs) {
        player.bestTimeMs = elapsedMs;
        player.bestRunId = done.id;
        player.bestRun = done;
      }
    }, 30_000);
    const racing = [
      { side: "left", playerId: player.id, nickname: player.nickname, runId: run.id },
    ];
    return HttpResponse.json({ line: [], racing, split: false, skipped: [] }, { status: 202 });
  };

  const findPlayer = (id) => allPlayers().find((p) => p.id === id);
  const requireMe = () =>
    state.me ? null : fail(404, "not_found", "This device has no racer yet");
  const requireAdmin = (request) =>
    request.headers.get("x-admin-pin") === adminPin ? null : fail(401, "unauthorized", "Wrong PIN");

  return [
    http.post(`${baseUrl}/api/device`, async () => {
      await wait();
      return HttpResponse.json({ deviceId: state.me?.deviceId ?? "dev_mockdevice01" });
    }),
    http.get(`${baseUrl}/api/state`, async () => {
      await wait();
      return HttpResponse.json({ session: state.session, config: state.config, me: state.me });
    }),
    http.post(`${baseUrl}/api/players`, async ({ request }) => {
      await wait();
      if (state.me) return fail(409, "player_exists", "This device already has a racer");
      if (allPlayers().length >= state.config.maxPlayers)
        return fail(409, "server_full", "The track is full");
      const body = NicknameBodySchema.safeParse(await request.json());
      if (!body.success) return fail(400, "bad_request", "Racer name must be 1–16 characters");
      state.me = newPlayer(body.data.nickname, "dev_mockdevice01");
      return HttpResponse.json(state.me);
    }),
    http.patch(`${baseUrl}/api/players/me`, async ({ request }) => {
      await wait();
      const missing = requireMe();
      if (missing) return missing;
      const body = NicknameBodySchema.safeParse(await request.json());
      if (!body.success) return fail(400, "bad_request", "Racer name must be 1–16 characters");
      state.me.nickname = body.data.nickname;
      return HttpResponse.json(state.me);
    }),
    http.post(`${baseUrl}/api/players/me/reroll`, async () => {
      await wait();
      const missing = requireMe();
      if (missing) return missing;
      if (state.rerolls >= 3) return fail(409, "reroll_limit", "No more new looks");
      state.rerolls++;
      return HttpResponse.json(startJob(state.me));
    }),
    http.post(`${baseUrl}/api/players/me/drawings`, async ({ request }) => {
      await delay(delayMs * 4); // uploads are slow
      const missing = requireMe();
      if (missing) return missing;
      const form = await request.formData();
      if (!form.get("character") || !form.get("vehicle")) {
        return fail(400, "bad_request", "Both drawings are needed");
      }
      return HttpResponse.json(startJob(state.me));
    }),
    http.put(`${baseUrl}/api/players/me/build`, async ({ request }) => {
      await wait();
      return requireMe() ?? putBuild(request, state.me);
    }),
    http.post(`${baseUrl}/api/players/me/runs`, async () => {
      await wait();
      return requireMe() ?? launch(state.me);
    }),
    http.post(`${baseUrl}/api/players/me/runs/current/boost`, async () => {
      await delay(20);
      const missing = requireMe();
      if (missing) return missing;
      if (!state.me.currentRun) return fail(409, "not_found", "No run on the track");
      return HttpResponse.json({ ok: true });
    }),
    http.get(`${baseUrl}/api/leaderboard`, async () => {
      await wait();
      return HttpResponse.json(state.leaderboard);
    }),
    http.get(`${baseUrl}/api/players/me/runs`, async ({ request }) => {
      await wait();
      const missing = requireMe();
      if (missing) return missing;
      const limit = Number(new URL(request.url).searchParams.get("limit") ?? 10);
      return HttpResponse.json(state.runs.slice(-limit).reverse());
    }),

    // Admin
    http.post(`${baseUrl}/api/admin/session/start`, async ({ request }) => {
      await wait();
      const denied = requireAdmin(request);
      if (denied) return denied;
      const body = SessionStartBodySchema.parse(await request.json().catch(() => ({})));
      const durationMs = body.durationMs ?? state.config.sessionMinutes * 60_000;
      state.session = {
        id: state.session.id,
        status: "running",
        startedAt: now(),
        endsAt: new Date(Date.now() + durationMs).toISOString(),
        durationMs,
      };
      return HttpResponse.json(state.session);
    }),
    http.post(`${baseUrl}/api/admin/session/end`, async ({ request }) => {
      await wait();
      const denied = requireAdmin(request);
      if (denied) return denied;
      state.session = { ...state.session, status: "ended", endsAt: now() };
      return HttpResponse.json(state.session);
    }),
    http.post(`${baseUrl}/api/admin/session/reset`, async ({ request }) => {
      await wait();
      const denied = requireAdmin(request);
      if (denied) return denied;
      state.session = {
        id: newId("session"),
        status: "idle",
        durationMs: state.config.sessionMinutes * 60_000,
      };
      state.me = undefined;
      state.others = [];
      state.runs = [];
      state.leaderboard = [];
      return HttpResponse.json(state.session);
    }),
    http.get(`${baseUrl}/api/admin/players`, async ({ request }) => {
      await wait();
      return requireAdmin(request) ?? HttpResponse.json(allPlayers());
    }),
    http.post(`${baseUrl}/api/admin/players`, async ({ request }) => {
      await wait();
      const denied = requireAdmin(request);
      if (denied) return denied;
      const body = NicknameBodySchema.safeParse(await request.json());
      if (!body.success) return fail(400, "bad_request", "Racer name must be 1–16 characters");
      const player = newPlayer(body.data.nickname, "");
      player.connected = false;
      state.others.push(player);
      return HttpResponse.json(player);
    }),
    http.post(`${baseUrl}/api/admin/players/:id/drawings`, async ({ request, params }) => {
      await delay(delayMs * 4);
      const player = findPlayer(params.id);
      return (
        requireAdmin(request) ??
        (player ? HttpResponse.json(startJob(player)) : fail(404, "not_found", "No such racer"))
      );
    }),
    http.put(`${baseUrl}/api/admin/players/:id/build`, async ({ request, params }) => {
      await wait();
      const player = findPlayer(params.id);
      return (
        requireAdmin(request) ??
        (player ? putBuild(request, player) : fail(404, "not_found", "No such racer"))
      );
    }),
    http.post(`${baseUrl}/api/admin/players/:id/runs`, async ({ request, params }) => {
      await wait();
      const player = findPlayer(params.id);
      return (
        requireAdmin(request) ?? (player ? launch(player) : fail(404, "not_found", "No such racer"))
      );
    }),
    http.post(`${baseUrl}/api/admin/players/:id/approve`, async ({ request, params }) => {
      await wait();
      const denied = requireAdmin(request);
      if (denied) return denied;
      const player = findPlayer(params.id);
      if (!player) return fail(404, "not_found", "No such racer");
      startJob(player);
      return HttpResponse.json(player);
    }),
    http.delete(`${baseUrl}/api/admin/players/:id`, async ({ request, params }) => {
      await wait();
      const denied = requireAdmin(request);
      if (denied) return denied;
      if (state.me?.id === params.id) state.me = undefined;
      state.others = state.others.filter((p) => p.id !== params.id);
      return new HttpResponse(null, { status: 204 });
    }),
    http.patch(`${baseUrl}/api/admin/config`, async ({ request }) => {
      await wait();
      const denied = requireAdmin(request);
      if (denied) return denied;
      try {
        state.config = mergeConfig(state.config, await request.json());
      } catch (err) {
        return fail(400, "bad_request", err.message);
      }
      return HttpResponse.json(state.config);
    }),
  ];
}
