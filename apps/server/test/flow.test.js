// End-to-end over real HTTP + WebSockets: phone creates a racer, uploads drawings (a fake design client stands in for Claude),
// the game gets the roster, the phone presses Go, the game races and reports, the phone gets the result.
import { afterAll, beforeAll, expect, test } from "bun:test";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createMockClient } from "@bebbikart/asset-pipeline";
import { DEFAULT_CONFIG, makeMsg } from "@bebbikart/shared";
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
  expect(start.payload.build.stars.speed).toBe(2);
  await phone.wait("run.queued");
  game.send("gameToServer", "game.run.started", { runId });
  await phone.wait("run.started");
  phone.send("phoneToServer", "phone.boost", { runId });
  await game.wait("run.boost", (p) => p.runId === runId);
  game.send("gameToServer", "game.run.section", { runId, section: "hills", splitMs: 8000 });
  await phone.wait("run.section");
  game.send("gameToServer", "game.run.finished", {
    runId,
    elapsedMs: 32100,
    splits: { hills: 8000, pond: 8000, crossing: 8000, bends: 8100 },
    events: [{ kind: "boost_perfect", section: "hills", atMs: 3000 }],
    boostsUsed: 1,
    weatherSeen: [],
    trace: { runId, hz: 10, samples: [0, 0, 0, 0, 0] },
  });
  const ended = await phone.wait("run.ended");
  expect(ended.payload.isPersonalBest).toBe(true);
  expect(ended.payload.rank).toBe(1);
  expect(ended.payload.coach.text.length).toBeGreaterThan(0);
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
  game.send("gameToServer", "game.run.started", { runId });
  const splits = { hills: 5000, pond: 5000, crossing: 5000, bends: 5000 };
  game.send("gameToServer", "game.run.lap", {
    runId,
    lap: 1,
    lapMs: 20000,
    elapsedMs: 20000,
    splits,
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
    events: [],
    boostsUsed: 0,
    weatherSeen: [],
    trace: { runId, hz: 10, samples: [0, 0, 0, 0, 0] },
  });
  const ended = await phone.wait("run.ended", (p) => p.run.id === runId);
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
  game.send("gameToServer", "game.run.failed", {
    runId: start2.payload.runId,
    reason: "off_track",
    section: "bends",
    elapsedMs: 30000,
    laps: [18000],
    bestLapMs: 18000,
    splits,
    events: [],
    boostsUsed: 0,
    weatherSeen: [],
  });
  const ended2 = await phone.wait("run.ended", (p) => p.run.id === start2.payload.runId);
  expect(ended2.payload.run.outcome).toBe("failed");
  expect(ended2.payload.isPersonalBest).toBe(true);
  await phone.wait("player.updated", (p) => p.bestTimeMs === 18000);
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
