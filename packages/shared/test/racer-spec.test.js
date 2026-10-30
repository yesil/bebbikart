import { expect, test } from "bun:test";
import { clampRacerSpec, nearestName, RacerSpecSchema } from "../src/index.js";
import { DEFAULT_SPEC, SAMPLE_SPECS } from "../testing/fixtures.js";

test("sample specs are valid", () => {
  for (const spec of [DEFAULT_SPEC, ...Object.values(SAMPLE_SPECS)]) {
    const r = RacerSpecSchema.safeParse(spec);
    if (!r.success) throw new Error(JSON.stringify(r.error.issues));
  }
});

test("clamp repairs names, numbers, extras and palette refs", () => {
  const raw = structuredClone(DEFAULT_SPEC);
  raw.character.body.shape = "Beans";
  raw.character.head.size = 9;
  raw.ride.base = "rockett";
  raw.ride.color = 7;
  raw.ride.extras = Array.from({ length: 12 }, () => ({
    shape: "star",
    socket: "ride_top",
    offset: [0, 5, 0],
    scale: [3, 3, 3],
    rotationDeg: [0, 0, 400],
    color: 1,
  }));
  expect(RacerSpecSchema.safeParse(raw).success).toBe(false);

  const r = clampRacerSpec(raw);
  expect(r.ok).toBe(true);
  expect(r.spec.character.body.shape).toBe("bean");
  expect(r.spec.character.head.size).toBe(1.5);
  expect(r.spec.ride.base).toBe("rocket");
  expect(r.spec.ride.color).toBe(3);
  expect(r.spec.ride.extras).toHaveLength(8);
  expect(r.spec.ride.extras[0].offset[1]).toBe(0.4);
  expect(r.spec.ride.extras[0].scale[0]).toBe(2);
  expect(r.fixes.length).toBeGreaterThan(0);
});

test("clamp reports structural errors it can't fix", () => {
  const raw = structuredClone(DEFAULT_SPEC);
  delete raw.ride;
  const r = clampRacerSpec(raw);
  expect(r.ok).toBe(false);
  expect(r.errors.join()).toContain("ride");
});

test("nearestName", () => {
  expect(nearestName("big round", ["dots", "big_round", "sleepy"])).toBe("big_round");
});
