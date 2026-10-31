// End-to-end over real HTTP + WebSockets: phone creates a racer, uploads drawings (a fake design client stands in for Claude),
// the game gets the roster, the phone presses Go, the game races and reports, the phone gets the result.
import { afterAll, beforeAll, expect, test } from "bun:test";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createMockClient } from "@bebbikart/asset-pipeline";
import { DEFAULT_BUILD, DEFAULT_CONFIG, makeMsg } from "@bebbikart/shared";
import { loadSettings, REPO_ROOT } from "../src/env.js";
import { startServer } from "../src/index.js";

const SAMPLES = join(REPO_ROOT, "packages/asset-pipeline/samples");
let srv;
let base;
let settings;

beforeAll(() => {
  settings = {
    ...loadSettings({}),
    port: 0,
    dataDir: mkdtempSync(join(tmpdir(), "bk-test-")),
    designClient: createMockClient({ designId: "pair01" }),
    config: { ...DEFAULT_CONFIG, launchCooldownMs: 0 },
  };
  settings.dbFile = ":memory:";
  srv = startServer(settings, { log: () => {} });
  base = `http://localhost:${srv.server.port}`;
  settings.publicUrl = base;
});
afterAll(() => srv?.stop());

/** A WS client that records messages and can wait for one by type. */
function client(headers, hello) {
  const ws = new WebSocket(`${base.replace("http", "ws")}/ws`, { headers });
  const msgs = [];
  const waiters = [];
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    msgs.push(m);
    for (const w of [...waiters]) {
      if (!w.pred(m)) continue;
      waiters.splice(waiters.indexOf(w), 1);
      w.res(m);
    }
  };
  const opened = new Promise((r) => (ws.onopen = r));
  return {
    ws,
    msgs,
    async start() {
      await opened;
      ws.send(JSON.stringify(makeMsg("phoneToServer", "hello", hello)));
    },
    send: (ch, type, payload) => ws.send(JSON.stringify(makeMsg(ch, type, payload))),
    wait(type, pred = () => true, ms = 8000) {
      const hit = msgs.find((m) => m.type === type && pred(m.payload));
      if (hit) return Promise.resolve(hit);
      return new Promise((res, rej) => {
        const w = { pred: (m) => m.type === type && pred(m.payload), res };
        waiters.push(w);
        setTimeout(() => rej(new Error(`timeout waiting for ${type}`)), ms);
      });
    },
  };
}

