// WebSocket protocol (contracts.md §7). Each channel maps a message type to its payload schema.
import { z } from "zod";
import { ConfigSchema } from "./config.js";
import { PROTOCOL_VERSION } from "./enums.js";
import { newId } from "./ids.js";
import {
  CoachTipSchema,
  FailReasonSchema,
  GhostTraceSchema,
  HeatEntrySchema,
  LeaderboardEntrySchema,
  PaddockEntrySchema,
  PlayerViewSchema,
  RosterEntrySchema,
  RunEventSchema,
  RunSchema,
  RunStartSchema,
  SectionIdSchema,
  SessionSchema,
  SplitsSchema,
  StretchIdSchema,
  StretchResultSchema,
  StretchTimeSchema,
  TrackIdSchema,
  WeatherKindSchema,
  WeatherStateSchema,
} from "./schemas.js";

const ms = z.number().int().nonnegative();
const empty = z.object({});
const progress = z.number().min(0).max(1);

const hello = z.discriminatedUnion("role", [
  z.object({ role: z.literal("phone") }), // the bk_device cookie identifies the device
  // track: the course the game has loaded; Go is refused (track_changing) while it differs from
  // config.track. Left out by a game that races whatever config.track says (fake-game).
  z.object({ role: z.literal("game"), gameKey: z.string(), track: TrackIdSchema.optional() }),
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
  // finished: the best lap's stretches (point to point: the run's); failed: the stretches done
  // on the lap it failed in (the one it failed on not included).
  stretches: z.array(StretchTimeSchema),
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
    // The run is on the start grid; it leaves (game.run.started) in goInMs, with everyone else
    // who pressed Go in the same countdown (config.startCountdownMs).
    "game.run.grid": z.object({ runId: z.string(), goInMs: ms }),
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
      stretches: z.array(StretchTimeSchema), // this lap's, in driving order; they add up to lapMs
      weatherSeen: z.array(WeatherKindSchema), // rain/wind active at any time on this lap
      isBest: z.boolean(),
    }),
    "game.run.finished": z.object({ ...runResult, trace: GhostTraceSchema }),
    "game.run.failed": z.object({
      ...runResult,
      reason: FailReasonSchema,
      section: SectionIdSchema,
      stretch: StretchIdSchema, // where it ended
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
    // Relayed game.run.grid: on the start grid, the lights go green in goInMs.
    "run.grid": z.object({ runId: z.string(), goInMs: ms }),
    // Everyone in the session (§7 "Paddock"), on joins, design steps, renders, races starting and
    // ending; also right after welcome.
    "paddock.updated": z.array(PaddockEntrySchema),
    // To every phone: a countdown is open and these racers are on the grid; others can still
    // press Go and join that race (§2c).
    "grid.updated": z.object({
      goInMs: ms,
      racers: z.array(z.object({ playerId: z.string(), nickname: z.string() })),
    }),
    "run.started": z.object({ run: RunSchema }),
    "run.progress": z.object({
      runId: z.string(),
      progress,
      elapsedMs: ms,
      section: SectionIdSchema,
      deltaVsBestMs: z.number().int().optional(),
      boostsLeft: z.number().int().nonnegative(),
      ...lapInfo,
      // In a heat (§7 "Heats"): place right now among the racers who left together, of how many.
      place: z.number().int().positive().optional(),
      of: z.number().int().positive().optional(),
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
      // run.stretches with the player's best and the session's fastest on each (§2d); empty
      // for an aborted run.
      stretches: z.array(StretchResultSchema),
    }),
    // The racers who left the start with this one: places so far, sent on each of their results;
    // done once the last of them is home (§7 "Heats").
    "run.heat": z.object({
      heatId: z.string(),
      done: z.boolean(),
      entries: z.array(HeatEntrySchema),
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
