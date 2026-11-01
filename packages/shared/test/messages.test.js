import { expect, test } from "bun:test";
import { DEFAULT_CONFIG } from "../src/config.js";
import { CHANNELS, makeMsg, parseMsg } from "../src/index.js";
import { GHOST_TRACE, ROSTER, RUNS, SESSION_RUNNING } from "../testing/fixtures.js";

test("makeMsg builds a v1 envelope and parseMsg reads it back", () => {
  const msg = makeMsg("phoneToServer", "phone.steer", { runId: "run_x", x: -0.4 });
  expect(msg.v).toBe(1);
  expect(msg.id).toStartWith("msg_");
  const r = parseMsg("phoneToServer", JSON.stringify(msg));
  expect(r.ok).toBe(true);
  expect(r.msg.payload).toEqual({ runId: "run_x", x: -0.4 });
});

test("makeMsg throws on a payload that breaks the contract", () => {
  expect(() => makeMsg("phoneToServer", "phone.steer", { runId: "run_x" })).toThrow();
  expect(() => makeMsg("phoneToServer", "game.weather", {})).toThrow("Unknown message type");
});

test("parseMsg rejects bad JSON, unknown types and wrong channels", () => {
  expect(parseMsg("gameToServer", "{").ok).toBe(false);
  const steer = makeMsg("phoneToServer", "phone.steer", { runId: "run_x", x: null });
  const r = parseMsg("gameToServer", steer);
  expect(r.ok).toBe(false);
  expect(r.error).toMatchObject({ code: "bad_message", refId: steer.id });
});

test("hello per role", () => {
  expect(
    parseMsg("gameToServer", makeMsg("gameToServer", "hello", { role: "game", gameKey: "k" })).ok,
  ).toBe(true);
  expect(() => makeMsg("gameToServer", "hello", { role: "game" })).toThrow();
});

test("game messages round-trip with fixtures", () => {
  const run = RUNS[0];
  const finished = makeMsg("gameToServer", "game.run.finished", {
    runId: run.id,
    elapsedMs: run.elapsedMs,
    splits: run.splits,
    stretches: run.stretches,
    events: run.events,
    boostsUsed: run.boostsUsed,
    weatherSeen: run.weatherSeen,
    routes: run.routes,
    trace: GHOST_TRACE,
  });
  expect(parseMsg("gameToServer", JSON.stringify(finished)).ok).toBe(true);
  // Every event names its stretch; a stretch that isn't on any track is refused.
  const noStretch = {
    ...finished,
    payload: { ...finished.payload, events: [{ kind: "slip", section: "pond", atMs: 1 }] },
  };
  expect(parseMsg("gameToServer", JSON.stringify(noStretch)).ok).toBe(false);
  const unknown = {
    ...finished,
    payload: { ...finished.payload, stretches: [{ id: "moon", ms: 1, lostMs: 0 }] },
  };
  expect(parseMsg("gameToServer", JSON.stringify(unknown)).ok).toBe(false);

  const welcome = makeMsg("serverToGame", "welcome", {
    session: SESSION_RUNNING,
    config: DEFAULT_CONFIG,
    roster: ROSTER,
    activeRuns: [],
  });
  expect(parseMsg("serverToGame", JSON.stringify(welcome)).ok).toBe(true);
});

test("config carries the track and the lap cap", () => {
  expect(DEFAULT_CONFIG.track).toBe("village");
  expect(DEFAULT_CONFIG.lapsPerRun).toBe(3);
  expect(() =>
    makeMsg("serverToGame", "config.updated", { ...DEFAULT_CONFIG, track: "moon" }),
  ).toThrow();
});