test("phone → drawings → racer on the big screen → race → result", async () => {
  // Each designer pass takes a moment, like the real one, so the big screen's roster (debounced
  // 250 ms) gets to show the design steps before the racer is ready.
  const instant = settings.designClient.complete;
  settings.designClient.complete = async (...args) => {
    await Bun.sleep(300);
    return instant(...args);
  };
  // Game connects first.
  const game = client({}, { role: "game", gameKey: settings.gameKey });
  await game.start();
  const gw = await game.wait("welcome");
  expect(gw.payload.roster).toEqual([]);

  // Phone: device cookie, player, ws.
  const dev = await fetch(`${base}/api/device`, { method: "POST" });
  const cookie = dev.headers.get("set-cookie").split(";")[0];
  const h = { cookie, "content-type": "application/json" };
  const created = await fetch(`${base}/api/players`, {
    method: "POST",
    headers: h,
    body: JSON.stringify({ nickname: "  Mila " }),
  });
  expect(created.status).toBe(201);
  const player = await created.json();
  expect(player.nickname).toBe("Mila");
  expect(player.status).toBe("draft");
  const again = await fetch(`${base}/api/players`, {
    method: "POST",
    headers: h,
    body: JSON.stringify({ nickname: "x" }),
  });
  expect((await again.json()).error.code).toBe("player_exists");

  const phone = client({ cookie }, { role: "phone" });
  await phone.start();
  const pw = await phone.wait("welcome");
  expect(pw.payload.me.id).toBe(player.id);

  // Not ready yet → Go refused.
  const early = await fetch(`${base}/api/players/me/runs`, { method: "POST", headers: h });
  expect((await early.json()).error.code).toBe("not_ready");

  // Upload the sample pair.
  const form = new FormData();
  form.append(
    "character",
    new File([readFileSync(join(SAMPLES, "pair01-character-cat.jpg"))], "c.jpg", {
      type: "image/jpeg",
    }),
  );
  form.append(
    "vehicle",
    new File([readFileSync(join(SAMPLES, "pair01-vehicle-kart.jpg"))], "v.jpg", {
      type: "image/jpeg",
    }),
  );
  const up = await fetch(`${base}/api/players/me/drawings`, {
    method: "POST",
    headers: { cookie },
    body: form,
  });
  expect(up.status).toBe(202);
  expect((await up.json()).status).toBe("queued");

  const ready = await phone.wait("player.updated", (p) => p.status === "ready", 20000);
  // The phone saw the pipeline stage while designing, and the stage is gone once ready.
  expect(
    phone.msgs.some((m) => m.type === "player.updated" && m.payload.job?.stage === "designing"),
  ).toBe(true);
  expect(ready.payload.job.stage).toBeUndefined();
  // The big screen saw the steps too (roster stage), in order.
  const seen = game.msgs
    .filter((m) => m.type === "roster.updated")
    .flatMap((m) => m.payload.map((e) => e.stage).filter(Boolean));
  expect(seen.length).toBeGreaterThan(0);
  settings.designClient.complete = instant;
  expect(ready.payload.asset.spec.title).toBe("The Purple Flash");
  const roster = await game.wait("roster.updated", (r) => r.some((e) => e.status === "ready"));
  const entry = roster.payload.find((e) => e.playerId === player.id);
  expect(entry.connected).toBe(true);
  expect(entry.assetBaseUrl).toContain(entry.asset.packageId);
  const drawing = await fetch(`${base}${entry.asset.drawings.vehicle}`);
  expect(drawing.status).toBe(200);

  // Game uploads a render.
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0]);
  const put = await fetch(`${base}/api/game/renders/${player.id}/hero`, {
    method: "PUT",
    headers: { "x-game-key": settings.gameKey },
    body: png,
  });
  expect(put.status).toBe(204);
  await phone.wait("player.updated", (p) => !!p.asset?.renders?.hero);

  // Go! over WS.
  phone.send("phoneToServer", "phone.go", {});
  const start = await game.wait("run.start");
  const runId = start.payload.runId;
  expect(start.payload.build.stars.speed).toBe(DEFAULT_BUILD.stars.speed);
  await phone.wait("run.queued");
  // The start countdown: the phone hears when the lights go green.
  game.send("gameToServer", "game.run.grid", { runId, goInMs: 3000 });
  const grid = await phone.wait("run.grid");
  expect(grid.payload).toEqual({ runId, goInMs: 3000 });
  // Every phone hears who is on the grid (friends can join the countdown).
  const call = await phone.wait("grid.updated");
  expect(call.payload).toEqual({
    goInMs: 3000,
    racers: [{ playerId: player.id, nickname: "Mila" }],
  });
  game.send("gameToServer", "game.run.started", { runId });
  await phone.wait("run.started");
  phone.send("phoneToServer", "phone.boost", { runId });
  await game.wait("run.boost", (p) => p.runId === runId);
  // "Show me on the big screen" reaches the game; the game's camera cut reaches the phones.
  phone.send("phoneToServer", "phone.watch", { runId });
  await game.wait("run.watch", (p) => p.runId === runId);
  game.send("gameToServer", "game.camera", { runId });
  const onCamera = await phone.wait("camera.updated", (p) => p.runId === runId);
  expect(onCamera.payload.playerId).toBe(player.id);
  game.send("gameToServer", "game.camera", {});
  await phone.wait("camera.updated", (p) => p.playerId === undefined);
  game.send("gameToServer", "game.run.section", { runId, section: "hills", splitMs: 8000 });
  await phone.wait("run.section");
  game.send("gameToServer", "game.run.finished", {
    runId,
    elapsedMs: 32100,
    splits: { hills: 8000, pond: 8000, crossing: 8000, bends: 8100 },
    stretches: [
      { id: "bumpy_road", ms: 5000, lostMs: 0 },
      { id: "knoll_road", ms: 2000, lostMs: 0 },
      { id: "hilltop", ms: 1000, lostMs: 0 },
      { id: "stone_bridge", ms: 8000, lostMs: 0 },
      { id: "hedge_lane", ms: 8000, lostMs: 0 },
      { id: "rainbow_bends", ms: 8100, lostMs: 0 },
    ],
    events: [{ kind: "boost_perfect", section: "hills", stretch: "bumpy_road", atMs: 3000 }],
    boostsUsed: 1,
    weatherSeen: [],
    trace: { runId, hz: 10, samples: [0, 0, 0, 0, 0] },
  });
  const ended = await phone.wait("run.ended");
  expect(ended.payload.isPersonalBest).toBe(true);
  expect(ended.payload.rank).toBe(1);
  expect(ended.payload.coach.text.length).toBeGreaterThan(0);
  // Its stretches come back with the star each tests; it is the session's fastest on all of them.
  expect(ended.payload.stretches.map((s) => [s.id, s.ability, s.bestMs, s.fastestMs])).toEqual([
    ["bumpy_road", "bounce", undefined, 5000],
    ["knoll_road", null, undefined, 2000],
    ["hilltop", "speed", undefined, 1000],
    ["stone_bridge", null, undefined, 8000],
    ["hedge_lane", null, undefined, 8000],
    ["rainbow_bends", "grip", undefined, 8100],
  ]);
  expect(ended.payload.stretches[0].fastestNickname).toBe(player.nickname);
  const lb = await game.wait("leaderboard.updated", (l) => l.length === 1);
  expect(lb.payload[0].bestTimeMs).toBe(32100);

  // Second run gets the ghost.
  phone.send("phoneToServer", "phone.go", {});
  const start2 = await game.wait("run.start", (p) => p.runId !== runId);
  expect(start2.payload.bestTrace.runId).toBe(runId);
  expect(start2.payload.bestSplits.hills).toBe(8000);

  // Game disconnects → active run aborted.
  game.ws.close();
  const aborted = await phone.wait("run.ended", (p) => p.run.outcome === "aborted");
  expect(aborted.payload.run.id).toBe(start2.payload.runId);
  const offline = await fetch(`${base}/api/players/me/runs`, { method: "POST", headers: h });
  expect((await offline.json()).error.code).toBe("game_offline");
  phone.ws.close();
}, 40000);

