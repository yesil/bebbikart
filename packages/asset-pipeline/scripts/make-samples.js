#!/usr/bin/env bun
// Generates the hand-made "kid drawing" samples in samples/ (crayon / marker on paper,
// photographed on a table). Deterministic: same seed → same images.
// Usage: bun scripts/make-samples.js [--only name]
import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import sharp from "sharp";

const OUT = join(import.meta.dir, "..", "samples");
const PW = 1000; // paper width (paper units)
const PH = 1400; // paper height

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const COLORS = {
  red: "#d92b2b",
  orange: "#f07a1a",
  yellow: "#f5c518",
  green: "#2f9e44",
  lime: "#8bc63f",
  blue: "#2463c9",
  sky: "#5bb8f0",
  purple: "#7b3fb8",
  violet: "#a66be0",
  pink: "#ef6fa8",
  brown: "#8a5a2b",
  black: "#222222",
  grey: "#8a8f98",
  pencil: "#5a5a5a",
  teal: "#1aa39a",
};

function makeCanvas(seed, medium = "crayon") {
  const rnd = mulberry32(seed);
  const r = (a, b) => a + (b - a) * rnd();
  const els = [];
  const defs = [];
  let clipId = 0;

  const j = (p, amt) => [p[0] + r(-amt, amt), p[1] + r(-amt, amt)];

  function smooth(pts, closed = false) {
    if (pts.length < 2) return "";
    const P = closed
      ? [pts[pts.length - 1], ...pts, pts[0], pts[1]]
      : [pts[0], ...pts, pts[pts.length - 1]];
    let d = `M${P[1][0].toFixed(1)},${P[1][1].toFixed(1)}`;
    for (let i = 1; i < P.length - 2; i++) {
      const [p0, p1, p2, p3] = [P[i - 1], P[i], P[i + 1], P[i + 2]];
      const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
      const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
      d += ` C${c1[0].toFixed(1)},${c1[1].toFixed(1)} ${c2[0].toFixed(1)},${c2[1].toFixed(1)} ${p2[0].toFixed(1)},${p2[1].toFixed(1)}`;
    }
    return closed ? `${d} Z` : d;
  }

  // Kid-style line: wobbly, drawn with 2 passes (crayon) or 1 pass (marker).
  function line(pts, color, w = 9, { wobble = 4, passes } = {}) {
    const n = passes ?? (medium === "crayon" ? 2 : 1);
    for (let k = 0; k < n; k++) {
      const jp = pts.map((p) => j(p, wobble));
      els.push(
        `<path d="${smooth(jp)}" fill="none" stroke="${COLORS[color] ?? color}" stroke-width="${(w * r(0.85, 1.1)).toFixed(1)}" stroke-linecap="round" stroke-linejoin="round" opacity="${medium === "crayon" ? r(0.75, 0.95).toFixed(2) : 0.95}" filter="url(#tex)"/>`,
      );
    }
  }

  // Points of a wobbly loop; kids overshoot the start, so open loops get a tail.
  function loopPts(cx, cy, rx, ry, { n = 16, wob = 0.06, overshoot = 0.15, rot = 0 } = {}) {
    const pts = [];
    const start = r(0, Math.PI * 2);
    const total = Math.PI * 2 * (1 + overshoot);
    for (let i = 0; i <= n * (1 + overshoot); i++) {
      const a = start + (total * i) / (n * (1 + overshoot));
      const k = 1 + r(-wob, wob);
      const x = Math.cos(a) * rx * k;
      const y = Math.sin(a) * ry * k;
      pts.push([
        cx + x * Math.cos(rot) - y * Math.sin(rot),
        cy + x * Math.sin(rot) + y * Math.cos(rot),
      ]);
    }
    return pts;
  }

  function ellipse(cx, cy, rx, ry, color, w = 9, opts = {}) {
    line(loopPts(cx, cy, rx, ry, opts), color, w, { wobble: 2 });
  }

  // Scribble fill: zigzag strokes clipped to the shape, with gaps and overshoot.
  function fill(
    shapeD,
    color,
    { angle = r(-35, 35), gap = 16, w = 14, coverage = 0.85, overshoot = 10 } = {},
  ) {
    const id = `c${clipId++}`;
    defs.push(
      `<clipPath id="${id}"><path d="${shapeD}" stroke="#000" stroke-width="${overshoot * 2}"/></clipPath>`,
    );
    const strokes = [];
    const R = 1200;
    for (let y = -R; y < R; y += gap * r(0.7, 1.3)) {
      if (rnd() > coverage) continue;
      const pts = [];
      for (let x = -R; x <= R; x += 60)
        pts.push([x + r(-8, 8), y + r(-5, 5) + (pts.length % 2 ? gap * 0.6 : 0)]);
      strokes.push(
        `<path d="${smooth(pts)}" fill="none" stroke="${COLORS[color] ?? color}" stroke-width="${(w * r(0.7, 1.2)).toFixed(1)}" stroke-linecap="round" opacity="${r(0.55, 0.85).toFixed(2)}"/>`,
      );
    }
    els.push(
      `<g clip-path="url(#${id})" filter="url(#tex)"><g transform="translate(${PW / 2},${PH / 2}) rotate(${angle.toFixed(1)})">${strokes.join("")}</g></g>`,
    );
  }

  function fillEllipse(cx, cy, rx, ry, color, opts) {
    fill(smooth(loopPts(cx, cy, rx, ry, { overshoot: 0, wob: 0.05 }), true), color, opts);
  }
  function fillPoly(pts, color, opts) {
    fill(
      smooth(
        pts.map((p) => j(p, 3)),
        true,
      ),
      color,
      opts,
    );
  }
  function poly(pts, color, w = 9, { closed = true } = {}) {
    const P = closed ? [...pts, pts[0], j(pts[1] ?? pts[0], 6)] : pts;
    // Densify so the smoother keeps corners loose but recognisable.
    const dense = [];
    for (let i = 0; i < P.length - 1; i++) {
      const [a, b] = [P[i], P[i + 1]];
      dense.push(a, [a[0] + (b[0] - a[0]) * 0.5, a[1] + (b[1] - a[1]) * 0.5]);
    }
    dense.push(P[P.length - 1]);
    line(dense, color, w);
  }
  function dot(x, y, rr, color) {
    els.push(
      `<circle cx="${(x + r(-2, 2)).toFixed(1)}" cy="${(y + r(-2, 2)).toFixed(1)}" r="${rr}" fill="${COLORS[color] ?? color}" filter="url(#tex)" opacity="0.92"/>`,
    );
  }
  function sun(x, y, s = 1) {
    fillEllipse(x, y, 60 * s, 60 * s, "yellow");
    ellipse(x, y, 60 * s, 60 * s, "orange", 8);
    for (let i = 0; i < 9; i++) {
      const a = (i / 9) * Math.PI * 2 + r(-0.1, 0.1);
      line(
        [
          [x + Math.cos(a) * 80 * s, y + Math.sin(a) * 80 * s],
          [x + Math.cos(a) * 125 * s, y + Math.sin(a) * 125 * s],
        ],
        "orange",
        8,
      );
    }
  }
  function grass(y = 1280) {
    for (let x = 20; x < PW - 20; x += r(18, 34))
      line(
        [
          [x, y + r(0, 20)],
          [x + r(-8, 8), y - r(25, 55)],
        ],
        "green",
        7,
        { passes: 1 },
      );
  }

  const texFilter =
    medium === "crayon"
      ? `<filter id="tex" x="-10%" y="-10%" width="120%" height="120%"><feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed="${seed % 97}" result="n"/><feColorMatrix in="n" type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 -3 2.05" result="m"/><feComposite in="SourceGraphic" in2="m" operator="in" result="g"/><feTurbulence type="fractalNoise" baseFrequency="0.035" numOctaves="2" seed="${(seed * 7) % 89}" result="w"/><feDisplacementMap in="g" in2="w" scale="5" xChannelSelector="R" yChannelSelector="G"/></filter>`
      : `<filter id="tex" x="-10%" y="-10%" width="120%" height="120%"><feTurbulence type="fractalNoise" baseFrequency="0.04" numOctaves="2" seed="${seed % 89}" result="w"/><feDisplacementMap in="SourceGraphic" in2="w" scale="3" xChannelSelector="R" yChannelSelector="G"/></filter>`;

  function paperSvg() {
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${PW}" height="${PH}" viewBox="0 0 ${PW} ${PH}">
<defs>${texFilter}${defs.join("")}
<filter id="paper"><feTurbulence type="fractalNoise" baseFrequency="0.6" numOctaves="3" seed="${seed % 50}"/><feColorMatrix type="matrix" values="0 0 0 0 0.96 0 0 0 0 0.94 0 0 0 0 0.88 0 0 0 -0.35 0.35"/></filter>
<radialGradient id="light" cx="${r(30, 70).toFixed(0)}%" cy="${r(25, 60).toFixed(0)}%" r="85%"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#6b5a3c" stop-opacity="${r(0.18, 0.32).toFixed(2)}"/></radialGradient>
</defs>
<rect width="100%" height="100%" fill="#fbf8f0"/>
<rect width="100%" height="100%" filter="url(#paper)"/>
${els.join("\n")}
<rect width="100%" height="100%" fill="url(#light)"/>
</svg>`;
  }

  return {
    r,
    rnd,
    line,
    ellipse,
    fill,
    fillEllipse,
    fillPoly,
    poly,
    dot,
    sun,
    grass,
    smooth,
    loopPts,
    paperSvg,
  };
}

// Render the paper and "photograph" it: slight rotation, on a table, with a soft shadow.
async function photograph(svg, outPath, seed) {
  const rnd = mulberry32(seed * 13 + 1);
  const paper = await sharp(Buffer.from(svg)).png().toBuffer();
  const angle = (rnd() - 0.5) * 7;
  const rotated = await sharp(paper)
    .rotate(angle, { background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer();
  const meta = await sharp(rotated).metadata();
  const W = 1200;
  const H = 1600;
  const scale = Math.min((W * 0.9) / meta.width, (H * 0.9) / meta.height);
  const pw = Math.round(meta.width * scale);
  const ph = Math.round(meta.height * scale);
  const sheet = await sharp(rotated).resize(pw, ph).png().toBuffer();
  const alpha = await sharp(sheet).extractChannel("alpha").toBuffer();
  const shadow = await sharp({
    create: { width: pw, height: ph, channels: 3, background: { r: 40, g: 30, b: 20 } },
  })
    .joinChannel(alpha)
    .blur(14)
    .png()
    .toBuffer();
  const tables = ["#b7895a", "#c9c3b8", "#9a7552", "#d8d2c4", "#7e8a96"];
  const table = tables[Math.floor(rnd() * tables.length)];
  const tableSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}"><defs><filter id="t"><feTurbulence type="fractalNoise" baseFrequency="0.012 0.25" numOctaves="3" seed="${seed}"/><feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 -0.6 0.45"/></filter></defs><rect width="100%" height="100%" fill="${table}"/><rect width="100%" height="100%" filter="url(#t)"/></svg>`;
  const left = Math.round((W - pw) / 2 + (rnd() - 0.5) * 50);
  const top = Math.round((H - ph) / 2 + (rnd() - 0.5) * 50);
  await sharp(Buffer.from(tableSvg))
    .composite([
      {
        input: shadow,
        left: Math.max(0, Math.min(W - pw, left + 12)),
        top: Math.max(0, Math.min(H - ph, top + 16)),
        blend: "multiply",
      },
      { input: sheet, left, top },
    ])
    .modulate({ brightness: 0.96 + rnd() * 0.08 })
    .jpeg({ quality: 82 })
    .toFile(outPath);
}

// ─── The drawings ─────────────────────────────────────────────────────────────

const DRAWINGS = {
  // 1 · purple cat + red kart with flames (the classic case)
  "pair01-character-cat": [
    101,
    "crayon",
    (d) => {
      d.fillEllipse(500, 430, 210, 190, "purple");
      d.ellipse(500, 430, 210, 190, "purple", 11);
      d.poly(
        [
          [330, 330],
          [350, 160],
          [440, 260],
        ],
        "purple",
        11,
      );
      d.poly(
        [
          [560, 255],
          [650, 150],
          [672, 330],
        ],
        "purple",
        11,
      );
      d.fillPoly(
        [
          [340, 310],
          [352, 190],
          [425, 265],
        ],
        "pink",
      );
      d.fillPoly(
        [
          [575, 262],
          [645, 185],
          [660, 310],
        ],
        "pink",
      );
      d.dot(430, 400, 26, "black");
      d.dot(575, 400, 26, "black");
      d.dot(438, 392, 7, "#ffffff");
      d.dot(583, 392, 7, "#ffffff");
      d.fillEllipse(400, 480, 34, 22, "pink");
      d.fillEllipse(605, 480, 34, 22, "pink");
      d.line(
        [
          [460, 505],
          [500, 535],
          [545, 505],
        ],
        "black",
        8,
      );
      for (const s of [-1, 1])
        for (const k of [0, 1, 2])
          d.line(
            [
              [500 + s * 90, 470 + k * 20],
              [500 + s * 230, 440 + k * 35],
            ],
            "black",
            5,
            { passes: 1 },
          );
      d.fillPoly(
        [
          [430, 610],
          [570, 610],
          [640, 980],
          [360, 980],
        ],
        "violet",
        { gap: 20 },
      );
      d.poly(
        [
          [430, 610],
          [570, 610],
          [640, 980],
          [360, 980],
        ],
        "purple",
        10,
      );
      d.line(
        [
          [425, 680],
          [300, 800],
          [270, 760],
        ],
        "purple",
        10,
      );
      d.line(
        [
          [575, 680],
          [710, 600],
          [740, 540],
        ],
        "purple",
        10,
      );
      d.line(
        [
          [440, 980],
          [430, 1180],
          [380, 1190],
        ],
        "purple",
        10,
      );
      d.line(
        [
          [560, 980],
          [570, 1180],
          [620, 1190],
        ],
        "purple",
        10,
      );
      d.line(
        [
          [640, 900],
          [760, 860],
          [800, 760],
          [760, 700],
          [720, 740],
        ],
        "purple",
        12,
      );
      d.fillPoly(
        [
          [440, 600],
          [560, 600],
          [600, 650],
          [400, 650],
        ],
        "orange",
      );
      d.grass();
    },
  ],
  "pair01-vehicle-kart": [
    102,
    "crayon",
    (d) => {
      d.sun(830, 170, 0.9);
      const body = [
        [140, 760],
        [260, 640],
        [700, 640],
        [860, 720],
        [880, 880],
        [130, 880],
      ];
      d.fillPoly(body, "red", { gap: 14 });
      d.poly(body, "red", 12);
      d.poly(
        [
          [330, 640],
          [400, 540],
          [560, 540],
          [600, 640],
        ],
        "black",
        9,
        { closed: false },
      );
      d.fillEllipse(480, 600, 45, 45, "sky");
      d.line(
        [
          [640, 640],
          [690, 540],
        ],
        "black",
        9,
      );
      d.ellipse(700, 525, 38, 22, "black", 9);
      for (const x of [260, 730]) {
        d.fillEllipse(x, 900, 95, 95, "black", { gap: 10, coverage: 0.95 });
        d.ellipse(x, 900, 95, 95, "black", 10);
        d.fillEllipse(x, 900, 30, 30, "grey");
      }
      d.fillPoly(
        [
          [130, 720],
          [20, 660],
          [70, 760],
          [0, 800],
          [80, 830],
          [130, 860],
        ],
        "orange",
      );
      d.fillPoly(
        [
          [130, 760],
          [60, 740],
          [90, 790],
          [130, 820],
        ],
        "yellow",
      );
      d.line(
        [
          [460, 700],
          [480, 690],
          [480, 840],
        ],
        "yellow",
        14,
      ); // number 1
      d.line(
        [
          [0, 1010],
          [1000, 1000],
        ],
        "grey",
        8,
        { passes: 1 },
      );
    },
  ],

  // 2 · boxy robot + rocket shoe (non-kart vehicle)
  "pair02-character-robot": [
    201,
    "marker",
    (d) => {
      d.line(
        [
          [500, 300],
          [505, 170],
        ],
        "black",
        8,
      );
      d.fillEllipse(505, 150, 35, 35, "red");
      d.ellipse(505, 150, 35, 35, "red", 7);
      const head = [
        [340, 300],
        [660, 305],
        [655, 540],
        [345, 535],
      ];
      d.fillPoly(head, "sky", { gap: 22, coverage: 0.7 });
      d.poly(head, "blue", 9);
      d.poly(
        [
          [390, 360],
          [470, 360],
          [470, 440],
          [390, 440],
        ],
        "black",
        7,
      );
      d.dot(430, 400, 18, "green");
      d.poly(
        [
          [530, 360],
          [610, 360],
          [610, 440],
          [530, 440],
        ],
        "black",
        7,
      );
      d.dot(570, 400, 18, "green");
      d.line(
        [
          [400, 490],
          [430, 470],
          [460, 495],
          [490, 470],
          [520, 495],
          [550, 470],
          [580, 495],
          [600, 480],
        ],
        "black",
        7,
      );
      const body = [
        [300, 560],
        [700, 565],
        [690, 990],
        [310, 985],
      ];
      d.fillPoly(body, "grey", { gap: 22, coverage: 0.75 });
      d.poly(body, "blue", 9);
      for (const [y, c] of [
        [650, "red"],
        [740, "yellow"],
        [830, "green"],
      ])
        d.dot(500, y, 28, c);
      d.line(
        [
          [300, 620],
          [190, 760],
          [180, 880],
        ],
        "blue",
        12,
      );
      d.line(
        [
          [700, 620],
          [820, 740],
          [830, 860],
        ],
        "blue",
        12,
      );
      d.line(
        [
          [150, 900],
          [180, 880],
          [215, 905],
        ],
        "black",
        9,
      );
      d.line(
        [
          [800, 880],
          [830, 860],
          [870, 885],
        ],
        "black",
        9,
      );
      d.poly(
        [
          [370, 990],
          [440, 990],
          [440, 1190],
          [370, 1190],
        ],
        "blue",
        9,
      );
      d.poly(
        [
          [560, 990],
          [630, 990],
          [630, 1190],
          [560, 1190],
        ],
        "blue",
        9,
      );
    },
  ],
  "pair02-vehicle-rocket-shoe": [
    202,
    "marker",
    (d) => {
      const shoe = [
        [240, 620],
        [420, 600],
        [470, 720],
        [800, 820],
        [840, 930],
        [200, 940],
        [190, 760],
      ];
      d.fillPoly(shoe, "lime", { gap: 18 });
      d.poly(shoe, "green", 11);
      d.line(
        [
          [180, 960],
          [860, 960],
        ],
        "black",
        16,
      );
      for (const k of [0, 1, 2, 3])
        d.line(
          [
            [430 + k * 70, 715 + k * 25],
            [470 + k * 70, 680 + k * 25],
          ],
          "black",
          7,
        );
      d.fillPoly(
        [
          [190, 700],
          [40, 640],
          [60, 760],
          [10, 830],
          [120, 840],
          [190, 900],
        ],
        "orange",
      );
      d.fillPoly(
        [
          [190, 760],
          [100, 740],
          [110, 800],
          [190, 850],
        ],
        "yellow",
      );
      d.poly(
        [
          [260, 600],
          [230, 470],
          [330, 590],
        ],
        "red",
        9,
      );
      d.fillPoly(
        [
          [260, 600],
          [235, 490],
          [325, 590],
        ],
        "red",
      );
      d.poly(
        [
          [600, 770],
          [640, 640],
          [700, 800],
        ],
        "red",
        9,
      );
      d.ellipse(320, 760, 50, 50, "blue", 8);
      d.fillEllipse(320, 760, 50, 50, "sky");
      for (let i = 0; i < 5; i++) d.dot(80 + d.r(0, 900), 200 + d.r(0, 250), 9, "yellow");
    },
  ],

  // 3 · three-horned dinosaur + yellow bike
  "pair03-character-dino": [
    301,
    "crayon",
    (d) => {
      const body = [
        [230, 760],
        [340, 560],
        [560, 520],
        [760, 620],
        [860, 800],
        [740, 960],
        [330, 960],
      ];
      d.fillPoly(body, "green", { gap: 15 });
      d.poly(body, "green", 11);
      d.fillEllipse(520, 820, 160, 90, "yellow");
      d.fillEllipse(270, 520, 150, 120, "green");
      d.ellipse(270, 520, 150, 120, "green", 11);
      d.poly(
        [
          [230, 420],
          [200, 300],
          [265, 405],
        ],
        "orange",
        9,
      );
      d.poly(
        [
          [300, 410],
          [320, 280],
          [345, 420],
        ],
        "orange",
        9,
      );
      d.poly(
        [
          [150, 470],
          [70, 400],
          [140, 520],
        ],
        "orange",
        9,
      );
      d.fillPoly(
        [
          [230, 420],
          [205, 320],
          [260, 405],
        ],
        "orange",
      );
      d.fillPoly(
        [
          [300, 410],
          [320, 300],
          [340, 415],
        ],
        "orange",
      );
      d.dot(240, 500, 20, "black");
      d.dot(320, 495, 20, "black");
      d.line(
        [
          [180, 580],
          [240, 610],
          [330, 590],
        ],
        "black",
        8,
      );
      for (let i = 0; i < 6; i++) {
        const x = 400 + i * 75;
        const y = 545 + Math.abs(i - 2) * 22;
        d.poly(
          [
            [x, y + 10],
            [x + 35, y - 60],
            [x + 70, y + 15],
          ],
          "red",
          9,
          { closed: false },
        );
      }
      d.line(
        [
          [850, 800],
          [960, 900],
          [980, 980],
        ],
        "green",
        14,
      );
      for (const x of [380, 470, 660, 740])
        d.line(
          [
            [x, 950],
            [x + d.r(-10, 10), 1110],
          ],
          "green",
          18,
        );
      for (let i = 0; i < 6; i++) d.dot(420 + d.r(0, 330), 640 + d.r(0, 100), 14, "blue");
      d.grass(1170);
    },
  ],
  "pair03-vehicle-bike": [
    302,
    "crayon",
    (d) => {
      for (const x of [270, 730]) {
        d.ellipse(x, 880, 170, 170, "black", 11);
        d.ellipse(x, 880, 22, 22, "black", 8);
        for (let k = 0; k < 6; k++) {
          const a = (k / 6) * Math.PI * 2;
          d.line(
            [
              [x, 880],
              [x + Math.cos(a) * 160, 880 + Math.sin(a) * 160],
            ],
            "grey",
            4,
            { passes: 1 },
          );
        }
      }
      d.line(
        [
          [270, 880],
          [470, 880],
          [620, 640],
          [380, 640],
          [270, 880],
        ],
        "yellow",
        16,
      );
      d.line(
        [
          [470, 880],
          [380, 640],
          [360, 580],
        ],
        "yellow",
        16,
      );
      d.line(
        [
          [620, 640],
          [730, 880],
        ],
        "yellow",
        16,
      );
      d.line(
        [
          [600, 560],
          [620, 640],
        ],
        "yellow",
        14,
      );
      d.line(
        [
          [540, 550],
          [600, 560],
          [680, 530],
        ],
        "black",
        12,
      );
      d.line(
        [
          [300, 570],
          [420, 570],
        ],
        "brown",
        20,
      );
      d.poly(
        [
          [650, 460],
          [830, 460],
          [800, 560],
          [670, 560],
        ],
        "brown",
        9,
      );
      for (let k = 0; k < 4; k++)
        d.line(
          [
            [660 + k * 45, 470],
            [680 + k * 40, 550],
          ],
          "brown",
          5,
          { passes: 1 },
        );
      d.line(
        [
          [740, 460],
          [745, 360],
        ],
        "green",
        7,
      );
      d.fillEllipse(745, 340, 30, 30, "yellow");
      for (let k = 0; k < 5; k++) {
        const a = (k / 5) * Math.PI * 2;
        d.fillEllipse(745 + Math.cos(a) * 42, 340 + Math.sin(a) * 42, 24, 24, "pink");
      }
      d.line(
        [
          [20, 1060],
          [980, 1055],
        ],
        "brown",
        8,
        { passes: 1 },
      );
    },
  ],

  // 4 · girl with crown + horse (non-kart vehicle)
  "pair04-character-girl-crown": [
    401,
    "marker",
    (d) => {
      d.fillPoly(
        [
          [300, 380],
          [260, 820],
          [360, 760],
          [380, 420],
        ],
        "orange",
        { gap: 14 },
      );
      d.fillPoly(
        [
          [700, 380],
          [740, 820],
          [640, 760],
          [620, 420],
        ],
        "orange",
        { gap: 14 },
      );
      d.fillEllipse(500, 420, 170, 175, "#f6c9a3", { coverage: 0.7, gap: 24 });
      d.ellipse(500, 420, 170, 175, "brown", 8);
      d.fillPoly(
        [
          [340, 330],
          [500, 250],
          [660, 330],
          [600, 300],
          [500, 290],
          [400, 300],
        ],
        "orange",
      );
      const crown = [
        [370, 270],
        [360, 120],
        [430, 200],
        [500, 90],
        [570, 200],
        [640, 120],
        [630, 270],
      ];
      d.fillPoly(crown, "yellow");
      d.poly(crown, "orange", 8);
      d.dot(500, 140, 16, "red");
      d.dot(400, 240, 12, "blue");
      d.dot(600, 240, 12, "green");
      d.dot(440, 410, 18, "blue");
      d.dot(565, 410, 18, "blue");
      d.line(
        [
          [410, 370],
          [450, 360],
        ],
        "brown",
        6,
        { passes: 1 },
      );
      d.line(
        [
          [545, 360],
          [590, 370],
        ],
        "brown",
        6,
        { passes: 1 },
      );
      d.line(
        [
          [420, 490],
          [500, 545],
          [585, 490],
        ],
        "red",
        9,
      );
      d.fillEllipse(400, 470, 30, 18, "pink");
      d.fillEllipse(605, 470, 30, 18, "pink");
      const dress = [
        [440, 600],
        [560, 600],
        [740, 1080],
        [260, 1080],
      ];
      d.fillPoly(dress, "pink", { gap: 16 });
      d.poly(dress, "pink", 10);
      for (let i = 0; i < 7; i++) d.dot(340 + d.r(0, 320), 700 + d.r(0, 330), 14, "violet");
      d.line(
        [
          [450, 650],
          [300, 760],
          [240, 700],
        ],
        "brown",
        9,
      );
      d.line(
        [
          [550, 650],
          [700, 760],
          [760, 700],
        ],
        "brown",
        9,
      );
      d.line(
        [
          [420, 1080],
          [420, 1220],
        ],
        "brown",
        9,
      );
      d.line(
        [
          [580, 1080],
          [580, 1220],
        ],
        "brown",
        9,
      );
      d.fillEllipse(400, 1225, 40, 18, "red");
      d.fillEllipse(600, 1225, 40, 18, "red");
    },
  ],
  "pair04-vehicle-horse": [
    402,
    "marker",
    (d) => {
      const body = [
        [260, 620],
        [700, 600],
        [760, 700],
        [700, 840],
        [270, 850],
        [210, 740],
      ];
      d.fillPoly(body, "brown", { gap: 15 });
      d.poly(body, "brown", 11);
      d.poly(
        [
          [680, 630],
          [760, 430],
          [820, 380],
          [900, 430],
          [880, 500],
          [800, 520],
          [760, 700],
        ],
        "brown",
        11,
        { closed: false },
      );
      d.fillPoly(
        [
          [690, 640],
          [760, 440],
          [820, 395],
          [890, 440],
          [875, 495],
          [800, 515],
          [750, 690],
        ],
        "brown",
        { gap: 15 },
      );
      d.dot(830, 430, 14, "black");
      d.poly(
        [
          [790, 395],
          [800, 330],
          [830, 385],
        ],
        "brown",
        9,
      );
      for (let i = 0; i < 6; i++) {
        const t = i / 5;
        const x = 770 - t * 90;
        const y = 400 + t * 230;
        d.line(
          [
            [x, y],
            [x - 60, y + 20],
            [x - 70, y + 70],
          ],
          ["red", "orange", "yellow", "green", "blue", "purple"][i],
          12,
        );
      }
      for (const x of [300, 380, 600, 680]) {
        d.line(
          [
            [x, 830],
            [x + d.r(-15, 15), 1100],
          ],
          "brown",
          18,
        );
        d.fillEllipse(x, 1110, 30, 18, "black");
      }
      d.line(
        [
          [220, 680],
          [120, 720],
          [90, 900],
        ],
        "pink",
        22,
      );
      d.line(
        [
          [220, 700],
          [140, 760],
          [130, 920],
        ],
        "violet",
        16,
      );
      d.fillPoly(
        [
          [400, 600],
          [560, 600],
          [540, 680],
          [420, 680],
        ],
        "blue",
      );
      d.poly(
        [
          [400, 600],
          [560, 600],
          [540, 680],
          [420, 680],
        ],
        "blue",
        8,
      );
      d.grass(1200);
    },
  ],

  // 5 · one-eyed alien + dragon (flying ride)
  "pair05-character-alien": [
    501,
    "crayon",
    (d) => {
      d.line(
        [
          [420, 300],
          [360, 150],
        ],
        "lime",
        9,
      );
      d.fillEllipse(355, 140, 26, 26, "pink");
      d.line(
        [
          [580, 300],
          [650, 150],
        ],
        "lime",
        9,
      );
      d.fillEllipse(655, 140, 26, 26, "pink");
      const blob = d.smooth(d.loopPts(500, 560, 260, 290, { overshoot: 0, wob: 0.08 }), true);
      d.fill(blob, "lime", { gap: 14 });
      d.line(d.loopPts(500, 560, 260, 290, { wob: 0.05 }), "green", 11);
      d.fillEllipse(500, 470, 110, 100, "#ffffff", { coverage: 1 });
      d.ellipse(500, 470, 110, 100, "black", 9);
      d.dot(510, 480, 45, "purple");
      d.dot(525, 465, 12, "#ffffff");
      d.poly(
        [
          [370, 640],
          [630, 640],
          [560, 720],
          [440, 720],
        ],
        "black",
        9,
      );
      d.fillPoly(
        [
          [380, 645],
          [620, 645],
          [555, 715],
          [445, 715],
        ],
        "red",
      );
      for (const x of [420, 480, 540, 590])
        d.poly(
          [
            [x, 645],
            [x + 20, 680],
            [x + 40, 645],
          ],
          "#ffffff",
          7,
          { closed: false },
        );
      for (let i = 0; i < 7; i++) d.dot(330 + d.r(0, 340), 760 + d.r(0, 60), 18, "teal");
      d.line(
        [
          [250, 560],
          [140, 470],
          [110, 400],
        ],
        "green",
        12,
      );
      d.line(
        [
          [750, 560],
          [870, 640],
          [900, 720],
        ],
        "green",
        12,
      );
      d.line(
        [
          [400, 840],
          [380, 1050],
          [320, 1060],
        ],
        "green",
        12,
      );
      d.line(
        [
          [600, 840],
          [620, 1050],
          [680, 1060],
        ],
        "green",
        12,
      );
      for (let i = 0; i < 12; i++) d.dot(60 + d.r(0, 880), 60 + d.r(0, 200), 6, "blue");
    },
  ],
  "pair05-vehicle-dragon": [
    502,
    "crayon",
    (d) => {
      const body = [
        [230, 760],
        [400, 650],
        [640, 660],
        [760, 760],
        [640, 860],
        [380, 870],
      ];
      d.fillPoly(body, "red", { gap: 14 });
      d.poly(body, "red", 11);
      d.fillPoly(
        [
          [400, 680],
          [380, 420],
          [180, 300],
          [280, 500],
          [160, 520],
          [330, 680],
        ],
        "orange",
        { gap: 18 },
      );
      d.poly(
        [
          [400, 680],
          [380, 420],
          [180, 300],
          [280, 500],
          [160, 520],
          [330, 680],
        ],
        "red",
        9,
      );
      d.fillPoly(
        [
          [560, 670],
          [640, 400],
          [860, 320],
          [760, 500],
          [880, 540],
          [640, 690],
        ],
        "orange",
        { gap: 18 },
      );
      d.poly(
        [
          [560, 670],
          [640, 400],
          [860, 320],
          [760, 500],
          [880, 540],
          [640, 690],
        ],
        "red",
        9,
      );
      d.line(
        [
          [740, 760],
          [820, 700],
          [880, 700],
        ],
        "red",
        22,
      );
      d.fillEllipse(900, 700, 70, 55, "red");
      d.ellipse(900, 700, 70, 55, "red", 10);
      d.dot(915, 680, 12, "black");
      d.poly(
        [
          [880, 650],
          [870, 600],
          [905, 645],
        ],
        "yellow",
        8,
      );
      d.fillPoly(
        [
          [960, 720],
          [1000, 700],
          [1000, 760],
        ],
        "yellow",
      );
      d.line(
        [
          [230, 780],
          [120, 820],
          [60, 760],
          [30, 800],
        ],
        "red",
        14,
      );
      d.poly(
        [
          [25, 790],
          [5, 760],
          [50, 770],
        ],
        "red",
        8,
      );
      for (const x of [380, 600])
        d.line(
          [
            [x, 860],
            [x - 10, 980],
            [x + 30, 990],
          ],
          "red",
          14,
        );
      for (let i = 0; i < 4; i++) {
        const x = 330 + i * 90;
        d.poly(
          [
            [x, 660],
            [x + 30, 610],
            [x + 60, 655],
          ],
          "yellow",
          8,
          { closed: false },
        );
      }
      d.fillEllipse(180, 200, 120, 50, "sky", { coverage: 0.6, gap: 22 });
      d.fillEllipse(780, 160, 140, 55, "sky", { coverage: 0.6, gap: 22 });
    },
  ],

  // 6 · blue blob monster + sailing boat
  "pair06-character-blob-monster": [
    601,
    "marker",
    (d) => {
      const blob = [
        [250, 900],
        [220, 600],
        [320, 380],
        [500, 300],
        [700, 370],
        [790, 600],
        [770, 900],
        [690, 870],
        [620, 930],
        [520, 880],
        [430, 940],
        [340, 880],
      ];
      d.fillPoly(blob, "sky", { gap: 16 });
      d.poly(blob, "blue", 11);
      d.fillEllipse(410, 540, 55, 65, "#ffffff", { coverage: 1 });
      d.ellipse(410, 540, 55, 65, "black", 7);
      d.dot(420, 555, 22, "black");
      d.fillEllipse(600, 540, 55, 65, "#ffffff", { coverage: 1 });
      d.ellipse(600, 540, 55, 65, "black", 7);
      d.dot(590, 555, 22, "black");
      d.line(
        [
          [380, 680],
          [450, 740],
          [560, 745],
          [640, 680],
        ],
        "black",
        9,
      );
      d.poly(
        [
          [470, 742],
          [490, 790],
          [515, 744],
        ],
        "#ffffff",
        7,
        { closed: false },
      );
      for (const [x, y] of [
        [300, 300],
        [700, 250],
        [850, 420],
      ])
        d.poly(
          [
            [x, y - 40],
            [x + 12, y - 10],
            [x + 42, y - 10],
            [x + 18, y + 10],
            [x + 28, y + 40],
            [x, y + 20],
            [x - 28, y + 40],
            [x - 18, y + 10],
            [x - 42, y - 10],
            [x - 12, y - 10],
          ],
          "yellow",
          7,
        );
      d.line(
        [
          [230, 650],
          [110, 600],
          [80, 520],
        ],
        "blue",
        12,
      );
      d.line(
        [
          [780, 650],
          [900, 610],
          [930, 530],
        ],
        "blue",
        12,
      );
      d.poly(
        [
          [440, 300],
          [470, 220],
          [500, 300],
        ],
        "blue",
        9,
        { closed: false },
      );
    },
  ],
  "pair06-vehicle-boat": [
    602,
    "marker",
    (d) => {
      const hull = [
        [150, 820],
        [850, 820],
        [740, 1000],
        [260, 1000],
      ];
      d.fillPoly(hull, "brown", { gap: 14 });
      d.poly(hull, "brown", 11);
      for (const x of [340, 500, 660]) {
        d.ellipse(x, 900, 34, 34, "black", 7);
        d.fillEllipse(x, 900, 34, 34, "sky");
      }
      d.line(
        [
          [500, 820],
          [500, 260],
        ],
        "black",
        12,
      );
      const sail = [
        [510, 280],
        [800, 760],
        [510, 760],
      ];
      d.fillPoly(sail, "#ffffff", { coverage: 1 });
      d.poly(sail, "red", 10);
      d.poly(
        [
          [230, 760],
          [490, 360],
          [490, 760],
        ],
        "orange",
        10,
      );
      d.fillPoly(
        [
          [240, 755],
          [485, 380],
          [485, 755],
        ],
        "yellow",
        { gap: 18 },
      );
      d.fillEllipse(620, 545, 26, 22, "red");
      d.line(
        [
          [500, 260],
          [600, 280],
          [500, 320],
        ],
        "red",
        9,
      );
      d.fillPoly(
        [
          [500, 262],
          [600, 282],
          [500, 318],
        ],
        "green",
      );
      for (let y = 1030; y < 1300; y += 70) {
        const pts = [];
        for (let x = 0; x <= 1000; x += 50) pts.push([x, y + ((x / 50) % 2 ? -18 : 18)]);
        d.line(pts, "blue", 9, { passes: 1 });
      }
      d.sun(140, 160, 0.8);
    },
  ],

  // ─── tricky cases ───
  "tricky-scribble": [
    901,
    "crayon",
    (d) => {
      for (const c of ["red", "blue", "green", "black", "orange", "purple"]) {
        const pts = [];
        let [x, y] = [d.r(250, 750), d.r(350, 1050)];
        for (let i = 0; i < 40; i++) {
          x = Math.min(950, Math.max(50, x + d.r(-220, 220)));
          y = Math.min(1350, Math.max(50, y + d.r(-220, 220)));
          pts.push([x, y]);
        }
        d.line(pts, c, d.r(8, 16), { passes: 1, wobble: 10 });
      }
    },
  ],
  "tricky-blank-page": [
    902,
    "crayon",
    (d) => {
      d.line(
        [
          [880, 1300],
          [905, 1290],
        ],
        "pencil",
        3,
        { passes: 1 },
      ); // a stray pencil tick
    },
  ],
  "tricky-both-on-one-page": [
    903,
    "marker",
    (d) => {
      // Kid on a skateboard, both drawn on one sheet (the same photo is uploaded twice).
      d.ellipse(500, 300, 110, 110, "black", 8);
      d.fillEllipse(500, 300, 110, 110, "#f6c9a3", { coverage: 0.6, gap: 24 });
      d.fillPoly(
        [
          [395, 260],
          [420, 180],
          [500, 160],
          [590, 185],
          [610, 260],
          [500, 220],
        ],
        "black",
      );
      d.dot(460, 300, 12, "black");
      d.dot(540, 300, 12, "black");
      d.line(
        [
          [460, 345],
          [500, 370],
          [545, 345],
        ],
        "red",
        7,
      );
      d.fillPoly(
        [
          [420, 420],
          [580, 420],
          [600, 700],
          [400, 700],
        ],
        "green",
        { gap: 16 },
      );
      d.poly(
        [
          [420, 420],
          [580, 420],
          [600, 700],
          [400, 700],
        ],
        "green",
        9,
      );
      d.poly(
        [
          [440, 480],
          [500, 540],
          [560, 480],
        ],
        "yellow",
        9,
        { closed: false },
      );
      d.line(
        [
          [420, 450],
          [280, 380],
          [240, 300],
        ],
        "black",
        9,
      );
      d.line(
        [
          [580, 450],
          [720, 380],
          [760, 300],
        ],
        "black",
        9,
      );
      d.line(
        [
          [440, 700],
          [380, 920],
        ],
        "blue",
        14,
      );
      d.line(
        [
          [560, 700],
          [640, 920],
        ],
        "blue",
        14,
      );
      d.fillPoly(
        [
          [180, 930],
          [820, 930],
          [860, 980],
          [140, 980],
        ],
        "orange",
        { gap: 12 },
      );
      d.poly(
        [
          [180, 930],
          [820, 930],
          [860, 980],
          [140, 980],
        ],
        "red",
        9,
      );
      for (const x of [260, 740]) d.fillEllipse(x, 1020, 40, 40, "black", { coverage: 1 });
      for (let k = 0; k < 3; k++)
        d.line(
          [
            [80, 960 + k * 30],
            [10, 960 + k * 30],
          ],
          "grey",
          6,
          { passes: 1 },
        );
    },
  ],
};

async function main() {
  const only = process.argv.includes("--only")
    ? process.argv[process.argv.indexOf("--only") + 1]
    : null;
  await mkdir(OUT, { recursive: true });
  for (const [name, [seed, medium, draw]] of Object.entries(DRAWINGS)) {
    if (only && name !== only) continue;
    const c = makeCanvas(seed, medium);
    draw(c);
    await photograph(c.paperSvg(), join(OUT, `${name}.jpg`), seed);
    console.log(`samples/${name}.jpg`);
  }
}

main();
