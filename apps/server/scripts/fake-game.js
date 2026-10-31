// Stand-in for the Godot game, for testing the phone flow without Godot:
//   bun apps/server/scripts/fake-game.js [ws://localhost:8080/ws]
// Connects as the game, prints the roster, and "races" every run.start in ~12 s with fake splits.
import { LOOP_TRACKS, makeMsg, SECTION_IDS } from "@bebbikart/shared";

const url = process.argv[2] ?? "ws://localhost:8080/ws";
const gameKey = process.env.BK_GAME_KEY ?? "bebbikart-dev";
const ws = new WebSocket(url);
const send = (type, payload) => ws.send(JSON.stringify(makeMsg("gameToServer", type, payload)));
const runs = new Map();
let config = { track: "countryside", lapsPerRun: 3 };

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
  } else if (type === "run.boost") {
    const r = runs.get(payload.runId);
    if (r && r.boostsLeft > 0) {
      r.boostsLeft--;
      r.boosts++;
      console.log(`[fake-game] boost ${payload.runId}`);
    }
  } else if (type === "run.stop") {
    const r = runs.get(payload.runId);
    if (r) {
      r.pitIn = true;
      console.log(`[fake-game] pit in ${payload.runId}`);
    }
  } else if (type === "run.abort") {
    runs.get(payload.runId)?.stop();
  }
};

function race(start) {
  if (LOOP_TRACKS.includes(config.track)) return raceLoop(start);
  const r = { boostsLeft: 3, boosts: 0, stop: () => {} };
  runs.set(start.runId, r);
  console.log(`[fake-game] run ${start.runId} for ${start.playerId}`);
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
      boostsLeft: r.boostsLeft,
    });
    if (progress >= 1) {
      clearInterval(timer);
      splits.bends = t - sectionStart;
      const elapsedMs = Object.values(splits).reduce((a, b) => a + b, 0) - r.boosts * 400;
      const fail = Math.random() < 0.15;
      const common = {
        runId: start.runId,
        splits,
        events: [],
        boostsUsed: r.boosts,
        weatherSeen: [],
      };
      if (fail)
        send("game.run.failed", { ...common, elapsedMs, reason: "off_track", section: "bends" });
      else
        send("game.run.finished", {
          ...common,
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

// Loop track: 8 s laps; finishes after lapsPerRun laps, or at the next line after Pit in.
function raceLoop(start) {
  const r = { boostsLeft: 3, boosts: 0, pitIn: false, stop: () => {} };
  runs.set(start.runId, r);
  console.log(`[fake-game] loop run ${start.runId} (${config.lapsPerRun} laps)`);
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
      boostsLeft: r.boostsLeft,
      lap: laps.length + 1,
      lapMs: lapT,
    });
    if (lapT < lapLen) return;
    const lapMs = lapT - r.boosts * 300;
    laps.push(lapMs);
    send("game.run.lap", {
      runId: start.runId,
      lap: laps.length,
      lapMs,
      elapsedMs: t,
      splits: splitsOf(lapMs),
      isBest: lapMs === Math.min(...laps),
    });
    lapT = 0;
    r.boosts = 0;
    lapLen = lapTarget + Math.round(Math.random() * 1500);
    if (laps.length >= config.lapsPerRun || r.pitIn) {
      clearInterval(timer);
      const best = Math.min(...laps);
      send("game.run.finished", {
        runId: start.runId,
        elapsedMs: t,
        laps,
        bestLapMs: best,
        splits: splitsOf(best),
        events: [],
        boostsUsed: 0,
        weatherSeen: [],
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