test("bad hello is refused, admin needs the PIN", async () => {
  const bad = client({}, { role: "game", gameKey: "nope" });
  const closed = new Promise((r) => (bad.ws.onclose = (e) => r(e.code)));
  await bad.start();
  expect(await closed).toBe(4001);
  const r = await fetch(`${base}/api/admin/players`);
  expect(r.status).toBe(401);
  const ok = await fetch(`${base}/api/admin/players`, {
    headers: { "x-admin-pin": settings.adminPin },
  });
  expect((await ok.json()).length).toBeGreaterThanOrEqual(1);
});

test("a design API failure fails the job loudly: no sample design, phone sees the error", async () => {
  settings.designClient.complete = async () => {
    throw new Error("HTTP 401: invalid api key");
  };
  const dev = await fetch(`${base}/api/device`, { method: "POST" });
  const cookie = dev.headers.get("set-cookie").split(";")[0];
  await fetch(`${base}/api/players`, {
    method: "POST",
    headers: { cookie, "content-type": "application/json" },
    body: JSON.stringify({ nickname: "Fails" }),
  });
  const form = new FormData();
  for (const [k, f] of [
    ["character", "pair01-character-cat.jpg"],
    ["vehicle", "pair01-vehicle-kart.jpg"],
  ])
    form.append(k, new File([readFileSync(join(SAMPLES, f))], `${k}.jpg`, { type: "image/jpeg" }));
  await fetch(`${base}/api/players/me/drawings`, {
    method: "POST",
    headers: { cookie },
    body: form,
  });
  let me;
  for (let i = 0; i < 50; i++) {
    me = (await (await fetch(`${base}/api/state`, { headers: { cookie } })).json()).me;
    if (me.job?.status === "failed") break;
    await Bun.sleep(100);
  }
  expect(me.job.status).toBe("failed");
  expect(me.job.error).toContain("HTTP 401");
  expect(me.status).toBe("draft");
  expect(me.asset).toBeUndefined();
});

