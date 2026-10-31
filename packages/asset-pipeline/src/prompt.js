// The DeepSeek check + design prompt (asset-pipeline.md §1 step 2).
// The kit catalog and limits come from @bebbikart/shared/racer-kit.js, so a part added there is
// usable by the AI right away. Tune wording and examples here; keep examples valid (tests check).
import { RACER_KIT, REJECT_REASONS, SPEC_LIMITS } from "@bebbikart/shared";

export const PROMPT_VERSION = 1;

/** Kit catalog as compact prompt text: one line per part, grouped by slot. */
export function catalogText(kit = RACER_KIT) {
  const group = (title, parts) =>
    `${title}:\n${parts.map((p) => `  - ${p.name}: ${p.desc}`).join("\n")}`;
  const sockets = (on) =>
    kit.sockets
      .filter((s) => s.on === on)
      .map((s) => `  - ${s.name}: ${s.desc} (offset each axis within ±${s.maxOffset})`)
      .join("\n");
  return [
    group("character.body.shape", kit.bodyShapes),
    group("character.head.shape", kit.headShapes),
    group("character.face.eyes", kit.eyes),
    group("character.face.mouth", kit.mouths),
    group("character.hair.style", kit.hairStyles),
    group("character.hat.type", kit.hatTypes),
    group("ride.base", kit.rideBases),
    group("ride.wheels.style", kit.wheelStyles),
    group("ride.legs.style", kit.legStyles),
    group("ride.wings.style", kit.wingStyles),
    group("ride.tail.style", kit.tailStyles),
    `extra.shape: ${kit.extraShapes.join(", ")}`,
    `character extra sockets:\n${sockets("character")}`,
    `ride extra sockets:\n${sockets("ride")}`,
  ].join("\n\n");
}

function schemaText(L = SPEC_LIMITS) {
  const r = ([a, b]) => `${a}–${b}`;
  return `RacerSpec (all fields required unless marked optional):
{
  "specVersion": 1,
  "title": string, max ${L.titleMax} chars, a fun racer name like "The Purple Flash",
  "personality": ${L.personalityMin}–${L.personalityMax} single words, e.g. ["brave","bouncy"],
  "palette": ${L.paletteMin}–${L.paletteMax} hex colours "#rrggbb" taken from the drawings, most important first,
  "character": {
    "body": { "shape": <body shape>, "color": <palette index>, "scale": [x,y,z] each ${r(L.bodyScale)} },
    "head": { "shape": <head shape>, "color": <palette index>, "size": ${r(L.headSize)} },
    "face": { "eyes": <eyes>, "eyeColor": "#rrggbb", "mouth": <mouth>, "brows": bool, "cheeks": <palette index> (optional) },
    "hair": { "style": <hair style>, "color": <palette index> } (optional),
    "hat": { "type": <hat type>, "color": <palette index> } (optional),
    "arms": { "color": <palette index> },
    "extras": [<extra>] max ${L.characterExtrasMax}, character sockets only
  },
  "ride": {
    "base": <ride base>, "color": <palette index>, "accent": <palette index>, "scale": [x,y,z] each ${r(L.rideScale)},
    "wheels": { "count": 2|3|4, "style": <wheel style>, "color": <palette index>, "size": ${r(L.wheelSize)} } (optional),
    "legs": { "style": <leg style>, "color": <palette index> } (optional),
    "wings": { "style": <wing style>, "color": <palette index>, "size": ${r(L.wingSize)} } (optional),
    "tail": { "style": <tail style>, "color": <palette index> } (optional),
    "extras": [<extra>] max ${L.rideExtrasMax}, ride sockets only,
    "drawingSticker": bool
  }
}
<extra> = { "shape": <extra shape>, "socket": <socket>, "offset": [x,y,z] within the socket's range,
            "scale": [x,y,z] each ${r(L.extraScale)}, "rotationDeg": [x,y,z] each ${r(L.extraRotationDeg)},
            "color": <palette index>, "mirror": bool (optional, true = also place a copy on the other side) }
<palette index> = 0-based index into "palette". Units: 1.0 = normal size; +y is up, +z is forward (towards the front of the ride), +x is the racer's left.`;
}

