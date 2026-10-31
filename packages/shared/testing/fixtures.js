// Sample data for tests and the phone site's MSW mock API (contracts.md §9).
// Every object here is checked against its schema in test/fixtures.test.js.
import { DEFAULT_BUILD, routesFor } from "../src/build.js";
import { DEFAULT_CONFIG } from "../src/config.js";
import { DEFAULT_SPEC } from "../src/default-spec.js";
import { DEFAULT_PACKAGE_ID } from "../src/enums.js";

export { DEFAULT_SPEC };

const T0 = Date.parse("2026-11-20T09:00:00.000Z");
export const at = (offsetMs) => new Date(T0 + offsetMs).toISOString();

const extra = (shape, socket, color, opts = {}) => ({
  shape,
  socket,
  offset: opts.offset ?? [0, 0, 0],
  scale: opts.scale ?? [0.3, 0.3, 0.3],
  rotationDeg: opts.rotationDeg ?? [0, 0, 0],
  color,
  ...(opts.mirror ? { mirror: true } : {}),
});

export const SAMPLE_SPECS = {
  pkg_purpleflash: {
    specVersion: 1,
    title: "The Purple Flash",
    personality: ["brave", "speedy", "silly"],
    palette: ["#7b2cbf", "#ffd60a", "#ffffff", "#ff006e"],
    character: {
      body: { shape: "tall", color: 0, scale: [0.9, 1.2, 0.9] },
      head: { shape: "round", color: 2, size: 1.1 },
      face: { eyes: "big_round", eyeColor: "#7b2cbf", mouth: "grin", brows: true },
      hair: { style: "spiky", color: 1 },
      arms: { color: 0 },
      extras: [extra("star", "body_front", 1, { offset: [0, 0.1, 0.1], scale: [0.4, 0.4, 0.1] })],
    },
    ride: {
      base: "rocket",
      color: 0,
      accent: 3,
      scale: [1.1, 1, 1.2],
      tail: { style: "flame", color: 1 },
      extras: [
        extra("cone", "ride_front", 3, { offset: [0, 0, 0.3], scale: [0.5, 0.5, 0.8] }),
        extra("box", "ride_side", 1, { mirror: true, scale: [0.8, 0.1, 0.4] }),
      ],
      drawingSticker: true,
    },
  },
  pkg_dinohorse: {
    specVersion: 1,
    title: "Rex the Galloper",
    personality: ["stompy", "friendly"],
    palette: ["#2d6a4f", "#95d5b2", "#f4a261", "#1b1b1b"],
    character: {
      body: { shape: "round", color: 2, scale: [1, 1, 1] },
      head: { shape: "oval", color: 2, size: 0.9 },
      face: { eyes: "dots", eyeColor: "#1b1b1b", mouth: "smile", brows: false, cheeks: 2 },
      hat: { type: "cap", color: 0 },
      arms: { color: 2 },
      extras: [],
    },
    ride: {
      base: "animal4",
      color: 0,
      accent: 1,
      scale: [1.2, 1.1, 1.3],
      legs: { style: "claws", color: 0 },
      tail: { style: "dino", color: 0 },
      extras: [
        extra("cone", "ride_top", 1, { offset: [0, 0.2, 0], scale: [0.2, 0.4, 0.2] }),
        extra("cone", "ride_back", 1, { offset: [0, 0.2, -0.2], scale: [0.2, 0.3, 0.2] }),
      ],
      drawingSticker: false,
    },
  },
  pkg_cloudbike: {
    specVersion: 1,
    title: "Cloud Pedals",
    personality: ["dreamy", "calm"],
    palette: ["#a2d2ff", "#ffffff", "#ffafcc"],
    character: {
      body: { shape: "bean", color: 2, scale: [0.9, 0.9, 0.9] },
      head: { shape: "round", color: 1, size: 1.2 },
      face: { eyes: "sleepy", eyeColor: "#3a86ff", mouth: "smile", brows: false, cheeks: 2 },
      hair: { style: "long", color: 0 },
      hat: { type: "bow", color: 2 },
      arms: { color: 1 },
      extras: [],
    },
    ride: {
      base: "bike",
      color: 0,
      accent: 1,
      scale: [1, 1, 1],
      wheels: { count: 2, style: "spoked", color: 1, size: 1.3 },
      wings: { style: "fairy", color: 1, size: 0.8 },
      extras: [extra("sphere", "ride_bottom", 1, { scale: [0.6, 0.3, 0.6] })],
      drawingSticker: true,
    },
  },
  pkg_robotshoe: {
    specVersion: 1,
    title: "Bolt Boot",
    personality: ["clever", "bouncy", "loud"],
    palette: ["#adb5bd", "#e63946", "#ffbe0b", "#1d3557", "#06d6a0"],
    character: {
      body: { shape: "box", color: 0, scale: [1, 1, 1] },
      head: { shape: "square", color: 0, size: 1 },
      face: { eyes: "visor", eyeColor: "#06d6a0", mouth: "none", brows: false },
      arms: { color: 3 },
      extras: [
        extra("sphere", "head_top", 1, { offset: [0, 0.25, 0], scale: [0.15, 0.15, 0.15] }),
        extra("cylinder", "head_side", 2, { mirror: true, scale: [0.1, 0.2, 0.1] }),
      ],
    },
    ride: {
      base: "blob",
      color: 1,
      accent: 2,
      scale: [1.3, 0.8, 1.4],
      wheels: { count: 3, style: "monster", color: 3, size: 0.8 },
      extras: [extra("torus", "ride_side", 4, { mirror: true, scale: [0.3, 0.3, 0.3] })],
      drawingSticker: false,
    },
  },
  pkg_duckboat: {
    specVersion: 1,
    title: "Captain Quack",
    personality: ["splashy", "happy"],
    palette: ["#ffd60a", "#fb8500", "#219ebc", "#ffffff"],
    character: {
      body: { shape: "pear", color: 0, scale: [1, 0.9, 1] },
      head: { shape: "round", color: 0, size: 1 },
      face: { eyes: "googly", eyeColor: "#000000", mouth: "beak", brows: true },
      hat: { type: "party", color: 2 },
      arms: { color: 0 },
      extras: [],
    },
    ride: {
      base: "boat",
      color: 2,
      accent: 3,
      scale: [1, 1, 1.1],
      wheels: { count: 4, style: "donut", color: 1, size: 0.9 },
      extras: [extra("heart", "ride_front", 1, { scale: [0.3, 0.3, 0.1] })],
      drawingSticker: true,
    },
  },
};

