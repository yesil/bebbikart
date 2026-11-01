// Stand-in for the Godot game, for testing the phone flow without Godot:
//   bun apps/server/scripts/fake-game.js [ws://localhost:8080/ws]
// Connects as the game, prints the roster, and "races" every run.start in ~12 s with fake splits.
// The phone's thumb steers it (contracts §2g): the side the kart is on at a fork picks the way;
// hands off it takes the stars' way.
import { LOOP_TRACKS, makeMsg, SECTION_IDS, TRACK_STRETCHES, trackMap } from "@bebbikart/shared";

const url = process.argv[2] ?? "ws://localhost:8080/ws";
const gameKey = process.env.BK_GAME_KEY ?? "bebbikart-dev";
const ws = new WebSocket(url);
const send = (type, payload) => ws.send(JSON.stringify(makeMsg("gameToServer", type, payload)));
const runs = new Map();
let config; // the session config: from welcome, then config.updated

ws.onopen = () =>
  ws.send(JSON.stringify(makeMsg("phoneToServer", "hello", { role: "game", gameKey })));
ws.onclose = (e) => {
  console.log(`[fake-game] closed ${e.code} ${e.reason}`);
  process.exit(1);
};
ws.onmessage = (e) => {
  const { type, payload } = JSON.parse(e.data);
  if (type === "welcome") config = payload.config;
  if (type === "config.updated") config = payload;
  if (type === "welcome" || type === "roster.updated") {
    const roster = type === "welcome" ? payload.roster : payload;
    console.log(
      `[fake-game] roster: ${roster.map((r) => `${r.nickname}(${r.status}${r.connected ? "" : ",offline"})`).join(", ") || "empty"}`,
    );
  } else if (type === "run.start") {
    race(payload);
  } else if (type === "run.steer") {
    const r = runs.get(payload.runId);
    if (r) {
      if ((r.drive.x === null) !== (payload.x === null))
        console.log(`[fake-game] steer ${payload.x === null ? "let go" : "on"} ${payload.runId}`);
      r.drive.x = payload.x;
    }
  } else if (type === "queue.updated") {
    const q = payload;
    console.log(
      `[fake-game] halves (${q.split ? "split" : "full screen"}): racing ${q.racing.map((r) => `${r.side}:${r.nickname}`).join(" ") || "-"} · line ${q.line.map((e) => e.nickname).join(", ") || "-"} · champion ${q.champion ? `${q.champion.nickname} ${q.champion.timeMs} ms` : "-"}`,
    );
  } else if (type === "run.abort") {
    runs.get(payload.runId)?.stop();
  }
};

/**
 * A fake kart's lane and forks over a lap (contracts §2g): the lane follows the thumb (x, null
 * when it lets go); hands off it leans toward the stars' way near a fork. The track's forks are
 * spread evenly over the lap; passing one takes the way on the kart's side, or the stars' way.
 */
function driver(build) {
  const forks = [];
  for (const s of trackMap(config.track).segments) {
    if (!s.fork) continue;
    if (!forks.some((x) => x.id === s.fork)) forks.push({ id: s.fork, ways: {} });
    forks.find((x) => x.id === s.fork).ways[s.choice] = s.steer;
  }
  forks.forEach((f, i) => {
    f.at = (i + 1) / (forks.length + 1);
  });
  const wayTo = (f, side) => Object.keys(f.ways).find((c) => f.ways[c] === side);
  const d = {
    x: null,
    lane: 0,
    routes: {}, // the ways taken on this lap
    lap() {
      d.routes = {};
    },
    /** One tick of dt s at lap progress p; returns the fork hint while one is near. */
    tick(p, dt) {
      const f = forks.find((k) => d.routes[k.id] === undefined);
      const near = f && f.at - p < 0.1;
      const target = d.x ?? (near ? 0.5 * f.ways[build.routes[f.id]] : 0);
      d.lane += Math.max(-2.5 * dt, Math.min(2.5 * dt, target - d.lane));
      if (f && p >= f.at) {
        const side = Math.abs(d.lane) > 0.25 ? Math.sign(d.lane) : 0;
        d.routes[f.id] = (side && wayTo(f, side)) || build.routes[f.id];
        return undefined;
      }
      if (!near) return undefined;
      const way = Math.abs(d.lane) > 0.25 ? wayTo(f, Math.sign(d.lane)) : build.routes[f.id];
      return {
        id: f.id,
        inM: Math.max(0, Math.round((f.at - p) * 600)),
        left: wayTo(f, -1),
        right: wayTo(f, 1),
        way,
      };
    },
  };
  return d;
}

/** The progress payload's steering part (contracts §2g). */
function steerInfo(r, p, dt) {
  const fork = r.drive.tick(p, dt);
  return { lane: Math.round(r.drive.lane * 100) / 100, ...(fork ? { fork } : {}) };
}

/**
 * Fake stretch times (contracts §2d) for a lap or run of `ms` on the ways taken: every stretch
 * of the track except the fork pieces it didn't take, sharing `ms` at random; they add up to it.
 */
function stretchesOf(routes, ms) {
  const list = TRACK_STRETCHES[config.track].filter((s) => !s.fork || routes[s.fork] === s.choice);
  const weights = list.map(() => 0.6 + Math.random());
  const sum = weights.reduce((a, b) => a + b, 0);
  const out = list.map((s, i) => ({
    id: s.id,
    ms: Math.floor((ms * weights[i]) / sum),
    lostMs: 0,
  }));
  out[out.length - 1].ms += ms - out.reduce((a, s) => a + s.ms, 0);
  return out;
}