test("village loop: laps, run.lap deltas, Pit in, best lap ranks", async () => {
  settings.designClient.complete = createMockClient({ designId: "pair02" }).complete;
  const admin = { "x-admin-pin": settings.adminPin, "content-type": "application/json" };
  const locked = await fetch(`${base}/api/admin/config`, {
    method: "PATCH",
    headers: admin,
    body: JSON.stringify({ track: "village" }),
  });
  expect(locked.status).toBe(409);
  expect((await locked.json()).error.code).toBe("track_locked");
  await fetch(`${base}/api/admin/session/end`, { method: "POST", headers: admin });
  const patched = await fetch(`${base}/api/admin/config`, {
    method: "PATCH",
    headers: admin,
    body: JSON.stringify({ track: "village" }),
  });
  expect((await patched.json()).track).toBe("village");
  await fetch(`${base}/api/admin/session/start`, { method: "POST", headers: admin, body: "{}" });

  const game = client({}, { role: "game", gameKey: settings.gameKey });
  await game.start();
  await game.wait("welcome");
  const dev = await fetch(`${base}/api/device`, { method: "POST" });
  const cookie = dev.headers.get("set-cookie").split(";")[0];
  await fetch(`${base}/api/players`, {
    method: "POST",
    headers: { cookie, "content-type": "application/json" },
    body: JSON.stringify({ nickname: "Lapper" }),
  });
  const phone = client({ cookie }, { role: "phone" });
  await phone.start();
  await phone.wait("welcome");
  const form = new FormData();
  for (const [k, f] of [
    ["character", "pair02-character-robot.jpg"],
    ["vehicle", "pair02-vehicle-rocket-shoe.jpg"],
  ])
    form.append(k, new File([readFileSync(join(SAMPLES, f))], `${k}.jpg`, { type: "image/jpeg" }));
  await fetch(`${base}/api/players/me/drawings`, {
    method: "POST",
    headers: { cookie },
    body: form,
  });
  await phone.wait("player.updated", (p) => p.status === "ready", 20000);

  phone.send("phoneToServer", "phone.go", {});
  const start = await game.wait("run.start", (p) => p.playerId !== undefined);
  const runId = start.payload.runId;
  const queued = await phone.wait("run.queued");
  expect(queued.payload.run.track).toBe("village");
  // The laps travel with the run, to the big screen and the phone.
  expect(start.payload.lapsPerRun).toBe(DEFAULT_CONFIG.lapsPerRun);
  expect(queued.payload.run.lapsPerRun).toBe(DEFAULT_CONFIG.lapsPerRun);
  game.send("gameToServer", "game.run.started", { runId });
  const splits = { hills: 5000, pond: 5000, crossing: 5000, bends: 5000 };
  // Village stretches of a lap of `ms`: the farm takes `farm` of it.
  const lapStretches = (ms, farm) => [
    { id: "main_street", ms: ms - farm - 2000, lostMs: 0 },
    { id: "farm", ms: farm, lostMs: 0 },
    { id: "square", ms: 2000, lostMs: 0 },
  ];
  game.send("gameToServer", "game.run.lap", {
    runId,
    lap: 1,
    lapMs: 20000,
    elapsedMs: 20000,
    splits,
    stretches: lapStretches(20000, 4000),
    weatherSeen: [],
    isBest: true,
  });
  const lap1 = await phone.wait("run.lap", (p) => p.lap === 1);
  expect(lap1.payload.isLapBest).toBe(true);
  expect(lap1.payload.deltaVsBestLapMs).toBeUndefined();
  game.send("gameToServer", "game.run.lap", {
    runId,
    lap: 2,
    lapMs: 19000,
    elapsedMs: 39000,
    splits,
    stretches: lapStretches(19000, 3500),
    weatherSeen: ["rain"],
    isBest: true,
  });
  const lap2 = await phone.wait("run.lap", (p) => p.lap === 2);
  expect(lap2.payload.isLapBest).toBe(true);
  expect(lap2.payload.deltaVsBestLapMs).toBe(-1000);

  phone.send("phoneToServer", "phone.stop", { runId });
  await game.wait("run.stop", (p) => p.runId === runId);
  game.send("gameToServer", "game.run.finished", {
    runId,
    elapsedMs: 60000,
    laps: [20000, 19000, 21000],
    bestLapMs: 19000,
    splits,
    stretches: lapStretches(19000, 3500),
    events: [],
    boostsUsed: 0,
    weatherSeen: [],
    trace: { runId, hz: 10, samples: [0, 0, 0, 0, 0] },
  });
  const ended = await phone.wait("run.ended", (p) => p.run.id === runId);
  expect(ended.payload.run.lapStretches).toHaveLength(2); // the laps the game reported
  expect(ended.payload.stretches.find((s) => s.id === "farm")).toMatchObject({
    ms: 3500,
    ability: "grip",
    fastestMs: 3500,
  });
  expect(ended.payload.run.laps).toEqual([20000, 19000, 21000]);
  expect(ended.payload.run.bestLapMs).toBe(19000);
  expect(ended.payload.isPersonalBest).toBe(true);
  const me = await phone.wait("player.updated", (p) => p.bestTimeMs === 19000);
  expect(me.payload.bestRun.id).toBe(runId);
  const lb = await (await fetch(`${base}/api/leaderboard`)).json();
  expect(lb.find((e) => e.nickname === "Lapper").bestTimeMs).toBe(19000);

  // A failed run that still completed a faster lap counts.
  await Bun.sleep(10);
  phone.send("phoneToServer", "phone.go", {});
  const start2 = await game.wait("run.start", (p) => p.runId !== runId);
  // Every lap reaches the server as game.run.lap before the run ends (contracts §2d, §2f).
  game.send("gameToServer", "game.run.lap", {
    runId: start2.payload.runId,
    lap: 1,
    lapMs: 18000,
    elapsedMs: 18000,
    splits,
    stretches: lapStretches(18000, 3000),
    weatherSeen: ["wind"],
    isBest: true,
  });
  await phone.wait("run.lap", (p) => p.runId === start2.payload.runId);
  game.send("gameToServer", "game.run.failed", {
    runId: start2.payload.runId,
    reason: "off_track",
    section: "bends",
    elapsedMs: 30000,
    laps: [18000],
    bestLapMs: 18000,
    splits,
    stretches: [{ id: "main_street", ms: 12000, lostMs: 0 }],
    stretch: "farm",
    events: [{ kind: "slip", section: "crossing", stretch: "farm", atMs: 29000, timeLostMs: 900 }],
    boostsUsed: 0,
    weatherSeen: [],
  });
  const ended2 = await phone.wait("run.ended", (p) => p.run.id === start2.payload.runId);
  expect(ended2.payload.run.outcome).toBe("failed");
  expect(ended2.payload.isPersonalBest).toBe(true);
  expect(ended2.payload.run.failStretch).toBe("farm");
  expect(ended2.payload.coach).toMatchObject({ key: "fail_slip", stretch: "farm" });
  // The player's best on main street comes from the earlier run's laps (19000 - 3500 - 2000);
  // the session's fastest is this run's own lap (18000 - 3000 - 2000), with that lap's setup:
  // the build and the weather on that lap (contracts §2f).
  const setup = {
    stars: { speed: 4, jump: 4, grip: 4, water: 2, stability: 4, bounce: 2 },
    routes: { pond: "bridge", ramp: "around", crossing: "sheltered" },
    style: "balanced",
  };
  expect(ended2.payload.stretches).toEqual([
    {
      id: "main_street",
      ms: 12000,
      lostMs: 0,
      ability: "grip",
      bestMs: 13500,
      fastestMs: 13000,
      fastestPlayerId: me.payload.id,
      fastestNickname: "Lapper",
      fastestSetup: { ...setup, weather: ["wind"] },
    },
  ]);
  await phone.wait("player.updated", (p) => p.bestTimeMs === 18000);
  // The leaderboard shows what the best lap was set with, in that lap's weather.
  const lb2 = await (await fetch(`${base}/api/leaderboard`)).json();
  expect(lb2.find((e) => e.nickname === "Lapper").setup).toEqual({ ...setup, weather: ["wind"] });
  game.ws.close();
  phone.ws.close();
}, 40000);

