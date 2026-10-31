// --mock mode: a stand-in for DeepSeek that returns hand-written replies for the sample drawings.
// Replies go through the same parse → check → clamp path as real ones, so the Racer Viewer gets
// realistic input without an API key. pair05 deliberately contains typical model mistakes
// (wrong part spellings, out-of-range numbers) to show the repair step.
import { basename, extname } from "node:path";

const x = (shape, socket, color, offset, scale, rotationDeg = [0, 0, 0], mirror = false) => ({
  shape,
  socket,
  offset,
  scale: scale.map((v) => Math.max(0.1, v)), // kit minimum; thin parts like antennae end up 0.1 thick
  rotationDeg,
  color,
  ...(mirror ? { mirror: true } : {}),
});

const ok = (seen) => ({ ok: true, reason: null, seen });

/** Per-file check results for the tricky samples; every other file passes. */
export const MOCK_CHECKS = {
  "tricky-photo-gokart": {
    ok: false,
    reason: "not_a_drawing",
    seen: "a photo of a real go-kart on a race track",
  },
  "tricky-photo-boy-toy-car": {
    ok: false,
    reason: "real_person",
    seen: "an old photo of a real child in a toy car",
  },
  "tricky-blank-page": {
    ok: false,
    reason: "empty_page",
    seen: "a blank sheet of paper with one tiny pencil mark",
  },
};

