import { LOOP_TRACKS } from "@bebbikart/shared";
import { html } from "htm/preact";
import { useEffect, useState } from "preact/hooks";
import { COPY } from "../copy.js";

/** The racer's face for the app: avatar render, else hero, else the driver drawing. */
export function avatarUrl(me, mood = "happy") {
  const r = me?.asset?.renders ?? {};
  return r[`avatar_${mood}`] ?? r.avatar_happy ?? r.hero ?? me?.asset?.drawings?.character ?? "";
}

export function Avatar({ me, mood, size = 96 }) {
  const url = avatarUrl(me, mood);
  return url
    ? html`<img class="avatar" src=${url} width=${size} height=${size} alt="" />`
    : html`<div class="avatar placeholder" style=${{ width: size, height: size }}>🏎️</div>`;
}

export const secs = (ms) => (ms === undefined || ms === null ? "–" : `${(ms / 1000).toFixed(2)} s`);
export const delta = (ms) =>
  `${ms > 0 ? "+" : ms < 0 ? "−" : "±"}${(Math.abs(ms) / 1000).toFixed(1)}`;

/** Loop tracks (village) are raced in laps and rank by best lap. */
export const isLoop = (track) => LOOP_TRACKS.includes(track);

/** Seconds until an open start countdown (grid.updated) goes green, or 0 when there is none to
 *  join: none open, already green, or I'm on that grid. Re-renders while it counts. */
export function useGridCall(s) {
  const [, tick] = useState(0);
  const now = Date.now(); // not a stored clock: a call that just arrived counts from now
  const g = s.grid;
  const open = !!g && g.goAt > now && !g.racers.some((r) => r.playerId === s.me?.id);
  useEffect(() => {
    if (!open) return;
    const t = setInterval(() => tick((n) => n + 1), 200);
    return () => clearInterval(t);
  }, [open, g]);
  return open ? Math.ceil((g.goAt - now) / 1000) : 0;
}

/** "Mia and Noah are on the grid! Join the race: 2" above the Go button. */
export function GridCall({ s, left }) {
  if (!left) return null;
  return html`<div class="grid-call">🚦 ${COPY.grid.call(
    s.grid.racers.map((r) => r.nickname),
    left,
  )}</div>`;
}

/** Who else is here: friends' racers being made, ready, or out racing (paddock.updated). */
export function Paddock({ s }) {
  const others = (s.paddock ?? []).filter((e) => e.playerId !== s.me?.id);
  if (!others.length) return null;
  const badge = (e) =>
    e.racing ? "🏁" : e.status === "processing" ? "🎨" : e.status === "ready" ? "✓" : "📷";
  const note = (e) =>
    e.racing
      ? COPY.paddock.racing
      : e.status === "processing"
        ? COPY.paddock.making
        : e.status === "ready"
          ? COPY.paddock.ready
          : COPY.paddock.photos;
  return html`
    <section class="paddock">
      <div class="muted small">${COPY.paddock.title}</div>
      <div class="paddock-row">
        ${others.map(
          (e) => html`<div key=${e.playerId} class=${`pad ${e.connected ? "" : "away"}`}>
            <span class="pad-face">
              ${e.avatarUrl ? html`<img src=${e.avatarUrl} alt="" />` : html`<span>🏎️</span>`}
              <i>${badge(e)}</i>
            </span>
            <b>${e.nickname}</b>
            <small>${note(e)}</small>
          </div>`,
        )}
      </div>
    </section>
  `;
}