test("game manager sets track and laps from the big screen; a new session starts clean", async () => {
  const game = client({}, { role: "game", gameKey: settings.gameKey });
  await game.start();
  const welcome = await game.wait("welcome");
  expect(welcome.payload.session.status).toBe("running");
  const oldSession = welcome.payload.session.id;
  const phone = client({}, { role: "phone" });
  await phone.start();
  await phone.wait("welcome");
  expect((await (await fetch(`${base}/api/leaderboard`)).json()).length).toBeGreaterThan(0);

  // Track can't change mid-session: the error names the message it refuses.
  const refused = makeMsg("gameToServer", "game.config.set", { track: "countryside" });
  game.ws.send(JSON.stringify(refused));
  const err = await game.wait("error", (p) => p.refId === refused.id);
  expect(err.payload.code).toBe("track_locked");

  // Unknown or player-only fields are rejected by the contract.
  const bad = {
    v: 1,
    type: "game.config.set",
    id: "m1",
    ts: new Date().toISOString(),
    payload: { maxPlayers: 1 },
  };
  game.ws.send(JSON.stringify(bad));
  expect((await game.wait("error", (p) => p.code === "bad_message")).payload.code).toBe(
    "bad_message",
  );

  // Switch track: end, set, start (back to back).
  game.send("gameToServer", "game.session.end", {});
  game.send("gameToServer", "game.config.set", { track: "countryside", lapsPerRun: 5 });
  game.send("gameToServer", "game.session.start", {});
  await game.wait("session.updated", (s) => s.status === "ended");
  const cfg = await phone.wait("config.updated", (c) => c.track === "countryside");
  expect(cfg.payload.lapsPerRun).toBe(5);
  const fresh = await phone.wait("session.updated", (s) => s.status === "running");
  expect(fresh.payload.id).not.toBe(oldSession);
  expect(await (await fetch(`${base}/api/leaderboard`)).json()).toEqual([]);

  // Starting a running session is refused loudly.
  const again = makeMsg("gameToServer", "game.session.start", {});
  game.ws.send(JSON.stringify(again));
  expect((await game.wait("error", (p) => p.refId === again.id)).payload.code).toBe("bad_request");
  game.ws.close();
  phone.ws.close();
});

test("autostart: a session that runs out is followed by a new one, also across restarts", async () => {
  const dir = mkdtempSync(join(tmpdir(), "bk-session-"));
  const mk = (over) => ({
    ...settings,
    port: 0,
    dataDir: dir,
    dbFile: join(dir, "db.sqlite"),
    config: { ...settings.config, sessionMinutes: 0.003 }, // 180 ms
    ...over,
  });
  const get = async (s) =>
    (await (await fetch(`http://localhost:${s.server.port}/api/state`)).json()).session;

  let s = startServer(mk({}), { log: () => {} });
  const first = await get(s);
  expect(first.status).toBe("running");
  await Bun.sleep(400);
  const next = await get(s);
  expect(next.status).toBe("running");
  expect(next.id).not.toBe(first.id);
  s.stop();

  // Manual mode: time runs out and the session stays ended.
  s = startServer(mk({ autoStart: false }), { log: () => {} });
  await Bun.sleep(400);
  expect((await get(s)).status).toBe("ended");
  s.stop();

  // Back in autostart: the ended session is replaced at boot.
  s = startServer(mk({ config: { ...settings.config } }), { log: () => {} });
  expect((await get(s)).status).toBe("running");
  s.stop();
});

