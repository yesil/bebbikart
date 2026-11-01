import { SECTION_IDS, TRACK_STRETCHES } from "@bebbikart/shared";
import { html } from "htm/preact";
import { useEffect, useRef, useState } from "preact/hooks";
import { api } from "../api.js";
import { COPY, errorText } from "../copy.js";
import { Avatar, delta, isLoop, secs } from "./common.js";
import { SetupCard } from "./setup-card.js";
import { TrackMap } from "./track-map.js";

/** How often the thumb's lane goes to the server at most (contracts §2g): about 16 times a second. */
const STEER_EVERY_MS = 60;
/** Thumb travel, as a share of the screen's width, from the middle of the road to its edge. */
const STEER_SPAN = 0.35;
/** The kart's side of the road counts from this far off the middle (the sim's deadband). */
const SIDE_FROM = 0.25;

/** Where a lane (-1..1) sits across the pad's road (it spans 6%..94% of the pad). */
const pct = (lane) => `${(50 + lane * 38).toFixed(1)}%`;
const round2 = (x) => Math.round(x * 100) / 100;

export function Run({ ctx }) {
  const { s, send } = ctx;
  const live = s.live ?? {
    runId: s.me.currentRun?.id,
    progress: 0,
    elapsedMs: 0,
    sections: {},
  };
  // Its half of the big screen (contracts §2i): one lap against the clock.
  const side = s.me.currentRun?.side;
  const loop = isLoop(s.me.currentRun?.track ?? s.config.track);
  const started = s.me.currentRun?.status === "running" || live.elapsedMs > 0;
  const lastSection = SECTION_IDS.filter((id) => live.sections?.[id]).pop();
  const last = lastSection ? live.sections[lastSection] : null;
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

  const steer = useSteering(live, send);
  const leave = useLeave(live.runId, ctx.dispatch);
  const lane = live.lane ?? 0;
  const fork = live.fork;
  // A little buzz when the way the kart is heading for at the fork changes.
  useEffect(() => {
    if (fork?.way) navigator.vibrate?.(15);
  }, [fork?.id, fork?.way]);

  return html`
    <div class=${`run steer-surface ${steer.x !== null ? "steering" : ""}`} ...${steer.handlers}>
      <div class="run-top">
        ${side ? html`<div class=${`side-badge side-${side}`}>${COPY.duel.side[side]}</div>` : html`<div></div>`}
        <button
          class=${`leave-race ${leave.state}`}
          disabled=${leave.state === "sending"}
          onPointerDown=${(e) => e.stopPropagation()}
          onClick=${leave.tap}
        >
          ${leave.state === "ask" ? COPY.run.leaveAsk : leave.state === "sending" ? COPY.run.leaving : COPY.run.leave}
        </button>
      </div>
      ${counting ? html`<div class="get-ready">${COPY.run.getReady}</div>` : null}
      <div class=${`timer ${counting ? `count ${left > 0 ? "" : "go"}` : ""}`}>
        ${started ? secs(loop ? (live.lapMs ?? live.elapsedMs) : live.elapsedMs) : counting ? (left > 0 ? left : COPY.run.go) : COPY.run.queued}
      </div>
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
      ${fork ? html`<${ForkAhead} fork=${fork} />` : html`<div class="fork-ahead empty"></div>`}
      <div class=${`steer-pad ${steer.x !== null ? "on" : ""}`} aria-label=${COPY.run.padLabel}>
        <div class="road"><i class="mid"></i></div>
        ${steer.x !== null ? html`<div class="thumb" style=${{ left: pct(steer.x) }}></div>` : null}
        <div class="kart" style=${{ left: pct(lane) }}><${Avatar} me=${s.me} mood="happy" size=${54} /></div>
        <div class="pad-state">${steer.x !== null ? COPY.run.steering : COPY.run.handsOff}</div>
      </div>
      <p class="hint center">${fork ? COPY.run.forkHint : COPY.run.steerHint}</p>
      <p class="hint center">${COPY.run.arrowsHint}</p>
    </div>
  `;
}

