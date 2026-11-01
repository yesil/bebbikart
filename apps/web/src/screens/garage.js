import { ABILITIES, ROUTE_STARS, routesFor, starsLeft, TRACK_STRETCHES } from "@bebbikart/shared";
import { html } from "htm/preact";
import { useRef, useState } from "preact/hooks";
import { api } from "../api.js";
import { COPY, errorText } from "../copy.js";
import { Avatar, isLoop, Paddock, secs } from "./common.js";
import { SetupCard } from "./setup-card.js";
import { TrackMap } from "./track-map.js";

// The phone saves stars only; the server derives the routes from them (contracts §2h).
const pick = (b) => ({ stars: { ...b.stars } });
const same = (a, b) => JSON.stringify(pick(a)) === JSON.stringify(pick(b));

export function Garage({ ctx }) {
  const { s, dispatch } = ctx;
  const me = s.me;
  const cfg = s.config;
  const [build, setBuild] = useState(() => pick(me.build));
  const [saving, setSaving] = useState(false);
  const saveTimer = useRef(null);
  const left = starsLeft(build.stars, cfg);
  const dirty = !same(build, me.build);
  // Highlight the row the coach suggested after the last run.
  const hint = s.lastCoach?.ability;

  async function save(b) {
    if (starsLeft(b.stars, cfg) !== 0 || same(b, me.build)) return;
    setSaving(true);
    try {
      await api("PUT", "/api/players/me/build", b);
    } catch (err) {
      dispatch({ type: "toast", text: errorText(err) });
    }
    setSaving(false);
  }
  function change(next) {
    setBuild(next);
    clearTimeout(saveTimer.current);
    saveTimer.current = setTimeout(() => save(next), 400);
  }
  const setStar = (a, d) => {
    const n = build.stars[a] + d;
    if (n < 0 || n > cfg.starsMaxPerAbility) return;
    if (d > 0 && left <= 0) return;
    change({ ...build, stars: { ...build.stars, [a]: n } });
  };

  const routes = routesFor(build.stars);
  // My place in the line (1 = next), 0 when I'm not in it.
  const place = (s.queue?.line ?? []).findIndex((e) => e.playerId === me.id) + 1;
  const blocked =
    left !== 0
      ? COPY.garage.starsLeft(left)
      : s.session?.status !== "running"
        ? COPY.errors.session_not_running
        : null;

  /** Join the line: the server launches me when a half is free (contracts §2i). */
  async function go() {
    if (blocked) return;
    clearTimeout(saveTimer.current);
    try {
      if (dirty) await api("PUT", "/api/players/me/build", build);
      await api("POST", "/api/players/me/runs");
    } catch (err) {
      dispatch({ type: "toast", text: errorText(err) });
    }
  }
  async function leaveLine() {
    try {
      await api("DELETE", "/api/players/me/queue");
    } catch (err) {
      dispatch({ type: "toast", text: errorText(err) });
    }
  }

  return html`
    <section class="card me">
      <${Avatar} me=${me} size=${88} />
      <div>
        <div class="nick">${me.nickname}</div>
        <div class="muted">${me.asset?.spec.title ?? ""}</div>
        <div class="stats">
          <span>${isLoop(cfg.track) ? COPY.garage.bestLap : COPY.garage.best}: <b>${me.bestTimeMs ? secs(me.bestTimeMs) : COPY.garage.noBest}</b></span>
          ${me.rank ? html`<span>${COPY.garage.rank}: <b>#${me.rank}</b></span>` : null}
        </div>
      </div>
    </section>

    ${
      me.job?.status === "failed"
        ? html`<div class="error-box"><b>${COPY.garage.lookFailed}</b><code>${me.job.error}</code></div>`
        : null
    }

    <${DuelCard} s=${s} place=${place} />
    <${Paddock} s=${s} />

    <${WeatherStrip} weather=${s.weather} />
    <${GarageMap} track=${cfg.track} routes=${routes} weather=${s.weather} />

    <section class="card">
      <div class="row-head">
        <h2>⭐ ${COPY.garage.stars}</h2>
        <span class=${`count ${left === 0 ? "ok" : "warn"}`}>${COPY.garage.starsLeft(left)}</span>
      </div>
      ${ABILITIES.map((a) => {
        const [icon, name, line] = COPY.abilities[a];
        return html`<div key=${a} class=${`stat ${hint === a ? "pulse" : ""}`}>
          <span class="icon">${icon}</span>
          <span class="what"><b>${name}</b><small>${line}</small></span>
          <button class="round" onClick=${() => setStar(a, -1)} disabled=${build.stars[a] === 0}>−</button>
          <span class="stars">${Array.from(
            { length: cfg.starsMaxPerAbility },
            (_, i) => html`<i class=${i < build.stars[a] ? "on" : ""}>★</i>`,
          )}</span>
          <button class="round" onClick=${() => setStar(a, 1)} disabled=${left <= 0 || build.stars[a] >= cfg.starsMaxPerAbility}>+</button>
        </div>`;
      })}
    </section>

    <${Ways} stars=${build.stars} />

    <button class="ghost" onClick=${() => dispatch({ type: "redo", on: true })}>📷 ${COPY.garage.newDrawings}</button>

    ${
      place
        ? html`<div class="go-bar">
            <div class="line-place">${COPY.duel.place(place)}</div>
            <button class="ghost" onClick=${leaveLine}>${COPY.duel.leave}</button>
          </div>`
        : html`<div class="go-bar">
            ${blocked ? html`<div class="muted small center">${blocked}</div>` : null}
            <button class="go" disabled=${!!blocked || saving} onClick=${go}>${COPY.duel.join}</button>
          </div>`
    }
  `;
}

/**
 * Which way the stars take at each fork (contracts §2h): the way they take now, and how many
 * stars of which ability take (or keep) the risky way. Updates live as the stars move.
 */
function Ways({ stars }) {
  const routes = routesFor(stars);
  return html`
    <section class="card ways">
      <h2>${COPY.garage.ways}</h2>
      ${Object.entries(ROUTE_STARS).map(([fork, rule]) => {
        const [icon, name] = COPY.abilities[rule.ability];
        const have = stars[rule.ability];
        const on = routes[fork] === rule.choice;
        return html`<div key=${fork} class=${`way ${on ? "on" : ""}`}>
          <b>${COPY.forks[fork][routes[fork]][0]}</b>
          <small>${icon} ${
            on
              ? COPY.garage.wayOn(have, name, COPY.forks[fork].way)
              : COPY.garage.wayOff(rule.stars - have, name, COPY.forks[fork].way)
          }</small>
        </div>`;
      })}
    </section>
  `;
}

/**
 * Duel mode (contracts §2i): who holds the crown and how many tried, who is on the track, the
 * line in launch order (the champion last), and my place in it.
 */
function DuelCard({ s, place }) {
  const q = s.queue ?? { line: [], racing: [], split: false, skipped: [] };
  const me = s.me;
  const c = q.champion;
  const mine = c?.playerId === me.id;
  const who = (e) => (e.playerId === me.id ? html`<b>${e.nickname}</b>` : e.nickname);
  return html`
    <section class="card duel">
      <h2>${COPY.duel.title}</h2>
      <p class=${`crown ${mine ? "mine" : ""}`}>
        ${c ? (mine ? COPY.duel.mine(secs(c.timeMs)) : COPY.duel.champion(c.nickname, secs(c.timeMs))) : COPY.duel.none}
      </p>
      ${c ? html`<p class="muted small">${COPY.duel.tries(c.tries)}</p>` : null}
      ${
        q.racing.length
          ? html`<div class="duel-row"><span class="muted small">${COPY.duel.onTrack}</span>
              ${q.racing.map((r) => html`<span key=${r.side} class=${`chip side-${r.side}`}>${COPY.duel.sideShort[r.side]}: ${who(r)}</span>`)}
            </div>`
          : null
      }
      <div class="duel-row"><span class="muted small">${COPY.duel.line}</span>
        ${
          q.line.length
            ? html`<ol class="line">${q.line.map((e) => html`<li key=${e.playerId} class=${e.playerId === me.id ? "mine" : ""}>${who(e)}</li>`)}</ol>`
            : html`<span class="small">${COPY.duel.nobody}</span>`
        }
      </div>
      ${mine && place ? html`<p class="hint">${COPY.duel.restHint}</p>` : null}
      ${q.skipped.includes(me.id) ? html`<p class="warn-line">${COPY.duel.skipped}</p>` : null}
    </section>
  `;
}

/**
 * Where each star matters (contracts §2e): the track with each stretch's ability, the route
 * choices as the two branches (the chosen one bold), and a weather badge on the stretches the
 * active or coming rain or wind hits hardest. Collapsible, so small phones keep the stars close.
 */
function GarageMap({ track, routes, weather }) {
  const [picked, setPicked] = useState(null);
  const meta = TRACK_STRETCHES[track]?.find((st) => st.id === picked);
  const stormy = weather && (weather.rain.phase !== "calm" || weather.wind.phase !== "calm");
  return html`
    <details class="card map" open>
      <summary>${COPY.map.title}</summary>
      <${TrackMap} track=${track} routes=${routes} icons=${true} weather=${weather}
        selected=${picked} onPick=${setPicked} />
      <p class="pick">
        ${
          meta
            ? COPY.map.picked(
                COPY.stretches[track][meta.id],
                meta.ability
                  ? `${COPY.abilities[meta.ability][0]} ${COPY.abilities[meta.ability][1]}`
                  : null,
              )
            : COPY.map.garageHint
        }
      </p>
      ${stormy ? html`<p class="hint center">${COPY.map.weatherHint}</p>` : null}
    </details>
  `;
}

export function WeatherStrip({ weather }) {
  if (!weather) return null;
  const parts = [];
  for (const k of ["rain", "wind"]) {
    const ph = weather[k].phase;
    if (ph === "warning") parts.push(COPY.weather[`${k}Warn`]);
    if (ph === "active") parts.push(COPY.weather[k]);
  }
  return html`<div class="weather">${parts.length ? parts.join("  ") : COPY.weather.calm}</div>`;
}

export function Leaderboard({ ctx }) {
  const { s } = ctx;
  const [open, setOpen] = useState(null); // the entry whose setup card is open
  const loop = isLoop(s.config.track);
  return html`
    <section class="card">
      <h2>🏆 ${COPY.tabs.leaderboard.slice(3)}</h2>
      ${s.leaderboard.length === 0 ? html`<p class="muted">${COPY.garage.noBest}</p>` : html`<p class="hint">${COPY.setup.tapHint}</p>`}
      <ol class="board">
        ${s.leaderboard.map(
          (e) => html`<li key=${e.playerId} class=${`tap ${e.playerId === s.me?.id ? "mine" : ""}`}
            role="button" tabindex="0" onClick=${() => setOpen(e)}>
            <span class="rank">${e.rank}</span>
            ${e.avatarUrl ? html`<img src=${e.avatarUrl} alt="" />` : html`<span class="ph">🏎️</span>`}
            <span class="who"><b>${e.nickname}</b><small>${e.racerTitle ?? ""}</small></span>
            <span class="time">${secs(e.bestTimeMs)}</span>
          </li>`,
        )}
      </ol>
    </section>
    ${
      open && s.me
        ? html`<${SetupCard}
            who=${{
              nickname: open.nickname,
              avatarUrl: open.avatarUrl,
              timeMs: open.bestTimeMs,
              timeLabel: loop ? COPY.setup.bestLap : COPY.setup.bestTime,
            }}
            setup=${open.setup} mine=${s.me.build} maxStars=${s.config.starsMaxPerAbility}
            onClose=${() => setOpen(null)} />`
        : null
    }
  `;
}