/** Hand-written designs, keyed by design id. */
export const MOCK_DESIGNS = {
  pair01: {
    seen: [
      "purple cat with pink ears, whiskers and an orange collar",
      "red kart with flames, a number 1 and a sun",
    ],
    notes: "Cat ears and tail as extras, flames as twin exhaust cones, kart in the drawing's red.",
    spec: {
      specVersion: 1,
      title: "The Purple Flash",
      personality: ["cheeky", "speedy"],
      palette: ["#7b3fb8", "#d92b2b", "#f07a1a", "#ef6fa8", "#222222"],
      character: {
        body: { shape: "pear", color: 0, scale: [1, 1, 1] },
        head: { shape: "wide", color: 0, size: 1.25 },
        face: { eyes: "big_round", eyeColor: "#222222", mouth: "smile", brows: false, cheeks: 3 },
        arms: { color: 0 },
        extras: [
          x("cone", "head_side", 0, [0.05, 0.15, 0], [0.3, 0.35, 0.25], [0, 0, -15], true),
          x("cone", "head_side", 3, [0.05, 0.14, 0.03], [0.18, 0.22, 0.1], [0, 0, -15], true),
          x("cylinder", "head_front", 4, [0.1, -0.02, 0.1], [0.02, 0.4, 0.02], [0, 0, 80], true),
          x("torus", "body_front", 2, [0, 0.18, 0], [0.6, 0.15, 0.6]),
          x("capsule", "body_back", 0, [0, -0.1, -0.2], [0.12, 0.6, 0.12], [-40, 0, 0]),
        ],
      },
      ride: {
        base: "kart",
        color: 1,
        accent: 2,
        scale: [1.1, 1, 1.1],
        wheels: { count: 4, style: "toy", color: 4, size: 1.3 },
        tail: { style: "flame", color: 2 },
        extras: [
          x("cylinder", "ride_back", 4, [0.15, 0.1, -0.2], [0.12, 0.3, 0.12], [90, 0, 0], true),
          x("cone", "ride_back", 2, [0.15, 0.1, -0.4], [0.2, 0.5, 0.2], [-90, 0, 0], true),
          x("torus", "ride_front", 4, [0, 0.3, 0], [0.3, 0.3, 0.05], [60, 0, 0]),
        ],
        drawingSticker: true,
      },
    },
  },

  pair02: {
    seen: [
      "boxy blue robot with an antenna, green eyes and coloured buttons",
      "green sneaker with rocket flames and red fins",
    ],
    notes:
      "Box robot with a red antenna ball; the rocket shoe is a rocket base with a shoe sole and laces.",
    spec: {
      specVersion: 1,
      title: "Bolt-Bot Rocket",
      personality: ["clever", "zoomy"],
      palette: ["#5bb8f0", "#8a8f98", "#2463c9", "#8bc63f", "#d92b2b"],
      character: {
        body: { shape: "box", color: 1, scale: [1.1, 1.1, 1] },
        head: { shape: "square", color: 0, size: 1.1 },
        face: { eyes: "big_round", eyeColor: "#2f9e44", mouth: "grin", brows: false },
        arms: { color: 2 },
        extras: [
          x("cylinder", "head_top", 1, [0, 0.15, 0], [0.05, 0.4, 0.05]),
          x("sphere", "head_top", 4, [0, 0.3, 0], [0.15, 0.15, 0.15]),
          x("sphere", "body_front", 4, [0, 0.12, 0.1], [0.12, 0.12, 0.06]),
          x("sphere", "body_front", 3, [0, -0.02, 0.1], [0.12, 0.12, 0.06]),
        ],
      },
      ride: {
        base: "rocket",
        color: 3,
        accent: 4,
        scale: [1.2, 0.9, 1.3],
        tail: { style: "flame", color: 4 },
        extras: [
          x("cone", "ride_side", 4, [0, 0.15, -0.2], [0.25, 0.4, 0.08], [0, 0, 30], true),
          x("box", "ride_bottom", 2, [0, -0.1, 0], [1.6, 0.12, 1.9]),
          x("cylinder", "ride_top", 1, [0, 0.1, 0.05], [0.03, 0.3, 0.03], [0, 0, 90]),
          x("cylinder", "ride_top", 1, [0, 0.12, 0.15], [0.03, 0.3, 0.03], [0, 0, 90]),
          x("cylinder", "ride_top", 1, [0, 0.14, 0.25], [0.03, 0.3, 0.03], [0, 0, 90]),
        ],
        drawingSticker: true,
      },
    },
  },

  pair03: {
    seen: [
      "green three-horned dinosaur with red back spikes and blue spots",
      "yellow bicycle with a basket of flowers",
    ],
    notes:
      "Triceratops horns and back spikes as cones, belly and spots as spheres; flower basket on the bike.",
    spec: {
      specVersion: 1,
      title: "Trike Spike",
      personality: ["friendly", "stompy"],
      palette: ["#2f9e44", "#f5c518", "#d92b2b", "#f07a1a", "#2463c9"],
      character: {
        body: { shape: "round", color: 0, scale: [1.2, 1, 1.2] },
        head: { shape: "wide", color: 0, size: 1.2 },
        face: { eyes: "dots", eyeColor: "#222222", mouth: "smile", brows: true },
        arms: { color: 0 },
        extras: [
          x("cone", "head_top", 3, [0, 0.2, 0.1], [0.12, 0.4, 0.12], [20, 0, 0]),
          x("cone", "head_top", 3, [0.12, 0.15, 0.05], [0.1, 0.3, 0.1], [10, 0, -25], true),
          x("cone", "body_back", 2, [0, 0.15, -0.1], [0.18, 0.35, 0.18], [-30, 0, 0]),
          x("cone", "body_back", 2, [0, -0.05, -0.15], [0.16, 0.3, 0.16], [-50, 0, 0]),
          x("sphere", "body_front", 1, [0, -0.05, 0.05], [0.6, 0.6, 0.3]),
          x("sphere", "body_front", 4, [0.15, 0.1, 0.08], [0.12, 0.12, 0.06], [0, 0, 0], true),
        ],
      },
      ride: {
        base: "bike",
        color: 1,
        accent: 0,
        scale: [1, 1, 1],
        wheels: { count: 2, style: "spoked", color: 4, size: 1.3 },
        extras: [
          x("box", "ride_front", 3, [0, 0.2, 0.3], [0.4, 0.3, 0.3]),
          x("star", "ride_front", 2, [0, 0.4, 0.3], [0.2, 0.2, 0.05]),
        ],
        drawingSticker: false,
      },
    },
  },

  pair04: {
    seen: [
      "girl with long orange hair, a golden crown and a pink dress",
      "brown horse with a rainbow mane and a saddle",
    ],
    notes: "Crown hat with a jewel; the horse is animal4 with hooves and a three-colour mane.",
    spec: {
      specVersion: 1,
      title: "Queen Rainbow",
      personality: ["royal", "kind"],
      palette: ["#ef6fa8", "#f07a1a", "#f5c518", "#8a5a2b", "#f6c9a3"],
      character: {
        body: { shape: "pear", color: 0, scale: [1.1, 1, 1] },
        head: { shape: "round", color: 4, size: 1.15 },
        face: { eyes: "big_round", eyeColor: "#2463c9", mouth: "smile", brows: true, cheeks: 0 },
        hair: { style: "long", color: 1 },
        hat: { type: "crown", color: 2 },
        arms: { color: 4 },
        extras: [
          x("sphere", "head_top", 0, [0, 0.25, 0.1], [0.1, 0.1, 0.1]),
          x("sphere", "body_front", 2, [0.1, 0, 0.1], [0.08, 0.08, 0.04], [0, 0, 0], true),
        ],
      },
      ride: {
        base: "animal4",
        color: 3,
        accent: 0,
        scale: [1, 1, 1.1],
        legs: { style: "hooves", color: 3 },
        tail: { style: "fluffy", color: 0 },
        extras: [
          x("capsule", "ride_top", 0, [0, 0.3, 0.25], [0.08, 0.35, 0.08], [-20, 0, 0]),
          x("capsule", "ride_top", 1, [0, 0.3, 0.15], [0.08, 0.35, 0.08], [-20, 0, 0]),
          x("capsule", "ride_top", 2, [0, 0.3, 0.05], [0.08, 0.35, 0.08], [-20, 0, 0]),
          x("box", "ride_top", 0, [0, 0.1, 0], [0.6, 0.1, 0.6]),
          x("cone", "ride_front", 3, [0.08, 0.35, 0.35], [0.08, 0.18, 0.08], [0, 0, 0], true),
        ],
        drawingSticker: false,
      },
    },
  },

  // Deliberately imperfect, like a real model reply: part spellings and ranges get repaired.
  pair05: {
    seen: [
      "lime one-eyed alien with antennae and a toothy grin",
      "red dragon with orange wings and yellow spikes",
    ],
    notes: "One big eye and antennae; the dragon flies on bat wings with a dino tail.",
    spec: {
      specVersion: 1,
      title: "Zorp the Dragon Rider!!",
      personality: ["silly", "fearless"],
      palette: ["#8bc63f", "#7b3fb8", "#d92b2b", "#f07a1a", "#f5c518"],
      character: {
        body: { shape: "round", color: 0, scale: [1.1, 1.2, 1.1] },
        head: { shape: "drop", color: 0, size: 1.8 },
        face: { eyes: "one-eye", eyeColor: "#7b3fb8", mouth: "big grin", brows: false },
        arms: { color: 0 },
        extras: [
          x("cylinder", "head_top", 0, [0.12, 0.2, 0], [0.04, 0.4, 0.04], [0, 0, -25], true),
          x("sphere", "head_top", 1, [0.2, 0.42, 0], [0.12, 0.12, 0.12], [0, 0, 0], true),
          x("sphere", "body_front", 4, [0.1, -0.05, 0.1], [0.1, 0.1, 0.05], [0, 0, 0], true),
        ],
      },
      ride: {
        base: "bird",
        color: 2,
        accent: 3,
        scale: [1.1, 1, 1.2],
        legs: { style: "claw", color: 2 },
        wings: { style: "bat", color: 3, size: 2.4 },
        tail: { style: "dino", color: 2 },
        extras: [
          x("cone", "ride_top", 4, [0, 0.25, -0.2], [0.12, 0.25, 0.12]),
          x("cone", "ride_top", 4, [0, 0.27, 0], [0.12, 0.25, 0.12]),
          x("cone", "ride_top", 4, [0, 0.25, 0.2], [0.12, 0.25, 0.12]),
          x("cone", "ride_front", 4, [0.1, 0.35, 0.5], [0.08, 0.2, 0.08], [0, 0, 0], true),
        ],
        drawingSticker: false,
      },
    },
  },

  pair06: {
    seen: [
      "blue blob monster with big eyes, one tooth and stars around it",
      "brown sailing boat with portholes on blue waves",
    ],
    notes:
      "Googly-eyed blob with a fang smile; a boat on small wheels with a mast, sail and portholes.",
    spec: {
      specVersion: 1,
      title: "Captain Wobble",
      personality: ["goofy", "happy"],
      palette: ["#5bb8f0", "#2463c9", "#8a5a2b", "#d92b2b", "#f5c518"],
      character: {
        body: { shape: "round", color: 0, scale: [1.2, 1.1, 1.1] },
        head: { shape: "wide", color: 0, size: 1 },
        face: { eyes: "googly", eyeColor: "#222222", mouth: "fangs", brows: false },
        arms: { color: 1 },
        extras: [
          x("cone", "head_top", 1, [0, 0.2, 0], [0.12, 0.25, 0.12]),
          x("star", "head_side", 4, [0.15, 0.15, 0], [0.15, 0.15, 0.05], [0, 0, 0], true),
        ],
      },
      ride: {
        base: "boat",
        color: 2,
        accent: 3,
        scale: [1.1, 1, 1.2],
        wheels: { count: 4, style: "toy", color: 1, size: 0.8 },
        extras: [
          x("cylinder", "ride_top", 2, [0, 0.4, 0], [0.06, 1.6, 0.06]),
          x("box", "ride_top", 4, [0.05, 0.4, 0.05], [0.04, 1.2, 0.8]),
          x("box", "ride_top", 3, [0, 0.4, -0.1], [0.04, 0.2, 0.3]),
          x("torus", "ride_side", 1, [0, 0, 0.1], [0.15, 0.15, 0.05], [0, 90, 0], true),
        ],
        drawingSticker: true,
      },
    },
  },

  board: {
    seen: [
      "kid with black hair and a green shirt on a skateboard",
      "orange skateboard with speed lines (same sheet)",
    ],
    notes: "Same sheet for both: rider becomes the character, the skateboard becomes a board ride.",
    spec: {
      specVersion: 1,
      title: "Sk8 Sam",
      personality: ["cool", "quick"],
      palette: ["#2f9e44", "#f07a1a", "#2463c9", "#f6c9a3", "#222222"],
      character: {
        body: { shape: "tall", color: 0, scale: [1, 1.1, 1] },
        head: { shape: "round", color: 3, size: 1.2 },
        face: { eyes: "dots", eyeColor: "#222222", mouth: "smile", brows: false },
        hair: { style: "spiky", color: 4 },
        arms: { color: 3 },
        extras: [x("cone", "body_front", 1, [0, 0.05, 0.1], [0.2, 0.2, 0.05], [180, 0, 0])],
      },
      ride: {
        base: "board",
        color: 1,
        accent: 3,
        scale: [1, 1, 1.1],
        wheels: { count: 4, style: "toy", color: 4, size: 0.7 },
        extras: [],
        drawingSticker: true,
      },
    },
  },

  pd: {
    seen: [
      "red-pencil sketches of a deer, an eagle and a face",
      "pencil sketch of riders racing horses",
    ],
    notes:
      "Sparse old pencil drawings: the face becomes the character with deer antlers; the race horse is animal4.",
    spec: {
      specVersion: 1,
      title: "Pencil Prince",
      personality: ["noble", "calm"],
      palette: ["#c0392b", "#7a6a58", "#f4e9d8", "#2b2b2b"],
      character: {
        body: { shape: "tall", color: 1, scale: [1, 1.1, 1] },
        head: { shape: "oval", color: 2, size: 1.1 },
        face: { eyes: "dots", eyeColor: "#2b2b2b", mouth: "smile", brows: true },
        hat: { type: "tophat", color: 3 },
        arms: { color: 1 },
        extras: [
          x("cylinder", "head_top", 0, [0.12, 0.2, 0], [0.04, 0.35, 0.04], [0, 0, -30], true),
        ],
      },
      ride: {
        base: "animal4",
        color: 1,
        accent: 0,
        scale: [1, 1, 1.1],
        legs: { style: "hooves", color: 1 },
        tail: { style: "fluffy", color: 3 },
        extras: [x("box", "ride_top", 0, [0, 0.1, 0], [0.6, 0.1, 0.6])],
        drawingSticker: true,
      },
    },
  },

  scribble: {
    seen: ["a wild multicolour scribble", "pencil sketch of a chamois (mountain goat)"],
    notes:
      "The scribble becomes a playful abstract creature in its crayon colours; the chamois is animal4 with little horns.",
    spec: {
      specVersion: 1,
      title: "Scribble Zoom",
      personality: ["wild", "bouncy"],
      palette: ["#d92b2b", "#2463c9", "#2f9e44", "#f07a1a", "#7b3fb8"],
      character: {
        body: { shape: "star", color: 4, scale: [1, 1, 1] },
        head: { shape: "round", color: 3, size: 1.1 },
        face: { eyes: "googly", eyeColor: "#222222", mouth: "open", brows: false },
        hair: { style: "curly", color: 0 },
        arms: { color: 1 },
        extras: [x("torus", "body_front", 2, [0, 0, 0.1], [0.4, 0.4, 0.1], [0, 0, 30])],
      },
      ride: {
        base: "animal4",
        color: 1,
        accent: 3,
        scale: [0.9, 1, 1],
        legs: { style: "hooves", color: 1 },
        tail: { style: "fluffy", color: 3 },
        extras: [
          x("cone", "ride_front", 3, [0.08, 0.35, 0.35], [0.06, 0.2, 0.06], [-20, 0, 0], true),
        ],
        drawingSticker: false,
      },
    },
  },
};

