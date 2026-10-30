// RacerSpec: the AI-written 3D design of a racer (contracts.md §5).
// RacerSpecSchema checks a spec strictly; clampRacerSpec repairs a DeepSeek reply into one.
import { z } from "zod";
import { MOODS } from "./enums.js";
import { CHARACTER_SOCKETS, partNames, RACER_KIT, RIDE_SOCKETS, SPEC_LIMITS } from "./racer-kit.js";

const L = SPEC_LIMITS;
const HEX = /^#[0-9a-fA-F]{6}$/;

export const MoodSchema = z.enum(MOODS);
export const PaletteRefSchema = z
  .number()
  .int()
  .min(0)
  .max(L.paletteMax - 1);

/**
 * Builds the spec schema. In strict mode out-of-range input fails; in repair mode it is fixed
 * and each fix is written to `fixes`.
 * @param {"strict" | "repair"} mode
 * @param {string[]} fixes
 */
function specSchema(mode, fixes) {
  const repair = mode === "repair";

  const range = ([min, max]) =>
    repair
      ? z.number().transform((v, ctx) => {
          const c = Math.min(max, Math.max(min, v));
          if (c !== v) fixes.push(`${ctx.path?.join(".") ?? "number"}: ${v} → ${c}`);
          return c;
        })
      : z.number().min(min).max(max);

  const vec3 = (r) => z.tuple([range(r), range(r), range(r)]);

  const part = (names) =>
    repair
      ? z.string().transform((v) => {
          const n = nearestName(v, names);
          if (n !== v) fixes.push(`unknown part "${v}" → "${n}"`);
          return n;
        })
      : z.enum(names);

  const paletteRef = repair ? z.number().int().nonnegative() : PaletteRefSchema;

  const capped = (item, max, label) =>
    repair
      ? z.array(item).transform((a) => {
          if (a.length > max) fixes.push(`${label}: kept ${max} of ${a.length}`);
          return a.slice(0, max);
        })
      : z.array(item).max(max);

  const text = (max) =>
    repair ? z.string().transform((s) => s.trim().slice(0, max)) : z.string().min(1).max(max);

  const extra = (sockets) => {
    const names = sockets.map((s) => s.name);
    const schema = z.object({
      shape: part(RACER_KIT.extraShapes),
      socket: part(names),
      offset: z.tuple([z.number(), z.number(), z.number()]),
      scale: vec3(L.extraScale),
      rotationDeg: vec3(L.extraRotationDeg),
      color: paletteRef,
      mirror: z.boolean().optional(),
    });
    // Offsets are limited per socket, so they are checked after the socket name is known.
    return repair
      ? schema.transform((e) => {
          const max = sockets.find((s) => s.name === e.socket).maxOffset;
          const offset = e.offset.map((v) => Math.min(max, Math.max(-max, v)));
          if (offset.some((v, i) => v !== e.offset[i])) fixes.push(`${e.socket} offset clamped`);
          return { ...e, offset };
        })
      : schema.refine(
          (e) => {
            const max = sockets.find((s) => s.name === e.socket)?.maxOffset ?? 0;
            return e.offset.every((v) => Math.abs(v) <= max);
          },
          { message: "offset is outside the socket's range", path: ["offset"] },
        );
  };

  const kit = RACER_KIT;
  return z.object({
    specVersion: z.literal(1),
    title: text(L.titleMax),
    personality: repair
      ? z.array(z.string()).transform((a) => a.slice(0, L.personalityMax))
      : z.array(z.string().min(1)).min(L.personalityMin).max(L.personalityMax),
    palette: repair
      ? z
          .array(z.string().regex(HEX))
          .min(L.paletteMin)
          .transform((a) => a.slice(0, L.paletteMax))
      : z.array(z.string().regex(HEX)).min(L.paletteMin).max(L.paletteMax),
    character: z.object({
      body: z.object({
        shape: part(partNames(kit.bodyShapes)),
        color: paletteRef,
        scale: vec3(L.bodyScale),
      }),
      head: z.object({
        shape: part(partNames(kit.headShapes)),
        color: paletteRef,
        size: range(L.headSize),
      }),
      face: z.object({
        eyes: part(partNames(kit.eyes)),
        eyeColor: z.string().regex(HEX),
        mouth: part(partNames(kit.mouths)),
        brows: z.boolean(),
        cheeks: paletteRef.optional(),
      }),
      hair: z.object({ style: part(partNames(kit.hairStyles)), color: paletteRef }).optional(),
      hat: z.object({ type: part(partNames(kit.hatTypes)), color: paletteRef }).optional(),
      arms: z.object({ color: paletteRef }),
      extras: capped(extra(CHARACTER_SOCKETS), L.characterExtrasMax, "character.extras"),
    }),
    ride: z.object({
      base: part(partNames(kit.rideBases)),
      color: paletteRef,
      accent: paletteRef,
      scale: vec3(L.rideScale),
      wheels: z
        .object({
          count: z.union([z.literal(2), z.literal(3), z.literal(4)]),
          style: part(partNames(kit.wheelStyles)),
          color: paletteRef,
          size: range(L.wheelSize),
        })
        .optional(),
      legs: z.object({ style: part(partNames(kit.legStyles)), color: paletteRef }).optional(),
      wings: z
        .object({
          style: part(partNames(kit.wingStyles)),
          color: paletteRef,
          size: range(L.wingSize),
        })
        .optional(),
      tail: z.object({ style: part(partNames(kit.tailStyles)), color: paletteRef }).optional(),
      extras: capped(extra(RIDE_SOCKETS), L.rideExtrasMax, "ride.extras"),
      drawingSticker: z.boolean(),
    }),
  });
}

