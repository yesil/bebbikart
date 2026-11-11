import { expect, test } from "bun:test";
import { reducer } from "../src/state.js";

const player = { id: "ply_test", status: "ready", asset: { packageId: "pkg_test" } };
const run = { id: "run_test", outcome: "finished" };
const ws = (s, msgType, payload) => reducer(s, { type: "ws", msgType, payload });

test("finishing a race keeps the racer and result, without opening drawing upload", () => {
  const s = ws({ me: player, redo: true, live: { runId: run.id } }, "run.ended", { run });
  expect(s.redo).toBe(false);
  expect(s.live).toBeNull();
  expect(s.result.run).toEqual(run);
  expect(s.me.status).toBe("ready");
  const updated = ws(s, "player.updated", { ...player, lastRun: run });
  expect(updated.result).toBe(s.result);
  expect(updated.redo).toBe(false);
  const ended = ws(updated, "session.updated", { status: "ended" });
  expect(ended.result).toBe(s.result);
  expect(ended.me).toBe(updated.me);
  expect(ended.redo).toBe(false);
});

test("new drawings are an explicit choice and a successful upload exits that choice", () => {
  const s = reducer({ me: player, result: { run } }, { type: "redo", on: true });
  expect(s.redo).toBe(true);
  expect(s.result).toBeNull();
  const uploaded = reducer(s, { type: "redo", on: false });
  expect(uploaded.redo).toBe(false);
  expect(uploaded.me).toBe(player);
});

test("live processing clears a stale drawing-upload flag without a page refresh", () => {
  const s = { me: player, redo: true, result: { run } };
  const processing = { ...player, status: "processing" };
  for (const changed of [
    ws(s, "player.updated", processing),
    reducer(s, { type: "me", me: processing }),
  ]) {
    expect(changed.redo).toBe(false);
    expect(changed.result).toBeNull();
    const ready = ws(changed, "player.updated", player);
    expect(ready.redo).toBe(false);
    expect(ready.me.status).toBe("ready");
  }
  expect(ws(s, "run.started", { run }).redo).toBe(false);
});
