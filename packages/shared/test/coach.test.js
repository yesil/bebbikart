import { expect, test } from "bun:test";
import { COACH_COPY, coachTip, DEFAULT_BUILD } from "../src/index.js";
import { BUILDS, RUNS } from "../testing/fixtures.js";

test("all copy fits in 70 chars", () => {
  for (const [key, { text }] of Object.entries(COACH_COPY)) {
    const filled = text.replace("{where}", "the windy crossing").replace("{s}", "12.3");
    expect(filled.length, key).toBeLessThanOrEqual(70);
  }
});

test("failed run: tip about the fail", () => {
  const tip = coachTip(RUNS[2], BUILDS[1]);
  expect(tip).toMatchObject({ key: "fail_slip", section: "bends", ability: "grip" });
  expect(tip.text).toBe("Slipped on the rainbow bends! Try +1 grip or Careful style.");
});

test("slower than best: biggest loss section", () => {
  const tip = coachTip(RUNS[1], BUILDS[0], RUNS[0]);
  expect(tip).toMatchObject({ key: "loss_water_slow", section: "pond" });
  expect(tip.text).toContain("2.5 s");
});

test("new best: cheer plus an experiment", () => {
  const tip = coachTip(RUNS[0], DEFAULT_BUILD);
  expect(tip).toMatchObject({ key: "best_try_water", route: { fork: "pond", choice: "water" } });
});
