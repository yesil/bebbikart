// Kit catalog: every toy part the Godot game can build (contracts.md §5, WS5 §3).
// WS3 keeps this in sync with the parts in apps/game; WS5 puts it in the DeepSeek prompt.
// Adding a part = model it in Godot + add one line here + `bun run kit:export`.

/** @typedef {{ name: string, desc: string }} KitPart */
/** @typedef {{ name: string, desc: string, on: "character" | "ride", maxOffset: number }} KitSocket */

export const RACER_KIT = Object.freeze({
  kitVersion: 1,
  bodyShapes: [
    { name: "bean", desc: "soft jelly-bean body, the default" },
    { name: "round", desc: "chubby ball body" },
    { name: "tall", desc: "tall, thin body" },
    { name: "box", desc: "square toy-block body, robots" },
    { name: "pear", desc: "small top, wide bottom" },
    { name: "star", desc: "chunky five-point star body" },
  ],
  headShapes: [
    { name: "round", desc: "ball head, the default" },
    { name: "oval", desc: "egg-shaped head" },
    { name: "square", desc: "rounded cube head, robots" },
    { name: "wide", desc: "wide, flat head, frogs and monsters" },
    { name: "drop", desc: "teardrop head, pointed top" },
  ],
  eyes: [
    { name: "dots", desc: "two small black dots" },
    { name: "big_round", desc: "big shiny cartoon eyes" },
    { name: "sleepy", desc: "half-closed eyes" },
    { name: "googly", desc: "wobbly googly eyes" },
    { name: "one_eye", desc: "a single big eye in the middle" },
    { name: "visor", desc: "robot visor strip" },
  ],
  mouths: [
    { name: "smile", desc: "simple smile" },
    { name: "grin", desc: "big toothy grin" },
    { name: "open", desc: "open 'wow' mouth" },
    { name: "fangs", desc: "smile with two little fangs" },
    { name: "beak", desc: "bird beak" },
    { name: "none", desc: "no mouth drawn" },
  ],
  hairStyles: [
    { name: "spiky", desc: "spiky cartoon hair" },
    { name: "curly", desc: "curly mop" },
    { name: "long", desc: "long straight hair" },
    { name: "ponytail", desc: "ponytail" },
    { name: "mohawk", desc: "mohawk stripe" },
    { name: "tuft", desc: "single tuft on top" },
  ],
  hatTypes: [
    { name: "cap", desc: "baseball cap" },
    { name: "crown", desc: "king or queen crown" },
    { name: "helmet", desc: "racing helmet" },
    { name: "wizard", desc: "pointy wizard hat" },
    { name: "beanie", desc: "woolly beanie" },
    { name: "tophat", desc: "tall top hat" },
    { name: "bow", desc: "big hair bow" },
    { name: "party", desc: "party cone hat" },
  ],
  rideBases: [
    { name: "kart", desc: "go-kart, anything with a seat and wheels" },
    { name: "bike", desc: "bicycle, scooter or motorbike" },
    { name: "animal4", desc: "four-legged animal: horse, dog, dinosaur" },
    { name: "bird", desc: "big bird or flying creature" },
    { name: "board", desc: "skateboard, surfboard, magic carpet" },
    { name: "rocket", desc: "rocket, plane, spaceship" },
    { name: "boat", desc: "boat or bathtub on wheels" },
    { name: "blob", desc: "anything else: a slime, a cloud, a shoe" },
  ],
  wheelStyles: [
    { name: "toy", desc: "chunky toy wheels" },
    { name: "spoked", desc: "thin bicycle wheels" },
    { name: "monster", desc: "huge monster-truck wheels" },
    { name: "donut", desc: "wheels that look like donuts" },
  ],
  legStyles: [
    { name: "hooves", desc: "horse legs with hooves" },
    { name: "paws", desc: "soft animal paws" },
    { name: "claws", desc: "dinosaur feet" },
    { name: "stumpy", desc: "short round toy legs" },
  ],
  wingStyles: [
    { name: "feather", desc: "bird wings" },
    { name: "bat", desc: "bat or dragon wings" },
    { name: "fairy", desc: "see-through fairy wings" },
    { name: "plane", desc: "stiff aeroplane wings" },
  ],
  tailStyles: [
    { name: "fluffy", desc: "fluffy tail" },
    { name: "dino", desc: "thick dinosaur tail" },
    { name: "flame", desc: "rocket flame" },
    { name: "feathers", desc: "fan of tail feathers" },
  ],
  extraShapes: ["sphere", "capsule", "box", "cone", "cylinder", "torus", "star", "heart"],
  sockets: [
    { name: "head_top", desc: "top of the head: horns, antennae", on: "character", maxOffset: 0.3 },
    { name: "head_side", desc: "side of the head: ears", on: "character", maxOffset: 0.2 },
    { name: "head_front", desc: "face: nose, glasses", on: "character", maxOffset: 0.15 },
    { name: "body_front", desc: "chest: badges, logos", on: "character", maxOffset: 0.2 },
    {
      name: "body_back",
      desc: "back: capes, backpacks, jetpacks",
      on: "character",
      maxOffset: 0.25,
    },
    { name: "hand", desc: "in the hand: wand, flag, ice cream", on: "character", maxOffset: 0.2 },
    { name: "ride_front", desc: "front of the ride: horns, lights", on: "ride", maxOffset: 0.4 },
    { name: "ride_back", desc: "back of the ride: spoilers, exhausts", on: "ride", maxOffset: 0.4 },
    { name: "ride_side", desc: "sides of the ride: fins, stripes", on: "ride", maxOffset: 0.35 },
    { name: "ride_top", desc: "on top of the ride: flags, propellers", on: "ride", maxOffset: 0.4 },
    { name: "ride_bottom", desc: "under the ride: skids, flames", on: "ride", maxOffset: 0.3 },
  ],
});

/** @param {KitPart[]} parts */
export const partNames = (parts) => parts.map((p) => p.name);

export const CHARACTER_SOCKETS = RACER_KIT.sockets.filter((s) => s.on === "character");
export const RIDE_SOCKETS = RACER_KIT.sockets.filter((s) => s.on === "ride");

/** Number ranges the RacerSpec clamps to. */
export const SPEC_LIMITS = Object.freeze({
  titleMax: 24,
  bodyScale: [0.6, 1.4],
  headSize: [0.6, 1.5],
  rideScale: [0.6, 1.4],
  wheelSize: [0.5, 2.0],
  wingSize: [0.5, 2.0],
  extraScale: [0.1, 2.0],
  extraRotationDeg: [-180, 180],
  characterExtrasMax: 6,
  rideExtrasMax: 8,
  paletteMin: 3,
  paletteMax: 5,
  personalityMin: 2,
  personalityMax: 3,
});