/** Sample runs for `design --samples`: [name, character file, vehicle file] (relative to samples/). */
export const SAMPLE_RUNS = [
  ["pair01-cat-kart", "pair01-character-cat.jpg", "pair01-vehicle-kart.jpg"],
  ["pair02-robot-rocket-shoe", "pair02-character-robot.jpg", "pair02-vehicle-rocket-shoe.jpg"],
  ["pair03-dino-bike", "pair03-character-dino.jpg", "pair03-vehicle-bike.jpg"],
  ["pair04-girl-horse", "pair04-character-girl-crown.jpg", "pair04-vehicle-horse.jpg"],
  ["pair05-alien-dragon", "pair05-character-alien.jpg", "pair05-vehicle-dragon.jpg"],
  ["pair06-blob-boat", "pair06-character-blob-monster.jpg", "pair06-vehicle-boat.jpg"],
  ["board-one-sheet", "tricky-both-on-one-page.jpg", "tricky-both-on-one-page.jpg"],
  ["pd-prince-horse", "pd-rudolf-deer-eagle-face.jpg", "pd-franzjoseph-1842-horse-race.jpg"],
  ["scribble-chamois", "tricky-scribble.jpg", "pd-rudolf-chamois.jpg"],
  ["reject-photo-kart", "pair01-character-cat.jpg", "tricky-photo-gokart.jpg"],
  ["reject-real-person", "tricky-photo-boy-toy-car.jpg", "pair02-vehicle-rocket-shoe.jpg"],
  ["reject-blank-page", "tricky-blank-page.jpg", "pair06-vehicle-boat.jpg"],
];