function race(start) {
  if (LOOP_TRACKS.includes(config.track)) return raceLoop(start);
  const r = { drive: driver(start.build), stop: () => {} };
  runs.set(start.runId, r);
  console.log(
    `[fake-game] run ${start.runId} for ${start.playerId}${start.side ? ` (${start.side})` : ""}`,
  );
  const total = 12_000;
  const splits = {};
  let t = 0;
  let sectionStart = 0;
  setTimeout(() => send("game.run.started", { runId: start.runId }), 1000);
  const timer = setInterval(() => {
    t += 200;
    const progress = Math.min(1, t / total);
    const idx = Math.min(3, Math.floor(progress * 4));
    const section = SECTION_IDS[idx];
    if (idx > 0 && splits[SECTION_IDS[idx - 1]] === undefined) {
      splits[SECTION_IDS[idx - 1]] = t - sectionStart + Math.round(Math.random() * 800);
      sectionStart = t;
      send("game.run.section", {
        runId: start.runId,
        section: SECTION_IDS[idx - 1],
        splitMs: splits[SECTION_IDS[idx - 1]],
      });
    }
    send("game.run.progress", {
      runId: start.runId,
      progress,
      elapsedMs: t,
      section,
      ...steerInfo(r, progress, 0.2),
    });
    if (progress >= 1) {
      clearInterval(timer);
      splits.bends = t - sectionStart;
      const elapsedMs = Object.values(splits).reduce((a, b) => a + b, 0);
      const fail = Math.random() < 0.15;
      const common = {
        runId: start.runId,
        splits,
        events: [],
        boostsUsed: 0,
        weatherSeen: [],
        routes: r.drive.routes,
      };
      const stretches = stretchesOf(r.drive.routes, elapsedMs);
      if (fail)
        send("game.run.failed", {
          ...common,
          elapsedMs,
          reason: "flipped",
          section: "bends",
          stretches: stretches.slice(0, -1),
          stretch: stretches[stretches.length - 1].id,
        });
      else
        send("game.run.finished", {
          ...common,
          stretches,
          elapsedMs,
          trace: { runId: start.runId, hz: 10, samples: [0, 0, 0, 0, 0] },
        });
      runs.delete(start.runId);
    }
  }, 200);
  r.stop = () => {
    clearInterval(timer);
    runs.delete(start.runId);
  };
}

// Loop track: 8 s laps; finishes after lapsPerRun laps (one, §2i).
function raceLoop(start) {
  const r = { drive: driver(start.build), stop: () => {} };
  runs.set(start.runId, r);
  const lapsPerRun = start.lapsPerRun;
  if (!lapsPerRun) {
    console.error(`[fake-game] ERROR loop run ${start.runId} without lapsPerRun: not racing it`);
    return;
  }
  console.log(`[fake-game] loop run ${start.runId} (${lapsPerRun} laps)`);
  const lapTarget = 8000;
  const laps = [];
  let t = 0;
  let lapT = 0;
  let lapLen = lapTarget + Math.round(Math.random() * 1500);
  setTimeout(() => send("game.run.started", { runId: start.runId }), 500);
  const splitsOf = (ms) => Object.fromEntries(SECTION_IDS.map((s) => [s, Math.round(ms / 4)]));
  const timer = setInterval(() => {
    t += 200;
    lapT += 200;
    const progress = Math.min(1, lapT / lapLen);
    const section = SECTION_IDS[Math.min(3, Math.floor(progress * 4))];
    send("game.run.progress", {
      runId: start.runId,
      progress,
      elapsedMs: t,
      section,
      ...steerInfo(r, progress, 0.2),
      lap: laps.length + 1,
      lapMs: lapT,
    });
    if (lapT < lapLen) return;
    const lapMs = lapT;
    laps.push(lapMs);
    const routes = r.drive.routes;
    const stretches = stretchesOf(routes, lapMs);
    if (lapMs === Math.min(...laps))
      Object.assign(r, { bestStretches: stretches, bestRoutes: routes });
    send("game.run.lap", {
      runId: start.runId,
      lap: laps.length,
      lapMs,
      elapsedMs: t,
      splits: splitsOf(lapMs),
      stretches,
      weatherSeen: [],
      isBest: lapMs === Math.min(...laps),
      routes,
    });
    lapT = 0;
    r.drive.lap();
    lapLen = lapTarget + Math.round(Math.random() * 1500);
    if (laps.length >= lapsPerRun) {
      clearInterval(timer);
      const best = Math.min(...laps);
      send("game.run.finished", {
        runId: start.runId,
        elapsedMs: t,
        laps,
        bestLapMs: best,
        splits: splitsOf(best),
        stretches: r.bestStretches,
        events: [],
        boostsUsed: 0,
        weatherSeen: [],
        routes: r.bestRoutes,
        trace: { runId: start.runId, hz: 10, samples: [0, 0, 0, 0, 0] },
      });
      runs.delete(start.runId);
    }
  }, 200);
  r.stop = () => {
    clearInterval(timer);
    runs.delete(start.runId);
  };
}
