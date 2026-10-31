import { expect, test } from "bun:test";
import { DEFAULT_CONFIG } from "../src/config.js";
import { makeMsg, parseMsg } from "../src/index.js";
import { GHOST_TRACE, ROSTER, RUNS, SESSION_RUNNING } from "../testing/fixtures.js";

test("makeMsg builds a v1 envelope and parseMsg reads it back", () => {
  const msg = makeMsg("phoneToServer", "phone.boost", { runId: "run_x" });
  expect(msg.v).toBe(1);
  expect(msg.id).toStartWith("msg_");
  const r = parseMsg("phoneToServer", JSON.stringify(msg));
  expect(r.ok).toBe(true);
  expect(r.msg.payload).toEqual({ runId: "run_x" });
});

test("makeMsg throws on a payload that breaks the contract", () => {
  expect(() => makeMsg("phoneToServer", "phone.boost", {})).toThrow();
  expect(() => makeMsg("phoneToServer", "game.weather", {})).toThrow("Unknown message type");
});

test("parseMsg rejects bad JSON, unknown types and wrong channels", () => {
  expect(parseMsg("gameToServer", "{").ok).toBe(false);
  const boost = makeMsg("phoneToServer", "phone.boost", { runId: "run_x" });
  const r = parseMsg("gameToServer", boost);
  expect(r.ok).toBe(false);
  expect(r.error).toMatchObject({ code: "bad_message", refId: boost.id });
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
  expect(DEFAULT_CONFIG.track).toBe("countryside");
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
    isBest: true,
  });
  expect(parseMsg("gameToServer", lap).ok).toBe(true);
  expect(() =>
    makeMsg("gameToServer", "game.run.lap", { runId: "run_x", lap: 0, lapMs: 1 }),
  ).toThrow();
  const progress = makeMsg("gameToServer", "game.run.progress", {
    runId: "run_x",
    progress: 0.5,
    elapsedMs: 40_000,
    section: "pond",
    boostsLeft: 1,
    lap: 2,
    lapMs: 9_000,
  });
  expect(progress.payload.lap).toBe(2);
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
    trace: { runId: "run_x", hz: 10, samples: [] },
  });
  expect(finished.payload.laps).toEqual([32_000, 31_250, 31_750]);
  expect(
    parseMsg("phoneToServer", makeMsg("phoneToServer", "phone.stop", { runId: "run_x" })).ok,
  ).toBe(true);
  expect(makeMsg("serverToGame", "run.stop", { runId: "run_x" }).payload).toEqual({
    runId: "run_x",
  });
  expect(
    makeMsg("serverToPhone", "run.lap", { runId: "run_x", lap: 1, lapMs: 32_000, isLapBest: true })
      .payload.isLapBest,
  ).toBe(true);
});
