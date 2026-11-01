// Track maps for the phone (contracts §2e): each sim course as 2D polylines per segment, tagged
// with its stretch. Generated from the Godot sim by `bun run maps:export`
// (apps/game/tools/export_track_maps.gd); `-- --check` and village_laps.gd fail when stale.
import { z } from "zod";
import { TRACK_IDS } from "./enums.js";
import countryside from "./track-maps/countryside.json";
import village from "./track-maps/village.json";

const point = z.tuple([z.number(), z.number()]); // x, y (metres, north up)

export const TrackMapSchema = z.object({
  generated: z.string(),
  track: z.enum(TRACK_IDS),
  loop: z.boolean(),
  bounds: z.tuple([z.number(), z.number(), z.number(), z.number()]), // min x, min y, max x, max y
  start: z.tuple([point, point]), // the start line, across the road
  segments: z
    .array(
      z.object({
        id: z.string(),
        stretch: z.string(),
        fork: z.string(), // "" when not a fork piece
        choice: z.string(),
        // A fork piece: the side a kid steers to at the junction to take it, -1 left or 1 right as
        // the big screen shows it (contracts §2g); 0 off the forks.
        steer: z.union([z.literal(-1), z.literal(0), z.literal(1)]),
        arrows: z.number().int().nonnegative(), // boost arrow strips on it (§2g)
        rain: z.boolean(), // rain hits it hardest: a ford, mud or a slick deck (sim course data)
        wind: z.boolean(), // wind hits it hardest: open ground
        pts: z.array(point).min(2),
      }),
    )
    .min(1),
});

export const TRACK_MAPS = { countryside, village };

/** The map of a track. A track without one is a bug: it throws (the phone shows the error). */
export function trackMap(track) {
  const map = TRACK_MAPS[track];
  if (!map) throw new Error(`no track map for "${track}" (run bun run maps:export)`);
  return map;
}
