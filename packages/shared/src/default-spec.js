// The default racer (pkg_default), shipped with the game, for anyone without a valid spec yet.

const extra = (shape, socket, color, opts = {}) => ({
  shape,
  socket,
  offset: opts.offset ?? [0, 0, 0],
  scale: opts.scale ?? [0.3, 0.3, 0.3],
  rotationDeg: opts.rotationDeg ?? [0, 0, 0],
  color,
});

export const DEFAULT_SPEC = {
  specVersion: 1,
  title: "Speedy Bean",
  personality: ["cheerful", "speedy"],
  palette: ["#ff6b35", "#ffd23f", "#3bceac", "#2b2140"],
  character: {
    body: { shape: "bean", color: 0, scale: [1, 1, 1] },
    head: { shape: "round", color: 1, size: 1 },
    face: { eyes: "big_round", eyeColor: "#2b2140", mouth: "smile", brows: true, cheeks: 0 },
    hat: { type: "helmet", color: 2 },
    arms: { color: 0 },
    extras: [],
  },
  ride: {
    base: "kart",
    color: 2,
    accent: 1,
    scale: [1, 1, 1],
    wheels: { count: 4, style: "toy", color: 3, size: 1 },
    extras: [extra("cylinder", "ride_back", 3, { offset: [0, 0.1, -0.2], scale: [0.2, 0.4, 0.2] })],
    drawingSticker: false,
  },
};
