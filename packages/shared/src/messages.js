// WebSocket protocol (contracts.md §7). Each channel maps a message type to its payload schema.
import { z } from "zod";
import { ConfigSchema } from "./config.js";
import { PROTOCOL_VERSION } from "./enums.js";
import { newId } from "./ids.js";
import {
  CoachTipSchema,
  FailReasonSchema,
  GhostTraceSchema,
  LeaderboardEntrySchema,
  PlayerViewSchema,
  RosterEntrySchema,
  RunEventSchema,
  RunSchema,
  RunStartSchema,
  SectionIdSchema,
  SessionSchema,
  SplitsSchema,
  WeatherKindSchema,
  WeatherStateSchema,
} from "./schemas.js";

const ms = z.number().int().nonnegative();
const empty = z.object({});
const progress = z.number().min(0).max(1);

const hello = z.discriminatedUnion("role", [
  z.object({ role: z.literal("phone") }), // the bk_device cookie identifies the device
  z.object({ role: z.literal("game"), gameKey: z.string() }),
  z.object({ role: z.literal("admin"), pin: z.string() }),
]);

const errorPayload = z.object({
  code: z.string(),
  message: z.string(),
  refId: z.string().optional(),
});

const broadcasts = {
  "leaderboard.updated": z.array(LeaderboardEntrySchema),
  "session.updated": SessionSchema,
  "config.updated": ConfigSchema,
  error: errorPayload,
};

const phoneBroadcasts = {
  ...broadcasts,
  "weather.updated": WeatherStateSchema,
};

const lapInfo = {
  lap: z.number().int().positive().optional(), // loop tracks: lap in progress, from 1
  lapMs: ms.optional(), // loop tracks: time on the lap in progress
};

const runResult = {
  runId: z.string(),
  elapsedMs: ms,
  laps: z.array(ms).optional(), // loop tracks: completed laps, in order
  bestLapMs: ms.optional(), // loop tracks: fastest completed lap
  splits: SplitsSchema, // loop tracks: the best lap's splits
  events: z.array(RunEventSchema),
  boostsUsed: z.number().int().nonnegative(),
  weatherSeen: z.array(WeatherKindSchema),
};

export const CHANNELS = {
  phoneToServer: {
    hello,
    "phone.go": empty,
    "phone.boost": z.object({ runId: z.string() }),
    // Loop tracks: "Pit in" ends the run when the racer next crosses the line.
    "phone.stop": z.object({ runId: z.string() }),
    // "Show me on the big screen": the game's camera cuts to this racer soon.
    "phone.watch": z.object({ runId: z.string() }),
  },
  adminToServer: {
    hello,
  },
  gameToServer: {
    hello,
    "game.run.started": z.object({ runId: z.string() }),
    "game.run.progress": z.object({
      runId: z.string(),
      progress,
      elapsedMs: ms,
      section: SectionIdSchema,
      boostsLeft: z.number().int().nonnegative(),
      ...lapInfo,
    }),
    "game.run.section": z.object({ runId: z.string(), section: SectionIdSchema, splitMs: ms }),
    // Loop tracks: the racer crossed the line. isBest = fastest lap of this run so far.
    "game.run.lap": z.object({
      runId: z.string(),
      lap: z.number().int().positive(),
      lapMs: ms,
      elapsedMs: ms,
      splits: SplitsSchema,
      isBest: z.boolean(),
    }),
    "game.run.finished": z.object({ ...runResult, trace: GhostTraceSchema }),
    "game.run.failed": z.object({
      ...runResult,
      reason: FailReasonSchema,
      section: SectionIdSchema,
    }),
    "game.weather": WeatherStateSchema,
    "game.capacity": z.object({ freeSlots: z.number().int().nonnegative() }),
    // Game manager options on the big screen (phones never set options).
    // track changes only while no session is running (error track_locked).
    "game.config.set": ConfigSchema.pick({
      track: true,
      lapsPerRun: true,
      sessionMinutes: true,
      language: true,
    })
      .partial()
      .strict(),
    "game.session.start": empty, // ended → a new session with a fresh leaderboard
    "game.session.end": empty,
    // The run the big-screen camera follows now, on every cut; no runId when nobody races.
    "game.camera": z.object({ runId: z.string().optional() }),
  },
  serverToPhone: {
    ...phoneBroadcasts,
    welcome: z.object({
      session: SessionSchema,
      config: ConfigSchema,
      me: PlayerViewSchema.optional(),
      weather: WeatherStateSchema,
    }),
    "player.updated": PlayerViewSchema,
    // The player quit (or the admin removed them): the phone goes back to the join screen.
    "player.removed": z.object({ playerId: z.string() }),
    "run.queued": z.object({ run: RunSchema }),
    "run.started": z.object({ run: RunSchema }),
    "run.progress": z.object({
      runId: z.string(),
      progress,
      elapsedMs: ms,
      section: SectionIdSchema,
      deltaVsBestMs: z.number().int().optional(),
      boostsLeft: z.number().int().nonnegative(),
      ...lapInfo,
    }),
    // Loop tracks: a lap completed. isLapBest = the player's fastest lap ever (session).
    "run.lap": z.object({
      runId: z.string(),
      lap: z.number().int().positive(),
      lapMs: ms,
      isLapBest: z.boolean(),
      deltaVsBestLapMs: z.number().int().optional(),
    }),
    "run.section": z.object({
      runId: z.string(),
      section: SectionIdSchema,
      splitMs: ms,
      bestSplitMs: ms.optional(),
    }),
    "run.ended": z.object({
      run: RunSchema,
      isPersonalBest: z.boolean(),
      rank: z.number().int().positive().optional(),
      coach: CoachTipSchema,
    }),
    // Who the big-screen camera follows now (relayed game.camera); empty when nobody.
    "camera.updated": z.object({
      playerId: z.string().optional(),
      runId: z.string().optional(),
    }),
  },
  // Not spelled out in contracts.md: the console gets the phone broadcasts plus the full
  // player list, so it can show every racer live.
  serverToAdmin: {
    ...phoneBroadcasts,
    welcome: z.object({
      session: SessionSchema,
      config: ConfigSchema,
      players: z.array(PlayerViewSchema),
      weather: WeatherStateSchema,
    }),
    "player.updated": PlayerViewSchema,
    "player.removed": z.object({ playerId: z.string() }),
  },
  serverToGame: {
    ...broadcasts,
    welcome: z.object({
      session: SessionSchema,
      config: ConfigSchema,
      roster: z.array(RosterEntrySchema),
      activeRuns: z.array(RunStartSchema),
    }),
    "roster.updated": z.array(RosterEntrySchema),
    "run.start": RunStartSchema,
    "run.boost": z.object({ runId: z.string() }),
    "run.stop": z.object({ runId: z.string() }), // loop tracks: finish at the next line crossing
    "run.watch": z.object({ runId: z.string() }), // a phone asked for the big screen
    "run.abort": z.object({ runId: z.string(), reason: z.string() }),
  },
};

