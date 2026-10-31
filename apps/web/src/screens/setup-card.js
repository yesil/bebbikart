// A faster racer's setup (contracts §2f): what their time was set with, next to mine, so a kid
// sees the difference and decides what to change. No "copy" button on purpose.
import { ABILITIES, FORK_IDS } from "@bebbikart/shared";
import { html } from "htm/preact";
import { COPY } from "../copy.js";
import { secs } from "./common.js";

/**
 * Props:
 *   who        { nickname, avatarUrl?, timeMs?, timeLabel }   whose setup
 *   setup      Setup { stars, routes, style, weather }
 *   mine       my build { stars, routes, style }
 *   maxStars   config.starsMaxPerAbility
 *   ability    an ability to highlight ("Mia has 8 grip, you have 4")
 *   fork       a fork to highlight ("Mia took the ford, you took the bridge")
 *   onClose
 */
export function SetupCard({ who, setup, mine, maxStars, ability, fork, onClose }) {
  const t = COPY.setup;
  const weather = setup.weather.length
    ? setup.weather.map((w) => t.setIn[w]).join(" · ")
    : t.setIn.calm;
  const [aIcon, aName] = ability ? COPY.abilities[ability] : [];
  return html`
    <div class="sheet-back" onClick=${onClose}>
      <section class="card sheet" role="dialog" aria-label=${t.title(who.nickname)}
        onClick=${(e) => e.stopPropagation()}>
        <div class="sheet-head">
          ${who.avatarUrl ? html`<img src=${who.avatarUrl} alt="" />` : html`<span class="ph">🏎️</span>`}
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
          fork
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
            const same = setup.routes[f] === mine.routes[f];
            return html`<span key=${f} class=${`chip ${same ? "" : "diff"} ${fork === f ? "hl" : ""}`}>
              ${COPY.forks[f][setup.routes[f]][0]}
            </span>`;
          })}
          <span class=${`chip ${setup.style === mine.style ? "" : "diff"}`}>${COPY.styles[setup.style]}</span>
        </div>
        <p class="hint center">${t.decide}</p>
      </section>
    </div>
  `;
}