test("lap messages for loop tracks", () => {
  const lap = makeMsg("gameToServer", "game.run.lap", {
    runId: "run_x",
    lap: 2,
    lapMs: 31_250,
    elapsedMs: 63_000,
    splits: { hills: 9_000, pond: 8_000, crossing: 6_000, bends: 8_250 },
    stretches: [
      { id: "main_street", ms: 9_000, lostMs: 0 },
      { id: "covered_bridge", ms: 8_000, lostMs: 300 },
      { id: "farm", ms: 6_000, lostMs: 0 },
      { id: "square", ms: 8_250, lostMs: 0 },
    ],
    weatherSeen: ["rain"],
    isBest: true,
    routes: { ramp: "around", pond: "bridge", crossing: "sheltered" },
  });
  expect(parseMsg("gameToServer", lap).ok).toBe(true);
  // A lap drives through every fork, so it names a way at each.
  expect(() =>
    makeMsg("gameToServer", "game.run.lap", { ...lap.payload, routes: { ramp: "around" } }),
  ).toThrow();
  expect(() =>
    makeMsg("gameToServer", "game.run.lap", { runId: "run_x", lap: 0, lapMs: 1 }),
  ).toThrow();
  const progress = makeMsg("gameToServer", "game.run.progress", {
    runId: "run_x",
    progress: 0.5,
    elapsedMs: 40_000,
    section: "pond",
    lane: -0.3,
    fork: { id: "pond", inM: 42, left: "water", right: "bridge", way: "bridge" },
    lap: 2,
    lapMs: 9_000,
  });
  expect(progress.payload.lap).toBe(2);
  expect(progress.payload.fork.way).toBe("bridge");
  const finished = makeMsg("gameToServer", "game.run.finished", {
    runId: "run_x",
    elapsedMs: 95_000,
    laps: [32_000, 31_250, 31_750],
    bestLapMs: 31_250,
    splits: { hills: 9_000 },
    stretches: [{ id: "main_street", ms: 9_000, lostMs: 0 }],
    events: [],
    boostsUsed: 3,
    weatherSeen: [],
    routes: { ramp: "jump", pond: "water", crossing: "sheltered" },
    trace: { runId: "run_x", hz: 10, samples: [] },
  });
  expect(finished.payload.laps).toEqual([32_000, 31_250, 31_750]);
  expect(
    makeMsg("serverToPhone", "run.lap", { runId: "run_x", lap: 1, lapMs: 32_000, isLapBest: true })
      .payload.isLapBest,
  ).toBe(true);
});

test("steering and the fork ahead (contracts §2g)", () => {
  const ok = (ch, type, payload) => parseMsg(ch, makeMsg(ch, type, payload)).ok;
  expect(ok("phoneToServer", "phone.steer", { runId: "run_x", x: 1 })).toBe(true);
  expect(ok("phoneToServer", "phone.steer", { runId: "run_x", x: null })).toBe(true); // let go
  expect(() => makeMsg("phoneToServer", "phone.steer", { runId: "run_x", x: 1.2 })).toThrow();
  expect(ok("serverToGame", "run.steer", { runId: "run_x", x: -0.5 })).toBe(true);
  for (const gone of ["phone.push", "phone.boost"])
    expect(() => makeMsg("phoneToServer", gone, { runId: "run_x", on: true })).toThrow();
  for (const gone of ["run.push", "run.boost"]) expect(CHANNELS.serverToGame[gone]).toBeUndefined();
  const base = { runId: "run_x", progress: 0.2, elapsedMs: 5_000, section: "hills" };
  expect(ok("serverToPhone", "run.progress", { ...base, lane: 0 })).toBe(true);
  expect(() => makeMsg("serverToPhone", "run.progress", base)).toThrow(); // lane is always there
  const fork = { id: "ramp", inM: 30, left: "around", right: "jump", way: "jump" };
  expect(ok("serverToPhone", "run.progress", { ...base, lane: 0.6, fork })).toBe(true);
  // A way that isn't at that fork is refused.
  expect(() =>
    makeMsg("serverToPhone", "run.progress", {
      ...base,
      lane: 0,
      fork: { ...fork, way: "bridge" },
    }),
  ).toThrow();
});

test("the line and the halves (contracts §2i); there is no game mode", () => {
  expect(DEFAULT_CONFIG.mode).toBeUndefined();
  expect(DEFAULT_CONFIG.duelResultMs).toBe(5_000);
  expect(DEFAULT_CONFIG.splitHoldMs).toBe(30_000);
  const ok = (ch, type, payload) => parseMsg(ch, makeMsg(ch, type, payload)).ok;
  expect(ok("phoneToServer", "phone.queue.leave", {})).toBe(true);
  expect(() => makeMsg("gameToServer", "game.config.set", { mode: "duel" })).toThrow();
  for (const gone of ["phone.stop", "phone.watch"])
    expect(() => makeMsg("phoneToServer", gone, { runId: "run_x" })).toThrow();
  for (const gone of ["run.heat", "grid.updated", "camera.updated"])
    expect(CHANNELS.serverToPhone[gone]).toBeUndefined();
  const queue = {
    line: [{ playerId: "ply_a", nickname: "Ava" }],
    racing: [{ side: "left", playerId: "ply_b", nickname: "Ben", runId: "run_b" }],
    champion: { playerId: "ply_c", nickname: "Cleo", timeMs: 52_300, tries: 4 },
    split: true,
    skipped: [],
  };
  for (const ch of ["serverToPhone", "serverToAdmin", "serverToGame"])
    expect(ok(ch, "queue.updated", queue)).toBe(true);
  expect(() =>
    makeMsg("serverToGame", "queue.updated", {
      ...queue,
      racing: [{ ...queue.racing[0], side: "middle" }],
    }),
  ).toThrow();
});
