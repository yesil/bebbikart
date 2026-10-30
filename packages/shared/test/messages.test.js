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
    events: run.events,
    boostsUsed: run.boostsUsed,
    weatherSeen: run.weatherSeen,
    trace: GHOST_TRACE,
  });
  expect(parseMsg("gameToServer", JSON.stringify(finished)).ok).toBe(true);

  const welcome = makeMsg("serverToGame", "welcome", {
    session: SESSION_RUNNING,
    config: DEFAULT_CONFIG,
    roster: ROSTER,
    activeRuns: [],
  });
  expect(parseMsg("serverToGame", JSON.stringify(welcome)).ok).toBe(true);
});
