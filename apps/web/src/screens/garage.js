import { ABILITIES, FORK_CHOICES, starsLeft } from "@bebbikart/shared";
import { html } from "htm/preact";
import { useEffect, useRef, useState } from "preact/hooks";
import { api } from "../api.js";
import { COPY } from "../copy.js";
import { Avatar, secs } from "./common.js";

const pick = (b) => ({ stars: { ...b.stars }, routes: { ...b.routes }, style: b.style });
const same = (a, b) => JSON.stringify(pick(a)) === JSON.stringify(pick(b));

export function Garage({ ctx }) {
  const { s, dispatch } = ctx;
  const me = s.me;
  const cfg = s.config;
  const [build, setBuild] = useState(() => pick(me.build));
  const [saving, setSaving] = useState(false);
  const [now, setNow] = useState(Date.now());
  const saveTimer = useRef(null);
  const left = starsLeft(build.stars, cfg);
  const dirty = !same(build, me.build);
  // Highlight the row the coach suggested after the last run.
  const hint = s.lastCoach?.ability;

  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 250);
    return () => clearInterval(t);
  }, []);

  async function save(b) {
    if (starsLeft(b.stars, cfg) !== 0 || same(b, me.build)) return;
    setSaving(true);
    try {
      await api("PUT", "/api/players/me/build", b);
    } catch (err) {
      dispatch({ type: "toast", text: err.message });
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

  const cooldownLeft = me.lastRun?.endedAt
    ? Date.parse(me.lastRun.endedAt) + cfg.launchCooldownMs - now
    : 0;
  const blocked =
    left !== 0
      ? COPY.garage.starsLeft(left)
      : s.session?.status !== "running"
        ? COPY.errors.session_not_running
        : cooldownLeft > 0
          ? `${COPY.errors.cooldown} ${Math.ceil(cooldownLeft / 1000)}`
          : null;

  async function go() {
    if (blocked) return;
    clearTimeout(saveTimer.current);
    try {
      if (dirty) await api("PUT", "/api/players/me/build", build);
      await api("POST", "/api/players/me/runs");
    } catch (err) {
      dispatch({ type: "toast", text: COPY.errors[err.code] ?? err.message });
    }
  }

  return html`
    <section class="card me">
      <${Avatar} me=${me} size=${88} />
      <div>
        <div class="nick">${me.nickname}</div>
        <div class="muted">${me.asset?.spec.title ?? ""}</div>
        <div class="stats">
          <span>${COPY.garage.best}: <b>${me.bestTimeMs ? secs(me.bestTimeMs) : COPY.garage.noBest}</b></span>
          ${me.rank ? html`<span>${COPY.garage.rank}: <b>#${me.rank}</b></span>` : null}
        </div>
      </div>
    </section>

    <${WeatherStrip} weather=${s.weather} />

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

    <section class="card">
      <h2>🛣️ ${COPY.garage.routes}</h2>
      ${Object.entries(FORK_CHOICES).map(
        ([fork, choices]) => html`
        <div key=${fork} class="fork">
          <div class="muted small">${COPY.forks[fork].title}</div>
          <div class="choices">
            ${choices.map((c) => {
              const [label, note] = COPY.forks[fork][c];
              return html`<button
                class=${`choice ${build.routes[fork] === c ? "on" : ""}`}
                onClick=${() => change({ ...build, routes: { ...build.routes, [fork]: c } })}
              >
                <b>${label}</b><small>${note}</small>
              </button>`;
            })}
          </div>
        </div>
      `,
      )}
    </section>

    <section class="card">
      <h2>🎛️ ${COPY.garage.style}</h2>
      <div class="choices three">
        ${Object.entries(COPY.styles).map(
          ([
            st,
            label,
          ]) => html`<button class=${`choice ${build.style === st ? "on" : ""}`} onClick=${() => change({ ...build, style: st })}>
            <b>${label}</b>
          </button>`,
        )}
      </div>
    </section>

    <div class="go-bar">
      ${blocked ? html`<div class="muted small center">${blocked}</div>` : null}
      <button class="go" disabled=${!!blocked || saving} onClick=${go}>${COPY.garage.go}</button>
    </div>
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
  return html`
    <section class="card">
      <h2>🏆 ${COPY.tabs.leaderboard.slice(3)}</h2>
      ${s.leaderboard.length === 0 ? html`<p class="muted">${COPY.garage.noBest}</p>` : null}
      <ol class="board">
        ${s.leaderboard.map(
          (e) => html`<li key=${e.playerId} class=${e.playerId === s.me?.id ? "mine" : ""}>
            <span class="rank">${e.rank}</span>
            ${e.avatarUrl ? html`<img src=${e.avatarUrl} alt="" />` : html`<span class="ph">🏎️</span>`}
            <span class="who"><b>${e.nickname}</b><small>${e.racerTitle ?? ""}</small></span>
            <span class="time">${secs(e.bestTimeMs)}</span>
          </li>`,
        )}
      </ol>
    </section>
  `;
}
