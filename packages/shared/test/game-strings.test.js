// The big screen's string table (apps/game/data/strings.json, contracts §2b): every language has
// the same keys, and every key the game asks for exists. Godot can't run under bun test, so the
// keys are read from the .gd sources.
import { expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import {
  FAIL_REASONS,
  FORK_CHOICES,
  JOB_STAGES,
  LANGUAGES,
  SECTION_IDS,
  SESSION_STATUSES,
  TRACK_IDS,
  WEATHER_PHASES,
} from "../src/index.js";

const GAME = join(import.meta.dir, "../../../apps/game");
const strings = JSON.parse(readFileSync(join(GAME, "data/strings.json"), "utf8"));

function gdFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    if (e.name === "addons" || e.name === ".godot") return [];
    const p = join(dir, e.name);
    return e.isDirectory() ? gdFiles(p) : e.name.endsWith(".gd") ? [p] : [];
  });
}

test("one table per language, all with exactly the same keys, no ß", () => {
  expect(LANGUAGES.every((l) => typeof strings[l] === "object")).toBe(true);
  const en = Object.keys(strings.en).sort();
  for (const lang of LANGUAGES) {
    expect(Object.keys(strings[lang]).sort(), lang).toEqual(en);
    for (const [k, v] of Object.entries(strings[lang]))
      expect(v.length, `${lang} ${k}`).toBeGreaterThan(0);
  }
  expect(JSON.stringify(strings.de)).not.toContain("ß");
});

test("placeholders match between languages", () => {
  const holes = (s) => (s.match(/%[-0-9.]*[sdf]/g) ?? []).map((h) => h.at(-1)).join("");
  for (const k of Object.keys(strings.en))
    for (const lang of LANGUAGES)
      expect(holes(strings[lang][k]), `${lang} ${k}`).toBe(holes(strings.en[k]));
});

test("every key the game uses exists", () => {
  const used = new Set();
  for (const f of gdFiles(GAME)) {
    for (const m of readFileSync(f, "utf8").matchAll(/I18n\.[tf]\("([a-z_.A-Z]+)"/g))
      used.add(m[1]);
  }
  // Keys built from ids: "track." + id and the like.
  const surprises = [
    ...readFileSync(join(GAME, "sim/obstacles.gd"), "utf8").matchAll(/^\t"([a-z]+)": \{"half"/gm),
  ].map((m) => m[1]);
  expect(surprises.length, "sim/obstacles.gd KINDS").toBeGreaterThan(0);
  const families = {
    track: TRACK_IDS,
    section: SECTION_IDS,
    fail: FAIL_REASONS,
    making: JOB_STAGES,
    lang: LANGUAGES,
    weather: WEATHER_PHASES,
    session: [...SESSION_STATUSES, "unknown"],
    net: ["connecting", "online", "offline"],
    quality: ["low", "medium", "high"],
    // The village surprises (sim/obstacles.gd KINDS): their warnings and the words a hit pops up.
    "duel.ahead": surprises,
    "obstacle.pop": surprises,
    way: Object.entries(FORK_CHOICES).flatMap(([fork, ways]) => ways.map((w) => `${fork}.${w}`)),
    bus: JSON.parse(
      readFileSync(join(GAME, "audio/audio_settings.gd"), "utf8").match(
        /const BUSES := (\[.*\])/,
      )[1],
    ),
  };
  for (const [prefix, ids] of Object.entries(families))
    for (const id of ids) used.add(`${prefix}.${id}`);
  const dynamic = [...used].filter((k) => k.endsWith("."));
  for (const k of [...used].filter((k) => !k.endsWith(".")))
    expect(strings.en, k).toHaveProperty([k]);
  for (const prefix of dynamic)
    expect(Object.keys(families), prefix).toContain(prefix.slice(0, -1));
});
