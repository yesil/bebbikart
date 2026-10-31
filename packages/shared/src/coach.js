// Coach tips (contracts.md §8). First version of the rules; WS3 owns the gameplay knowledge
// and tunes them. All kid-facing copy is in COACH_COPY so it is reviewed in one place.
import { LANGUAGES, SECTION_IDS } from "./enums.js";

/** Section names per language. German names carry their preposition ("beim Teich"). */
export const SECTION_NAMES = {
  en: {
    hills: "the hills",
    pond: "the pond",
    crossing: "the windy crossing",
    bends: "the rainbow bends",
    track: "the track",
  },
  de: {
    hills: "bei den Hügeln",
    pond: "beim Teich",
    crossing: "an der Windkreuzung",
    bends: "in den Regenbogenkurven",
    track: "auf der Strecke",
  },
};

/** The star each tip suggests (the phone highlights that row). */
export const COACH_ABILITY = {
  fail_slip: "grip",
  fail_wind_push: "stability",
  fail_water_slow: "water",
  fail_bad_landing: "bounce",
  fail_bounce_wobble: "bounce",
  fail_bumped: "stability",
  fail_off_track: "grip",
  fail_flipped: "stability",
  fail_stuck: "speed",
  fail_timeout: "speed",
  loss_slip: "grip",
  loss_water_slow: "water",
  loss_wind_push: "stability",
  loss_bad_landing: "bounce",
  loss_slow_corner: "grip",
  loss_bounce_wobble: "bounce",
  loss_bumped: "stability",
  loss_none: "speed",
};

/**
 * Text templates per language (config.language). {where} = section name, {s} = seconds lost.
 * Keep each ≤ 70 chars. Both languages have exactly the same keys (coach.test.js).
 */
export const COACH_COPY = {
  en: {
    // Rule 1: failed runs, by reason and dominant event.
    fail_slip: "Slipped on {where}! Try +1 grip or Careful style.",
    fail_wind_push: "Blown off at {where}! Try +1 stability.",
    fail_water_slow: "Stuck in the water! Try +1 water, or the bridge.",
    fail_bad_landing: "Crash landing on {where}! Try +1 bounce.",
    fail_bounce_wobble: "Too wobbly on {where}! Try -1 bounce.",
    fail_bumped: "Bumped off! Wait for a quiet track, or +1 stability.",
    fail_off_track: "Off the road at {where}! Try Careful style.",
    fail_flipped: "Flipped over at {where}! Try +1 stability.",
    fail_stuck: "Got stuck at {where}! Try a different route.",
    fail_timeout: "Out of time! Try +1 speed.",
    // Rule 2: finished but slower than best somewhere, by dominant event in that section.
    loss_slip: "Lost {s} s slipping on {where}. Try +1 grip.",
    loss_water_slow: "Lost {s} s at {where}. Try the bridge, or +1 water.",
    loss_wind_push: "Lost {s} s in the wind. Try +1 stability.",
    loss_bad_landing: "Lost {s} s on a bumpy landing. Try +1 bounce.",
    loss_slow_corner: "Lost {s} s in {where}. Try Daring style!",
    loss_bounce_wobble: "Lost {s} s wobbling on {where}. Try -1 bounce.",
    loss_boost_weak: "Lost {s} s at {where}. Boost on the glowing zones!",
    loss_bumped: "Lost {s} s in bumps. Wait for a quieter track!",
    loss_missed_exit: "Lost {s} s going round the roundabout again! Try Careful style.",
    loss_none: "Lost {s} s at {where}. Try +1 speed!",
    // Rule 3: first finish or new best, plus one experiment.
    best_try_water: "New best! Brave enough to try the water shortcut?",
    best_try_jump: "New best! Dare to jump the big ramp next time?",
    best_try_exposed: "New best! Try the fast windy bridge next time?",
    best_try_daring: "New best! Try Daring style for even more speed?",
    best_keep: "New best! Can you beat it again?",
    // The run was stopped (session ended, game gone, admin).
    aborted: "That race was stopped. Press Go! to try again.",
  },
  de: {
    fail_slip: "Ausgerutscht {where}! Probier +1 Grip oder Vorsichtig.",
    fail_wind_push: "Weggeweht {where}! Probier +1 Stabilität.",
    fail_water_slow: "Im Wasser stecken geblieben! Probier +1 Wasser oder die Brücke.",
    fail_bad_landing: "Bruchlandung {where}! Probier +1 Federung.",
    fail_bounce_wobble: "Zu wackelig {where}! Probier -1 Federung.",
    fail_bumped: "Weggerempelt! Warte auf freie Bahn oder +1 Stabilität.",
    fail_off_track: "Von der Strasse geflogen {where}! Probier Vorsichtig.",
    fail_flipped: "Überschlagen {where}! Probier +1 Stabilität.",
    fail_stuck: "Stecken geblieben {where}! Probier eine andere Route.",
    fail_timeout: "Zeit abgelaufen! Probier +1 Tempo.",
    loss_slip: "{s} s verloren, gerutscht {where}. Probier +1 Grip.",
    loss_water_slow: "{s} s verloren {where}. Brücke nehmen oder +1 Wasser.",
    loss_wind_push: "{s} s im Wind verloren. Probier +1 Stabilität.",
    loss_bad_landing: "{s} s bei einer holprigen Landung verloren. Probier +1 Federung.",
    loss_slow_corner: "{s} s verloren {where}. Probier Mutig!",
    loss_bounce_wobble: "{s} s weg, gewackelt {where}. Probier -1 Federung.",
    loss_boost_weak: "{s} s verloren {where}. Boost auf den Leuchtfeldern!",
    loss_bumped: "{s} s durch Rempler verloren. Warte auf freie Bahn!",
    loss_missed_exit: "{s} s verloren, nochmal um den Kreisel! Probier Vorsichtig.",
    loss_none: "{s} s verloren {where}. Probier +1 Tempo!",
    best_try_water: "Neue Bestzeit! Traust du dich durch die Wasser-Abkürzung?",
    best_try_jump: "Neue Bestzeit! Wagst du nächstes Mal den grossen Sprung?",
    best_try_exposed: "Neue Bestzeit! Nächstes Mal über die schnelle windige Brücke?",
    best_try_daring: "Neue Bestzeit! Probier Mutig für noch mehr Tempo?",
    best_keep: "Neue Bestzeit! Schaffst du es noch schneller?",
    aborted: "Das Rennen wurde gestoppt. Drück Los! und versuch es nochmal.",
  },
};

