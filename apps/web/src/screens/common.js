import { LOOP_TRACKS } from "@bebbikart/shared";
import { html } from "htm/preact";

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
