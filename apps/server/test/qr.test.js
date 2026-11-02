// The join QR code (src/qr.js) and GET /api/join, which the big screen's options menu shows.
import { afterAll, beforeAll, expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createMockClient } from "@bebbikart/asset-pipeline";
import { DEFAULT_CONFIG } from "@bebbikart/shared";
import { loadSettings } from "../src/env.js";
import { startServer } from "../src/index.js";
import { qrRows } from "../src/qr.js";

const URL = "http://192.168.1.23:8080";

// The same text, level M, mask 5, from an independent encoder (qrcode-generator 1.4.4).
const REFERENCE_MASK_5 = [
  "1111111001001100101111111",
  "1000001010110100001000001",
  "1011101010001000101011101",
  "1011101010110111101011101",
  "1011101000101010001011101",
  "1000001000101100101000001",
  "1111111010101010101111111",
  "0000000011001010000000000",
  "1000001011011101111001110",
  "0101110010011101110011110",
  "0111101111100101001101011",
  "0111000010010001100011001",
  "0000011001110010111000001",
  "1001010100101111000000010",
  "1011101101100001010101011",
  "1001000010001010100010101",
  "1000001111001100111110100",
  "0000000010000011100010100",
  "1111111000101110101011001",
  "1000001001010000100010001",
  "1011101001011101111111100",
  "1011101001101100001101011",
  "1011101000101000010000101",
  "1000001001101001101110001",
  "1111111011110011101001001",
];

/** The 15 format bits around the top-left finder, read back (cell i holds bit i). */
function formatAt(rows) {
  const at = (x, y) => (rows[y][x] === "1" ? 1 : 0);
  const cells = [
    [8, 0],
    [8, 1],
    [8, 2],
    [8, 3],
    [8, 4],
    [8, 5],
    [8, 7],
    [8, 8],
    [7, 8],
    [5, 8],
    [4, 8],
    [3, 8],
    [2, 8],
    [1, 8],
    [0, 8],
  ];
  return cells.reduce((v, [x, y], i) => v | (at(x, y) << i), 0);
}

test("the join address encodes like an independent QR encoder", () => {
  expect(qrRows(URL, 5)).toEqual(REFERENCE_MASK_5);
  expect(((formatAt(REFERENCE_MASK_5) ^ 0x5412) >> 10) & 0b111).toBe(5);
});

test("QR codes grow with the text, keep their finders and say level M", () => {
  for (const [text, version] of [
    ["a", 1],
    [URL, 2],
    ["x".repeat(60), 4],
    ["y".repeat(114), 7],
    ["z".repeat(213), 10],
  ]) {
    const rows = qrRows(text);
    const size = 17 + 4 * version;
    expect(rows.length).toBe(size);
    expect(rows.every((r) => r.length === size && /^[01]+$/.test(r))).toBe(true);
    for (const [x, y] of [
      [0, 0],
      [size - 7, 0],
      [0, size - 7],
    ]) {
      expect(rows[y].slice(x, x + 7)).toBe("1111111");
      expect(rows[y + 2].slice(x, x + 7)).toBe("1011101");
    }
    const fmt = formatAt(rows) ^ 0x5412;
    expect(fmt >> 13).toBe(0b00); // level M
  }
  expect(() => qrRows("q".repeat(214))).toThrow("too long");
});

let srv;
let base;
let settings;
beforeAll(() => {
  settings = {
    ...loadSettings({}),
    port: 0,
    dataDir: mkdtempSync(join(tmpdir(), "bk-qr-")),
    webDist: mkdtempSync(join(tmpdir(), "bk-qr-web-")), // empty: the phone site isn't built
    designClient: createMockClient({ designId: "pair01" }),
    config: DEFAULT_CONFIG,
    publicUrl: URL,
  };
  settings.dbFile = ":memory:";
  srv = startServer(settings, { log: () => {} });
  base = `http://localhost:${srv.server.port}`;
});
afterAll(() => srv?.stop());

test("GET /api/join: the phone address, its QR code, and whether the phone site is built", async () => {
  const res = await fetch(`${base}/api/join`);
  expect(res.status).toBe(200);
  const join = await res.json();
  expect(join.url).toBe(URL);
  expect(join.qr).toEqual(qrRows(URL));
  expect(join.phoneSite).toBe(false);
});

test("GET /api/join under bun run dev: Vite's address, whose phone site needs no build", async () => {
  settings.phoneVitePort = 5173;
  try {
    const join = await (await fetch(`${base}/api/join`)).json();
    expect(join.url).toBe("http://192.168.1.23:5173");
    expect(join.qr).toEqual(qrRows("http://192.168.1.23:5173"));
    expect(join.phoneSite).toBe(true);
    const page = await (await fetch(`${base}/`)).text();
    expect(page).toContain('href="http://192.168.1.23:5173"');
  } finally {
    settings.phoneVitePort = null;
  }
});