const FAIL_EVENT_KEYS = [
  "slip",
  "wind_push",
  "water_slow",
  "bad_landing",
  "bounce_wobble",
  "bumped",
];
const LOSS_EVENT_KEYS = [
  "slip",
  "water_slow",
  "wind_push",
  "bad_landing",
  "slow_corner",
  "bounce_wobble",
  "boost_weak",
  "bumped",
  "missed_exit",
];

/**
 * @param {object} run    the run that just ended (outcome, failReason, failSection, splits, events)
 * @param {object} build  the build used for the run
 * @param {object} [best] the racer's best finished run before this one
 * @param {string} language config.language: the tip's text is in this language
 * @returns {{ key: string, text: string, section?: string, ability?: string, route?: { fork: string, choice: string } }}
 */
export function coachTip(run, build, best, language) {
  copyFor(language);
  const events = run.events ?? [];

  if (run.outcome !== "finished") {
    const section = run.failSection;
    const sectionEvents = section ? events.filter((e) => e.section === section) : events;
    const ev = dominantEvent(sectionEvents, FAIL_EVENT_KEYS);
    const key =
      run.failReason === "timeout" || !ev ? `fail_${run.failReason ?? "off_track"}` : `fail_${ev}`;
    return tip(
      language,
      key,
      { section },
      key === "fail_water_slow" ? { fork: "pond", choice: "bridge" } : undefined,
    );
  }

  if (best?.elapsedMs !== undefined && run.elapsedMs >= best.elapsedMs) {
    let worst;
    let worstLoss = 0;
    for (const s of SECTION_IDS) {
      const loss = (run.splits?.[s] ?? 0) - (best.splits?.[s] ?? 0);
      if (run.splits?.[s] !== undefined && best.splits?.[s] !== undefined && loss > worstLoss) {
        worst = s;
        worstLoss = loss;
      }
    }
    if (worst) {
      const ev = dominantEvent(
        events.filter((e) => e.section === worst),
        LOSS_EVENT_KEYS,
      );
      const key = `loss_${ev ?? "none"}`;
      const route =
        ev === "water_slow" && build.routes.pond === "water"
          ? { fork: "pond", choice: "bridge" }
          : undefined;
      return tip(language, key, { section: worst, lossMs: worstLoss }, route);
    }
  }

  const experiment = [
    ["pond", "water", "best_try_water"],
    ["ramp", "jump", "best_try_jump"],
    ["crossing", "exposed", "best_try_exposed"],
  ].find(([fork, choice]) => build.routes[fork] !== choice);
  if (experiment)
    return tip(language, experiment[2], {}, { fork: experiment[0], choice: experiment[1] });
  return tip(language, build.style === "daring" ? "best_keep" : "best_try_daring", {});
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

function tip(language, key, { section, lossMs }, route) {
  const template = copyFor(language)[key];
  if (template === undefined) throw new Error(`coach: no "${language}" text for tip "${key}"`);
  const names = SECTION_NAMES[language];
  const text = template
    .replace("{where}", section ? names[section] : names.track)
    .replace("{s}", ((lossMs ?? 0) / 1000).toFixed(1));
  const out = { key, text };
  if (section) out.section = section;
  if (COACH_ABILITY[key]) out.ability = COACH_ABILITY[key];
  if (route) out.route = route;
  return out;
}