const VEHICLE_DESIGNS = {
  "tricky-both-on-one-page": "board",
  "pd-franzjoseph-1842-horse-race": "pd",
  "pd-rudolf-chamois": "scribble",
};

const stem = (p) => basename(p, extname(p));

/** Which hand-written design fits these two files, if any. */
export function mockDesignId(characterPath, vehiclePath) {
  for (const p of [vehiclePath, characterPath]) {
    const m = stem(p).match(/^(pair\d\d)-/);
    if (m && MOCK_DESIGNS[m[1]]) return m[1];
  }
  return VEHICLE_DESIGNS[stem(vehiclePath)] ?? null;
}

/**
 * Mock DesignClient. Unknown drawings get `spec: null`, so the job falls back to the default
 * racer in the drawing's colours, the same as a broken real reply would.
 */
export function createMockClient() {
  return {
    name: "mock",
    async complete(_messages, _opts, ctx) {
      const id = mockDesignId(ctx.characterPath, ctx.vehiclePath);
      const design = id ? MOCK_DESIGNS[id] : null;
      const check = {};
      for (const [kind, path, i] of [
        ["character", ctx.characterPath, 0],
        ["vehicle", ctx.vehiclePath, 1],
      ]) {
        check[kind] =
          MOCK_CHECKS[stem(path)] ?? ok(design?.seen[i] ?? "a drawing (mock: no description)");
      }
      const failed = Object.values(check).some((c) => !c.ok);
      let spec = failed || !design ? null : structuredClone(design.spec);
      if (spec && ctx.reroll) spec = rerollVariant(spec);
      return JSON.stringify({
        check,
        spec,
        notes: design?.notes ?? "mock has no hand-written design for these files",
      });
    },
  };
}

/** A visibly different take for "try another look" in mock mode. */
function rerollVariant(spec) {
  const s = spec;
  [s.ride.color, s.ride.accent] = [s.ride.accent, s.ride.color];
  s.ride.scale = s.ride.scale.map((v, i) => (i === 1 ? v * 0.9 : v * 1.1));
  s.character.head.size = Math.min(1.5, s.character.head.size + 0.15);
  s.title = `${s.title.slice(0, 20)} II`;
  return s;
}