export const SYSTEM_PROMPT = `You are the Racer Designer for BebbiKart, a racing game for children aged 6–10 at a family event.
A child drew two pictures: their racing CHARACTER (image 1) and their VEHICLE (image 2). Turn them into a 3D toy racer
by choosing parts from a fixed toy kit and writing a RacerSpec JSON. You write a design, not a picture.

STEP 1: CHECK each image. Be generous: kids' drawings are messy, sparse, faint, crooked and photographed badly, and
that is fine. Only flag an image when you are sure:
- "not_a_drawing": a real photo of a real object or scene (a real car, toy, room), not a drawing on paper.
- "real_person": a photo that shows a real person or a real face. Never describe the person.
- "empty_page": blank or nearly blank paper (a stray mark or two is still empty).
- "unreadable": too dark, blurry or cropped to see anything at all. A wild scribble is NOT unreadable: treat it as a
  playful abstract creature (character) or a "blob" ride and design something fun from its colours.
The same drawing may be used for both images (e.g. a kid riding a skateboard on one sheet): design the character from
the rider and the ride from the vehicle. If a drawing has several things, use the biggest or most central one.

STEP 2: DESIGN the racer so the child instantly says "that's mine!":
- Spirit: a short fun title and 2–3 personality words that match the drawing's mood.
- Palette: 3–5 colours actually used in the drawings (crayon colours, made bright and toy-like). Skip paper white, table
  colours and pencil grey unless the drawing really uses them. Every part refers to the palette by index.
- Pick the closest kit parts. A character that is an animal, robot or monster still uses a body + head + face; ears,
  horns, antennae, spikes and tails are extras. Vehicles that are not karts are welcome: a horse is "animal4" with legs,
  a dragon is "bird" with wings, a rocket shoe is "rocket" (or "blob"), a boat is "boat".
- Capture the 2–4 most distinctive features of each drawing with extras (three horns, a crown jewel, flames, a number,
  spots, a flag). Fewer, bigger, well-placed extras beat many tiny ones. Use "mirror": true for pairs (ears, wings).
- Keep it cute and kid-friendly: friendly faces, no weapons, no scary or gory details, no text or brand names.
- Proportions: chunky toy style. Make what the child exaggerated bigger (a huge head, tiny wheels).
- Set "drawingSticker": true when the vehicle drawing has a nice flat side to show the child's own picture.

Reply with ONE JSON object and nothing else:
{
  "check": {
    "character": { "ok": bool, "reason": one of ${JSON.stringify(REJECT_REASONS.filter((r) => r !== "unsupported_file"))} or null, "seen": short description of what is drawn },
    "vehicle":   { "ok": bool, "reason": ... or null, "seen": short description }
  },
  "spec": RacerSpec, or null if any check failed,
  "notes": one short sentence about your design choices
}

Use only the part names listed in the kit. Stay inside every range.

=== TOY KIT CATALOG ===
${catalogText()}

=== SCHEMA ===
${schemaText()}`;

const ex = (shape, socket, color, offset, scale, rotationDeg = [0, 0, 0], mirror) => ({
  shape,
  socket,
  offset,
  scale,
  rotationDeg,
  color,
  ...(mirror ? { mirror: true } : {}),
});

