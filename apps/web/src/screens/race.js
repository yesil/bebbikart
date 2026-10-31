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
  // The laps this run races (set when it was queued); never the config's, which may have changed.
  const runLaps = s.me.currentRun?.lapsPerRun;
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
              <span>${
                runLaps
                  ? COPY.run.lap(Math.min(live.lap ?? lapsDone.length + 1, runLaps), runLaps)
                  : html`<b class="bad">${COPY.run.lapsMissing}</b>`
              }</span>
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
    ${r.coach ? html`<section class="card coach">💡 ${r.coach.text}</section>` : null}
    ${r.stretches?.length || run.failStretch ? html`<${Stretches} r=${r} meId=${s.me?.id} />` : null}
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
    <div class="go-bar-space" aria-hidden="true"></div>
    <div class="go-bar two">
      ${gridLeft ? html`<div class="span2"><${GridCall} s=${s} left=${gridLeft} /></div>` : null}
      <button class="ghost" onClick=${() => dispatch({ type: "clearResult", coach: r.coach })}>${COPY.result.change}</button>
      <button class="go small" onClick=${again}>${gridLeft ? COPY.grid.join : COPY.result.again}</button>
    </div>
  `;
}

/** A gap to the session's fastest smaller than this isn't worth a note. */
const FASTER_NOTE_MS = 200;

/**
 * "See why" (contracts §2d): each stretch of the run with its star, my time and the gap to my best
 * there; the coach tip's stretch highlighted; a note on the one stretch where the session's
 * fastest racer (someone else) gains most on me; a failed run's last stretch at the end.
 */
function Stretches({ r, meId }) {
  const run = r.run;
  const names = COPY.stretches[run.track];
  let faster;
  for (const st of r.stretches) {
    if (!st.fastestNickname || st.fastestPlayerId === meId) continue;
    const gap = st.ms - st.fastestMs;
    if (gap >= FASTER_NOTE_MS && (!faster || gap > faster.gap))
      faster = { id: st.id, gap, who: st.fastestNickname };
  }
  return html`
    <section class="card">
      <h2>${COPY.result.stretchesTitle}</h2>
      <ol class="stretches">
        ${r.stretches.map((st) => {
          // Tenths, like delta() shows them: a hair either way is ±0.0, not red.
          const d = st.bestMs !== undefined ? Math.round((st.ms - st.bestMs) / 100) * 100 : null;
          return html`<li key=${st.id} class=${r.coach?.stretch === st.id ? "tip" : ""}>
            <span class="ic">${st.ability ? COPY.abilities[st.ability][0] : COPY.result.safeRoute}</span>
            <span class="nm">${names[st.id]}</span>
            <span class="t">${secs(st.ms)}</span>
            <span class=${`d ${d === null || d === 0 ? "" : d < 0 ? "good" : "bad"}`}>${d === null ? "–" : delta(d)}</span>
            ${
              faster?.id === st.id
                ? html`<span class="note">${COPY.result.fasterHere(faster.who, (faster.gap / 1000).toFixed(1))}</span>`
                : null
            }
          </li>`;
        })}
        ${
          run.failStretch
            ? html`<li class=${`ended ${r.coach?.stretch === run.failStretch ? "tip" : ""}`}>
                <span class="ic">💥</span>
                <span class="nm">${names[run.failStretch]}</span>
                <span class="note">${COPY.result.endedHere}</span>
              </li>`
            : null
        }
      </ol>
      <p class="hint">${COPY.result.vsYourBest}</p>
    </section>
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
