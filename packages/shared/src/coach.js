// Coach tips (contracts.md §8). WS3 owns the gameplay knowledge and tunes the rules. All
// kid-facing copy is in COACH_COPY / STRETCH_NAMES / ROUTE_NAMES so it is reviewed in one place.
import { LANGUAGES, ROUTE_STARS, TRACK_STRETCHES } from "./enums.js";
import { trackMap } from "./track-maps.js";

/**
 * Where each stretch is, per language and track, with its preposition ("on the muddy farm
 * track", "auf dem matschigen Feldweg"): it fills {where}. Every TRACK_STRETCHES id has one.
 */
export const STRETCH_NAMES = {
  en: {
    countryside: {
      bumpy_road: "on the bumpy hill road",
      kicker: "at the big ramp",
      knoll_road: "round the knoll",
      hilltop: "on the hilltop straight",
      ford: "in the pond ford",
      stone_bridge: "on the stone bridge",
      causeway: "on the windy causeway",
      hedge_lane: "on the hedge path",
      rainbow_bends: "in the rainbow bends",
    },
    village: {
      main_street: "on the main street",
      kicker: "at the ski jump",
      churchyard: "round the churchyard",
      church_hill: "down the church hill",
      ford: "in the duck pond ford",
      covered_bridge: "on the covered bridge",
      farm: "on the muddy farm track",
      cobbles: "on the bumpy cobbles",
      ridge: "on the windy ridge",
      alpbach: "in the mountain stream",
      causeway: "on the windy causeway",
      arcades: "in the arcades",
      square: "on the village square",
    },
  },
  de: {
    countryside: {
      bumpy_road: "auf der Holperstrasse",
      kicker: "bei der grossen Schanze",
      knoll_road: "um den Hügel herum",
      hilltop: "auf der Hügelkuppe",
      ford: "in der Teichfurt",
      stone_bridge: "auf der Steinbrücke",
      causeway: "auf dem windigen Damm",
      hedge_lane: "auf dem Heckenweg",
      rainbow_bends: "in den Regenbogenkurven",
    },
    village: {
      main_street: "auf der Hauptstrasse",
      kicker: "bei der Sprungschanze",
      churchyard: "um die Kirche herum",
      church_hill: "den Kirchhügel hinunter",
      ford: "in der Teichfurt",
      covered_bridge: "auf der gedeckten Brücke",
      farm: "auf dem matschigen Feldweg",
      cobbles: "auf dem holprigen Pflaster",
      ridge: "auf dem windigen Grat",
      alpbach: "im Alpbach",
      causeway: "auf dem windigen Damm",
      arcades: "unter den Lauben",
      square: "auf dem Dorfplatz",
    },
  },
};

/** A fork piece as the other route to try ("Try the ford next time!"): fills {alt}. */
export const ROUTE_NAMES = {
  en: {
    countryside: {
      kicker: "the big ramp",
      knoll_road: "the knoll road",
      ford: "the ford",
      stone_bridge: "the stone bridge",
      causeway: "the windy causeway",
      hedge_lane: "the hedge path",
    },
    village: {
      kicker: "the ski jump",
      churchyard: "the churchyard lane",
      ford: "the ford",
      covered_bridge: "the bridge",
      causeway: "the windy causeway",
      arcades: "the arcades",
    },
  },
  de: {
    countryside: {
      kicker: "die grosse Schanze",
      knoll_road: "den Weg um den Hügel",
      ford: "die Furt",
      stone_bridge: "die Steinbrücke",
      causeway: "den windigen Damm",
      hedge_lane: "den Heckenweg",
    },
    village: {
      kicker: "die Sprungschanze",
      churchyard: "den Kirchweg",
      ford: "die Furt",
      covered_bridge: "die Brücke",
      causeway: "den windigen Damm",
      arcades: "die Lauben",
    },
  },
};

/** Star names inside tips ({ability}). */
export const ABILITY_NAMES = {
  en: {
    speed: "speed",
    jump: "jump",
    grip: "grip",
    water: "water",
    stability: "stability",
    bounce: "bounce",
  },
  de: {
    speed: "Tempo",
    jump: "Sprung",
    grip: "Grip",
    water: "Wasser",
    stability: "Stabilität",
    bounce: "Federung",
  },
};

/** The side to steer to at a fork ({side}), as the big screen shows it. */
export const SIDE_NAMES = {
  en: { left: "left", right: "right" },
  de: { left: "links", right: "rechts" },
};

