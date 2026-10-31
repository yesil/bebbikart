// Everything about a racer's per-run setup lives here, so the stars/build design can change
// in one place (contracts.md §4, §2h, README §2 rule 4).
import { z } from "zod";
import { DEFAULT_CONFIG } from "./config.js";
import { ABILITIES, FORK_CHOICES, ROUTE_STARS } from "./enums.js";

export const StarsSchema = z.object(
  Object.fromEntries(ABILITIES.map((a) => [a, z.number().int().nonnegative()])),
);

export const ForkChoiceSchema = z.object({
  pond: z.enum(FORK_CHOICES.pond),
  ramp: z.enum(FORK_CHOICES.ramp),
  crossing: z.enum(FORK_CHOICES.crossing),
});

/**
 * Body of PUT /api/players/me/build. Star totals are checked by validateStars. Other fields
 * (the routes and driving style older phones sent) are dropped: stars choose the routes (§2h).
 */
export const BuildInputSchema = z.object({
  stars: StarsSchema,
});

export const BuildSchema = BuildInputSchema.extend({
  routes: ForkChoiceSchema, // routesFor(stars), set by the server
  id: z.string(),
  playerId: z.string(),
  createdAt: z.iso.datetime(),
});

/**
 * The way the stars take at each fork (contracts §2h): ROUTE_STARS[fork].stars or more of its
 * ability take the risky way, else the safe one.
 * @param {Record<string, number>} stars
 * @returns {{ pond: string, ramp: string, crossing: string }}
 */
export function routesFor(stars) {
  return Object.fromEntries(
    Object.entries(ROUTE_STARS).map(([fork, rule]) => [
      fork,
      (stars[rule.ability] ?? 0) >= rule.stars
        ? rule.choice
        : FORK_CHOICES[fork].find((c) => c !== rule.choice),
    ]),
  );
}

const DEFAULT_STARS = Object.freeze({
  speed: 4,
  jump: 4,
  grip: 4,
  water: 2,
  stability: 4,
  bounce: 2,
});
export const DEFAULT_BUILD = Object.freeze({
  stars: DEFAULT_STARS,
  routes: Object.freeze(routesFor(DEFAULT_STARS)),
});

/**
 * Checks the star rules: integers, each 0..starsMaxPerAbility, sum === starsTotal.
 * @param {unknown} stars
 * @param {{ starsTotal: number, starsMaxPerAbility: number }} [config]
 * @returns {{ ok: true } | { ok: false, errors: string[] }}
 */
export function validateStars(stars, config = DEFAULT_CONFIG) {
  const parsed = StarsSchema.safeParse(stars);
  if (!parsed.success) {
    return {
      ok: false,
      errors: parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`),
    };
  }
  const errors = [];
  let sum = 0;
  for (const ability of ABILITIES) {
    const n = parsed.data[ability];
    sum += n;
    if (n > config.starsMaxPerAbility) {
      errors.push(`${ability}: at most ${config.starsMaxPerAbility} stars`);
    }
  }
  if (sum !== config.starsTotal) {
    errors.push(`stars must add up to ${config.starsTotal}, got ${sum}`);
  }
  return errors.length ? { ok: false, errors } : { ok: true };
}

/** Stars still to place (negative means too many). */
export function starsLeft(stars, config = DEFAULT_CONFIG) {
  return config.starsTotal - ABILITIES.reduce((sum, a) => sum + (stars[a] ?? 0), 0);
}

/**
 * Parses a build body and checks the star rules. The result carries the routes the stars take.
 * @returns {{ ok: true, build: { stars: Record<string, number>, routes: object } } | { ok: false, errors: string[] }}
 */
export function parseBuildInput(input, config = DEFAULT_CONFIG) {
  const parsed = BuildInputSchema.safeParse(input);
  if (!parsed.success) {
    return {
      ok: false,
      errors: parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`),
    };
  }
  const stars = validateStars(parsed.data.stars, config);
  if (!stars.ok) return stars;
  return { ok: true, build: { stars: parsed.data.stars, routes: routesFor(parsed.data.stars) } };
}
