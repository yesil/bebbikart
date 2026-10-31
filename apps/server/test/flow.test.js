// End-to-end over real HTTP + WebSockets: phone creates a racer, uploads drawings (a fake design client stands in for DeepSeek),
// the game gets the roster, the phone presses Go, the game races and reports, the phone gets the result.
import { afterAll, beforeAll, expect, test } from "bun:test";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { MOCK_DESIGNS } from "@bebbikart/asset-pipeline";
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
    designClient: {
      name: "fake",
      complete: async () =>
        JSON.stringify({ check: {}, spec: MOCK_DESIGNS.pair01.spec, notes: "test" }),
    },
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

test("a DeepSeek failure fails the job loudly: no sample design, phone sees the error", async () => {
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