/** The star each fixed tip suggests (the phone highlights that row); loss_stretch: the stretch's. */
export const COACH_ABILITY = {
  fail_slip: "grip",
  fail_wind_push: "stability",
  fail_water_slow: "water",
  fail_bad_landing: "bounce",
  fail_bounce_wobble: "bounce",
  fail_bumped: "stability",
  fail_off_track: "stability", // every road has rails: only the wind tips a kart over the causeway's low wall
  fail_flipped: "stability",
  fail_stuck: "speed",
  fail_timeout: "speed",
  loss_bumped: "stability",
};

/**
 * Text templates per language (config.language). {where} = a STRETCH_NAMES entry, {s} = seconds
 * lost, {ability} = an ABILITY_NAMES entry, {alt} = a ROUTE_NAMES entry, {n} = the stars of
 * {ability} that take the other way at a fork (ROUTE_STARS, contracts §2h), {side} = a
 * SIDE_NAMES entry: where to steer for {alt} (§2g). Each fits 70 chars with the longest names
 * (coach.test.js). Both languages have exactly the same keys.
 */
export const COACH_COPY = {
  en: {
    // Rule 1: failed runs, by reason and the dominant event on the stretch where it ended.
    fail_slip: "Slipped {where}! Try +2 grip.",
    fail_wind_push: "Blown off {where}! Try +2 stability.",
    fail_water_slow: "Stuck {where}! Try +2 water.",
    fail_bad_landing: "Crash landing {where}! Try +2 bounce.",
    fail_bounce_wobble: "Too wobbly {where}! Try -2 bounce.",
    fail_bumped: "Bumped off {where}! Try +2 stability.",
    fail_off_track: "Blown over the wall {where}! Try +2 stability.",
    fail_flipped: "Flipped over {where}! Try +2 stability.",
    fail_stuck: "Got stuck {where}! Try other stars.",
    fail_timeout: "Out of time {where}! Try +2 speed.",
    // Rule 2: the stretch that cost most against your best (first run: the session's fastest).
    loss_stretch: "Lost {s} s {where}. Try +2 {ability}!",
    loss_route: "Lost {s} s {where}. Steer {side} for {alt}!",
    loss_slick: "Lost {s} s on the wet, slippery bridge. Steer {side} for {alt}!",
    loss_scrape: "Lost {s} s scraping the wall {where}. Steer away!",
    loss_bumped: "Lost {s} s to bumps {where}. Wait for a quiet track!",
    loss_missed_exit: "Lost {s} s going round the roundabout again!",
    close: "So close to your best! Go again?",
    // Rule 3: first finish or new best, plus one experiment.
    best_try_arrows: "New best! Steer over the glowing arrows for a boost!",
    best_try_route: "New best! Try {n} {ability} stars: they take {alt}!",
    best_keep: "New best! Can you beat it again?",
    // The run was stopped (session ended, game gone, admin).
    aborted: "That race was stopped. Press Go! to try again.",
  },
  de: {
    fail_slip: "Ausgerutscht {where}! Probier +2 Grip.",
    fail_wind_push: "Weggeweht {where}! Probier +2 Stabilität.",
    fail_water_slow: "Stecken geblieben {where}! Probier +2 Wasser.",
    fail_bad_landing: "Bruchlandung {where}! Probier +2 Federung.",
    fail_bounce_wobble: "Zu wackelig {where}! Probier -2 Federung.",
    fail_bumped: "Weggerempelt {where}! Warte auf freie Bahn.",
    fail_off_track: "Über die Mauer {where}! Probier +2 Stabilität.",
    fail_flipped: "Überschlagen {where}! Probier +2 Stabilität.",
    fail_stuck: "Stecken geblieben {where}! Probier andere Sterne.",
    fail_timeout: "Zeit abgelaufen {where}! Probier +2 Tempo.",
    loss_stretch: "{s} s verloren {where}. Probier +2 {ability}!",
    loss_route: "{s} s verloren {where}. Lenk {side}: {alt}!",
    loss_slick: "{s} s auf der nassen Brücke verloren. Lenk {side}: {alt}!",
    loss_scrape: "{s} s an der Mauer geschrammt {where}. Lenk weg!",
    loss_bumped: "{s} s durch Rempler {where}. Warte auf freie Bahn!",
    loss_missed_exit: "{s} s verloren, nochmal um den Kreisel!",
    close: "Ganz knapp an deiner Bestzeit! Nochmal?",
    best_try_arrows: "Neue Bestzeit! Fahr über die Leuchtpfeile für einen Boost!",
    best_try_route: "Neue Bestzeit! {n} Sterne {ability} und du nimmst {alt}!",
    best_keep: "Neue Bestzeit! Schaffst du es noch schneller?",
    aborted: "Das Rennen wurde gestoppt. Drück Los! und versuch es nochmal.",
  },
};

