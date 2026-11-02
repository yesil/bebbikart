// The Claude prompts for the four design passes (asset-pipeline.md §1 step 2):
//   1 look     (vision)  check both photos and describe every feature of the drawings
//   2 design   (text)    turn the description into a RacerSpec
//   3 critique (vision)  compare the spec with the drawings, list concrete fixes
//   4 refine   (text)    apply the fixes, write the final RacerSpec
// The kit catalog and limits come from @bebbikart/shared/racer-kit.js, so a part added there is
// usable by the AI right away. Tune wording and examples here; keep examples valid (tests check).
import { RACER_KIT, REJECT_REASONS, SPEC_LIMITS } from "@bebbikart/shared";

export const PROMPT_VERSION = 4;

/** Kit catalog as compact prompt text: one line per part, grouped by slot. */
export function catalogText(kit = RACER_KIT) {
  const group = (title, parts) =>
    `${title}:\n${parts.map((p) => `  - ${p.name}: ${p.desc}`).join("\n")}`;
  const sockets = (on) =>
    kit.sockets
      .filter((s) => s.on === on)
      .map((s) => `  - ${s.name}: ${s.desc} (offset each axis within ±${s.maxOffset})`)
      .join("\n");
  const notes = kit.extraShapeNotes ?? {};
  return [
    group("character.body.shape", kit.bodyShapes),
    group("character.head.shape", kit.headShapes),
    group("character.face.eyes", kit.eyes),
    group("character.face.mouth", kit.mouths),
    group("character.hair.style", kit.hairStyles),
    group("character.hat.type", kit.hatTypes),
    group("character.outfit[].type", kit.outfits),
    group("character.legs.shoes", kit.shoeStyles),
    group("ride.base", kit.rideBases),
    group("ride.wheels.style", kit.wheelStyles),
    group("ride.legs.style", kit.legStyles),
    group("ride.wings.style", kit.wingStyles),
    group("ride.tail.style", kit.tailStyles),
    group("pattern.type (body, head, ride)", kit.patterns),
    group("finish (character.body.finish = whole character, ride.finish)", kit.finishes),
    group("motion.style", kit.motionStyles),
    group("sound.engine", kit.engineSounds),
    group("sound.horn", kit.hornSounds),
    `extra.shape: ${kit.extraShapes.map((s) => (notes[s] ? `${s} (${notes[s]})` : s)).join(", ")}`,
    `character extra sockets:\n${sockets("character")}`,
    `ride extra sockets:\n${sockets("ride")}`,
  ].join("\n\n");
}

