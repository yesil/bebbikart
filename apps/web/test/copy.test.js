import { expect, test } from "bun:test";
import { ERROR_CODES, LANGUAGES } from "@bebbikart/shared";
import * as copy from "../src/copy.js";

const { COPY_TABLES, errorText, setLanguage } = copy;

/** Every key path of a table; arrays and functions are leaves. */
function paths(table, prefix = "") {
  return Object.entries(table).flatMap(([k, v]) =>
    v && typeof v === "object" && !Array.isArray(v)
      ? paths(v, `${prefix}${k}.`)
      : [`${prefix}${k}`],
  );
}
const leaves = (table) =>
  Object.values(table).flatMap((v) =>
    v && typeof v === "object" && !Array.isArray(v) ? leaves(v) : [v],
  );

test("one table per language, all with exactly the same keys", () => {
  expect(Object.keys(COPY_TABLES).sort()).toEqual([...LANGUAGES].sort());
  const en = paths(COPY_TABLES.en).sort();
  for (const lang of LANGUAGES) expect(paths(COPY_TABLES[lang]).sort(), lang).toEqual(en);
});

test("no empty texts, same shapes (lists stay lists, functions stay functions), no ß", () => {
  for (const lang of LANGUAGES) {
    for (const p of paths(COPY_TABLES.en)) {
      const get = (t) => p.split(".").reduce((o, k) => o[k], t);
      const en = get(COPY_TABLES.en);
      const v = get(COPY_TABLES[lang]);
      expect(typeof v, `${lang} ${p}`).toBe(typeof en);
      expect(Array.isArray(v), `${lang} ${p}`).toBe(Array.isArray(en));
      if (typeof v === "function") expect(v.length, `${lang} ${p}`).toBe(en.length);
    }
    for (const v of leaves(COPY_TABLES[lang])) {
      for (const text of Array.isArray(v) ? v : [v]) {
        if (typeof text === "function") continue;
        expect(text.length).toBeGreaterThan(0);
      }
    }
  }
  expect(JSON.stringify(COPY_TABLES.de)).not.toContain("ß");
});

test("every error code has a line in every language", () => {
  for (const lang of LANGUAGES)
    for (const code of ERROR_CODES)
      expect(Object.hasOwn(COPY_TABLES[lang].errors, code), `${lang} ${code}`).toBe(true);
});

test("no fallbacks: reading before the language is known, a missing key or an unknown language throws", () => {
  expect(() => copy.COPY.reveal).toThrow(/before the server sent the language/);
  expect(() => setLanguage("fr")).toThrow(/unknown language "fr"/);
  setLanguage("de");
  expect(copy.COPY.reveal.go).toBe("Los geht's!");
  expect(copy.COPY.garage.starsLeft(2)).toBe("Sterne übrig: 2");
  expect(() => copy.COPY.reveal.nope).toThrow(/no text for "de.reveal.nope"/);
  expect(errorText({ code: "cooldown", message: "x" })).toBe(COPY_TABLES.de.errors.cooldown);
  expect(errorText({ code: "weird", message: "boom" })).toBe(
    `${COPY_TABLES.de.errors.generic} (weird: boom)`,
  );
  setLanguage("en");
  expect(copy.COPY.reveal.go).toBe("Let's race!");
});