/**
 * Leave the race, any time (contracts §6, DELETE /api/players/me/race): the kart leaves the
 * track, the lap doesn't count, the phone goes back to the garage. The whole screen steers, so a
 * thumb can brush the button: the first tap asks, a second within 3 s leaves.
 * Returns { state: "" | "ask" | "sending", tap }.
 */
function useLeave(runId, dispatch) {
  const [state, setState] = useState("");
  useEffect(() => {
    if (state !== "ask") return;
    const t = setTimeout(() => setState(""), 3000);
    return () => clearTimeout(t);
  }, [state]);
  async function tap(e) {
    e.stopPropagation();
    if (state === "") return setState("ask");
    if (state !== "ask") return;
    setState("sending");
    try {
      await api("DELETE", "/api/players/me/race");
      dispatch({ type: "leftRace", runId });
    } catch (err) {
      dispatch({ type: "toast", text: errorText(err) });
      setState("");
    }
  }
  return { state, tap };
}

/**
 * The fork coming up (run.progress fork, contracts §2g): the way to each side, the one the kart
 * is heading for lit up, and how far off it is.
 */
function ForkAhead({ fork }) {
  const ways = COPY.forks[fork.id];
  const sign = (dir, choice) =>
    html`<div class=${`sign ${dir} ${fork.way === choice ? "on" : ""}`}>
      ${dir === "left" ? html`<b>◀</b> ` : null}${ways[choice][0]}${dir === "right" ? html` <b>▶</b>` : null}
    </div>`;
  return html`
    <div class="fork-ahead">
      ${sign("left", fork.left)}
      <div class="dist">${COPY.run.forkIn(fork.inM)}</div>
      ${sign("right", fork.right)}
    </div>
  `;
}

/**
 * The steering pad (contracts §2g): a thumb dragged anywhere on the run screen moves the kart's
 * lane, relative to where it went down (starting from the lane the kart is in). Dragging past the
 * edge of the road moves the anchor, so coming back moves the kart straight away. Letting go,
 * the pointer being lost or the page hiding sends null: the autopilot drives again.
 * Returns { x: the lane asked for or null, handlers: pointer handlers for the surface }.
 */
function useSteering(live, send) {
  const [x, setX] = useState(null);
  const st = useRef({ id: null, px: 0, base: 0, span: 1, x: null, sent: undefined, timer: 0 });
  const runId = useRef(live.runId);
  runId.current = live.runId;
  const lane = useRef(0);
  lane.current = live.lane ?? 0;

  const flush = () => {
    const t = st.current;
    clearTimeout(t.timer);
    t.timer = 0;
    if (!runId.current || t.x === t.sent) return;
    t.sent = t.x;
    send("phone.steer", { runId: runId.current, x: t.x });
  };
  const queue = () => {
    if (!st.current.timer) st.current.timer = setTimeout(flush, STEER_EVERY_MS);
  };
  const letGo = () => {
    const t = st.current;
    if (t.id === null) return;
    t.id = null;
    t.x = null;
    setX(null);
    flush();
  };
  useEffect(() => {
    const hidden = () => document.hidden && letGo();
    document.addEventListener("visibilitychange", hidden);
    return () => {
      document.removeEventListener("visibilitychange", hidden);
      letGo();
    };
  }, [live.runId]);

  const handlers = {
    onPointerDown(e) {
      const t = st.current;
      if (!runId.current || t.id !== null) return;
      e.preventDefault();
      e.currentTarget.setPointerCapture?.(e.pointerId);
      t.id = e.pointerId;
      t.px = e.clientX;
      t.base = lane.current;
      t.span = Math.max(80, e.currentTarget.getBoundingClientRect().width * STEER_SPAN);
      t.x = round2(t.base);
      setX(t.x);
      navigator.vibrate?.(10);
      flush();
    },
    onPointerMove(e) {
      const t = st.current;
      if (e.pointerId !== t.id) return;
      e.preventDefault();
      let raw = t.base + (e.clientX - t.px) / t.span;
      // Past the edge: the anchor follows the thumb, so the way back starts moving at once.
      if (raw > 1) t.px = e.clientX - (1 - t.base) * t.span;
      if (raw < -1) t.px = e.clientX - (-1 - t.base) * t.span;
      raw = Math.max(-1, Math.min(1, raw));
      const nx = round2(raw);
      if (nx === t.x) return;
      // A buzz when the kart's side of the road flips: that side picks the way at a fork.
      const sideOf = (v) => (Math.abs(v) > SIDE_FROM ? Math.sign(v) : 0);
      if (sideOf(nx) !== sideOf(t.x ?? 0) && sideOf(nx) !== 0) navigator.vibrate?.(12);
      t.x = nx;
      setX(nx);
      queue();
    },
    onPointerUp: (e) => e.pointerId === st.current.id && letGo(),
    onPointerCancel: (e) => e.pointerId === st.current.id && letGo(),
    onLostPointerCapture: (e) => e.pointerId === st.current.id && letGo(),
    onContextMenu: (e) => e.preventDefault(),
  };
  return { x, handlers };
}