test("quit: the racer leaves the race, the big screen and the leaderboard; the phone goes back to join", async () => {
  const game = client({}, { role: "game", gameKey: settings.gameKey });
  await game.start();
  await game.wait("welcome");
  const dev = await fetch(`${base}/api/device`, { method: "POST" });
  const cookie = dev.headers.get("set-cookie").split(";")[0];
  const created = await fetch(`${base}/api/players`, {
    method: "POST",
    headers: { cookie, "content-type": "application/json" },
    body: JSON.stringify({ nickname: "Quitter" }),
  });
  const playerId = (await created.json()).id;
  const phone = client({ cookie }, { role: "phone" });
  await phone.start();
  await phone.wait("welcome");
  const form = new FormData();
  for (const [k, f] of [
    ["character", "pair02-character-robot.jpg"],
    ["vehicle", "pair02-vehicle-rocket-shoe.jpg"],
  ])
    form.append(k, new File([readFileSync(join(SAMPLES, f))], `${k}.jpg`, { type: "image/jpeg" }));
  await fetch(`${base}/api/players/me/drawings`, {
    method: "POST",
    headers: { cookie },
    body: form,
  });
  await phone.wait("player.updated", (p) => p.status === "ready", 20000);
  await game.wait("roster.updated", (r) => r.some((e) => e.playerId === playerId));

  phone.send("phoneToServer", "phone.go", {});
  const start = await game.wait("run.start", (p) => p.playerId === playerId);

  const res = await fetch(`${base}/api/players/me`, { method: "DELETE", headers: { cookie } });
  expect(res.status).toBe(204);
  const abort = await game.wait("run.abort", (p) => p.runId === start.payload.runId);
  expect(abort.payload.reason).toBe("player_quit");
  await phone.wait("player.removed", (p) => p.playerId === playerId);
  await Bun.sleep(400); // roster.updated is debounced
  const roster = game.msgs.filter((m) => m.type === "roster.updated").at(-1).payload;
  expect(roster.some((e) => e.playerId === playerId)).toBe(false);
  const lb = await (await fetch(`${base}/api/leaderboard`)).json();
  expect(lb.some((e) => e.playerId === playerId)).toBe(false);
  const st = await (await fetch(`${base}/api/state`, { headers: { cookie } })).json();
  expect(st.me).toBeUndefined();

  // Quitting twice fails loudly; joining again makes a new racer.
  const again = await fetch(`${base}/api/players/me`, { method: "DELETE", headers: { cookie } });
  expect(again.status).toBe(404);
  const rejoin = await fetch(`${base}/api/players`, {
    method: "POST",
    headers: { cookie, "content-type": "application/json" },
    body: JSON.stringify({ nickname: "Quitter" }),
  });
  expect(rejoin.status).toBe(201);
  game.ws.close();
  phone.ws.close();
}, 30000);

test("a saved build that breaks the star budget can't launch: invalid_build, no run", async () => {
  // The racer gets the 20-star default build; this server only allows 10 (like a build saved
  // before a budget change).
  const s = startServer(
    { ...settings, port: 0, dbFile: ":memory:", config: { ...settings.config, starsTotal: 10 } },
    { log: () => {} },
  );
  const sBase = `http://localhost:${s.server.port}`;
  const game = new WebSocket(`${sBase.replace("http", "ws")}/ws`);
  await new Promise((r) => (game.onopen = r));
  game.send(
    JSON.stringify(makeMsg("phoneToServer", "hello", { role: "game", gameKey: settings.gameKey })),
  );
  const dev = await fetch(`${sBase}/api/device`, { method: "POST" });
  const cookie = dev.headers.get("set-cookie").split(";")[0];
  await fetch(`${sBase}/api/players`, {
    method: "POST",
    headers: { cookie, "content-type": "application/json" },
    body: JSON.stringify({ nickname: "Oldie" }),
  });
  const form = new FormData();
  for (const [k, f] of [
    ["character", "pair01-character-cat.jpg"],
    ["vehicle", "pair01-vehicle-kart.jpg"],
  ])
    form.append(k, new File([readFileSync(join(SAMPLES, f))], `${k}.jpg`, { type: "image/jpeg" }));
  await fetch(`${sBase}/api/players/me/drawings`, {
    method: "POST",
    headers: { cookie },
    body: form,
  });
  for (let i = 0; i < 200; i++) {
    const st = await (await fetch(`${sBase}/api/state`, { headers: { cookie } })).json();
    if (st.me.status === "ready") break;
    await Bun.sleep(100);
  }

  const res = await fetch(`${sBase}/api/players/me/runs`, { method: "POST", headers: { cookie } });
  expect(res.status).toBe(400);
  const err = (await res.json()).error;
  expect(err.code).toBe("invalid_build");
  expect(err.message).toContain("stars must add up to 10, got 20");
  game.close();
  s.stop();
}, 30000);

test("language: the big screen picks it, every phone follows live (config.updated, welcome, state)", async () => {
  const game = client({}, { role: "game", gameKey: settings.gameKey });
  await game.start();
  expect((await game.wait("welcome")).payload.config.language).toBe("en");
  const phone = client({}, { role: "phone" });
  await phone.start();
  await phone.wait("welcome");

  // Allowed mid-session (unlike the track): phones switch right away.
  game.send("gameToServer", "game.config.set", { language: "de" });
  const cfg = await phone.wait("config.updated", (c) => c.language === "de");
  expect(cfg.payload.track).toBe(settings.config.track);
  await game.wait("config.updated", (c) => c.language === "de");

  // A phone that connects later, or boots over REST, gets it too.
  const late = client({}, { role: "phone" });
  await late.start();
  expect((await late.wait("welcome")).payload.config.language).toBe("de");
  expect((await (await fetch(`${base}/api/state`)).json()).config.language).toBe("de");

  // Only the contract's languages: anything else is refused, nothing changes.
  const bad = {
    v: 1,
    type: "game.config.set",
    id: "lang1",
    ts: new Date().toISOString(),
    payload: { language: "fr" },
  };
  game.ws.send(JSON.stringify(bad));
  expect((await game.wait("error", (p) => p.refId === "lang1")).payload.code).toBe("bad_message");
  expect((await (await fetch(`${base}/api/state`)).json()).config.language).toBe("de");

  game.send("gameToServer", "game.config.set", { language: "en" });
  await phone.wait("config.updated", (c) => c.language === "en");
  for (const c of [game, phone, late]) c.ws.close();
});