function schemaText(L = SPEC_LIMITS) {
  const r = ([a, b]) => `${a}–${b}`;
  return `RacerSpec (all fields required unless marked optional):
{
  "specVersion": 1,
  "palette": ${L.paletteMin}–${L.paletteMax} hex colours "#rrggbb" taken from the drawings, most important first,
  "motion": { "style": <motion style>, "energy": ${r(L.motionEnergy)} },
  "sound": { "engine": <engine sound>, "pitch": ${r(L.soundPitch)} (small/cute higher, big/heavy lower), "horn": <horn sound> },
  "character": {
    "body": { "shape": <body shape>, "color": <palette index>, "scale": [x,y,z] each ${r(L.bodyScale)},
              "pattern": <pattern> (optional), "finish": <finish> (optional) },
    "head": { "shape": <head shape>, "color": <palette index>, "size": ${r(L.headSize)}, "pattern": <pattern> (optional) },
    "face": { "eyes": <eyes>, "eyeColor": "#rrggbb", "mouth": <mouth>, "brows": bool, "cheeks": <palette index> (optional) },
    "hair": { "style": <hair style>, "color": <palette index> } (optional),
    "hat": { "type": <hat type>, "color": <palette index> } (optional),
    "arms": { "color": <palette index> },
    "outfit": [ { "type": <outfit>, "color": <palette index>, "pattern": <pattern> (optional) } ] max 2, e.g. a top + a skirt (optional),
    "legs": { "color": <palette index>, "shoes": <shoe style>, "shoeColor": <palette index>, "socks": <palette index> (optional, knee socks) } (optional, visible legs and shoes; color = skin or tights),
    "extras": [<extra>] max ${L.characterExtrasMax}, character sockets only
  },
  "ride": {
    "base": <ride base>, "color": <palette index>, "accent": <palette index>, "scale": [x,y,z] each ${r(L.rideScale)},
    "pattern": <pattern> (optional, painted on the parts in the ride's main colour), "finish": <finish> (optional),
    "number": { "value": ${r(L.rideNumber)} whole number, "color": <palette index> } (optional, racing number on both sides),
    "wheels": { "count": 2|3|4, "style": <wheel style>, "color": <palette index>, "size": ${r(L.wheelSize)} } (optional; color = the tyres as drawn, the hubs take the accent, or the main colour when the tyres are in the accent),
    "legs": { "style": <leg style>, "color": <palette index> } (optional),
    "wings": { "style": <wing style>, "color": <palette index>, "size": ${r(L.wingSize)} } (optional),
    "tail": { "style": <tail style>, "color": <palette index> } (optional),
    "extras": [<extra>] max ${L.rideExtrasMax}, ride sockets only,
    "drawingSticker": bool
  },
  "personality": ${L.personalityMin}–${L.personalityMax} single words read from the drawing's face and pose, e.g. ["calm","proud"],
  "title": string, max ${L.titleMax} chars, chosen LAST: a short name that says what is drawn, e.g. "Silver Braid", "Red Lightning",
  "tagline": string, max ${L.taglineMax} chars, chosen LAST: one plain line describing this racer as drawn, e.g. "Long silver hair and a winged gold bike"
}
The name and tagline come after the design and describe it. They never change it: no joke, theme or story that the
drawing does not show, and nothing is added, recoloured or reshaped to fit a name.
<pattern> = { "type": <pattern type>, "color": <palette index>, "scale": ${r(L.patternScale)} (bigger = larger motifs) }
<extra> = { "shape": <extra shape>, "socket": <socket>, "offset": [x,y,z] within the socket's range,
            "scale": [x,y,z] each ${r(L.extraScale)}, "rotationDeg": [x,y,z] each ${r(L.extraRotationDeg)},
            "color": <palette index>, "mirror": bool (optional, true = also place a copy on the other side) }
<palette index> = 0-based index into "palette".
GEOMETRY (read carefully, most design mistakes are here)
Axes: +y is up, +z is forward (towards the front of the ride), +x is the racer's LEFT. Offsets are metres.
Sockets are points ON the surface, and an extra is centred on its socket plus "offset":
  head_top = the crown of the head; head_side = the LEFT side of the head where an ear goes ("mirror": true adds the
  right one); head_front = the middle of the face, nose height; body_front = the chest; body_back = between the
  shoulders; hand = the right hand.
  ride_front = the nose of the ride; ride_back = the tail end; ride_side = the LEFT flank (mirror for both sides);
  ride_top = the top of the ride in front of the rider (hood, deck); ride_bottom = underneath.
Keep offsets SMALL (usually 0–0.08) so extras touch the surface: an offset of 0.3 makes a part float in the air.
  Head extras grow with head.size, so on a big head use even smaller offsets.
Character extras: scale 1.0 = 0.5 m. The head is about 0.4 m across (×head.size), the body about 0.4 m wide and
  0.5 m tall. Never go below ${SPEC_LIMITS.extraScale[0]}.
Ride extras: scale 1.0 = 1 m. A kart is about 1 m wide and 1.6 m long. Never go below ${SPEC_LIMITS.extraScale[0]} (5 cm).
Shape axes:
  sphere, box: scale is simply the size along x, y, z.
  capsule, cylinder, cone: the LENGTH runs along y (scale[1]); scale[0] and scale[2] are the thickness. They STAND ON
  THEIR BASE at the socket point and grow away from it, so their tip is scale[1] × unit away (unit = 0.5 m on the
  character, 1 m on the ride): something on the tip of a character stick of scale[1] = 0.6 goes at offset y = 0.3.
  To aim them: rotationDeg [0,0,90] makes them grow towards the racer's right, [0,0,-90] to the left (whiskers on
  head_side grow outwards with [0,0,-90] and mirror), [90,0,0] forward (+z), [-90,0,0] backwards, [0,0,±20] tilts a
  little sideways (ears). Never lay a stick by scaling x: a whisker is scale [0.1,0.4,0.1], not [0.9,0.1,0.1].
  Flat shapes (star, heart, lightning, flame, moon, flower, leaf, cloud, diamond, drop, bowtie) are puffy stickers
  facing forward (+z), scale [w,h,thickness]; on a ride_side use rotationDeg [0,90,0] and thickness 0.1.
  torus: a ring lying flat (hole points up); rotationDeg [90,0,0] stands it up facing forward.
  Building blocks: wedge, dome, half_cylinder and bucket also SIT ON THEIR FLAT BASE at the socket point and are
  scale[1] × unit tall. wedge = a ramp seen from the side, scale [width, height, length]: tall end at the back, thin
  edge pointing forward ([0,180,0] turns it round). half_cylinder = an arch seen from the side, scale [width across,
  height, length]: its flat sides face left and right. dome = half a ball, scale [width, height, length]. bucket =
  a cylinder narrower at the bottom, scale [width, height, width]; rotationDeg [180,0,0] hangs any of them upside
  down BELOW the point (a lampshade: put the point at the top of the pole + the shade's height).
  box and sphere are centred on the point.
  glasses: on head_front, about [0.6,0.6,0.6]. cape: on body_back, about [0.9,1,1], it hangs down and flows back.
Typical sizes: cat ear = cone on head_side, offset [0,0.05,0], scale [0.3,0.4,0.25], rotationDeg [0,0,-15], mirror;
  horn = cone on head_top [0.15,0.45,0.15]; antenna = capsule on head_top [0.1,0.6,0.1] with a sphere [0.15,0.15,0.15]
  at offset [0,0.3,0] (the tip); nose = sphere on head_front [0.15,0.12,0.12]; ride fin = cone [0.08,0.4,0.3];
  flag pole = cylinder on ride_top [0.1,0.8,0.1]; headlight = sphere on ride_front [0.2,0.2,0.1].
Ride colours: "color" paints the ride's main body; "accent" paints bumpers, seat back, trim and stripes — a big part
  of a kart — so pick the accent from the drawing too (or a close shade of the main colour), never a random colour.
  ride.finish covers the ride's extras too, and ride.pattern paints every ride part (extras too) in the main colour.

CHASSIS BUILDING (ride.base "chassis": for everyday objects, food, furniture, toys…)
The chassis is only a small seat pad in ride.color and, when you give ride.wheels, a dark floor 0.2 m above the
ground with the wheels (at x ±0.5, z ±0.47, radius 0.18 × wheels.size). It has NO wheels by default: give them as
drawn (count, size, tyre colour), and leave them out when the child drew none (a duck boat on water glides). The driver sits on the seat at y 0.36, z -0.1, facing forward (+z): about
0.35 m wide, 0.3 m deep and 1 m tall to the top of the head. You build the drawn object AROUND the driver with ride
extras on "ride_center" = the middle of the floor, (0, 0.2, 0) above the ground; its offsets go up to ±1.5, so the
whole object fits on this one socket. Keep ride.scale [1,1,1] on a chassis and size the parts instead.
- How it sits in 3D: the driver rides it the way a person would: on a sofa's seat with the backrest behind them,
  inside a bathtub, on top of a skate or a slice of melon, astride a cheese wedge. A drawing seen from the FRONT
  (sofas, beds, bathtubs are usually drawn so) shows the object's width: its long side runs across (x). A drawing
  seen from the SIDE (cars, shoes, teapots, cheese, fruit slices) shows its length: its long side runs along z.
- First the big parts that make the outline (3–6 extras, 0.3–1.8 m each), then the drawn details on them. The
  object is about 1–1.8 m long and 0.8–1.6 m wide, so it covers the wheels' tops and reads from the race camera.
- The driver must stay visible from the chest up: around the driver the object's top stays below about 0.8 m. A
  solid object (cheese, melon, barrel, tub) may hide the driver's legs and belly like a cockpit, but nothing goes
  over the driver's head and shoulders (no lid or roof there). Taller parts stand behind or beside the driver (a
  backrest, a lamp, a mast, a flag).
- Each drawn part goes where the child drew it: popcorn on the seat beside the driver, a lamp at a back corner, a
  duck on the rim, a lid on top of a teapot at the back. Offsets from ride_center are absolute positions minus
  (0, 0.2, 0).
- Give the body parts ride.color so ride.pattern (stars, dots, stripes the child drew on it) covers all of them.
- Parts on ride_center ride rigid. Parts on ride_top, ride_back, ride_front and ride_side wobble while driving: put
  flags, antennae, puffs and steam there (on a chassis: ride_back = (0, 0.3, -0.7), ride_front = (0, 0.3, 0.75),
  ride_top = (0, 0.4, 0.45), ride_side = (0.5, 0.3, 0)).
- Never set drawingSticker on a chassis (the sticker would sit inside the built body).`;
}

