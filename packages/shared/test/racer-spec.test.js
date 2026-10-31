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
  raw.ride.color = 9;
  raw.ride.extras = Array.from({ length: 14 }, () => ({
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
  expect(r.spec.ride.extras).toHaveLength(12);
  expect(r.spec.ride.extras[0].offset[1]).toBe(0.4);
  expect(r.spec.ride.extras[0].scale[0]).toBe(2);
  expect(r.fixes.length).toBeGreaterThan(0);
});

test("optional look fields: patterns, finishes, number, motion and tagline", () => {
  const raw = structuredClone(DEFAULT_SPEC);
  raw.tagline = "Loves fish, scared of puddles";
  raw.motion = { style: "wobbly", energy: 1.2 };
  raw.sound = { engine: "putter", pitch: 1.3, horn: "meow" };
  raw.character.body.pattern = { type: "stripes", color: 1, scale: 1 };
  raw.character.body.finish = "sparkle";
  raw.character.head.pattern = { type: "spots", color: 2, scale: 0.8 };
  raw.ride.pattern = { type: "checks", color: 0, scale: 1.5 };
  raw.ride.finish = "metallic";
  raw.ride.number = { value: 7, color: 1 };
  expect(RacerSpecSchema.safeParse(raw).success).toBe(true);

  raw.ride.pattern.type = "stripy";
  raw.ride.number.value = 123.4;
  raw.motion.energy = 3;
  const r = clampRacerSpec(raw);
  expect(r.ok).toBe(true);
  expect(r.spec.ride.pattern.type).toBe("stripes");
  expect(r.spec.ride.number.value).toBe(99);
  expect(r.spec.motion.energy).toBe(1.5);
  expect(r.spec.tagline).toBe("Loves fish, scared of puddles");
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
