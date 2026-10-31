import { SECTION_IDS } from "@bebbikart/shared";
import { html } from "htm/preact";
import { useState } from "preact/hooks";
import { api } from "../api.js";
import { COPY } from "../copy.js";
import { Avatar, delta, secs } from "./common.js";

export function Run({ ctx }) {
  const { s, send } = ctx;
  const live = s.live ?? {
    runId: s.me.currentRun?.id,
    progress: 0,
    elapsedMs: 0,
    boostsLeft: s.config.boostsPerRun,
    sections: {},
  };
  const [flash, setFlash] = useState(false);
  const started = s.me.currentRun?.status === "running" || live.elapsedMs > 0;
  const boostsLeft = live.boostsLeft ?? s.config.boostsPerRun;
  const lastSection = SECTION_IDS.filter((id) => live.sections?.[id]).pop();
  const last = lastSection ? live.sections[lastSection] : null;

  function boost(e) {
    e.preventDefault();
    if (!started || boostsLeft <= 0 || !live.runId) return;
    send("phone.boost", { runId: live.runId });
    navigator.vibrate?.(40);
    setFlash(true);
    setTimeout(() => setFlash(false), 180);
  }

  return html`
    <div class="run">
      <div class="timer">${started ? secs(live.elapsedMs) : COPY.run.queued}</div>
      <div class="track">
        <div class="fill" style=${{ width: `${Math.round((live.progress ?? 0) * 100)}%` }}></div>
        ${SECTION_IDS.slice(1).map((id, i) => html`<i key=${id} style=${{ left: `${((i + 1) / SECTION_IDS.length) * 100}%` }}></i>`)}
      </div>
      <div class="sections">
        ${SECTION_IDS.map((id) => html`<span key=${id} class=${live.section === id ? "on" : ""}>${COPY.sections[id]}</span>`)}
      </div>
      ${
        last && last.bestSplitMs !== undefined
          ? html`<div class=${`delta ${last.splitMs <= last.bestSplitMs ? "good" : "bad"}`}>
              ${COPY.sections[lastSection]} ${delta(last.splitMs - last.bestSplitMs)}
            </div>`
          : html`<div class="delta"></div>`
      }
      <button
        class=${`boost ${flash ? "flash" : ""}`}
        disabled=${!started || boostsLeft <= 0}
        onPointerDown=${boost}
      >
        ${COPY.run.boost}
        <span class="charges">${Array.from({ length: s.config.boostsPerRun }, (_, i) => html`<i class=${i < boostsLeft ? "on" : ""}>⚡</i>`)}</span>
      </button>
      <p class="muted center">📺 ${COPY.run.watch}</p>
    </div>
  `;
}

export function Result({ ctx }) {
  const { s, dispatch } = ctx;
  const r = s.result;
  const run = r.run;
  const ok = run.outcome === "finished";
  const mood = r.isPersonalBest ? "excited" : ok ? "happy" : "sad";
  const best = r.prevBest;

  async function again() {
    dispatch({ type: "clearResult" });
    try {
      await api("POST", "/api/players/me/runs");
    } catch (err) {
      dispatch({ type: "toast", text: COPY.errors[err.code] ?? err.message });
    }
  }

  return html`
    <div class="card center result">
      <${Avatar} me=${s.me} mood=${mood} size=${140} />
      ${
        ok
          ? html`<h1>${r.isPersonalBest ? COPY.result.pb : COPY.result.finished}</h1>
              <div class="bigtime">${secs(run.elapsedMs)}</div>`
          : html`<h1>${COPY.result.oops}</h1>
              <p class="lead">${run.outcome === "aborted" ? COPY.result.aborted : `${COPY.result.fail[run.failReason] ?? ""}${run.failSection ? ` · ${COPY.sections[run.failSection]}` : ""}`}</p>`
      }
      ${r.rank ? html`<p class="muted">${COPY.garage.rank} #${r.rank}</p>` : null}
    </div>
    ${
      run.splits && Object.keys(run.splits).length
        ? html`<section class="card">
            <table class="splits">
              <tr><th>${COPY.result.section}</th><th>${COPY.result.time}</th><th>${COPY.result.vsBest}</th></tr>
              ${SECTION_IDS.filter((id) => run.splits[id] !== undefined).map((id) => {
                const b = best?.splits?.[id];
                const d = b !== undefined ? run.splits[id] - b : null;
                return html`<tr key=${id}>
                  <td>${COPY.sections[id]}</td>
                  <td>${secs(run.splits[id])}</td>
                  <td class=${d === null ? "" : d <= 0 ? "good" : "bad"}>${d === null ? "–" : delta(d)}</td>
                </tr>`;
              })}
            </table>
          </section>`
        : null
    }
    ${r.coach ? html`<section class="card coach">💡 ${r.coach.text}</section>` : null}
    <div class="go-bar two">
      <button class="ghost" onClick=${() => dispatch({ type: "clearResult", coach: r.coach })}>${COPY.result.change}</button>
      <button class="go small" onClick=${again}>${COPY.result.again}</button>
    </div>
  `;
}
