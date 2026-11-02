import { LOOP_TRACKS } from "@bebbikart/shared";
import { html } from "htm/preact";
import { useState } from "preact/hooks";
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

/**
 * A racer's picture (LeaderboardEntry.avatarUrl, the avatar the big screen rendered) and why it
 * is missing: [problem, onError]. problem is "" while the picture is fine, else the line to show.
 * No fallbacks: no picture, or one that doesn't load, is said out loud, never swapped for another.
 */
export function usePicture(url) {
  const [bad, setBad] = useState("");
  const problem = !url ? COPY.board.noPicture : bad === url ? COPY.board.pictureFailed : "";
  const onError = () => {
    console.error(`racer picture didn't load: ${url}`);
    setBad(url);
  };
  return [problem, onError];
}

/** The round picture of a racer, or a red "!" saying why there is none (see usePicture). */
export function RacerPic({ url, problem, onError, size }) {
  const style = { width: `${size}px`, height: `${size}px` };
  return problem
    ? html`<span class="racer-pic missing" style=${style} role="img" aria-label=${problem} title=${problem}>!</span>`
    : html`<img class="racer-pic" style=${style} src=${url} alt="" onError=${onError} />`;
}

export const secs = (ms) => (ms === undefined || ms === null ? "–" : `${(ms / 1000).toFixed(2)} s`);
export const delta = (ms) =>
  `${ms > 0 ? "+" : ms < 0 ? "−" : "±"}${(Math.abs(ms) / 1000).toFixed(1)}`;

/** Loop tracks (village) are raced in laps and rank by best lap. */
export const isLoop = (track) => LOOP_TRACKS.includes(track);

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