const KIDS_RULES = `Keep it cute and kid-friendly: friendly faces, no weapons, nothing scary or gory, no words, letters or brand
names (numbers 0–99 are fine as the racing number).`;

// --- what to look for ---------------------------------------------------------------------------

const CHECK_RULES = `CHECK each image first. Be generous: kids' drawings are messy, sparse, faint, crooked and photographed badly, and
that is fine. Only flag an image when you are sure:
- "not_a_drawing": a real photo of a real object or scene (a real car, toy, room), not a drawing on paper.
- "real_person": a photo that shows a real person or a real face. Never describe the person.
- "empty_page": blank or nearly blank paper (a stray mark or two is still empty).
- "unreadable": too dark, blurry or cropped to see anything at all. A wild scribble is NOT unreadable: treat it as a
  playful abstract creature (character) or a "blob" ride.
The same drawing may be used for both images (e.g. a kid riding a skateboard on one sheet): the rider is the character
and the vehicle is the vehicle. If a drawing has several things, use the biggest or most central one.`;

const LOOK_RULES = `LOOK at each drawing closely before designing, and write down what you see in "observations":
- what it is and what the child most likely meant;
- EVERY visible feature (body parts, ears, horns, eyes, mouth, hair, hats, bows, clothes, socks, shoes, accessories,
  markings, wheels, wings, tails, lights, windows, numbers, things in the hands): where it is, its colour, its size,
  the exact count when there are several, and its importance (3 = defining, 2 = clearly drawn, 1 = small detail);
- written labels: children often write colour or part names next to the drawing with arrows, in any language
  ("Gold", "orange", "weiß", "Gelb", "schwarze Räder" = black wheels, "Licht" = light, "Glas" = glass). Read every
  label, translate it, and note which part it points at: the child's words are instructions and override guesses;
- the colours: crayon/marker colours as vivid toy-like hex codes. Parts left uncoloured keep their natural reading:
  white paper inside an outline = white (a white skirt, white socks), grey pencil shading = a real mid grey or
  silver such as #a9a9b8 (never pure white, which reads as a helmet). The black outline is only how the child draws:
  little circles drawn as outlines (bubbles, popcorn, puffs, pearls) are solid white balls, not black rings;
- proportions and exaggerations (a huge head, very long hair, an enormous wheel): what the child cared about most;
- for the VEHICLE, its SHAPE: what real thing it is (a go-kart, car, boat, rocket… or an everyday object, food,
  furniture, an animal, a toy), its outline, the view it is drawn from (front or side), and each big part in its place
  (seat, backrest, armrests, rim, lid, spout, handle, rind, sausage, bun, boot, wheels), with the drawn details on them;
- drawing marks: little puffs of smoke behind a vehicle are small grey or white clouds at its back; speed lines,
  steam and smell lines are not parts (steam may become thin wisps only on a sketch);
- "detail": "sketch" when it is just a few lines with little to copy, "detailed" when the child drew and/or coloured
  real details (clothes, hair style, patterns, accessories, labelled colours).`;

