import { expect, test } from "bun:test";
import {
  DEFAULT_BUILD,
  DEFAULT_CONFIG,
  parseBuildInput,
  starsLeft,
  validateStars,
} from "../src/index.js";

test("default build is valid", () => {
  expect(validateStars(DEFAULT_BUILD.stars)).toEqual({ ok: true });
  expect(starsLeft(DEFAULT_BUILD.stars)).toBe(0);
});

test("stars must add up to the total", () => {
  const r = validateStars({ ...DEFAULT_BUILD.stars, speed: 1 });
  expect(r.ok).toBe(false);
  expect(r.errors[0]).toContain("add up to 20");
});

test("stars are capped per ability", () => {
  const r = validateStars({ speed: 11, jump: 9, grip: 0, water: 0, stability: 0, bounce: 0 });
  expect(r.ok).toBe(false);
  expect(r.errors).toContain("speed: at most 10 stars");
});

test("star rules follow the config", () => {
  const config = { ...DEFAULT_CONFIG, starsTotal: 24, starsMaxPerAbility: 12 };
  expect(
    validateStars({ speed: 12, jump: 12, grip: 0, water: 0, stability: 0, bounce: 0 }, config).ok,
  ).toBe(true);
});

test("parseBuildInput rejects unknown routes and fractional stars", () => {
  expect(
    parseBuildInput({ ...DEFAULT_BUILD, routes: { ...DEFAULT_BUILD.routes, pond: "swim" } }).ok,
  ).toBe(false);
  expect(
    parseBuildInput({ ...DEFAULT_BUILD, stars: { ...DEFAULT_BUILD.stars, speed: 2.5 } }).ok,
  ).toBe(false);
  expect(parseBuildInput(DEFAULT_BUILD).ok).toBe(true);
});
