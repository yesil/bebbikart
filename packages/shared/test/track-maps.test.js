import { expect, test } from "bun:test";
import { TRACK_IDS, TRACK_MAPS, TRACK_STRETCHES, TrackMapSchema, trackMap } from "../src/index.js";

test("every track has a map that matches the contract", () => {
  for (const track of TRACK_IDS) {
    const r = TrackMapSchema.safeParse(TRACK_MAPS[track]);
    expect(r.success, `${track}: ${r.error?.message}`).toBe(true);
    expect(trackMap(track).track).toBe(track);
  }
  expect(() => trackMap("moon")).toThrow(/no track map for "moon"/);
});

// The maps are generated from the sim (bun run maps:export): a stretch added, renamed or removed in
// enums.js without re-exporting shows up here.
test("each map's stretches are exactly the track's stretches", () => {
  for (const track of TRACK_IDS) {
    const onMap = [...new Set(TRACK_MAPS[track].segments.map((s) => s.stretch))].sort();
    const known = TRACK_STRETCHES[track].map((s) => s.id).sort();
    expect(onMap, `${track} (stale map? run bun run maps:export)`).toEqual(known);
    for (const st of TRACK_STRETCHES[track].filter((s) => s.fork)) {
      const seg = TRACK_MAPS[track].segments.find((s) => s.stretch === st.id);
      expect([seg.fork, seg.choice], `${track} ${st.id}`).toEqual([st.fork, st.choice]);
    }
  }
});

test("a loop map closes; points stay inside the bounds", () => {
  for (const track of TRACK_IDS) {
    const m = TRACK_MAPS[track];
    const [x0, y0, x1, y1] = m.bounds;
    for (const s of m.segments)
      for (const [x, y] of s.pts) {
        expect(x >= x0 && x <= x1 && y >= y0 && y <= y1, `${track} ${s.id}`).toBe(true);
      }
    if (m.loop) {
      const first = m.segments[0].pts[0];
      const last = m.segments.at(-1).pts.at(-1);
      expect(Math.hypot(first[0] - last[0], first[1] - last[1])).toBeLessThan(0.2);
    }
  }
});

// Steering (contracts §2g): at every fork a kid steers left for one way and right for the other;
// every lap has boost arrows to steer over, off the forks.
test("each fork has a way to the left and one to the right; each lap has arrows", () => {
  for (const track of TRACK_IDS) {
    const segs = TRACK_MAPS[track].segments;
    const forks = [...new Set(segs.filter((s) => s.fork).map((s) => s.fork))];
    for (const fork of forks) {
      const sides = segs
        .filter((s) => s.fork === fork)
        .map((s) => s.steer)
        .sort();
      expect(sides, `${track} ${fork}`).toEqual([-1, 1]);
    }
    for (const s of segs.filter((s) => !s.fork)) expect(s.steer, `${track} ${s.id}`).toBe(0);
    expect(
      segs.filter((s) => s.fork).every((s) => s.arrows === 0),
      `${track}: arrows on a fork`,
    ).toBe(true);
    expect(
      segs.reduce((n, s) => n + s.arrows, 0),
      track,
    ).toBeGreaterThan(0);
  }
});
