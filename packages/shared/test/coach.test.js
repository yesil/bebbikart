import { expect, test } from "bun:test";
import {
  abortTip,
  COACH_COPY,
  coachTip,
  DEFAULT_BUILD,
  LANGUAGES,
  SECTION_NAMES,
} from "../src/index.js";
import { BUILDS, RUNS } from "../testing/fixtures.js";

test("all copy fits in 70 chars, in every language", () => {
  for (const lang of LANGUAGES) {
    const longest = Object.values(SECTION_NAMES[lang]).sort((a, b) => b.length - a.length)[0];
    for (const [key, text] of Object.entries(COACH_COPY[lang])) {
      const filled = text.replace("{where}", longest).replace("{s}", "12.3");
      expect(filled.length, `${lang} ${key}`).toBeLessThanOrEqual(70);
    }
  }
});

test("every language has the same tips and section names", () => {
  expect(Object.keys(COACH_COPY).sort()).toEqual([...LANGUAGES].sort());
  for (const lang of LANGUAGES) {
    expect(Object.keys(COACH_COPY[lang]).sort(), lang).toEqual(Object.keys(COACH_COPY.en).sort());
    expect(Object.keys(SECTION_NAMES[lang]).sort(), lang).toEqual(
      Object.keys(SECTION_NAMES.en).sort(),
    );
  }
});

test("German tips: same rule, German text, no ß", () => {
  const tip = coachTip(RUNS[2], BUILDS[1], undefined, "de");
  expect(tip).toMatchObject({ key: "fail_slip", section: "bends", ability: "grip" });
  expect(tip.text).toBe("Ausgerutscht in den Regenbogenkurven! Probier +1 Grip oder Vorsichtig.");
  for (const text of Object.values(COACH_COPY.de)) expect(text).not.toContain("ß");
  expect(abortTip("de").text).toStartWith("Das Rennen wurde gestoppt");
});

test("an unknown language throws instead of falling back to English", () => {
  expect(() => coachTip(RUNS[2], BUILDS[1], undefined, "fr")).toThrow(/unknown language "fr"/);
  expect(() => coachTip(RUNS[2], BUILDS[1])).toThrow(/unknown language/);
  expect(() => abortTip(undefined)).toThrow(/unknown language/);
});

test("failed run: tip about the fail", () => {
  const tip = coachTip(RUNS[2], BUILDS[1], undefined, "en");
  expect(tip).toMatchObject({ key: "fail_slip", section: "bends", ability: "grip" });
  expect(tip.text).toBe("Slipped on the rainbow bends! Try +1 grip or Careful style.");
});

test("slower than best: biggest loss section", () => {
  const tip = coachTip(RUNS[1], BUILDS[0], RUNS[0], "en");
  expect(tip).toMatchObject({ key: "loss_water_slow", section: "pond" });
  expect(tip.text).toContain("2.5 s");
});

test("new best: cheer plus an experiment", () => {
  const tip = coachTip(RUNS[0], DEFAULT_BUILD, undefined, "en");
  expect(tip).toMatchObject({ key: "best_try_water", route: { fork: "pond", choice: "water" } });
});