const manifest = (packageId, playerId, spec) => ({
  packageId,
  playerId,
  updatedAt: at(60_000),
  spec,
  drawings: {
    character: `/assets/${packageId}/drawing_character.jpg`,
    vehicle: `/assets/${packageId}/drawing_vehicle.jpg`,
  },
  renders: {
    hero: `/assets/${packageId}/hero.png`,
    avatar_happy: `/assets/${packageId}/avatar_happy.png`,
    avatar_excited: `/assets/${packageId}/avatar_excited.png`,
    avatar_sad: `/assets/${packageId}/avatar_sad.png`,
  },
});

export const DEFAULT_MANIFEST = {
  ...manifest(DEFAULT_PACKAGE_ID, "", DEFAULT_SPEC),
  drawings: { character: "", vehicle: "" },
};

export const SESSION_RUNNING = {
  id: "ses_fixture00001",
  status: "running",
  startedAt: at(0),
  endsAt: at(DEFAULT_CONFIG.sessionMinutes * 60_000),
  durationMs: DEFAULT_CONFIG.sessionMinutes * 60_000,
};

export const WEATHER_CALM = {
  rain: { phase: "calm", intensity: 0 },
  wind: { phase: "calm", strength: 0, dirDeg: 90 },
  changedAt: at(0),
};

export const WEATHER_RAIN_WARNING = {
  rain: { phase: "warning", intensity: 0.2 },
  wind: { phase: "calm", strength: 0, dirDeg: 90 },
  changedAt: at(120_000),
};

const names = ["Mila", "Noah", "Lena", "Elias", "Sofia"];
const pkgIds = Object.keys(SAMPLE_SPECS);

export const PLAYERS = pkgIds.map((pkgId, i) => ({
  id: `ply_fixture0000${i + 1}`,
  sessionId: SESSION_RUNNING.id,
  deviceId: `dev_fixture0000${i + 1}`,
  nickname: names[i],
  status: "ready",
  assetPackageId: pkgId,
  connected: i < 4,
  createdAt: at(30_000 + i * 10_000),
}));

