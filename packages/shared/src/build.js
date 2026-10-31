// Everything about a racer's per-run setup lives here, so the stars/build design can change
// in one place (contracts.md §4, README §2 rule 4).
import { z } from "zod";
import { DEFAULT_CONFIG } from "./config.js";
import { ABILITIES, DRIVING_STYLES, FORK_CHOICES } from "./enums.js";

export const StarsSchema = z.object(
  Object.fromEntries(ABILITIES.map((a) => [a, z.number().int().nonnegative()])),
);

export const ForkChoiceSchema = z.object({
  pond: z.enum(FORK_CHOICES.pond),
  ramp: z.enum(FORK_CHOICES.ramp),
  crossing: z.enum(FORK_CHOICES.crossing),
});

export const DrivingStyleSchema = z.enum(DRIVING_STYLES);

/** Body of PUT /api/players/me/build. Star totals are checked by validateStars. */
export const BuildInputSchema = z.object({
  stars: StarsSchema,
  routes: ForkChoiceSchema,
  style: DrivingStyleSchema,
});

export const BuildSchema = BuildInputSchema.extend({
  id: z.string(),
  playerId: z.string(),
  createdAt: z.iso.datetime(),
});

export const DEFAULT_BUILD = Object.freeze({
  stars: Object.freeze({ speed: 4, jump: 4, grip: 4, water: 2, stability: 4, bounce: 2 }),
  routes: Object.freeze({ pond: "bridge", ramp: "around", crossing: "sheltered" }),
  style: "balanced",
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
 * Parses a build body and checks the star rules.
 * @returns {{ ok: true, build: z.infer<typeof BuildInputSchema> } | { ok: false, errors: string[] }}
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
  return { ok: true, build: parsed.data };
}
