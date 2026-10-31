import { SECTION_IDS } from "@bebbikart/shared";
import { html } from "htm/preact";
import { useEffect, useState } from "preact/hooks";
import { api } from "../api.js";
import { COPY, errorText } from "../copy.js";
import { Avatar, delta, GridCall, isLoop, secs, useGridCall } from "./common.js";

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
  const [pitting, setPitting] = useState(false);
  const [asked, setAsked] = useState(false);
  const loop = isLoop(s.me.currentRun?.track ?? s.config.track);
  const lapsDone = live.laps ?? [];
  const lastLap = lapsDone[lapsDone.length - 1];
  const started = s.me.currentRun?.status === "running" || live.elapsedMs > 0;
  const boostsLeft = live.boostsLeft ?? s.config.boostsPerRun;
  const lastSection = SECTION_IDS.filter((id) => live.sections?.[id]).pop();
  const last = lastSection ? live.sections[lastSection] : null;
  const onCamera = !!live.runId && s.camera?.runId === live.runId;
  // The start countdown, in step with the lights on the big screen.
  const counting = !started && live.goAt !== undefined;
  const [, tick] = useState(0);
  useEffect(() => {
    if (!counting) return;
    const t = setInterval(() => tick((n) => n + 1), 100);
    return () => clearInterval(t);
  }, [counting]);
  const left = counting ? Math.ceil((live.goAt - Date.now()) / 1000) : 0;
  useEffect(() => {
    if (counting && left <= 0) navigator.vibrate?.(120);
  }, [counting, left <= 0]);

  // On the big screen now: a little buzz, and "Show me" can be asked again after this shot.
  useEffect(() => {
    if (!onCamera) return;
    navigator.vibrate?.([60, 40, 60]);
    setAsked(false);
  }, [onCamera]);
  // A request the big screen never got to (a crowd, or the racer's run ended): ask again later.
  useEffect(() => {
    if (!asked) return;
    const t = setTimeout(() => setAsked(false), 20000);
    return () => clearTimeout(t);
  }, [asked]);

  function boost(e) {
    e.preventDefault();
    if (!started || boostsLeft <= 0 || !live.runId) return;
    send("phone.boost", { runId: live.runId });
    navigator.vibrate?.(40);
    setFlash(true);
    setTimeout(() => setFlash(false), 180);
  }

  function showMe() {
    if (!started || !live.runId || onCamera || asked) return;
    send("phone.watch", { runId: live.runId });
    setAsked(true);
  }

  function pitIn() {
    if (!live.runId || pitting) return;
    send("phone.stop", { runId: live.runId });
    setPitting(true);
  }

  return html`
    <div class="run">
      ${
        loop && started
          ? html`<div class="lap-head">
              <span>${COPY.run.lap(Math.min(live.lap ?? lapsDone.length + 1, s.config.lapsPerRun), s.config.lapsPerRun)}</span>
              <span class="muted">${secs(live.elapsedMs)}</span>
            </div>`
          : null
      }
      ${counting ? html`<div class="get-ready">${COPY.run.getReady}</div>` : null}
      ${
        started && live.place && live.of > 1
          ? html`<div class=${`live-place p${Math.min(live.place, 4)}`}>${COPY.run.place(live.place, live.of)}</div>`
          : null
      }
      <div class=${`timer ${counting ? `count ${left > 0 ? "" : "go"}` : ""}`}>
        ${started ? secs(loop ? (live.lapMs ?? live.elapsedMs) : live.elapsedMs) : counting ? (left > 0 ? left : COPY.run.go) : COPY.run.queued}
      </div>
      ${
        loop && lastLap
          ? html`<div class=${`lap-result ${lastLap.isLapBest ? "good" : lastLap.deltaVsBestLapMs > 0 ? "bad" : ""}`}>
              ${lastLap.isLapBest ? COPY.run.bestLap : COPY.run.lastLap} ${secs(lastLap.lapMs)}
              ${lastLap.deltaVsBestLapMs !== undefined ? html` (${delta(lastLap.deltaVsBestLapMs)})` : null}
            </div>`
          : null
      }
      <div class="track">
        <div class="fill" style=${{ width: `${Math.round((live.progress ?? 0) * 100)}%` }}></div>
        ${SECTION_IDS.slice(1).map((id, i) => html`<i key=${id} class="tick" style=${{ left: `${((i + 1) / SECTION_IDS.length) * 100}%` }}></i>`)}
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
      ${
        loop && started
          ? html`<button class="ghost pit" disabled=${pitting} onClick=${pitIn}>
              ${pitting ? COPY.run.pitting : COPY.run.pitIn}
            </button>`
          : null
      }
      <button class=${`ghost watch ${onCamera ? "on" : ""}`} disabled=${!started || onCamera || asked} onClick=${showMe}>
        ${onCamera ? COPY.run.onScreen : asked ? COPY.run.showMeAsked : COPY.run.showMe}
      </button>
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
  const loop = isLoop(run.track);
  const laps = run.laps ?? [];
  const gridLeft = useGridCall(s);

  async function again() {
    dispatch({ type: "clearResult" });
    try {
      await api("POST", "/api/players/me/runs");
    } catch (err) {
      dispatch({ type: "toast", text: errorText(err) });
    }
  }

  return html`
    <div class="card center result">
      <${Avatar} me=${s.me} mood=${mood} size=${140} />
      ${
        loop && run.bestLapMs !== undefined
          ? html`<h1>${r.isPersonalBest ? COPY.result.pb : ok ? COPY.result.finished : COPY.result.oops}</h1>
              <div class="muted">${COPY.result.bestLapTitle}</div>
              <div class="bigtime">${secs(run.bestLapMs)}</div>
              ${!ok ? html`<p class="lead">${run.failReason ? COPY.result.fail[run.failReason] : ""}</p>` : null}`
          : ok
            ? html`<h1>${r.isPersonalBest ? COPY.result.pb : COPY.result.finished}</h1>
              <div class="bigtime">${secs(run.elapsedMs)}</div>`
            : html`<h1>${COPY.result.oops}</h1>
              <p class="lead">${run.outcome === "aborted" ? COPY.result.aborted : `${run.failReason ? COPY.result.fail[run.failReason] : ""}${run.failSection ? ` · ${COPY.sections[run.failSection]}` : ""}`}</p>`
      }
      ${r.rank ? html`<p class="muted">${COPY.garage.rank} #${r.rank}</p>` : null}
    </div>
    ${s.heat ? html`<${HeatCard} s=${s} />` : null}
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
    ${
      loop && laps.length
        ? html`<section class="card">
            <h2>${COPY.result.laps}</h2>
            <ol class="laps">
              ${laps.map((l, i) => html`<li key=${i} class=${l === run.bestLapMs ? "best" : ""}>${secs(l)}</li>`)}
            </ol>
          </section>`
        : null
    }
    ${r.coach ? html`<section class="card coach">💡 ${r.coach.text}</section>` : null}
    <div class="go-bar two">
      ${gridLeft ? html`<div class="span2"><${GridCall} s=${s} left=${gridLeft} /></div>` : null}
      <button class="ghost" onClick=${() => dispatch({ type: "clearResult", coach: r.coach })}>${COPY.result.change}</button>
      <button class="go small" onClick=${again}>${gridLeft ? COPY.grid.join : COPY.result.again}</button>
    </div>
  `;
}

/** Everyone who left the start with me: places as they come home, mine highlighted. */
function HeatCard({ s }) {
  const h = s.heat;
  const mine = h.entries.find((e) => e.playerId === s.me.id);
  const racing = h.entries.filter((e) => !e.outcome).length;
  return html`
    <section class="card heat">
      <h2>
        ${COPY.result.thisRace}${mine?.place ? html` · <b>${COPY.result.place(mine.place, h.entries.length)}</b>` : null}
      </h2>
      <ol class="board">
        ${h.entries.map(
          (e) => html`<li key=${e.playerId} class=${e.playerId === s.me.id ? "mine" : ""}>
            <span class="rank">${e.place ?? ""}</span>
            ${e.avatarUrl ? html`<img src=${e.avatarUrl} alt="" />` : html`<span class="ph">🏎️</span>`}
            <span class="who"><b>${e.nickname}</b></span>
            <span class="time">${e.timeMs !== undefined ? secs(e.timeMs) : e.outcome ? COPY.result.oops : COPY.result.racing}</span>
          </li>`,
        )}
      </ol>
      ${racing ? html`<p class="muted center">${COPY.result.stillRacing(racing)}</p>` : null}
    </section>
  `;
}
