// Coach tips (contracts.md §8). First version of the rules; WS3 owns the gameplay knowledge
// and tunes them. All kid-facing copy is in COACH_COPY so it is reviewed in one place.
import { SECTION_IDS } from "./enums.js";

export const SECTION_NAMES = {
  hills: "the hills",
  pond: "the pond",
  crossing: "the windy crossing",
  bends: "the rainbow bends",
};

/** Text templates. {where} = section name, {s} = seconds lost. Keep each ≤ 70 chars. */
export const COACH_COPY = {
  // Rule 1: failed runs, by reason and dominant event.
  fail_slip: { text: "Slipped on {where}! Try +1 grip or Careful style.", ability: "grip" },
  fail_wind_push: { text: "Blown off at {where}! Try +1 stability.", ability: "stability" },
  fail_water_slow: { text: "Stuck in the water! Try +1 water, or the bridge.", ability: "water" },
  fail_bad_landing: { text: "Crash landing on {where}! Try +1 bounce.", ability: "bounce" },
  fail_bounce_wobble: { text: "Too wobbly on {where}! Try -1 bounce.", ability: "bounce" },
  fail_bumped: {
    text: "Bumped off! Wait for a quiet track, or +1 stability.",
    ability: "stability",
  },
  fail_off_track: { text: "Off the road at {where}! Try Careful style.", ability: "grip" },
  fail_flipped: { text: "Flipped over at {where}! Try +1 stability.", ability: "stability" },
  fail_stuck: { text: "Got stuck at {where}! Try a different route.", ability: "speed" },
  fail_timeout: { text: "Out of time! Try +1 speed.", ability: "speed" },
  // Rule 2: finished but slower than best somewhere, by dominant event in that section.
  loss_slip: { text: "Lost {s} s slipping on {where}. Try +1 grip.", ability: "grip" },
  loss_water_slow: {
    text: "Lost {s} s at {where}. Try the bridge, or +1 water.",
    ability: "water",
  },
  loss_wind_push: { text: "Lost {s} s in the wind. Try +1 stability.", ability: "stability" },
  loss_bad_landing: { text: "Lost {s} s on a bumpy landing. Try +1 bounce.", ability: "bounce" },
  loss_slow_corner: { text: "Lost {s} s in {where}. Try Daring style!", ability: "grip" },
  loss_bounce_wobble: { text: "Lost {s} s wobbling on {where}. Try -1 bounce.", ability: "bounce" },
  loss_boost_weak: { text: "Lost {s} s at {where}. Boost on the glowing zones!" },
  loss_bumped: { text: "Lost {s} s in bumps. Wait for a quieter track!", ability: "stability" },
  loss_none: { text: "Lost {s} s at {where}. Try +1 speed!", ability: "speed" },
  // Rule 3: first finish or new best, plus one experiment.
  best_try_water: { text: "New best! Brave enough to try the water shortcut?" },
  best_try_jump: { text: "New best! Dare to jump the big ramp next time?" },
  best_try_exposed: { text: "New best! Try the fast windy bridge next time?" },
  best_try_daring: { text: "New best! Try Daring style for even more speed?" },
  best_keep: { text: "New best! Can you beat it again?" },
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
];

/**
 * @param {object} run    the run that just ended (outcome, failReason, failSection, splits, events)
 * @param {object} build  the build used for the run
 * @param {object} [best] the racer's best finished run before this one
 * @returns {{ key: string, text: string, section?: string, ability?: string, route?: { fork: string, choice: string } }}
 */
export function coachTip(run, build, best) {
  const events = run.events ?? [];

  if (run.outcome !== "finished") {
    const section = run.failSection;
    const sectionEvents = section ? events.filter((e) => e.section === section) : events;
    const ev = dominantEvent(sectionEvents, FAIL_EVENT_KEYS);
    const key =
      run.failReason === "timeout" || !ev ? `fail_${run.failReason ?? "off_track"}` : `fail_${ev}`;
    return tip(
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
      return tip(key, { section: worst, lossMs: worstLoss }, route);
    }
  }

  const experiment = [
    ["pond", "water", "best_try_water"],
    ["ramp", "jump", "best_try_jump"],
    ["crossing", "exposed", "best_try_exposed"],
  ].find(([fork, choice]) => build.routes[fork] !== choice);
  if (experiment) return tip(experiment[2], {}, { fork: experiment[0], choice: experiment[1] });
  return tip(build.style === "daring" ? "best_keep" : "best_try_daring", {});
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

function tip(key, { section, lossMs }, route) {
  const copy = COACH_COPY[key];
  const text = copy.text
    .replace("{where}", section ? SECTION_NAMES[section] : "the track")
    .replace("{s}", ((lossMs ?? 0) / 1000).toFixed(1));
  const out = { key, text };
  if (section) out.section = section;
  if (copy.ability) out.ability = copy.ability;
  if (route) out.route = route;
  return out;
}
