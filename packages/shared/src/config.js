import { z } from "zod";
import { GAME_MODES, LANGUAGES, TRACK_IDS } from "./enums.js";

/** Defaults from contracts.md §2. The server merges bebbikart.config.json and env vars on top. */
export const DEFAULT_CONFIG = Object.freeze({
  sessionMinutes: 30,
  maxPlayers: 20,
  maxConcurrentRuns: 20,
  starsTotal: 20,
  starsMaxPerAbility: 10,
  boostsPerRun: 3,
  runTimeCapMs: 90_000,
  stuckTimeoutMs: 3_000,
  launchCooldownMs: 2_000, // after a run ends, before the same racer can launch again
  startCountdownMs: 3_000, // race start: Go opens a countdown; everyone who presses Go in it starts together (0 = instant)
  track: "countryside", // TrackId; changes only while no session is running
  lapsPerRun: 3, // loop tracks: a run ends after this many laps (or earlier on "Pit in")
  language: "en", // Language: set on the big screen; every phone follows it
  mode: "race", // GameMode (contracts §2i): free races or a duel; changes only while no session is running
  duelResultMs: 5_000, // duel: a half shows its racer's result this long, then the next in line starts there
  weather: Object.freeze({
    rain: Object.freeze({
      minCalmMs: 20_000,
      maxCalmMs: 90_000,
      minMs: 6_000,
      maxMs: 15_000,
      warningMs: 5_000,
    }),
    wind: Object.freeze({
      minCalmMs: 25_000,
      maxCalmMs: 120_000,
      minMs: 5_000,
      maxMs: 40_000,
      warningMs: 5_000,
      maxStrength: 1.0,
    }),
  }),
  ghostEnabled: true,
  deleteUploadsOnReset: true,
});

const ms = z.number().int().nonnegative();
const weatherCycle = z.object({
  minCalmMs: ms,
  maxCalmMs: ms,
  minMs: ms,
  maxMs: ms,
  warningMs: ms,
});

export const ConfigSchema = z.object({
  sessionMinutes: z.number().positive(),
  maxPlayers: z.number().int().positive(),
  maxConcurrentRuns: z.number().int().positive(),
  starsTotal: z.number().int().positive(),
  starsMaxPerAbility: z.number().int().positive(),
  boostsPerRun: z.number().int().nonnegative(),
  runTimeCapMs: ms,
  stuckTimeoutMs: ms,
  launchCooldownMs: ms,
  startCountdownMs: ms,
  track: z.enum(TRACK_IDS),
  lapsPerRun: z.number().int().positive(),
  language: z.enum(LANGUAGES),
  mode: z.enum(GAME_MODES),
  duelResultMs: ms,
  weather: z.object({
    rain: weatherCycle,
    wind: weatherCycle.extend({ maxStrength: z.number().min(0).max(1) }),
  }),
  ghostEnabled: z.boolean(),
  deleteUploadsOnReset: z.boolean(),
});

/** Body of PATCH /api/admin/config: any subset, nested weather included. */
export const ConfigPatchSchema = ConfigSchema.extend({
  weather: z
    .object({
      rain: weatherCycle.partial(),
      wind: weatherCycle.extend({ maxStrength: z.number().min(0).max(1) }).partial(),
    })
    .partial(),
}).partial();

/**
 * Deep-merges a partial config onto a base and validates the result.
 * @param {z.infer<typeof ConfigSchema>} base
 * @param {unknown} patch
 * @returns {z.infer<typeof ConfigSchema>}
 */
export function mergeConfig(base, patch) {
  const p = ConfigPatchSchema.parse(patch);
  return ConfigSchema.parse({
    ...base,
    ...p,
    weather: {
      rain: { ...base.weather.rain, ...p.weather?.rain },
      wind: { ...base.weather.wind, ...p.weather?.wind },
    },
  });
}