test("two racers with the same name: the second is 'Mia 2' everywhere, renaming keeps it unique", async () => {
  const join = async (nickname) => {
    const dev = await fetch(`${base}/api/device`, { method: "POST" });
    const cookie = dev.headers.get("set-cookie").split(";")[0];
    const res = await fetch(`${base}/api/players`, {
      method: "POST",
      headers: { cookie, "content-type": "application/json" },
      body: JSON.stringify({ nickname }),
    });
    return { cookie, me: await res.json() };
  };
  const a = await join("Twin");
  const b = await join("twin");
  const c = await join("Twin");
  expect(a.me.nickname).toBe("Twin");
  expect(b.me.nickname).toBe("twin 2");
  expect(c.me.nickname).toBe("Twin 3");
  // Renaming to your own name keeps it; to a taken one gets a number.
  const rename = async (who, nickname) =>
    (
      await fetch(`${base}/api/players/me`, {
        method: "PATCH",
        headers: { cookie: who.cookie, "content-type": "application/json" },
        body: JSON.stringify({ nickname }),
      })
    ).json();
  expect((await rename(a, "Twin")).nickname).toBe("Twin");
  expect((await rename(c, "Sixteen chars ok")).nickname).toBe("Sixteen chars ok");
  expect((await rename(b, "Sixteen chars ok")).nickname).toBe("Sixteen chars 2");
});

test("a heat: racers who left together see each other's places on their phones, done when all are home", async () => {
  const game = client({}, { role: "game", gameKey: settings.gameKey });
  await game.start();
  await game.wait("welcome");
  const racer = async (nickname, pair) => {
    const dev = await fetch(`${base}/api/device`, { method: "POST" });
    const cookie = dev.headers.get("set-cookie").split(";")[0];
    const me = await (
      await fetch(`${base}/api/players`, {
        method: "POST",
        headers: { cookie, "content-type": "application/json" },
        body: JSON.stringify({ nickname }),
      })
    ).json();
    const phone = client({ cookie }, { role: "phone" });
    await phone.start();
    await phone.wait("welcome");
    const form = new FormData();
    for (const [k, f] of [
      ["character", `${pair}-character-cat.jpg`],
      ["vehicle", `${pair}-vehicle-kart.jpg`],
    ])
      form.append(
        k,
        new File([readFileSync(join(SAMPLES, f))], `${k}.jpg`, { type: "image/jpeg" }),
      );
    await fetch(`${base}/api/players/me/drawings`, {
      method: "POST",
      headers: { cookie },
      body: form,
    });
    await phone.wait("player.updated", (p) => p.status === "ready", 20000);
    return { me, phone };
  };
  const a = await racer("Heat A", "pair01");
  const b = await racer("Heat B", "pair01");
  const runIds = [];
  for (const r of [a, b]) {
    r.phone.send("phoneToServer", "phone.go", {});
    runIds.push((await game.wait("run.start", (p) => p.playerId === r.me.id)).payload.runId);
  }
  for (const runId of runIds) game.send("gameToServer", "game.run.started", { runId });
  // Live place in the heat: A is further along than B.
  for (const [runId, progress] of [
    [runIds[0], 0.5],
    [runIds[1], 0.3],
  ])
    game.send("gameToServer", "game.run.progress", {
      runId,
      progress,
      elapsedMs: 9000,
      section: "pond",
      boostsLeft: 3,
    });
  const pa = await a.phone.wait("run.progress", (p) => p.runId === runIds[0] && p.progress === 0.5);
  expect([pa.payload.place, pa.payload.of]).toEqual([1, 2]);
  const pb = await b.phone.wait("run.progress", (p) => p.runId === runIds[1] && p.progress === 0.3);
  expect([pb.payload.place, pb.payload.of]).toEqual([2, 2]);
  const result = { splits: {}, stretches: [], events: [], boostsUsed: 0, weatherSeen: [] };
  // B goes through the pond's ford; A (below) takes the bridge and fails further on.
  const via = (pond, pondMs) => [
    { id: "bumpy_road", ms: 5000, lostMs: 0 },
    { id: "knoll_road", ms: 2000, lostMs: 0 },
    { id: "hilltop", ms: 1000, lostMs: 0 },
    { id: pond, ms: pondMs, lostMs: 0 },
  ];
  game.send("gameToServer", "game.run.finished", {
    runId: runIds[1],
    elapsedMs: 31000,
    ...result,
    stretches: [
      ...via("ford", 6000),
      { id: "hedge_lane", ms: 8000, lostMs: 0 },
      { id: "rainbow_bends", ms: 9000, lostMs: 0 },
    ],
    weatherSeen: ["rain"],
    trace: { runId: runIds[1], hz: 10, samples: [] },
  });
  // B is home first: both phones hear it, A is still racing.
  for (const r of [a, b]) {
    const h = (await r.phone.wait("run.heat", (p) => !p.done)).payload;
    expect(h.heatId).toBe(runIds[0]);
    expect(h.entries.map((e) => [e.nickname, e.place, e.timeMs, e.outcome])).toEqual([
      ["Heat B", 1, 31000, "finished"],
      ["Heat A", undefined, undefined, undefined],
    ]);
  }
  game.send("gameToServer", "game.run.failed", {
    runId: runIds[0],
    elapsedMs: 8000,
    reason: "flipped",
    section: "crossing",
    stretch: "hedge_lane",
    ...result,
    stretches: via("stone_bridge", 9000),
  });
  // A's bridge shows who was fastest the other way through the pond, and with what (§2f).
  const endedA = await a.phone.wait("run.ended", (p) => p.run.id === runIds[0]);
  const bridge = endedA.payload.stretches.find((st) => st.id === "stone_bridge");
  expect(bridge.other).toMatchObject({ id: "ford", ms: 6000, nickname: "Heat B" });
  expect(bridge.other.setup).toMatchObject({ style: "balanced", weather: ["rain"] });
  expect(endedA.payload.stretches.find((st) => st.id === "bumpy_road").other).toBeUndefined();
  for (const r of [a, b]) {
    const h = (await r.phone.wait("run.heat", (p) => p.done)).payload;
    expect(h.entries.map((e) => [e.nickname, e.place, e.outcome, e.failReason])).toEqual([
      ["Heat B", 1, "finished", undefined],
      ["Heat A", undefined, "failed", "flipped"],
    ]);
  }
  game.ws.close();
  a.phone.ws.close();
  b.phone.ws.close();
}, 30000);

