// A faster racer's setup (contracts §2f): what their time was set with, next to mine, so a kid
// sees the difference and decides what to change. No "copy" button on purpose.
import { ABILITIES, FORK_IDS } from "@bebbikart/shared";
import { html } from "htm/preact";
import { COPY } from "../copy.js";
import { RacerPic, secs, usePicture } from "./common.js";

/**
 * Props:
 *   who        { nickname, avatarUrl?, timeMs?, timeLabel }   whose setup (no avatarUrl: the card
 *              says the picture is missing)
 *   setup      Setup { stars, routes, weather } (routes: the ways that lap took, steered or the
 *              stars', §2g)
 *   mine       { stars, routes }: my build, or after a run its stars and the ways it took (a
 *              failed run: only the forks it reached)
 *   maxStars   config.starsMaxPerAbility
 *   ability    an ability to highlight ("Mia has 8 grip, you have 4")
 *   fork       a fork to highlight ("Mia took the ford, you took the bridge")
 *   onClose
 */
export function SetupCard({ who, setup, mine, maxStars, ability, fork, onClose }) {
  const t = COPY.setup;
  const [problem, onError] = usePicture(who.avatarUrl);
  const weather = setup.weather.length
    ? setup.weather.map((w) => t.setIn[w]).join(" · ")
    : t.setIn.calm;
  const [aIcon, aName] = ability ? COPY.abilities[ability] : [];
  return html`
    <div class="sheet-back" onClick=${onClose}>
      <section class="card sheet" role="dialog" aria-label=${t.title(who.nickname)}
        onClick=${(e) => e.stopPropagation()}>
        <div class="sheet-head">
          <${RacerPic} url=${who.avatarUrl} problem=${problem} onError=${onError} size=${64} />
          <div class="grow">
            <h2>${who.nickname}</h2>
            ${who.timeMs !== undefined ? html`<div class="muted">${who.timeLabel} <b>${secs(who.timeMs)}</b></div>` : null}
            <div class="badge-weather">${weather}</div>
          </div>
          <button class="ghost close" onClick=${onClose} aria-label=${t.close}>✕</button>
        </div>
        ${
          ability
            ? html`<p class="why">${aIcon} ${t.hasAbility(who.nickname, setup.stars[ability], mine.stars[ability], aName)}</p>`
            : null
        }
        ${
          fork && mine.routes[fork]
            ? html`<p class="why">${t.tookRoute(who.nickname, COPY.forks[fork][setup.routes[fork]][0], COPY.forks[fork][mine.routes[fork]][0])}</p>`
            : null
        }
        <div class="setup-stars">
          <div class="legend"><span></span><span>${who.nickname}</span><span>${t.you}</span></div>
          ${ABILITIES.map((a) => {
            const theirs = setup.stars[a];
            const mineN = mine.stars[a];
            return html`<div key=${a} class=${`srow ${ability === a ? "hl" : ""}`}>
              <span class="icon" title=${COPY.abilities[a][1]}>${COPY.abilities[a][0]}</span>
              <span class="stars">${Array.from(
                { length: maxStars },
                (_, i) => html`<i class=${i < theirs ? "on" : ""}>★</i>`,
              )}</span>
              <span class=${`mine ${theirs > mineN ? "more" : theirs < mineN ? "less" : ""}`}>${mineN}</span>
            </div>`;
          })}
        </div>
        <div class="chips">
          ${FORK_IDS.map((f) => {
            // A fork my run didn't reach isn't a difference.
            const same = !mine.routes[f] || setup.routes[f] === mine.routes[f];
            return html`<span key=${f} class=${`chip ${same ? "" : "diff"} ${fork === f ? "hl" : ""}`}>
              ${COPY.forks[f][setup.routes[f]][0]}
            </span>`;
          })}
        </div>
        <p class="hint center">${t.decide}</p>
      </section>
    </div>
  `;
}
