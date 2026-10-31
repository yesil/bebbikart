// Data model and REST shapes (contracts.md §4–6).
import { z } from "zod";
import { BuildSchema } from "./build.js";
import {
  ABILITIES,
  DRAWING_KINDS,
  FAIL_REASONS,
  FORK_IDS,
  GHOST_HZ,
  JOB_STAGES,
  JOB_STATUSES,
  PLAYER_STATUSES,
  REJECT_REASONS,
  RENDER_KEYS,
  RUN_EVENT_KINDS,
  RUN_OUTCOMES,
  RUN_STATUSES,
  SECTION_IDS,
  SESSION_STATUSES,
  TRACK_IDS,
  WEATHER_KINDS,
  WEATHER_PHASES,
} from "./enums.js";
import { RacerSpecSchema } from "./racer-spec.js";

const iso = z.iso.datetime();
const ms = z.number().int().nonnegative();

export const AbilitySchema = z.enum(ABILITIES);
export const SectionIdSchema = z.enum(SECTION_IDS);
export const ForkIdSchema = z.enum(FORK_IDS);
export const FailReasonSchema = z.enum(FAIL_REASONS);
export const TrackIdSchema = z.enum(TRACK_IDS);
export const WeatherKindSchema = z.enum(WEATHER_KINDS);
export const PlayerStatusSchema = z.enum(PLAYER_STATUSES);
export const JobStatusSchema = z.enum(JOB_STATUSES);
export const RejectReasonSchema = z.enum(REJECT_REASONS);
export const RenderKeySchema = z.enum(RENDER_KEYS);

/** Partial<Record<SectionId, ms>> */
export const SplitsSchema = z.partialRecord(SectionIdSchema, ms);

export const SessionSchema = z.object({
  id: z.string(),
  status: z.enum(SESSION_STATUSES),
  startedAt: iso.optional(),
  endsAt: iso.optional(),
  durationMs: ms,
});

export const NicknameSchema = z.string().trim().min(1).max(16);

export const PlayerSchema = z.object({
  id: z.string(),
  sessionId: z.string(),
  deviceId: z.string(), // empty for facilitator-managed racers
  nickname: NicknameSchema,
  status: PlayerStatusSchema,
  assetPackageId: z.string().optional(),
  connected: z.boolean(),
  createdAt: iso,
  bestRunId: z.string().optional(),
  bestTimeMs: ms.optional(),
});

export const RunEventSchema = z.object({
  kind: z.enum(RUN_EVENT_KINDS),
  section: SectionIdSchema,
  atMs: ms,
  timeLostMs: z.number().int().optional(),
  otherPlayerId: z.string().optional(), // for bumps
});

export const RunSchema = z.object({
  id: z.string(),
  playerId: z.string(),
  buildId: z.string(),
  status: z.enum(RUN_STATUSES),
  outcome: z.enum(RUN_OUTCOMES).optional(),
  failReason: FailReasonSchema.optional(),
  failSection: SectionIdSchema.optional(),
  queuedAt: iso,
  startedAt: iso.optional(),
  endedAt: iso.optional(),
  elapsedMs: ms.optional(), // sim time, finished runs only
  track: TrackIdSchema.optional(), // set by the server when the run is queued
  laps: z.array(ms).optional(), // loop tracks: every completed lap, in order
  bestLapMs: ms.optional(), // loop tracks: fastest of `laps` (what ranks)
  splits: SplitsSchema.optional(), // loop tracks: the best lap's splits
  events: z.array(RunEventSchema).optional(),
  boostsUsed: z.number().int().nonnegative().optional(),
  weatherSeen: z.array(WeatherKindSchema).optional(),
});

export const WeatherStateSchema = z.object({
  rain: z.object({ phase: z.enum(WEATHER_PHASES), intensity: z.number().min(0).max(1) }),
  wind: z.object({
    phase: z.enum(WEATHER_PHASES),
    strength: z.number().min(0).max(1),
    dirDeg: z.number(),
  }),
  changedAt: iso,
});

export const AssetJobSchema = z.object({
  id: z.string(),
  playerId: z.string(),
  status: JobStatusSchema,
  stage: z.enum(JOB_STAGES).optional(), // while designing: the pipeline step in progress
  rejectReason: RejectReasonSchema.optional(),
  rejectedImage: z.enum(DRAWING_KINDS).optional(),
  error: z.string().optional(),
  createdAt: iso,
  updatedAt: iso,
});

/** Flat array, 5 numbers per sample: x, y, z, yawRad, pitchRad. */
export const GhostTraceSchema = z.object({
  runId: z.string(),
  hz: z.literal(GHOST_HZ),
  samples: z.array(z.number()).refine((s) => s.length % 5 === 0, "5 numbers per sample"),
});

export const AssetManifestSchema = z.object({
  packageId: z.string(),
  playerId: z.string(),
  updatedAt: iso,
  spec: RacerSpecSchema,
  drawings: z.object({ character: z.string(), vehicle: z.string() }),
  renders: z.partialRecord(RenderKeySchema, z.string()),
  fallback: z.boolean().optional(),
});

export const PlayerViewSchema = PlayerSchema.extend({
  job: AssetJobSchema.optional(),
  asset: AssetManifestSchema.optional(),
  build: BuildSchema,
  currentRun: RunSchema.optional(),
  lastRun: RunSchema.optional(),
  bestRun: RunSchema.optional(),
  rank: z.number().int().positive().optional(),
});

export const LeaderboardEntrySchema = z.object({
  rank: z.number().int().positive(),
  playerId: z.string(),
  nickname: z.string(),
  racerTitle: z.string().optional(),
  avatarUrl: z.string(),
  bestTimeMs: ms,
  setAt: iso,
});

export const RosterEntrySchema = z.object({
  playerId: z.string(),
  nickname: z.string(),
  connected: z.boolean(),
  status: PlayerStatusSchema,
  assetBaseUrl: z.string(),
  asset: AssetManifestSchema.optional(),
  bestTimeMs: ms.optional(),
});

export const RunStartSchema = z.object({
  runId: z.string(),
  playerId: z.string(),
  build: BuildSchema,
  bestTrace: GhostTraceSchema.optional(),
  bestSplits: SplitsSchema.optional(),
});

export const CoachTipSchema = z.object({
  key: z.string(),
  text: z.string().max(70),
  section: SectionIdSchema.optional(),
  ability: AbilitySchema.optional(),
  route: z.object({ fork: ForkIdSchema, choice: z.string() }).optional(),
});

// REST request bodies (contracts.md §6). Build bodies: BuildInputSchema / parseBuildInput.
export const NicknameBodySchema = z.object({ nickname: NicknameSchema });
export const SessionStartBodySchema = z.object({ durationMs: ms.optional() });
/** REST error body: { error: { code, message } } */
export const ErrorBodySchema = z.object({
  error: z.object({ code: z.string(), message: z.string() }),
});
