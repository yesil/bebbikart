import { expect, test } from "bun:test";
import {
  ABILITY_NAMES,
  abortTip,
  COACH_COPY,
  coachTip,
  DEFAULT_BUILD,
  LANGUAGES,
  ROUTE_NAMES,
  STRETCH_NAMES,
  TRACK_STRETCHES,
} from "../src/index.js";
import { BUILDS, RUNS } from "../testing/fixtures.js";

const longest = (values) => [...values].sort((a, b) => b.length - a.length)[0];

test("every tip fits in 70 chars, with every name it can get, in every language", () => {
  for (const lang of LANGUAGES) {
    const ability = longest(Object.values(ABILITY_NAMES[lang]));
    for (const [track, list] of Object.entries(TRACK_STRETCHES)) {
      for (const st of list) {
        const alt = list.find((t) => st.fork && t.fork === st.fork && t.id !== st.id);
        for (const [key, text] of Object.entries(COACH_COPY[lang])) {
          // Route tips go on a fork's safe alternative only; the slick tip on a slick deck only.
          if (text.includes("{alt}") && (st.ability || !alt)) continue;
          if (key === "loss_slick" && !st.slick) continue;
          const filled = text
            .replace("{where}", STRETCH_NAMES[lang][track][st.id])
            .replace("{alt}", alt ? ROUTE_NAMES[lang][track][alt.id] : "")
            .replace("{ability}", ability)
            .replace("{n}", "10")
            .replace("{s}", "12.3");
          expect(filled.length, `${lang} ${key}: ${filled}`).toBeLessThanOrEqual(70);
        }
      }
    }
  }
});

test("every language has the same tips, and a name for every stretch and fork piece", () => {
  expect(Object.keys(COACH_COPY).sort()).toEqual([...LANGUAGES].sort());
  for (const lang of LANGUAGES) {
    expect(Object.keys(COACH_COPY[lang]).sort(), lang).toEqual(Object.keys(COACH_COPY.en).sort());
    for (const [track, list] of Object.entries(TRACK_STRETCHES)) {
      expect(Object.keys(STRETCH_NAMES[lang][track]).sort(), `${lang} ${track}`).toEqual(
        list.map((s) => s.id).sort(),
      );
      expect(Object.keys(ROUTE_NAMES[lang][track]).sort(), `${lang} ${track} routes`).toEqual(
        list
          .filter((s) => s.fork)
          .map((s) => s.id)
          .sort(),
      );
    }
  }
});

test("German tips: same rule, German text, no ß", () => {
  const tip = coachTip(RUNS[2], BUILDS[1], undefined, "de", RUNS[2].stretches);
  expect(tip).toMatchObject({ key: "fail_slip", stretch: "rainbow_bends", ability: "grip" });
  expect(tip.text).toBe("Ausgerutscht in den Regenbogenkurven! Probier +2 Grip.");
  for (const lang of [
    COACH_COPY.de,
    ...Object.values(STRETCH_NAMES.de),
    ...Object.values(ROUTE_NAMES.de),
  ])
    for (const text of Object.values(lang)) expect(text).not.toContain("ß");
  expect(abortTip("de").text).toStartWith("Das Rennen wurde gestoppt");
});

test("an unknown language or track throws instead of falling back", () => {
  expect(() => coachTip(RUNS[2], BUILDS[1], undefined, "fr", [])).toThrow(/unknown language "fr"/);
  expect(() => coachTip(RUNS[2], BUILDS[1])).toThrow(/unknown language/);
  expect(() => abortTip(undefined)).toThrow(/unknown language/);
  expect(() => coachTip({ ...RUNS[2], track: "moon" }, BUILDS[1], undefined, "en", [])).toThrow(
    /unknown track "moon"/,
  );
  expect(() => coachTip(RUNS[1], BUILDS[0], RUNS[0], "en")).toThrow(/without its stretches/);
});

test("failed run: tip about the fail, named after the stretch where it ended", () => {
  const tip = coachTip(RUNS[2], BUILDS[1], undefined, "en", RUNS[2].stretches);
  expect(tip).toMatchObject({ key: "fail_slip", stretch: "rainbow_bends", ability: "grip" });
  expect(tip.text).toBe("Slipped in the rainbow bends! Try +2 grip.");
  const noStretch = { ...RUNS[2], failStretch: undefined };
  expect(() => coachTip(noStretch, BUILDS[1], undefined, "en", [])).toThrow(/failStretch/);
});

// A village lap: the player's best on each stretch from earlier runs, and the session's fastest.
const village = (over = {}) => ({
  id: "run_v",
  playerId: "ply_me",
  track: "village",
  outcome: "finished",
  elapsedMs: 52_000,
  weatherSeen: [],
  events: [],
  ...over,
});
const st = (id, ms, extra = {}) => ({ id, ms, lostMs: 0, ...extra });

test("slower than your best: the stretch that cost most, and its star", () => {
  const stretches = [
    st("main_street", 6_000, { bestMs: 5_900 }),
    st("farm", 4_600, { bestMs: 3_300 }),
    st("cobbles", 1_900, { bestMs: 1_700 }),
  ];
  const tip = coachTip(village(), DEFAULT_BUILD, { elapsedMs: 50_000 }, "en", stretches);
  expect(tip).toMatchObject({ key: "loss_stretch", stretch: "farm", ability: "grip" });
  expect(tip.text).toBe("Lost 1.3 s on the muddy farm track. Try +2 grip!");
  expect(coachTip(village(), DEFAULT_BUILD, { elapsedMs: 50_000 }, "de", stretches).text).toBe(
    "1.3 s verloren auf dem matschigen Feldweg. Probier +2 Grip!",
  );
});

