// The line (contracts §2i) and steering (§2g) over real HTTP + WebSockets: the two halves, the
// champion who rests, judging, offline phones, the session end, when the screen splits; the
// thumb's lane relayed to the game.
import { afterAll, beforeAll, expect, test } from "bun:test";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createMockClient } from "@bebbikart/asset-pipeline";
import { DEFAULT_CONFIG, makeMsg } from "@bebbikart/shared";
import { loadSettings, REPO_ROOT } from "../src/env.js";
import { startServer } from "../src/index.js";

const SAMPLES = join(REPO_ROOT, "packages/asset-pipeline/samples");
const RESULT_MS = 150;
const HOLD_MS = 600; // splitHoldMs
let srv;
let base;
let settings;
const admin = () => ({ "x-admin-pin": settings.adminPin, "content-type": "application/json" });

beforeAll(() => {
  settings = {
    ...loadSettings({}),
    port: 0,
    dataDir: mkdtempSync(join(tmpdir(), "bk-duel-")),
    designClient: createMockClient({ designId: "pair01" }),
    config: { ...DEFAULT_CONFIG, track: "village", duelResultMs: RESULT_MS, splitHoldMs: HOLD_MS },
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
    last: (type) => msgs.findLast((m) => m.type === type)?.payload,
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

/** A ready racer with a phone online. */
async function racer(nickname) {
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
    ["character", "pair01-character-cat.jpg"],
    ["vehicle", "pair01-vehicle-kart.jpg"],
  ])
    form.append(k, new File([readFileSync(join(SAMPLES, f))], `${k}.jpg`, { type: "image/jpeg" }));
  await fetch(`${base}/api/players/me/drawings`, {
    method: "POST",
    headers: { cookie },
    body: form,
  });
  await phone.wait("player.updated", (p) => p.status === "ready", 20000);
  return { me, phone, cookie, go: () => phone.send("phoneToServer", "phone.go", {}) };
}

const stretches = (lapMs) => [{ id: "main_street", ms: lapMs, lostMs: 0 }];
const routes = { ramp: "around", pond: "bridge", crossing: "exposed" };
/** The game reports one finished lap (a duel run is one lap). */
function finishLap(game, runId, lapMs) {
  game.send("gameToServer", "game.run.started", { runId });
  game.send("gameToServer", "game.run.lap", {
    runId,
    lap: 1,
    lapMs,
    elapsedMs: lapMs,
    splits: {},
    stretches: stretches(lapMs),
    weatherSeen: [],
    isBest: true,
    routes,
  });
  game.send("gameToServer", "game.run.finished", {
    runId,
    elapsedMs: lapMs,
    laps: [lapMs],
    bestLapMs: lapMs,
    splits: {},
    stretches: stretches(lapMs),
    events: [],
    boostsUsed: 0,
    weatherSeen: [],
    routes,
    trace: { runId, hz: 10, samples: [0, 0, 0, 0, 0] },
  });
}
const lineOf = (q) => q.line.map((e) => e.nickname);

test("duel: Go joins the line, a free half launches it, the champion rests, laps are judged", async () => {
  const game = client({}, { role: "game", gameKey: settings.gameKey, track: "village" });
  await game.start();
  await game.wait("welcome");
  const a = await racer("Ava");
  const b = await racer("Ben");
  const c = await racer("Cleo");
  // Three racers in the session, but nobody plays yet: one picture, not split.
  expect(game.last("queue.updated")).toMatchObject({ line: [], racing: [], split: false });

  // Ava and Ben go straight onto the two halves (left first), one lap each. Ava alone has the
  // whole screen; Ben joining splits it.
  a.go();
  const startA = (await game.wait("run.start", (p) => p.playerId === a.me.id)).payload;
  expect([startA.side, startA.lapsPerRun]).toEqual(["left", 1]);
  expect(game.last("queue.updated")).toMatchObject({ split: false });
  b.go();
  const startB = (await game.wait("run.start", (p) => p.playerId === b.me.id)).payload;
  expect(startB.side).toBe("right");
  expect(game.last("queue.updated")).toMatchObject({ split: true });
  expect((await b.phone.wait("run.queued")).payload.run.side).toBe("right");

  // Both halves busy: Cleo waits; a second Go is refused, and REST Go answers with the line.
  const rest = await fetch(`${base}/api/players/me/runs`, {
    method: "POST",
    headers: { cookie: c.cookie },
  });
  expect(rest.status).toBe(202);
  expect(lineOf(await rest.json())).toEqual(["Cleo"]);
  c.go();
  expect((await c.phone.wait("error")).payload.code).toBe("in_line");
  const busy = await c.phone.wait("queue.updated", (q) => q.racing.length === 2);
  expect(busy.payload.racing.map((r) => [r.side, r.nickname])).toEqual([
    ["left", "Ava"],
    ["right", "Ben"],
  ]);

  // Ava sets the first record: champion. Her half shows the result, then Cleo starts there.
  finishLap(game, startA.runId, 50_000);
  const endA = await a.phone.wait("run.ended", (p) => p.run.id === startA.runId);
  expect(endA.payload.duel).toEqual({ newChampion: true });
  const t0 = Date.now();
  const startC = (await game.wait("run.start", (p) => p.playerId === c.me.id)).payload;
  expect(Date.now() - t0).toBeGreaterThanOrEqual(RESULT_MS - 20);
  expect(startC.side).toBe("left");

  // The champion may join, but rests behind anyone who comes later.
  a.go();
  await a.phone.wait("queue.updated", (q) => lineOf(q).join() === "Ava");
  finishLap(game, startB.runId, 52_000);
  const endB = await b.phone.wait("run.ended", (p) => p.run.id === startB.runId);
  expect(endB.payload.duel).toEqual({ newChampion: false, gapMs: 2000, recordNickname: "Ava" });
  const tried = await b.phone.wait("queue.updated", (q) => q.champion?.tries === 1);
  expect(tried.payload.champion).toMatchObject({ nickname: "Ava", timeMs: 50_000 });
  b.go();
  const ordered = await b.phone.wait("queue.updated", (q) => q.line.length === 2);
  expect(lineOf(ordered.payload)).toEqual(["Ben", "Ava"]);
  const startB2 = (
    await game.wait("run.start", (p) => p.playerId === b.me.id && p.runId !== startB.runId)
  ).payload;
  expect(startB2.side).toBe("right");

  // Cleo beats the record: new champion, tries start again; Ava is a challenger again and races.
  finishLap(game, startC.runId, 49_000);
  const endC = await c.phone.wait("run.ended", (p) => p.run.id === startC.runId);
  expect(endC.payload.duel).toEqual({ newChampion: true, gapMs: -1000, recordNickname: "Ava" });
  const newChamp = await c.phone.wait("queue.updated", (q) => q.champion?.nickname === "Cleo");
  expect(newChamp.payload.champion.tries).toBe(0);
  const startA2 = (
    await game.wait("run.start", (p) => p.playerId === a.me.id && p.runId !== startA.runId)
  ).payload;
  expect(startA2.side).toBe("left");

  // Steering (§2g): relayed to the game; a phone that goes away mid-steer lets go.
  a.phone.send("phoneToServer", "phone.steer", { runId: startA2.runId, x: 0.7 });
  expect((await game.wait("run.steer", (p) => p.runId === startA2.runId)).payload.x).toBe(0.7);
  // Someone else's run can't be steered.
  a.phone.send("phoneToServer", "phone.steer", { runId: startB2.runId, x: -1 });
  a.phone.ws.close();
  await game.wait("run.steer", (p) => p.runId === startA2.runId && p.x === null);
  expect(game.msgs.some((m) => m.type === "run.steer" && m.payload.runId === startB2.runId)).toBe(
    false,
  );
  game.send("gameToServer", "game.run.failed", {
    runId: startA2.runId,
    reason: "off_track",
    section: "hills",
    stretch: "main_street",
    elapsedMs: 9000,
    splits: {},
    stretches: [],
    events: [],
    boostsUsed: 0,
    weatherSeen: [],
    routes: {},
  });
  finishLap(game, startB2.runId, 51_000);
  await b.phone.wait("run.ended", (p) => p.run.id === startB2.runId);
  await c.phone.wait("queue.updated", (q) => q.racing.length === 0 && q.champion?.tries === 2);
  for (const r of [b, c]) r.phone.ws.close();
  game.ws.close();
});

test("duel: an offline phone loses its turn loudly; leave the line; session end closes the line", async () => {
  const game = client({}, { role: "game", gameKey: settings.gameKey, track: "village" });
  await game.start();
  await game.wait("welcome");
  const d = await racer("Dan");
  const e = await racer("Eve");
  const f = await racer("Finn");
  const g = await racer("Gus");

  d.go();
  const runD = (await game.wait("run.start", (p) => p.playerId === d.me.id)).payload.runId;
  e.go();
  const runE = (await game.wait("run.start", (p) => p.playerId === e.me.id)).payload.runId;
  f.go();
  g.go();
  await g.phone.wait("queue.updated", (q) => lineOf(q).join() === "Finn,Gus");
  // Gus changes his mind; Finn's phone goes offline before his turn.
  g.phone.send("phoneToServer", "phone.queue.leave", {});
  await d.phone.wait("queue.updated", (q) => lineOf(q).join() === "Finn");
  f.phone.ws.close();
  await Bun.sleep(100);
  finishLap(game, runD, 55_000);
  const skipped = await d.phone.wait("queue.updated", (q) => q.skipped.includes(f.me.id));
  expect(skipped.payload.line).toEqual([]);
  await Bun.sleep(RESULT_MS + 100);
  expect(game.msgs.some((m) => m.type === "run.start" && m.payload.playerId === f.me.id)).toBe(
    false,
  );

  // Session end: the line closes, the lap on track still finishes.
  g.go();
  await g.phone.wait("run.queued");
  d.go();
  await d.phone.wait("queue.updated", (q) => lineOf(q).join() === "Dan");
  await fetch(`${base}/api/admin/session/end`, { method: "POST", headers: admin() });
  await d.phone.wait("queue.updated", (q) => q.line.length === 0 && q.skipped.length === 0);
  finishLap(game, runE, 54_000);
  await e.phone.wait("run.ended", (p) => p.run.id === runE);
  for (const r of [d, e, g]) r.phone.ws.close();
  game.ws.close();
});

test("split screen: one player has it all; a second player splits it; it stays split while anyone plays", async () => {
  await fetch(`${base}/api/admin/session/start`, { method: "POST", headers: admin(), body: "{}" });
  const game = client({}, { role: "game", gameKey: settings.gameKey, track: "village" });
  await game.start();
  await game.wait("welcome");
  const h = await racer("Hana");
  const i = await racer("Ivo");
  // (The racers of the tests before have stopped playing too.)
  await game.wait("queue.updated", (q) => !q.split && q.racing.length === 0, HOLD_MS + 2000);
  const from = game.msgs.length;
  const nextStart = async (r, seen) =>
    (await game.wait("run.start", (p) => p.playerId === r.me.id && !seen.has(p.runId))).payload;
  const seen = new Set();
  const lap = async (r, ms) => {
    const st = await nextStart(r, seen);
    seen.add(st.runId);
    finishLap(game, st.runId, ms);
    await r.phone.wait("run.ended", (p) => p.run.id === st.runId);
    return st;
  };

  // Hana alone, lap after lap: always the left half, never split (she waits out her own result).
  h.go();
  expect((await lap(h, 60_000)).side).toBe("left");
  h.go();
  expect((await lap(h, 59_000)).side).toBe("left");
  const shown = game.msgs.slice(from).filter((m) => m.type === "queue.updated");
  expect(shown.length).toBeGreaterThan(0);
  expect(shown.every((m) => !m.payload.split)).toBe(true);

  // Ivo joins while Hana races: split, Ivo on the right.
  h.go();
  const hRun = await nextStart(h, seen);
  seen.add(hRun.runId);
  i.go();
  const iRun = await nextStart(i, seen);
  seen.add(iRun.runId);
  expect(iRun.side).toBe("right");
  await game.wait("queue.updated", (q) => q.split && q.racing.length === 2);

  // Ivo finishes and stops; Hana keeps playing alone: the screen stays split.
  finishLap(game, iRun.runId, 61_000);
  finishLap(game, hRun.runId, 58_000);
  await h.phone.wait("run.ended", (p) => p.run.id === hRun.runId);
  h.go();
  const hRun2 = await nextStart(h, seen);
  seen.add(hRun2.runId);
  await Bun.sleep(HOLD_MS + 200);
  expect(game.last("queue.updated")).toMatchObject({ split: true });
  expect(game.last("queue.updated").racing.map((r) => r.nickname)).toEqual(["Hana"]);

  // Nobody plays any more: once the hold is over, the whole screen again.
  finishLap(game, hRun2.runId, 57_000);
  await h.phone.wait("run.ended", (p) => p.run.id === hRun2.runId);
  await Bun.sleep(HOLD_MS / 2);
  expect(game.last("queue.updated")).toMatchObject({ split: true, racing: [] });
  await Bun.sleep(HOLD_MS / 2 + 200);
  expect(game.last("queue.updated")).toMatchObject({ split: false, racing: [], line: [] });
  expect(game.last("queue.updated").champion.nickname).toBe("Hana");
  for (const r of [h, i]) r.phone.ws.close();
  game.ws.close();
});