/** Worked examples: description of the two drawings → full reply. Shown to the model. */
export const EXAMPLES = [
  {
    description:
      "Character: an orange tiger with black stripes, a big smile and a blue cap. Vehicle: a green go-kart with big black wheels and a lightning bolt on the side.",
    reply: {
      check: {
        character: { ok: true, reason: null, seen: "orange tiger with stripes and a blue cap" },
        vehicle: { ok: true, reason: null, seen: "green kart with a lightning bolt" },
      },
      spec: {
        specVersion: 1,
        title: "Tiger Bolt",
        personality: ["brave", "speedy"],
        palette: ["#ff8a1f", "#1f1f1f", "#2f6fe0", "#3fbf4a", "#ffd23f"],
        character: {
          body: { shape: "round", color: 0, scale: [1, 1, 1] },
          head: { shape: "wide", color: 0, size: 1.2 },
          face: { eyes: "big_round", eyeColor: "#1f1f1f", mouth: "grin", brows: true },
          hat: { type: "cap", color: 2 },
          arms: { color: 0 },
          extras: [
            ex("cone", "head_side", 0, [0.1, 0.15, 0], [0.25, 0.25, 0.2], [0, 0, 20], true),
            ex("box", "body_front", 1, [0, 0.05, 0.05], [0.5, 0.1, 0.1], [0, 0, 10]),
            ex("box", "body_front", 1, [0, -0.1, 0.05], [0.5, 0.1, 0.1], [0, 0, -10]),
          ],
        },
        ride: {
          base: "kart",
          color: 3,
          accent: 4,
          scale: [1, 1, 1],
          wheels: { count: 4, style: "monster", color: 1, size: 1.4 },
          extras: [ex("star", "ride_side", 4, [0, 0.05, 0], [0.5, 0.5, 0.1], [0, 0, 15], true)],
          drawingSticker: false,
        },
      },
      notes:
        "Tiger stripes as body bands, ears as mirrored cones, the lightning bolt as a yellow star on both sides.",
    },
  },
  {
    description:
      "Character: a pink unicorn girl with long purple hair and a horn. Vehicle: a white flying horse with feathery wings and a rainbow tail.",
    reply: {
      check: {
        character: { ok: true, reason: null, seen: "pink unicorn girl with purple hair" },
        vehicle: { ok: true, reason: null, seen: "winged white horse with a rainbow tail" },
      },
      spec: {
        specVersion: 1,
        title: "Rainbow Dash",
        personality: ["dreamy", "sparkly"],
        palette: ["#ff8fc8", "#9b5de5", "#fdfdfd", "#ffd23f", "#4cc9f0"],
        character: {
          body: { shape: "bean", color: 0, scale: [0.9, 1.1, 0.9] },
          head: { shape: "oval", color: 0, size: 1.1 },
          face: { eyes: "big_round", eyeColor: "#9b5de5", mouth: "smile", brows: false, cheeks: 0 },
          hair: { style: "long", color: 1 },
          arms: { color: 0 },
          extras: [ex("cone", "head_top", 3, [0, 0.1, 0.1], [0.15, 0.45, 0.15], [20, 0, 0])],
        },
        ride: {
          base: "animal4",
          color: 2,
          accent: 1,
          scale: [1, 1, 1.1],
          legs: { style: "hooves", color: 2 },
          wings: { style: "feather", color: 2, size: 1.3 },
          tail: { style: "fluffy", color: 4 },
          extras: [ex("heart", "ride_side", 0, [0, 0.1, 0], [0.3, 0.3, 0.1], [0, 0, 0], true)],
          drawingSticker: false,
        },
      },
      notes:
        "Animal4 with hooves and feather wings for the flying horse; the horn is a golden cone.",
    },
  },
  {
    description:
      "Character: a photo of a real boy smiling at the camera. Vehicle: a crayon drawing of a blue rocket.",
    reply: {
      check: {
        character: { ok: false, reason: "real_person", seen: "a photo of a real person" },
        vehicle: { ok: true, reason: null, seen: "blue crayon rocket" },
      },
      spec: null,
      notes: "Image 1 is a photo of a person, so no design.",
    },
  },
];

/** Builds the chat messages for one design call. `images` are data URLs (character, vehicle). */
export function buildMessages({
  characterDataUrl,
  vehicleDataUrl,
  reroll = false,
  previousErrors = null,
}) {
  const examples = EXAMPLES.map(
    (e, i) => `Example ${i + 1}. ${e.description}\nReply:\n${JSON.stringify(e.reply)}`,
  ).join("\n\n");

  const ask = [
    "Here are the two drawings. Image 1 = CHARACTER, image 2 = VEHICLE. Check them, then design the racer. Reply in JSON.",
  ];
  if (reroll) {
    ask.push(
      "The child asked to TRY ANOTHER LOOK: make a clearly different interpretation of the same drawings (other part choices, proportions, extras or title) while keeping the drawing's colours and key features.",
    );
  }
  if (previousErrors?.length) {
    ask.push(
      `Your previous reply did not pass validation. Fix these problems and reply with the full JSON again:\n- ${previousErrors.slice(0, 20).join("\n- ")}`,
    );
  }

  return [
    { role: "system", content: `${SYSTEM_PROMPT}\n\n=== WORKED EXAMPLES ===\n${examples}` },
    {
      role: "user",
      content: [
        { type: "text", text: "Image 1: CHARACTER drawing" },
        { type: "image_url", image_url: { url: characterDataUrl } },
        { type: "text", text: "Image 2: VEHICLE drawing" },
        { type: "image_url", image_url: { url: vehicleDataUrl } },
        { type: "text", text: ask.join("\n\n") },
      ],
    },
  ];
}

/** Friendly retake messages shown on the phone, per reject reason. */
export const REJECT_MESSAGES = {
  not_a_drawing: "That looks like a photo! Please take a picture of your drawing on paper.",
  real_person:
    "Oops, we can only use drawings, not photos of people. Please snap your drawing instead.",
  empty_page: "The page looks empty! Draw your racer first, then take the photo.",
  unreadable:
    "We couldn't see your drawing. Try again with more light and the whole page in the photo.",
  unsupported_file: "That file didn't work. Please take a new photo of your drawing.",
};