// --- 1 · design (sees the drawings) ------------------------------------------------------------

const DESIGN_RULES = `HOW TO DESIGN A GREAT RACER
0. LOYALTY TO THE DRAWING comes before everything else. The racer must look like what the child drew.
   - A "detailed" drawing: reproduce its details as closely as the kit allows and add NOTHING the child did not draw:
     no imaginary extras, flags, stars, lightning, spikes, capes or touches. Its colours are the drawn and labelled
     colours. What the child did not colour keeps its natural reading (white stays white, pencil grey stays grey or
     silver).
   - A "sketch" (just a few lines): keep every line you can, and you may enhance it: a cheerful palette that suits
     it and 1–3 finishing touches that fit its story.
   - Written labels are the child's instructions: "schwarze Räder" means black wheels, "Gold" on a part means gold.
1. THE VEHICLE KEEPS ITS SHAPE. A child must recognise the vehicle from its outline alone. Pick a ride.base only
   when its own body IS the drawn shape: kart = go-kart, car = car/van/bus, bike = bike/scooter/motorbike, boat =
   boat, sailboat = sailing boat, rocket = rocket/plane/spaceship, board = skateboard/surfboard/carpet, animal4 and
   bird = an animal you ride, blob = a slime or cloud. Every other vehicle (an everyday object, food, furniture, a toy,
   clothing: a sofa, bed, bathtub, teapot, toaster, cheese, watermelon, hot dog, cake, shoe, roller skate, trolley…)
   is ride.base "chassis" with its body BUILT from extras (see CHASSIS BUILDING). Never dress a kart, boat, rocket
   or blob in the object's colours with a few extras on top: a sofa on a kart reads as a kart, a skate as a blob reads
   as a lump. Map the vehicle's shape in "featureMap" first.
2. Faithful details. Every feature with importance 3 MUST appear, and every importance 2 feature should, with the right
   colour and the right count (three horns = three cones, not two; five buttons = five spheres). Use the closest kit
   part, then extras to add what the parts can't show. Map each feature in "featureMap".
3. The child's colours. Build the palette from the drawing's real and labelled colours, made bright and toy-like (up
   to ${SPEC_LIMITS.paletteMax}). Only a bare line sketch with no colours and no labels gets a palette you choose.
   Keep the drawing's main colour as the main colour of the matching part: a red kart is red, a purple cat is purple.
   Recreate markings with patterns: stripes, spots, stars, hearts, zigzags, checks. When the child coloured a part in
   with visible crayon/marker strokes, use the "crayon" pattern in a lighter or darker shade of that colour so the toy
   keeps the hand-made look. A rainbow or multicolour part = several extras in different palette colours.
4. Use real kit parts before extras: a closed car, van or bus is ride.base "car" (its glass cabin is built in), clothes
   are "outfit" (a top + a skirt, a ruffled skirt, a dress, overalls…), visible legs, socks, boots and shoes are
   "legs", buns, pigtails, very long hair and braids are hair styles, a bow in the hair is hat "bow". NEVER build cabins, windows, roofs or big blocks out of extras over the seat: they hide the driver.
   The driver must always be visible.
5. Exaggerate what the child exaggerated: a huge head = head.size 1.4+, tiny wheels = wheels.size 0.6, a long body =
   stretched scale. Bold, chunky toy proportions beat timid ones.
6. Personality you can see. Choose eyes, brows, mouth, motion.style and energy and personality words from the
   drawing's expression and pose (not from a name or a story you invent). A grumpy face gets "angry" eyes, a happy one a "grin" or "tongue",
   a dreamy unicorn "lashes" + "sparkle" + "floaty", a robot "visor" + "metallic" + "jittery".
7. Sound to match the vehicle and the character: sound.engine from what the vehicle is (kart → putter or vroom,
   horse → hooves, dragon → flap, boat or bathtub → splash, slime → squelch, rocket shoe → rocket, a sofa or a
   teapot → putter), sound.horn from the character
   or vehicle (a cat says meow, a dog woof, a horse neigh, a cow moo, a monster roar; otherwise honk/beep/toot/squeak/
   bell/boing to suit the personality), pitch higher for small cute racers, lower for big heavy ones.
8. Imagination only for sketches (rule 0): there, add 1–3 finishing touches that fit the drawing's story (a cat's
   kart gets a fish-shaped flag). Say which touches are yours in "featureMap" (feature "touch: …"). A detailed
   drawing gets no touches: its personality comes from the drawn face, the motion and the sound.
   Do not invent a theme, character or joke and then design towards it (a "moon princess" does not get moons).
9. Unique: the drawing makes it unique. Pick parts from what is drawn, not the bland defaults (bean body, round head,
   big_round eyes, smile, toy wheels) unless the drawing really shows them.
10. Readable from the race camera: fewer, bigger, well-placed extras beat many tiny ones. Use "mirror": true for pairs.
   The character and the ride should contrast so the rider stands out.
11. ${KIDS_RULES}
12. Set "drawingSticker": true when the vehicle drawing is a flat-sided thing worth showing (karts, boats, rockets),
    never on a chassis.
    Give the ride a "number" only when the child drew one (or, for a sketch, when it is a classic race kart).
13. Bows and ribbons sit where the child drew them; a single big bow is hat "bow". Several small bows are flat
    "bowtie" extras pressed onto the hair (offset 0–0.05 so they touch it), never sticking up like ears.`;

