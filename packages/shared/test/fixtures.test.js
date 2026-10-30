import { expect, test } from "bun:test";
import {
  AssetJobSchema,
  BuildSchema,
  GhostTraceSchema,
  LeaderboardEntrySchema,
  PlayerViewSchema,
  RosterEntrySchema,
  RunSchema,
  SessionSchema,
  WeatherStateSchema,
} from "../src/index.js";
import * as f from "../testing/fixtures.js";

const check = (schema, value) => {
  const r = schema.safeParse(value);
  if (!r.success) throw new Error(JSON.stringify(r.error.issues, null, 2));
};

test("fixtures match the contracts", () => {
  check(SessionSchema, f.SESSION_RUNNING);
  check(WeatherStateSchema, f.WEATHER_CALM);
  check(WeatherStateSchema, f.WEATHER_RAIN_WARNING);
  check(GhostTraceSchema, f.GHOST_TRACE);
  for (const b of f.BUILDS) check(BuildSchema, b);
  for (const r of f.RUNS) check(RunSchema, r);
  for (const j of f.JOBS) check(AssetJobSchema, j);
  for (const e of f.LEADERBOARD) check(LeaderboardEntrySchema, e);
  for (const e of f.ROSTER) check(RosterEntrySchema, e);
  for (let i = 0; i < f.PLAYERS.length; i++) check(PlayerViewSchema, f.playerView(i));
  expect(f.GHOST_TRACE.samples.length).toBe(322 * 5);
});
