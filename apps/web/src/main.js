// BebbiKart phone site (WS4): create a racer from two drawings, then tune, Go! and steer.
import { html } from "htm/preact";
import { render } from "preact";
import { useEffect, useErrorBoundary, useReducer, useRef, useState } from "preact/hooks";
import { api, connectWs } from "./api.js";
import { BOOT_COPY, COPY, errorText, setLanguage } from "./copy.js";
import { Create, Making, Rejected, Reveal } from "./screens/create.js";
import { Garage, Leaderboard } from "./screens/garage.js";
import { Result, Run } from "./screens/race.js";

const initial = {
  booted: false,
  online: false,
  session: null,
  config: null,
  me: null,
  weather: null,
  leaderboard: [],
  live: null, // { runId, progress, elapsedMs, section, lane, fork?, deltaVsBestMs, sections: {s: {splitMs, bestSplitMs}} }
  result: null, // run.ended payload, plus prevBest splits
  paddock: [], // paddock.updated: everyone in the session (friends' racers being made, racing)
  queue: null, // queue.updated (contracts §2i): the line, the two halves, the champion
  tab: "garage",
  revealSeen: readRevealSeen(),
  toast: null,
};

function readRevealSeen() {
  try {
    return localStorage.getItem("bk_reveal_seen") ?? "";
  } catch {
    return "";
  }
}

function reducer(s, a) {
  switch (a.type) {
    case "boot":
      return { ...s, booted: true, session: a.session, config: a.config, me: a.me ?? null };
    case "online":
      return { ...s, online: a.online };
    case "me":
      return { ...s, me: a.me };
    case "redo":
      return { ...s, redo: a.on };
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
      return { ...s, me: p };
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

function App() {
  const [s, dispatch] = useReducer(reducer, initial);
  const ws = useRef(null);

  useEffect(() => {
    (async () => {
      try {
        await api("POST", "/api/device");
        const st = await api("GET", "/api/state");
        dispatch({ type: "boot", ...st });
      } catch (err) {
        dispatch({ type: "toast", text: `${BOOT_COPY.failed} (${err.message})` });
      }
      ws.current = connectWs({
        onMessage: (msgType, payload) => dispatch({ type: "ws", msgType, payload }),
        onStatus: (online) => dispatch({ type: "online", online }),
      });
    })();
    return () => ws.current?.close();
  }, []);

  useEffect(() => {
    if (!s.toast) return;
    const t = setTimeout(() => dispatch({ type: "toast", text: null }), 3500);
    return () => clearTimeout(t);
  }, [s.toast]);

  const ctx = { s, dispatch, send: (type, payload) => ws.current?.send(type, payload) };
  // The big screen's language (config.language): switching it re-renders every screen live.
  if (s.config) setLanguage(s.config.language);
  if (!s.config)
    return html`
      <div class="app">
        <header class="top"><span class="logo">BebbiKart</span></header>
        <main><div class="center muted">${BOOT_COPY.connecting}</div></main>
        ${s.toast ? html`<div class="toast">${s.toast}</div>` : null}
      </div>
    `;
  return html`
    <div class="app">
      <header class="top">
        <span class="logo">${COPY.appName}</span>
        ${!s.online && s.booted ? html`<span class="pill warn">${COPY.offline}</span>` : null}
        ${s.me ? html`<button class="quit" onClick=${() => dispatch({ type: "quitting", on: true })}>${COPY.quit.button}</button>` : null}
      </header>
      ${s.me && s.quitting ? html`<${QuitBar} s=${s} dispatch=${dispatch} />` : null}
      ${s.session?.status === "ended" ? html`<div class="banner">${COPY.sessionEnded}</div>` : null}
      ${s.session?.status === "idle" ? html`<div class="banner">${COPY.sessionIdle}</div>` : null}
      <main>${screen(ctx)}</main>
      ${s.toast ? html`<div class="toast" onClick=${() => dispatch({ type: "toast", text: null })}>${s.toast}</div>` : null}
    </div>
  `;
}

function QuitBar({ s, dispatch }) {
  const [busy, setBusy] = useState(false);
  async function quit() {
    setBusy(true);
    try {
      await api("DELETE", "/api/players/me");
      dispatch({ type: "left" });
    } catch (err) {
      // Never pretend it worked: the racer is still on the big screen.
      dispatch({
        type: "toast",
        text: `${COPY.quit.failed} (${err.code ?? "error"}: ${err.message})`,
      });
      setBusy(false);
    }
  }
  return html`
    <div class="quit-bar">
      <p>${s.me.currentRun ? COPY.quit.askRacing : COPY.quit.ask}</p>
      <div class="row">
        <button class="ghost" disabled=${busy} onClick=${() => dispatch({ type: "quitting", on: false })}>${COPY.quit.stay}</button>
        <button class="danger" disabled=${busy} onClick=${quit}>${COPY.quit.confirm}</button>
      </div>
    </div>
  `;
}

function screen(ctx) {
  const { s } = ctx;
  const me = s.me;
  if (!me) return html`<${Create} ctx=${ctx} />`;
  if (me.status === "processing") return html`<${Making} ctx=${ctx} />`;
  if (me.status === "needs_review") return html`<${Making} ctx=${ctx} review />`;
  if (me.status === "rejected") return html`<${Rejected} ctx=${ctx} />`;
  if (me.status === "draft" || s.redo) return html`<${Create} ctx=${ctx} />`;
  // ready
  if (s.live || me.currentRun) return html`<${Run} ctx=${ctx} />`;
  if (s.result) return html`<${Result} ctx=${ctx} />`;
  if (me.asset && s.revealSeen !== me.asset.packageId) return html`<${Reveal} ctx=${ctx} />`;
  return html`
    <nav class="tabs">
      ${["garage", "leaderboard"].map(
        (t) =>
          html`<button class=${s.tab === t ? "on" : ""} onClick=${() => ctx.dispatch({ type: "tab", tab: t })}>
            ${COPY.tabs[t]}
          </button>`,
      )}
    </nav>
    ${s.tab === "leaderboard" ? html`<${Leaderboard} ctx=${ctx} />` : html`<${Garage} ctx=${ctx} />`}
  `;
}

/** A missing translation (or any render bug) shows up big on the phone, never as a blank page. */
function Crash() {
  const [error] = useErrorBoundary((err) => console.error(err));
  if (error)
    return html`<div class="error-box crash"><b>BebbiKart error</b><code>${String(error.message ?? error)}</code></div>`;
  return html`<${App} />`;
}

render(html`<${Crash} />`, document.getElementById("app"));