/** Channels a role sends on, and receives on. */
export const ROLE_CHANNELS = {
  phone: { send: "phoneToServer", receive: "serverToPhone" },
  admin: { send: "adminToServer", receive: "serverToAdmin" },
  game: { send: "gameToServer", receive: "serverToGame" },
};

/**
 * Builds a validated message envelope. Throws if the payload doesn't match the contract,
 * since that is a bug in the sender.
 * @param {keyof typeof CHANNELS} channel
 * @param {string} type
 * @param {unknown} payload
 */
export function makeMsg(channel, type, payload) {
  const schema = CHANNELS[channel]?.[type];
  if (!schema) throw new Error(`Unknown message type "${type}" on channel "${channel}"`);
  return {
    v: PROTOCOL_VERSION,
    type,
    id: newId("message"),
    ts: new Date().toISOString(),
    payload: schema.parse(payload),
  };
}

const EnvelopeSchema = z.object({
  v: z.literal(PROTOCOL_VERSION),
  type: z.string(),
  id: z.string(),
  ts: z.string(),
  payload: z.unknown(),
});

/**
 * Parses and validates a raw message (string or object) received on a channel.
 * @param {keyof typeof CHANNELS} channel
 * @param {unknown} raw
 * @returns {{ ok: true, msg: { v: 1, type: string, id: string, ts: string, payload: any } }
 *   | { ok: false, error: { code: "bad_message", message: string, refId?: string } }}
 */
export function parseMsg(channel, raw) {
  let data = raw;
  if (typeof raw === "string") {
    try {
      data = JSON.parse(raw);
    } catch {
      return fail("message is not valid JSON");
    }
  }
  const env = EnvelopeSchema.safeParse(data);
  if (!env.success) return fail(`bad envelope: ${issues(env.error)}`);
  const schema = CHANNELS[channel]?.[env.data.type];
  if (!schema) return fail(`unknown message type "${env.data.type}"`, env.data.id);
  const payload = schema.safeParse(env.data.payload);
  if (!payload.success)
    return fail(`bad ${env.data.type} payload: ${issues(payload.error)}`, env.data.id);
  return { ok: true, msg: { ...env.data, payload: payload.data } };
}

const issues = (error) =>
  error.issues.map((i) => `${i.path.join(".") || "(root)"} ${i.message}`).join("; ");
const fail = (message, refId) => ({ ok: false, error: { code: "bad_message", message, refId } });

/** Message type names per channel, e.g. MESSAGE_TYPES.gameToServer. */
export const MESSAGE_TYPES = Object.fromEntries(
  Object.entries(CHANNELS).map(([ch, types]) => [ch, Object.keys(types)]),
);
