// BebbiKart phone site (WS4): create a racer from two drawings, then tune, Go! and Boost!.
import { html } from "htm/preact";
import { render } from "preact";
import { useEffect, useReducer, useRef } from "preact/hooks";
import { api, connectWs } from "./api.js";
import { COPY } from "./copy.js";
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
  live: null, // { runId, progress, elapsedMs, section, boostsLeft, deltaVsBestMs, sections: {s: {splitMs, bestSplitMs}} }
  result: null, // run.ended payload, plus prevBest splits
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
    case "tab":
      return { ...s, tab: a.tab };
    case "toast":
      return { ...s, toast: a.text };
    case "revealSeen":
      try {
        localStorage.setItem("bk_reveal_seen", a.id);
      } catch {}
      return { ...s, revealSeen: a.id };
    case "clearResult":
      return { ...s, result: null, lastCoach: a.coach ?? s.lastCoach };
    case "ws":
      return onWs(s, a.msgType, a.payload);
    default:
      return s;
  }
}

function onWs(s, type, p) {
  switch (type) {
    case "welcome":
      return {
        ...s,
        booted: true,
        session: p.session,
        config: p.config,
        me: p.me ?? s.me,
        weather: p.weather,
      };
    case "player.updated":
      return { ...s, me: p };
    case "session.updated":
      return { ...s, session: p };
    case "config.updated":
      return { ...s, config: p };
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
                boostsLeft: s.config?.boostsPerRun ?? 3,
                sections: {},
              },
        me: s.me ? { ...s.me, currentRun: p.run } : s.me,
      };
    case "run.progress":
      if (s.live && s.live.runId !== p.runId) return s;
      return { ...s, live: { sections: {}, ...s.live, ...p } };
    case "run.section":
      if (!s.live || s.live.runId !== p.runId) return s;
      return { ...s, live: { ...s.live, sections: { ...s.live.sections, [p.section]: p } } };
    case "run.ended":
      return {
        ...s,
        live: null,
        result: { ...p, prevBest: s.me?.bestRun, build: s.me?.build },
        me: s.me ? { ...s.me, currentRun: undefined, lastRun: p.run } : s.me,
      };
    case "error":
      return { ...s, toast: COPY.errors[p.code] ?? p.message };
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
        dispatch({ type: "toast", text: `${COPY.errors.generic} (${err.message})` });
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
  return html`
    <div class="app">
      <header class="top">
        <span class="logo">${COPY.appName}</span>
        ${!s.online && s.booted ? html`<span class="pill warn">${COPY.offline}</span>` : null}
      </header>
      ${s.session?.status === "ended" ? html`<div class="banner">${COPY.sessionEnded}</div>` : null}
      ${s.session?.status === "idle" ? html`<div class="banner">${COPY.sessionIdle}</div>` : null}
      <main>${screen(ctx)}</main>
      ${s.toast ? html`<div class="toast" onClick=${() => dispatch({ type: "toast", text: null })}>${s.toast}</div>` : null}
    </div>
  `;
}

function screen(ctx) {
  const { s } = ctx;
  if (!s.booted) return html`<div class="center muted">${COPY.connecting}</div>`;
  const me = s.me;
  if (!me) return html`<${Create} ctx=${ctx} />`;
  if (me.status === "processing") return html`<${Making} ctx=${ctx} />`;
  if (me.status === "needs_review") return html`<${Making} ctx=${ctx} review />`;
  if (me.status === "rejected") return html`<${Rejected} ctx=${ctx} />`;
  if (me.status === "draft") return html`<${Create} ctx=${ctx} />`;
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

render(html`<${App} />`, document.getElementById("app"));