export function Result({ ctx }) {
  const { s, dispatch } = ctx;
  const r = s.result;
  const run = r.run;
  const ok = run.outcome === "finished";
  const mood = r.isPersonalBest ? "excited" : ok ? "happy" : "sad";
  const loop = isLoop(run.track);
  const [sel, setSel] = useState(null); // the stretch tapped on the map (its row lights up)
  const see = seeWhy(r, s.me?.id);
  const [peek, setPeek] = useState(false); // the faster racer's setup card is open
  const duelLine = r.duel ? duelVerdict(r.duel, run, s.me?.nickname) : null;

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
      ${duelLine ? html`<p class=${`duel-verdict ${r.duel.newChampion ? "crown" : ""}`}>${duelLine}</p>` : null}
      ${r.rank ? html`<p class="muted">${COPY.garage.rank} #${r.rank}</p>` : null}
    </div>
    ${r.coach ? html`<section class="card coach">💡 ${r.coach.text}</section>` : null}
    ${
      r.stretches?.length || run.failStretch
        ? html`<section class="card map">
              <${TrackMap} track=${run.track} routes=${run.routes} tone=${see.tone}
                pulse=${r.coach?.stretch} crash=${run.failStretch}
                flag=${see.faster ? { stretch: see.faster.id, text: see.faster.who } : null}
                selected=${sel} onPick=${setSel} />
              <p class="hint center">${COPY.map.tapHint}</p>
            </section>
            <${Stretches} r=${r} see=${see} sel=${sel} onPeek=${() => setPeek(true)} />`
        : null
    }
    ${
      peek && see.faster && s.me
        ? html`<${SetupCard}
            who=${{
              nickname: see.faster.who,
              avatarUrl: s.leaderboard.find((e) => e.playerId === see.faster.playerId)?.avatarUrl,
              timeMs: see.faster.ms,
              timeLabel: COPY.stretches[run.track][see.faster.route ?? see.faster.id],
            }}
            setup=${see.faster.setup} mine=${{ stars: (r.build ?? s.me.build).stars, routes: run.routes }}
            maxStars=${s.config.starsMaxPerAbility}
            ability=${see.faster.route ? null : see.faster.ability}
            fork=${see.faster.route ? TRACK_STRETCHES[run.track].find((x) => x.id === see.faster.route).fork : null}
            onClose=${() => setPeek(false)} />`
        : null
    }
    <div class="go-bar-space" aria-hidden="true"></div>
    <div class="go-bar two">
      <button class="ghost" onClick=${() => dispatch({ type: "clearResult", coach: r.coach })}>${COPY.result.change}</button>
      <button class="go small" onClick=${again}>${COPY.duel.join}</button>
    </div>
  `;
}

/**
 * A duel lap's verdict (run.ended.duel): the crown taken, or how far short of whose record. A
 * champion racing again (nobody else waiting) is judged against their own time.
 */
function duelVerdict(d, run, myNickname) {
  if (d.newChampion) return COPY.duel.newChampion;
  const own = d.recordNickname !== undefined && d.recordNickname === myNickname;
  const gap = d.gapMs !== undefined ? (Math.abs(d.gapMs) / 1000).toFixed(1) : null;
  if (run.outcome !== "finished" || gap === null)
    return d.recordNickname === undefined
      ? COPY.duel.noTimeNobody
      : own
        ? COPY.duel.noTimeOwn
        : COPY.duel.noTime(d.recordNickname);
  if (own) return d.gapMs < 0 ? COPY.duel.ownRecord : COPY.duel.ownShort(gap);
  return COPY.duel.short(gap, d.recordNickname);
}

/** A gap to the session's fastest smaller than this isn't worth a note. */
const FASTER_NOTE_MS = 200;

/** Gap to my best on a stretch in tenths, like delta() shows it (null without a best). */
const gapToBest = (st) =>
  st.bestMs !== undefined ? Math.round((st.ms - st.bestMs) / 100) * 100 : null;

/** Green or red only beyond noise: 0.2 s or 2% of the stretch, whichever is bigger. */
const toneOf = (st, d) =>
  d === null || Math.abs(d) < Math.max(200, st.ms * 0.02) ? "" : d < 0 ? "good" : "bad";

/**
 * What the map and the list show (contracts §2d, §2f): each stretch green or red against my best
 * (small gaps or no best yet stay neutral), and the one stretch where someone else in the session
 * gains most on me: on the same stretch, or on a fork through the other route ("Mia takes the
 * ford"), with their setup.
 */
function seeWhy(r, meId) {
  const tone = {};
  let faster;
  const consider = (f) => {
    if (f.gap >= FASTER_NOTE_MS && (!faster || f.gap > faster.gap)) faster = f;
  };
  for (const st of r.stretches ?? []) {
    const t = toneOf(st, gapToBest(st));
    if (t) tone[st.id] = t;
    if (st.fastestNickname && st.fastestPlayerId !== meId)
      consider({
        id: st.id,
        gap: st.ms - st.fastestMs,
        who: st.fastestNickname,
        playerId: st.fastestPlayerId,
        ms: st.fastestMs,
        setup: st.fastestSetup,
        ability: st.ability,
      });
    if (st.other && st.other.playerId !== meId)
      consider({
        id: st.id,
        gap: st.ms - st.other.ms,
        who: st.other.nickname,
        playerId: st.other.playerId,
        ms: st.other.ms,
        setup: st.other.setup,
        route: st.other.id, // their way through this fork
      });
  }
  return { tone, faster };
}

/**
 * "See why": each stretch of the run with its star, my time and the gap to my best there; the
 * coach tip's stretch highlighted, the one tapped on the map lit up; a note where the session's
 * fastest gains most on me; a failed run's last stretch at the end.
 */
function Stretches({ r, see, sel, onPeek }) {
  const run = r.run;
  const names = COPY.stretches[run.track];
  const faster = see.faster;
  const list = useRef(null);
  useEffect(() => {
    if (sel)
      list.current
        ?.querySelector(`[data-st="${sel}"]`)
        ?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }, [sel]);
  return html`
    <section class="card">
      <h2>${COPY.result.stretchesTitle}</h2>
      <ol class="stretches" ref=${list}>
        ${r.stretches.map((st) => {
          const d = gapToBest(st);
          const t = toneOf(st, d);
          return html`<li key=${st.id} data-st=${st.id}
            class=${`${r.coach?.stretch === st.id ? "tip" : ""} ${sel === st.id ? "sel" : ""}`}>
            <span class="ic">${st.ability ? COPY.abilities[st.ability][0] : COPY.result.safeRoute}</span>
            <span class="nm">${names[st.id]}</span>
            <span class="t">${secs(st.ms)}</span>
            <span class=${`d ${t}`}>${d === null ? "–" : delta(d)}</span>
            ${
              faster?.id === st.id
                ? html`<button class="note link" onClick=${onPeek}>
                    ${
                      faster.route
                        ? COPY.setup.fasterRoute(
                            faster.who,
                            names[faster.route],
                            (faster.gap / 1000).toFixed(1),
                          )
                        : COPY.result.fasterHere(faster.who, (faster.gap / 1000).toFixed(1))
                    } ›
                  </button>`
                : null
            }
          </li>`;
        })}
        ${
          run.failStretch
            ? html`<li data-st=${run.failStretch}
                class=${`ended ${r.coach?.stretch === run.failStretch ? "tip" : ""} ${sel === run.failStretch ? "sel" : ""}`}>
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