/** Strict RacerSpec schema: what the server stores and the game builds. */
export const RacerSpecSchema = specSchema("strict", []).superRefine((spec, ctx) => {
  const max = spec.palette.length - 1;
  for (const [path, ref] of paletteRefs(spec)) {
    if (ref > max) ctx.addIssue({ code: "custom", path, message: `palette ref ${ref} > ${max}` });
  }
});

/**
 * Repairs a DeepSeek reply into a valid RacerSpec: unknown part names → nearest valid part,
 * numbers clamped to their ranges, extras capped, palette refs clamped to the palette.
 * Missing or wrongly-typed fields can't be repaired and are returned as errors.
 * @param {unknown} raw
 * @returns {{ ok: true, spec: object, fixes: string[] } | { ok: false, errors: string[] }}
 */
export function clampRacerSpec(raw) {
  const fixes = [];
  const parsed = specSchema("repair", fixes).safeParse(raw);
  if (!parsed.success) {
    return {
      ok: false,
      errors: parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`),
    };
  }
  const spec = parsed.data;
  const max = spec.palette.length - 1;
  for (const [path, ref, set] of paletteRefs(spec)) {
    if (ref > max) {
      set(max);
      fixes.push(`${path.join(".")}: palette ref ${ref} → ${max}`);
    }
  }
  const check = RacerSpecSchema.safeParse(spec);
  if (!check.success) {
    return {
      ok: false,
      errors: check.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`),
    };
  }
  return { ok: true, spec: check.data, fixes };
}

/** Yields [path, ref, setter] for every palette reference in a spec. */
function* paletteRefs(spec) {
  const at = (obj, key, path) => {
    if (obj && typeof obj[key] === "number") {
      return [[...path, key], obj[key], (v) => (obj[key] = v)];
    }
    return null;
  };
  const c = spec.character;
  const r = spec.ride;
  const refs = [
    at(c.body, "color", ["character", "body"]),
    at(c.head, "color", ["character", "head"]),
    at(c.face, "cheeks", ["character", "face"]),
    at(c.hair, "color", ["character", "hair"]),
    at(c.hat, "color", ["character", "hat"]),
    at(c.arms, "color", ["character", "arms"]),
    ...c.extras.map((e, i) => at(e, "color", ["character", "extras", i])),
    at(r, "color", ["ride"]),
    at(r, "accent", ["ride"]),
    at(r.wheels, "color", ["ride", "wheels"]),
    at(r.legs, "color", ["ride", "legs"]),
    at(r.wings, "color", ["ride", "wings"]),
    at(r.tail, "color", ["ride", "tail"]),
    ...r.extras.map((e, i) => at(e, "color", ["ride", "extras", i])),
  ];
  for (const ref of refs) if (ref) yield ref;
}

/** Closest catalog name by edit distance (case- and separator-insensitive). */
export function nearestName(value, names) {
  const norm = (s) => s.toLowerCase().replace(/[\s-]+/g, "_");
  const v = norm(value);
  let best = names[0];
  let bestDist = Number.POSITIVE_INFINITY;
  for (const name of names) {
    const d = editDistance(v, norm(name));
    if (d < bestDist) {
      best = name;
      bestDist = d;
    }
  }
  return best;
}

function editDistance(a, b) {
  const row = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    let prev = row[0];
    row[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const tmp = row[j];
      row[j] = Math.min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] === b[j - 1] ? 0 : 1));
      prev = tmp;
    }
  }
  return row[b.length];
}