export function designSystemPrompt() {
  return `You are the Racer Designer for BebbiKart, a racing game for children aged 6–10 at a family event.
A child drew their racing CHARACTER (image 1) and their VEHICLE (image 2). Turn them into a 3D toy racer by choosing
parts from a fixed toy kit and writing a RacerSpec JSON. You write a design, not a picture: the game builds the 3D toy
from your spec. The child should instantly say "that's mine!".

${CHECK_RULES}

${LOOK_RULES}

${DESIGN_RULES}

Reply with ONE JSON object and nothing else:
{
  "check": {
    "character": { "ok": bool, "reason": one of ${JSON.stringify(REJECT_REASONS.filter((r) => r !== "unsupported_file"))} or null, "seen": short description },
    "vehicle":   { "ok": bool, "reason": ... or null, "seen": short description }
  },
  "observations": {
    "character": { "what": string, "detail": "sketch"|"detailed", "features": [ { "name": string, "color": "#rrggbb", "count": number, "importance": 1|2|3 } ], "labels": [ { "text": string, "meaning": string, "pointsAt": string } ] },
    "vehicle": same shape
  } (null for an image whose check failed),
  "featureMap": [ { "feature": a feature from your observations (or "touch: …" for an addition to a sketch), "how": which spec fields show it } ],
  "spec": RacerSpec, or null if any check failed,
  "notes": one sentence about the design
}

Use only the part names listed in the kit. Stay inside every range.

=== TOY KIT CATALOG ===
${catalogText()}

=== SCHEMA ===
${schemaText()}

=== WORKED EXAMPLE (from a written description; you will see real drawings) ===
${exampleText()}`;
}