test("after a track switch, Go waits until the big screen has loaded the new track (track_changing)", async () => {
  const s = startServer({ ...settings, port: 0, dbFile: ":memory:" }, { log: () => {} });
  const sBase = `http://localhost:${s.server.port}`;
  const admin = { "x-admin-pin": settings.adminPin, "content-type": "application/json" };
  const gameHello = async (track) => {
    const ws = new WebSocket(`${sBase.replace("http", "ws")}/ws`);
    await new Promise((r) => (ws.onopen = r));
    ws.send(
      JSON.stringify(
        makeMsg("phoneToServer", "hello", { role: "game", gameKey: settings.gameKey, track }),
      ),
    );
    await Bun.sleep(50);
    return ws;
  };
  const game = await gameHello("countryside");
  const dev = await fetch(`${sBase}/api/device`, { method: "POST" });
  const cookie = dev.headers.get("set-cookie").split(";")[0];
  await fetch(`${sBase}/api/players`, {
    method: "POST",
    headers: { cookie, "content-type": "application/json" },
    body: JSON.stringify({ nickname: "Switcher" }),
  });
  const form = new FormData();
  for (const [k, f] of [
    ["character", "pair01-character-cat.jpg"],
    ["vehicle", "pair01-vehicle-kart.jpg"],
  ])
    form.append(k, new File([readFileSync(join(SAMPLES, f))], `${k}.jpg`, { type: "image/jpeg" }));
  await fetch(`${sBase}/api/players/me/drawings`, {
    method: "POST",
    headers: { cookie },
    body: form,
  });
  for (let i = 0; i < 200; i++) {
    const st = await (await fetch(`${sBase}/api/state`, { headers: { cookie } })).json();
    if (st.me.status === "ready") break;
    await Bun.sleep(100);
  }
  await fetch(`${sBase}/api/admin/session/end`, { method: "POST", headers: admin });
  await fetch(`${sBase}/api/admin/config`, {
    method: "PATCH",
    headers: admin,
    body: JSON.stringify({ track: "village" }),
  });
  await fetch(`${sBase}/api/admin/session/start`, { method: "POST", headers: admin, body: "{}" });
  // The game still has the countryside loaded: a run now would race the old course.
  const early = await fetch(`${sBase}/api/players/me/runs`, {
    method: "POST",
    headers: { cookie },
  });
  expect(early.status).toBe(409);
  expect((await early.json()).error.code).toBe("track_changing");
  // It reloads and says hello with the village: Go works.
  const reloaded = await gameHello("village");
  const ok = await fetch(`${sBase}/api/players/me/runs`, { method: "POST", headers: { cookie } });
  expect(ok.status).toBe(201);
  expect((await ok.json()).track).toBe("village");
  game.close();
  reloaded.close();
  s.stop();
}, 30000);