test("first run: against the session's fastest racer on each stretch", () => {
  const stretches = [
    st("ridge", 7_400, { fastestMs: 5_900, fastestPlayerId: "ply_mia", fastestNickname: "Mia" }),
    st("cobbles", 1_900, { fastestMs: 1_900, fastestPlayerId: "ply_me" }),
  ];
  const tip = coachTip(village(), DEFAULT_BUILD, undefined, "en", stretches);
  expect(tip).toMatchObject({ key: "loss_stretch", stretch: "ridge", ability: "stability" });
  expect(tip.text).toBe("Lost 1.5 s on the windy ridge. Try +2 stability!");
  // Nobody faster (or only yourself): a cheer and an experiment.
  const alone = [st("ridge", 7_400, { fastestMs: 7_400, fastestPlayerId: "ply_me" })];
  expect(coachTip(village(), DEFAULT_BUILD, undefined, "en", alone).key).toBe("best_try_route");
});

test("a fork's safe alternative: the stars that take the other way; the bridge is slick in the rain", () => {
  const stretches = [st("covered_bridge", 9_000, { bestMs: 7_500 })];
  const dry = coachTip(village(), DEFAULT_BUILD, { elapsedMs: 50_000 }, "en", stretches);
  expect(dry).toMatchObject({
    key: "loss_route",
    stretch: "covered_bridge",
    route: { fork: "pond", choice: "water" },
  });
  expect(dry).toMatchObject({ ability: "water" });
  expect(dry.text).toBe("Lost 1.5 s on the covered bridge. Try 6 water stars!");
  const wet = coachTip(
    village({ weatherSeen: ["rain"] }),
    DEFAULT_BUILD,
    { elapsedMs: 50_000 },
    "en",
    stretches,
  );
  expect(wet.key).toBe("loss_slick");
  expect(wet.text).toBe("Lost 1.5 s on the wet, slippery bridge. Try 6 water stars!");
});

test("an off-zone boost or a missed exit on that stretch gets its own tip", () => {
  const events = [
    { kind: "boost_weak", section: "hills", stretch: "main_street", atMs: 900, timeLostMs: 400 },
    { kind: "missed_exit", section: "bends", stretch: "square", atMs: 50_000, timeLostMs: 8_000 },
  ];
  const run = village({ events });
  const boost = coachTip(run, DEFAULT_BUILD, { elapsedMs: 50_000 }, "en", [
    st("main_street", 6_500, { bestMs: 5_900 }),
  ]);
  expect(boost).toMatchObject({ key: "loss_boost_weak", stretch: "main_street" });
  expect(boost.text).toBe("Lost 0.6 s on the main street. Boost on the glowing zones!");
  const exit = coachTip(run, DEFAULT_BUILD, { elapsedMs: 50_000 }, "en", [
    st("square", 16_000, { bestMs: 8_000 }),
  ]);
  expect(exit.key).toBe("loss_missed_exit");
});

test("a slide with Push held: let go sooner, as a loss and as a fail", () => {
  const events = [
    { kind: "push_slide", section: "bends", stretch: "farm", atMs: 30_000, timeLostMs: 900 },
    { kind: "slip", section: "bends", stretch: "farm", atMs: 30_500, timeLostMs: 200 },
  ];
  const loss = coachTip(village({ events }), DEFAULT_BUILD, { elapsedMs: 50_000 }, "en", [
    st("farm", 4_600, { bestMs: 3_300 }),
  ]);
  expect(loss).toMatchObject({ key: "loss_push_slide", stretch: "farm" });
  expect(loss.text).toBe("Lost 1.3 s sliding on the muddy farm track. Let go of Push sooner!");
  const failed = village({
    events,
    outcome: "failed",
    failReason: "off_track",
    failStretch: "farm",
  });
  const fail = coachTip(failed, DEFAULT_BUILD, undefined, "de", []);
  expect(fail).toMatchObject({ key: "fail_push_slide", stretch: "farm", ability: "grip" });
  expect(fail.text).toBe("Abgerutscht auf dem matschigen Feldweg! Lass Push vor der Kurve los.");
});

test("slower than your best by a hair on every stretch: no lecture", () => {
  const tip = coachTip(village(), DEFAULT_BUILD, { elapsedMs: 51_900 }, "en", [
    st("farm", 3_400, { bestMs: 3_300 }),
  ]);
  expect(tip.key).toBe("close");
});

test("new best: cheer plus an experiment (a risky way the stars don't take yet, then Push)", () => {
  const tip = coachTip(RUNS[0], DEFAULT_BUILD, undefined, "en", RUNS[0].stretches);
  expect(tip).toMatchObject({
    key: "best_try_route",
    ability: "water",
    route: { fork: "pond", choice: "water" },
  });
  expect(tip.text).toBe("New best! Try 6 water stars: they take the ford!");
  const brave = { pond: "water", ramp: "jump", crossing: "exposed" };
  const all = coachTip(RUNS[0], { ...DEFAULT_BUILD, routes: brave }, undefined, "en", []);
  expect(all.key).toBe("best_try_push");
  const slid = {
    ...RUNS[0],
    events: [{ kind: "push_slide", section: "hills", stretch: "hilltop", atMs: 1 }],
  };
  expect(coachTip(slid, { ...DEFAULT_BUILD, routes: brave }, undefined, "en", []).key).toBe(
    "best_keep",
  );
});