/** Smaller gaps on a stretch than this are noise, not a tip. */
export const MIN_STRETCH_LOSS_MS = 300;

const FAIL_EVENT_KEYS = [
  "slip",
  "wind_push",
  "water_slow",
  "bad_landing",
  "bounce_wobble",
  "bumped",
];
// Loss events whose fix isn't the stretch's star: they get their own tip.
const OWN_TIP_EVENTS = ["bumped", "missed_exit", "scrape"];
const LOSS_EVENT_KEYS = [
  "slip",
  "water_slow",
  "wind_push",
  "bad_landing",
  "slow_corner",
  "bounce_wobble",
  ...OWN_TIP_EVENTS,
];

/**
 * @param {object} run    the run that just ended (track, outcome, failReason, failStretch, events, stretches)
 * @param {object} build  the build used for the run
 * @param {object} [best] the racer's best finished run before this one
 * @param {string} language config.language: the tip's text is in this language
 * @param {object[]} stretches run.ended's StretchResult[] (contracts §2d): this run's stretches
 *   with the player's best and the session's fastest on each
 * @returns {{ key: string, text: string, stretch?: string, ability?: string, route?: { fork: string, choice: string } }}
 */
export function coachTip(run, build, best, language, stretches) {
  copyFor(language);
  const track = trackStretches(run.track);
  const events = run.events ?? [];

  if (run.outcome !== "finished") {
    const stretch = run.failStretch;
    if (!track.some((t) => t.id === stretch))
      throw new Error(`coach: failed run ${run.id} has no ${run.track} failStretch ("${stretch}")`);
    const ev = dominantEvent(
      events.filter((e) => e.stretch === stretch),
      FAIL_EVENT_KEYS,
    );
    const key = run.failReason === "timeout" || !ev ? `fail_${run.failReason}` : `fail_${ev}`;
    return tip(language, run.track, key, { stretch });
  }

  if (!Array.isArray(stretches))
    throw new Error(`coach: finished run ${run.id} without its stretches`);
  const newBest = best?.elapsedMs === undefined || run.elapsedMs < best.elapsedMs;
  // Slower than your best: against your best on each stretch. First run: against the session's
  // fastest racer on each (if that's someone else). Another new best: a cheer.
  let ref;
  if (!newBest) ref = (st) => st.bestMs;
  else if (best?.elapsedMs === undefined)
    ref = (st) =>
      st.fastestPlayerId && st.fastestPlayerId !== run.playerId ? st.fastestMs : undefined;
  if (ref) {
    let worst;
    let worstLoss = 0;
    for (const st of stretches) {
      const r = ref(st);
      if (r !== undefined && st.ms - r > worstLoss) {
        worst = st;
        worstLoss = st.ms - r;
      }
    }
    if (worst && worstLoss >= MIN_STRETCH_LOSS_MS)
      return stretchTip(language, run, track, worst, worstLoss, events);
    if (!newBest) return tip(language, run.track, "close", {});
  }

  // Boost arrows left on the road (contracts §2g): steer over them first.
  if (countEvents(events, "boost_perfect") < arrowsPerLap(run.track) * (run.laps?.length || 1))
    return tip(language, run.track, "best_try_arrows", {});
  // A risky way the stars don't take yet (contracts §2h), in this order.
  const fork = ["pond", "ramp", "crossing"].find((f) => build.routes[f] !== ROUTE_STARS[f].choice);
  if (fork) {
    const rule = ROUTE_STARS[fork];
    const alt = track.find((t) => t.fork === fork && t.choice === rule.choice);
    return tip(
      language,
      run.track,
      "best_try_route",
      { alt: alt.id, ability: rule.ability, n: rule.stars },
      { fork, choice: rule.choice },
    );
  }
  return tip(language, run.track, "best_keep", {});
}

function countEvents(events, kind) {
  return events.filter((e) => e.kind === kind).length;
}