export const BUILDS = PLAYERS.map((p, i) => ({
  id: `bld_fixture0000${i + 1}`,
  playerId: p.id,
  ...structuredClone(DEFAULT_BUILD),
  createdAt: at(90_000 + i * 10_000),
}));
BUILDS[1].stars = { speed: 4, jump: 1, grip: 3, water: 0, stability: 1, bounce: 1 };
BUILDS[2].stars = { speed: 2, jump: 0, grip: 2, water: 6, stability: 0, bounce: 0 };
for (const b of BUILDS) b.routes = routesFor(b.stars);

const splits = (hills, pond, crossing, bends) =>
  Object.fromEntries(
    Object.entries({ hills, pond, crossing, bends }).filter(([, v]) => v !== undefined),
  );
/** Countryside stretches (contracts §2d): [id, ms, lostMs] in driving order. */
const stretches = (...rows) => rows.map(([id, ms, lostMs = 0]) => ({ id, ms, lostMs }));

export const RUNS = [
  {
    id: "run_fixture00001",
    playerId: PLAYERS[0].id,
    buildId: BUILDS[0].id,
    status: "done",
    outcome: "finished",
    queuedAt: at(200_000),
    startedAt: at(200_200),
    endedAt: at(232_400),
    elapsedMs: 32_200,
    track: "countryside",
    splits: splits(7_900, 9_400, 7_300, 7_600),
    stretches: stretches(
      ["bumpy_road", 4_400],
      ["knoll_road", 2_300],
      ["hilltop", 1_200],
      ["stone_bridge", 9_400, 1_200],
      ["hedge_lane", 7_300],
      ["rainbow_bends", 7_600],
    ),
    events: [
      { kind: "boost_perfect", section: "hills", stretch: "bumpy_road", atMs: 3_100 },
      { kind: "slip", section: "pond", stretch: "stone_bridge", atMs: 11_000, timeLostMs: 1_200 },
    ],
    boostsUsed: 2,
    weatherSeen: [],
  },
  {
    id: "run_fixture00002",
    playerId: PLAYERS[0].id,
    buildId: BUILDS[0].id,
    status: "done",
    outcome: "finished",
    queuedAt: at(300_000),
    startedAt: at(300_150),
    endedAt: at(334_850),
    elapsedMs: 34_700,
    track: "countryside",
    splits: splits(7_800, 11_900, 7_400, 7_600),
    stretches: stretches(
      ["bumpy_road", 4_300],
      ["knoll_road", 2_300],
      ["hilltop", 1_200],
      ["stone_bridge", 11_900, 2_500],
      ["hedge_lane", 7_400],
      ["rainbow_bends", 7_600],
    ),
    events: [
      { kind: "slip", section: "pond", stretch: "stone_bridge", atMs: 10_500, timeLostMs: 2_100 },
      {
        kind: "bumped",
        section: "pond",
        stretch: "stone_bridge",
        atMs: 12_000,
        timeLostMs: 400,
        otherPlayerId: PLAYERS[1].id,
      },
    ],
    boostsUsed: 3,
    weatherSeen: ["rain"],
  },
  {
    id: "run_fixture00003",
    playerId: PLAYERS[1].id,
    buildId: BUILDS[1].id,
    status: "done",
    outcome: "failed",
    failReason: "off_track",
    failSection: "bends",
    failStretch: "rainbow_bends",
    queuedAt: at(310_000),
    startedAt: at(310_100),
    endedAt: at(336_000),
    track: "countryside",
    splits: splits(6_900, 8_100, 6_800),
    stretches: stretches(
      ["bumpy_road", 3_900],
      ["knoll_road", 2_000],
      ["hilltop", 1_000],
      ["stone_bridge", 8_100],
      ["hedge_lane", 6_800],
    ),
    events: [
      { kind: "slip", section: "bends", stretch: "rainbow_bends", atMs: 24_500, timeLostMs: 900 },
    ],
    boostsUsed: 1,
    weatherSeen: ["rain"],
  },
  {
    id: "run_fixture00004",
    playerId: PLAYERS[2].id,
    buildId: BUILDS[2].id,
    status: "done",
    outcome: "finished",
    queuedAt: at(320_000),
    startedAt: at(320_100),
    endedAt: at(349_900),
    elapsedMs: 29_800,
    track: "countryside",
    splits: splits(7_600, 6_900, 7_500, 7_800),
    stretches: stretches(
      ["bumpy_road", 4_200],
      ["knoll_road", 2_200],
      ["hilltop", 1_200],
      ["ford", 6_900],
      ["hedge_lane", 7_500],
      ["rainbow_bends", 7_800],
    ),
    events: [{ kind: "boost_perfect", section: "pond", stretch: "ford", atMs: 9_200 }],
    boostsUsed: 3,
    weatherSeen: [],
  },
];

