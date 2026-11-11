import { COPY, errorText } from "./copy.js";

export function reducer(s, a) {
  switch (a.type) {
    case "boot":
      return { ...s, booted: true, session: a.session, config: a.config, me: a.me ?? null };
    case "online":
      return { ...s, online: a.online };
    case "me":
      return {
        ...s,
        me: a.me,
        ...(a.me?.status === "processing" ? { redo: false, result: null, live: null } : {}),
      };
    case "redo":
      return { ...s, redo: a.on, result: null };
    case "tab":
      return { ...s, tab: a.tab };
    case "toast":
      return { ...s, toast: a.text };
    case "revealSeen":
      try {
        localStorage.setItem("bk_reveal_seen", a.id);
      } catch {}
      return { ...s, revealSeen: a.id };
    case "quitting":
      return { ...s, quitting: a.on };
    case "left":
      return left(s);
    case "leftRace":
      // Left the race (DELETE /api/players/me/race): straight back to the garage, no result.
      return {
        ...s,
        live: null,
        result: null,
        leftRun: a.runId,
        toast: COPY.run.left,
        me: s.me ? { ...s.me, currentRun: undefined } : s.me,
      };
    case "clearResult":
      return { ...s, result: null, lastCoach: a.coach ?? s.lastCoach };
    case "ws":
      return onWs(s, a.msgType, a.payload);
    default:
      return s;
  }
}

/** Back to the join screen: the racer is gone (quit, or removed by the admin). */
function left(s) {
  return {
    ...s,
    me: null,
    live: null,
    result: null,
    redo: false,
    quitting: false,
    tab: "garage",
  };
}

function onWs(s, type, p) {
  switch (type) {
    case "welcome":
      return {
        ...s,
        booted: true,
        session: p.session,
        config: p.config,
        me: p.me ?? null, // no me = this device has no racer (e.g. it quit)
        weather: p.weather,
      };
    case "player.updated":
      return {
        ...s,
        me: p,
        ...(p.status === "processing" ? { redo: false, result: null, live: null } : {}),
      };
    case "player.removed":
      return s.me?.id === p.playerId ? left(s) : s;
    case "session.updated":
      return { ...s, session: p };
    case "config.updated":
      return { ...s, config: p };
    case "queue.updated":
      return { ...s, queue: p };
    case "weather.updated":
      return { ...s, weather: p };
    case "leaderboard.updated":
      return { ...s, leaderboard: p };
    case "run.queued":
    case "run.started":
      return {
        ...s,
        redo: false,
        result: null,
        live:
          s.live?.runId === p.run.id
            ? s.live
            : {
                runId: p.run.id,
                progress: 0,
                elapsedMs: 0,
                sections: {},
              },
        me: s.me ? { ...s.me, currentRun: p.run } : s.me,
      };
    case "paddock.updated":
      return { ...s, paddock: p };
    case "run.grid":
      // On the start grid in its half: the lights go green in goInMs (contracts §2c).
      if (!s.live || s.live.runId !== p.runId) return s;
      return { ...s, live: { ...s.live, goAt: Date.now() + p.goInMs } };
    case "run.progress":
      if (s.live && s.live.runId !== p.runId) return s;
      // fork is only there while one is near: an old one doesn't linger.
      return { ...s, live: { sections: {}, ...s.live, ...p, fork: p.fork } };
    case "run.lap":
      if (!s.live || s.live.runId !== p.runId) return s;
      return { ...s, live: { ...s.live, laps: [...(s.live.laps ?? []), p], sections: {} } };
    case "run.section":
      if (!s.live || s.live.runId !== p.runId) return s;
      return { ...s, live: { ...s.live, sections: { ...s.live.sections, [p.section]: p } } };
    case "run.ended":
      // The run this phone left: no result screen, the garage stays.
      if (p.run.id === s.leftRun)
        return { ...s, live: null, me: s.me ? { ...s.me, currentRun: undefined } : s.me };
      return {
        ...s,
        redo: false,
        live: null,
        result: { ...p, prevBest: s.me?.bestRun, build: s.me?.build },
        me: s.me ? { ...s.me, currentRun: undefined, lastRun: p.run } : s.me,
      };
    case "error":
      return { ...s, toast: errorText(p) };
    default:
      return s;
  }
}
