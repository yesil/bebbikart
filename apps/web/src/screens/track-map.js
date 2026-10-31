// The track map (contracts §2e): one SVG for the garage and the result screen. Drawn from the
// shared TRACK_MAPS (generated from the sim); a track without a map is an error, never a guess.
import { TRACK_STRETCHES, trackMap } from "@bebbikart/shared";
import { html } from "htm/preact";
import { COPY } from "../copy.js";

const PAD = 22; // metres around the track (room for the icons and badges)
const MIN_ASPECT = 0.38; // a long thin track is stretched across to at least this height/width

/** On the racer's route: not a fork piece, or the fork choice it takes. */
const onRoute = (seg, routes) => !seg.fork || routes?.[seg.fork] === seg.choice;

/**
 * Map coordinates → SVG: north up, a track longer than it is wide turned sideways, a very thin
 * one stretched across so its forks stay apart (a schematic, not a survey).
 */
function projection(map) {
  const [x0, y0, x1, y1] = map.bounds;
  const turn = y1 - y0 > (x1 - x0) * 1.3;
  const w = (turn ? y1 - y0 : x1 - x0) + PAD * 2;
  const h0 = (turn ? x1 - x0 : y1 - y0) + PAD * 2;
  const k = h0 / w < MIN_ASPECT ? (MIN_ASPECT * w) / h0 : 1;
  const h = h0 * k;
  const at = ([x, y]) =>
    turn ? [y1 - y + PAD, (x - x0 + PAD) * k] : [x - x0 + PAD, (y - y0 + PAD) * k];
  return { w, h, at };
}

/** Middle point of a stretch's polylines (the route's pieces when it has some). */
function middle(segs, at) {
  const pts = segs.flatMap((s) => s.pts);
  return at(pts[Math.floor(pts.length / 2)]);
}

/**
 * Props:
 *   track, routes            whose route is drawn on top (fork pieces off it thin)
 *   tone      {stretchId: "good" | "bad"}   result: against your best (absent: neutral)
 *   pulse     stretchId      the coach tip's stretch
 *   flag      {stretch, text}  where the session's fastest gains most
 *   crash     stretchId      where a failed run ended
 *   icons     bool           each stretch's ability icon (garage)
 *   weather   WeatherState   garage: badge the stretches the active or coming weather hits
 *   selected, onPick         tapping a stretch
 */
export function TrackMap(p) {
  let map;
  try {
    map = trackMap(p.track);
  } catch (err) {
    return html`<div class="error-box">${COPY.map.missing(p.track)}<code>${err.message}</code></div>`;
  }
  const { w, h, at } = projection(map);
  const line = (pts) => pts.map((q) => at(q).join(",")).join(" ");
  const stretches = TRACK_STRETCHES[p.track];
  const segsOf = (id) => map.segments.filter((s) => s.stretch === id);
  const routeSegs = (id) => {
    const on = segsOf(id).filter((s) => onRoute(s, p.routes));
    return on.length ? on : segsOf(id);
  };
  const wx = p.weather;
  const rainy = wx && wx.rain.phase !== "calm";
  const windy = wx && wx.wind.phase !== "calm";
  const scale = Math.max(w, h) / 320; // SVG units per CSS pixel at 320 px wide
  const icon = 15 * scale;
  return html`
    <svg class="track-map" viewBox=${`0 0 ${w.toFixed(1)} ${h.toFixed(1)}`} role="img"
      aria-label=${COPY.map.label}>
      <g class="base">
        ${map.segments.map((s) => html`<polyline key=${`b${s.id}`} points=${line(s.pts)} />`)}
      </g>
      <polyline class="start" points=${line(map.start)} />
      ${map.segments.map((s) => {
        const on = onRoute(s, p.routes);
        const cls = [
          "seg",
          on ? "on" : "off",
          p.tone?.[s.stretch] ?? "",
          p.pulse === s.stretch && on ? "pulse" : "",
          p.selected === s.stretch ? "sel" : "",
        ].join(" ");
        return html`<polyline key=${s.id} class=${cls} points=${line(s.pts)}
          onClick=${p.onPick ? () => p.onPick(s.stretch) : undefined} />`;
      })}
      ${
        p.icons
          ? stretches.map((st) => {
              const [x, y] = middle(routeSegs(st.id), at);
              const off = !segsOf(st.id).some((s) => onRoute(s, p.routes));
              const badge =
                (rainy && segsOf(st.id).some((s) => s.rain) ? COPY.map.rain : "") +
                (windy && segsOf(st.id).some((s) => s.wind) ? COPY.map.wind : "");
              return html`<g key=${`i${st.id}`} class=${`icon ${off ? "off" : ""}`}
                onClick=${p.onPick ? () => p.onPick(st.id) : undefined}>
                <circle cx=${x} cy=${y} r=${icon * 0.75} />
                <text x=${x} y=${y} font-size=${icon}>${st.ability ? COPY.abilities[st.ability][0] : COPY.result.safeRoute}</text>
                ${badge ? html`<text class="badge" x=${x + icon * 0.9} y=${y - icon * 0.7} font-size=${icon}>${badge}</text>` : null}
              </g>`;
            })
          : null
      }
      ${
        p.flag
          ? (
              () => {
                const [x, y] = middle(routeSegs(p.flag.stretch), at);
                return html`<g class="flag">
                <text x=${x} y=${y - icon * 0.4} font-size=${icon}>🚩</text>
                <text class="who" x=${x + icon * 0.6} y=${y - icon * 0.9} font-size=${icon * 0.8}>${p.flag.text}</text>
              </g>`;
              }
            )()
          : null
      }
      ${
        p.crash
          ? (
              () => {
                const [x, y] = middle(routeSegs(p.crash), at);
                return html`<text class="crash" x=${x} y=${y} font-size=${icon * 1.3}>💥</text>`;
              }
            )()
          : null
      }
    </svg>
  `;
}
