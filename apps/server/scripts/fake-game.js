// Stand-in for the Godot game, for testing the phone flow without Godot:
//   bun apps/server/scripts/fake-game.js [ws://localhost:8080/ws]
// Connects as the game, prints the roster, and "races" every run.start in ~12 s with fake splits.
import { makeMsg, SECTION_IDS } from "@bebbikart/shared";

const url = process.argv[2] ?? "ws://localhost:8080/ws";
const gameKey = process.env.BK_GAME_KEY ?? "bebbikart-dev";
const ws = new WebSocket(url);
const send = (type, payload) => ws.send(JSON.stringify(makeMsg("gameToServer", type, payload)));
const runs = new Map();

ws.onopen = () =>
  ws.send(JSON.stringify(makeMsg("phoneToServer", "hello", { role: "game", gameKey })));
ws.onclose = (e) => {
  console.log(`[fake-game] closed ${e.code} ${e.reason}`);
  process.exit(1);
};
ws.onmessage = (e) => {
  const { type, payload } = JSON.parse(e.data);
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
  } else if (type === "run.abort") {
    runs.get(payload.runId)?.stop();
  }
};

function race(start) {
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