PLAYERS[0].bestRunId = RUNS[0].id;
PLAYERS[0].bestTimeMs = RUNS[0].elapsedMs;
PLAYERS[2].bestRunId = RUNS[3].id;
PLAYERS[2].bestTimeMs = RUNS[3].elapsedMs;

/** A plausible 10 Hz trace for RUNS[0]: a wobbly loop, 5 numbers per sample. */
export const GHOST_TRACE = {
  runId: RUNS[0].id,
  hz: 10,
  samples: Array.from({ length: Math.round(RUNS[0].elapsedMs / 100) }, (_, i) => {
    const t = (i / (RUNS[0].elapsedMs / 100)) * Math.PI * 2;
    const r2 = (n) => Math.round(n * 100) / 100;
    return [
      r2(Math.cos(t) * 60),
      r2(Math.max(0, Math.sin(t * 3)) * 2),
      r2(Math.sin(t) * 40),
      r2(t + Math.PI / 2),
      0,
    ];
  }).flat(),
};

export const MANIFESTS = PLAYERS.map((p) =>
  manifest(p.assetPackageId, p.id, SAMPLE_SPECS[p.assetPackageId]),
);

export const JOBS = PLAYERS.map((p, i) => ({
  id: `job_fixture0000${i + 1}`,
  playerId: p.id,
  status: "ready",
  createdAt: at(35_000 + i * 10_000),
  updatedAt: at(55_000 + i * 10_000),
}));

/** A leaderboard / stretch-result setup (contracts §2f): the build raced and the run's weather. */
const setupOf = (b, run) => ({
  stars: { ...b.stars },
  routes: { ...b.routes },
  weather: [...run.weatherSeen],
});

export const LEADERBOARD = [
  {
    rank: 1,
    playerId: PLAYERS[2].id,
    nickname: PLAYERS[2].nickname,
    racerTitle: SAMPLE_SPECS[PLAYERS[2].assetPackageId].title,
    avatarUrl: MANIFESTS[2].renders.avatar_happy,
    bestTimeMs: RUNS[3].elapsedMs,
    setAt: RUNS[3].endedAt,
    setup: setupOf(BUILDS[2], RUNS[3]),
  },
  {
    rank: 2,
    playerId: PLAYERS[0].id,
    nickname: PLAYERS[0].nickname,
    racerTitle: SAMPLE_SPECS[PLAYERS[0].assetPackageId].title,
    avatarUrl: MANIFESTS[0].renders.avatar_happy,
    bestTimeMs: RUNS[0].elapsedMs,
    setAt: RUNS[0].endedAt,
    setup: setupOf(BUILDS[0], RUNS[0]),
  },
];

/** PlayerView for each fixture player, as the server would send it. */
export function playerView(index) {
  const p = PLAYERS[index];
  const runs = RUNS.filter((r) => r.playerId === p.id);
  const view = {
    ...p,
    job: JOBS[index],
    asset: MANIFESTS[index],
    build: BUILDS[index],
  };
  if (runs.length) view.lastRun = runs.at(-1);
  if (p.bestRunId) view.bestRun = RUNS.find((r) => r.id === p.bestRunId);
  const entry = LEADERBOARD.find((e) => e.playerId === p.id);
  if (entry) view.rank = entry.rank;
  return view;
}

export const ROSTER = PLAYERS.map((p, i) => ({
  playerId: p.id,
  nickname: p.nickname,
  connected: p.connected,
  status: p.status,
  assetBaseUrl: `/assets/${p.assetPackageId}/`,
  asset: MANIFESTS[i],
  ...(p.bestTimeMs !== undefined ? { bestTimeMs: p.bestTimeMs } : {}),
}));