/** The design pass: both drawings in, check + observations + spec out. */
export function buildDesignMessages({
  characterDataUrl,
  vehicleDataUrl,
  approved = false,
  reroll = false,
  previousErrors = null,
}) {
  const ask = [
    "Image 1 = CHARACTER, image 2 = VEHICLE. Check them, look closely, then design the racer. Reply in JSON.",
  ];
  if (approved) {
    ask.push(
      "A grown-up facilitator has already approved both photos: design the racer even if a check looks doubtful.",
    );
  }
  if (reroll) {
    ask.push(
      "The child asked to TRY ANOTHER LOOK: make a clearly different interpretation of the same drawings (other part choices, proportions, patterns, title and tagline) while keeping everything the child drew.",
    );
  }
  if (previousErrors?.length) ask.push(retryText(previousErrors));
  return [
    { role: "system", content: designSystemPrompt() },
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

// --- 2 · review (sees the drawings and the built racer) ------------------------------------------

export function reviewSystemPrompt() {
  return `You are the art director of BebbiKart, a racing game for children aged 6–10. A designer turned a child's two
drawings (image 1 = CHARACTER, image 2 = VEHICLE) into a 3D toy racer spec built from a fixed toy kit. Images 3 and 4
(when given) are renders of the racer that spec builds today, front 3/4 and left side. Compare what you SEE in the
renders with the drawings, find what is wrong, and fix it by editing the spec.

LOYALTY comes first: a "detailed" drawing must be reproduced as closely as the kit allows, and anything on the racer
that the child did not draw (extra spikes, lightning, stars, flags, capes, beams, invented colours) must be removed.
Only a "sketch" may be enhanced. The child's written labels (colour and part names, in any language) are
instructions: check them one by one.

Check, one by one:
- shape: cover the name and look at the renders: does the ride's outline read as the drawn vehicle (a sofa as a
  sofa, a bathtub as a bathtub, a teapot as a teapot)? A kart, boat, rocket or blob in the object's colours with a few
  extras on top is WRONG for an everyday object: rebuild it on base "chassis" (one "set" of the whole "ride" object,
  per CHASSIS BUILDING). On a chassis, check each big part is there, the right size and in its place, and the driver
  sits in or on it, visible.
- likeness: is every defining feature there, with the right count, colour, size and place? What's missing or wrong?
- colour: does the palette match the crayons and labels? Are the main colours on the right parts? The ride's
  "accent" paints bumpers, seat back and trim, a big part of a kart: if the drawn vehicle is mostly one colour, the
  accent must be that colour or a shade of it. Uncoloured parts keep their natural reading (white stays white,
  pencil grey stays grey).
- proportions and readability: exaggerations kept? Extras big enough to see, placed where the drawing has them
  (ears on the head side, horns on top), not floating, buried or hiding the driver? A side-view drawing shows one
  side only: two drawn wheels on a car mean four wheels.
- additions: anything on the racer that is not in the drawing; on a detailed drawing remove each one.
- names: the title and tagline must plainly describe what is drawn. Flag jokes, themes or stories the drawing does not
  show, and remove anything on the racer that was added to fit the name (moons for a "moon" name, flames for "blaze").
- personality: do face, motion and sound fit the drawing?

Then write a PATCH: the smallest set of edits that fixes every real problem. Keep what already works. Ops:
  { "op": "set", "path": "character.hair.style", "value": "very_long" }     replace a value (any depth; whole objects too)
  { "op": "set", "path": "ride.extras.2.scale", "value": [0.3, 0.3, 0.1] }  array items by index
  { "op": "remove", "path": "ride.extras.4" }                               delete an array item or an optional field
  { "op": "add", "path": "character.extras", "value": { ...extra... } }    append to an array
Indices always refer to the spec as you were given it. An empty patch is fine when the racer already matches.

Reply with ONE JSON object and nothing else:
{
  "scores": { "likeness": 1-10, "colour": 1-10, "personality": 1-10, "readability": 1-10, "loyalty": 1-10 },
  "issues": [ { "severity": "must"|"should"|"could", "problem": string } ],
  "patch": [ op, ... ],
  "notes": one sentence
}

${DESIGN_RULES}

=== TOY KIT CATALOG ===
${catalogText()}

=== SCHEMA ===
${schemaText()}`;
}

/** The review pass: drawings + renders + the design in, issues + patch out. */
export function buildReviewMessages({
  characterDataUrl,
  vehicleDataUrl,
  design,
  renders = null,
  previousErrors = null,
}) {
  const built = renders
    ? [
        { type: "text", text: "Image 3: the 3D toy racer this spec builds, front 3/4 view." },
        { type: "image_url", image_url: { url: renders.front } },
        { type: "text", text: "Image 4: the same racer from its left side." },
        { type: "image_url", image_url: { url: renders.side } },
      ]
    : [];
  const ask = [
    "The designer's observations, featureMap and spec:",
    JSON.stringify(design),
    "Review the racer against the drawings and reply with the JSON (scores, issues, patch, notes).",
  ];
  if (previousErrors?.length) ask.push(retryText(previousErrors));
  return [
    { role: "system", content: reviewSystemPrompt() },
    {
      role: "user",
      content: [
        { type: "text", text: "Image 1: CHARACTER drawing" },
        { type: "image_url", image_url: { url: characterDataUrl } },
        { type: "text", text: "Image 2: VEHICLE drawing" },
        { type: "image_url", image_url: { url: vehicleDataUrl } },
        ...built,
        { type: "text", text: ask.join("\n\n") },
      ],
    },
  ];
}

function retryText(errors) {
  return `Your previous reply did not pass validation. Fix these problems and reply with the full JSON again:\n- ${errors.slice(0, 20).join("\n- ")}`;
}

// --- worked example --------------------------------------------------------------------------

const ex = (shape, socket, color, offset, scale, rotationDeg = [0, 0, 0], mirror) => ({
  shape,
  socket,
  offset,
  scale,
  rotationDeg,
  color,
  ...(mirror ? { mirror: true } : {}),
});

/** Worked examples: short description of the two drawings → full design reply. Shown to the model. */
export const EXAMPLES = [
  {
    description:
      "Character: an orange tiger with thick black scribbled stripes, a huge grin, small round ears and a blue cap worn backwards. Vehicle: a green go-kart with enormous black wheels, a yellow lightning bolt on the side and a big number 3.",
    reply: {
      featureMap: [
        {
          feature: "orange tiger body with black stripes",
          how: "body round orange + stripes pattern in black",
        },
        { feature: "huge grin", how: "mouth grin, head.size 1.35" },
        { feature: "small round ears", how: "mirrored spheres on head_side" },
        { feature: "blue cap", how: "hat cap in blue" },
        { feature: "green kart", how: "ride kart, main green, crayon pattern in a darker green" },
        { feature: "enormous wheels", how: "monster wheels size 1.6" },
        { feature: "lightning bolt on the side", how: "mirrored yellow lightning on ride_side" },
        { feature: "number 3", how: "ride.number 3 in yellow" },
      ],
      spec: {
        specVersion: 1,
        palette: ["#ff8a1f", "#1f1f1f", "#2f6fe0", "#3fbf4a", "#ffd23f", "#2a8a35"],
        motion: { style: "bouncy", energy: 1.2 },
        sound: { engine: "vroom", pitch: 1.0, horn: "roar" },
        character: {
          body: {
            shape: "round",
            color: 0,
            scale: [1, 1, 1],
            pattern: { type: "stripes", color: 1, scale: 1.2 },
          },
          head: {
            shape: "wide",
            color: 0,
            size: 1.35,
            pattern: { type: "stripes", color: 1, scale: 1.2 },
          },
          face: { eyes: "big_round", eyeColor: "#1f1f1f", mouth: "grin", brows: true },
          hat: { type: "cap", color: 2 },
          arms: { color: 0 },
          extras: [
            ex("sphere", "head_side", 0, [0.02, 0.12, 0], [0.28, 0.28, 0.16], [0, 0, 0], true),
          ],
        },
        ride: {
          base: "kart",
          color: 3,
          accent: 4,
          scale: [1.05, 1, 1],
          pattern: { type: "crayon", color: 5, scale: 1 },
          number: { value: 3, color: 4 },
          wheels: { count: 4, style: "monster", color: 1, size: 1.6 },
          extras: [
            ex("lightning", "ride_side", 4, [0, 0.05, 0.1], [0.45, 0.45, 0.1], [0, 90, 0], true),
          ],
          drawingSticker: false,
        },
        personality: ["brave", "cheeky"],
        title: "Striped Tiger",
        tagline: "Orange striped tiger in a green kart with giant wheels",
      },
      notes:
        "Stripes on body and head make the tiger read instantly; monster wheels keep the child's giant wheels.",
    },
  },
  {
    description:
      "Character: a grey mouse with big round pink ears and a pink nose. Vehicle: drawn from the side, a brown wooden barrel lying on its side on four small black wheels, two black hoops round it, a red tap at the back end and two grey puffs of smoke behind.",
    reply: {
      featureMap: [
        {
          feature: "vehicle shape: a barrel lying along the ride, drawn from the side",
          how: "base chassis; a long brown cylinder on ride_center turned forward, its top 0.8 m up so the mouse sits in it",
        },
        { feature: "two black hoops", how: "two black tori stood up round the barrel" },
        { feature: "red tap at the back end", how: "small red capsule pointing backwards" },
        { feature: "four small black wheels", how: "wheels toy, size 0.9, black" },
        { feature: "two grey puffs of smoke", how: "two grey clouds on ride_back" },
        {
          feature: "grey mouse, big round pink ears",
          how: "round grey body and head, pink spheres on head_side",
        },
        { feature: "pink nose", how: "pink sphere on head_front" },
      ],
      spec: {
        specVersion: 1,
        palette: ["#a0662f", "#2b2b2b", "#d94040", "#b8b8c0", "#9a9aa6", "#ff9fb8"],
        motion: { style: "wobbly", energy: 0.9 },
        sound: { engine: "putter", pitch: 1.2, horn: "squeak" },
        character: {
          body: { shape: "round", color: 4, scale: [1, 1, 1] },
          head: { shape: "round", color: 4, size: 1.1 },
          face: { eyes: "dots", eyeColor: "#2b2b2b", mouth: "smile", brows: false },
          arms: { color: 4 },
          extras: [
            ex("sphere", "head_side", 5, [0.02, 0.1, 0], [0.4, 0.4, 0.12], [0, 0, -15], true),
            ex("sphere", "head_front", 5, [0, -0.02, 0], [0.14, 0.12, 0.12]),
          ],
        },
        ride: {
          base: "chassis",
          color: 0,
          accent: 1,
          scale: [1, 1, 1],
          finish: "matte",
          wheels: { count: 4, style: "toy", color: 1, size: 0.9 },
          extras: [
            ex("cylinder", "ride_center", 0, [0, 0.3, -0.7], [0.62, 1.4, 0.62], [90, 0, 0]),
            ex("torus", "ride_center", 1, [0, 0.3, 0.42], [0.66, 0.66, 0.66], [90, 0, 0]),
            ex("torus", "ride_center", 1, [0, 0.3, -0.42], [0.66, 0.66, 0.66], [90, 0, 0]),
            ex("capsule", "ride_center", 2, [0, 0.3, -0.72], [0.07, 0.14, 0.07], [-90, 0, 0]),
            ex("cloud", "ride_back", 3, [0.12, 0.1, -0.2], [0.26, 0.18, 0.1]),
            ex("cloud", "ride_back", 3, [0.25, 0.25, -0.35], [0.16, 0.12, 0.1]),
          ],
          drawingSticker: false,
        },
        personality: ["curious", "cheerful"],
        title: "Barrel Mouse",
        tagline: "Grey mouse riding a brown barrel with black hoops",
      },
      notes:
        "The barrel is built on a bare chassis so it reads as a barrel, with the mouse sitting in its top.",
    },
  },
];

function exampleText() {
  return EXAMPLES.map(
    (e, i) => `Example ${i + 1}. ${e.description}\nReply:\n${JSON.stringify(e.reply)}`,
  ).join("\n\n");
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