/** Boost arrow strips on one lap of a track (they sit off the forks, so every lap has them all). */
function arrowsPerLap(track) {
  return trackMap(track).segments.reduce((n, s) => n + (s.fork === "" ? s.arrows : 0), 0);
}

/** The side a kid steers to at the junction for a fork's way (the track map's steer, §2e). */
function steerSide(track, fork, choice) {
  const seg = trackMap(track).segments.find((s) => s.fork === fork && s.choice === choice);
  if (!seg || (seg.steer !== -1 && seg.steer !== 1))
    throw new Error(`coach: the ${track} map has no steering side for ${fork} "${choice}"`);
  return seg.steer < 0 ? "left" : "right";
}

/** The tip for the stretch that cost most: its own event's tip, else its star, else the other route. */
function stretchTip(language, run, track, st, lossMs, events) {
  const ev = dominantEvent(
    events.filter((e) => e.stretch === st.id),
    LOSS_EVENT_KEYS,
  );
  if (OWN_TIP_EVENTS.includes(ev))
    return tip(language, run.track, `loss_${ev}`, { stretch: st.id, lossMs });
  const meta = track.find((t) => t.id === st.id);
  if (!meta) throw new Error(`coach: "${st.id}" is not a ${run.track} stretch`);
  if (meta.ability)
    return tip(language, run.track, "loss_stretch", {
      stretch: st.id,
      lossMs,
      ability: meta.ability,
    });
  const alt = track.find((t) => t.fork === meta.fork && t.choice !== meta.choice);
  if (!alt) throw new Error(`coach: stretch "${st.id}" has no ability and no other route`);
  const key = meta.slick && (run.weatherSeen ?? []).includes("rain") ? "loss_slick" : "loss_route";
  // The kid steers onto the other way at the fork (§2g): name the side.
  return tip(
    language,
    run.track,
    key,
    { stretch: st.id, lossMs, alt: alt.id, side: steerSide(run.track, alt.fork, alt.choice) },
    { fork: alt.fork, choice: alt.choice },
  );
}

function trackStretches(track) {
  const list = TRACK_STRETCHES[track];
  if (!list) throw new Error(`coach: unknown track "${track}"`);
  return list;
}

/** Event kind with the most time lost (or most occurrences when no time is given). */
function dominantEvent(events, kinds) {
  const score = new Map();
  for (const e of events) {
    if (!kinds.includes(e.kind)) continue;
    score.set(e.kind, (score.get(e.kind) ?? 0) + (e.timeLostMs ?? 1));
  }
  let best;
  for (const [kind, s] of score) if (!best || s > score.get(best)) best = kind;
  return best;
}

/** The tip sent when a run is aborted, in the session's language. */
export function abortTip(language) {
  return { key: "aborted", text: copyFor(language).aborted };
}

/** No fallback language: an unknown language or a missing key is a bug, so it throws. */
function copyFor(language) {
  if (!LANGUAGES.includes(language)) throw new Error(`coach: unknown language "${language}"`);
  return COACH_COPY[language];
}

function tip(language, track, key, { stretch, lossMs, ability, alt, n, side }, route) {
  const template = copyFor(language)[key];
  if (template === undefined) throw new Error(`coach: no "${language}" text for tip "${key}"`);
  const fill = (table, id, what) => {
    const v = table[language][track]?.[id];
    if (v === undefined) throw new Error(`coach: no "${language}" ${what} for ${track} "${id}"`);
    return v;
  };
  let text = template.replace("{s}", ((lossMs ?? 0) / 1000).toFixed(1)).replace("{n}", String(n));
  if (text.includes("{where}"))
    text = text.replace("{where}", fill(STRETCH_NAMES, stretch, "name"));
  if (text.includes("{alt}")) text = text.replace("{alt}", fill(ROUTE_NAMES, alt, "route name"));
  if (text.includes("{side}")) {
    if (!SIDE_NAMES[language][side]) throw new Error(`coach: no "${language}" side "${side}"`);
    text = text.replace("{side}", SIDE_NAMES[language][side]);
  }
  const star = ability ?? COACH_ABILITY[key];
  if (text.includes("{ability}")) text = text.replace("{ability}", ABILITY_NAMES[language][star]);
  const out = { key, text };
  if (stretch) out.stretch = stretch;
  if (star) out.ability = star;
  if (route) out.route = route;
  return out;
}
