// QR codes for the join address, so the big screen can show one without a library: byte mode,
// error correction level M (15 % of the code can be covered or smudged), versions 1 to 10
// (up to 213 bytes, plenty for http://<ip>:<port>). ISO/IEC 18004; laid out like most encoders.

// Level M, per version: EC codewords per block, and the data codewords of each block.
const BLOCKS_M = [
  null,
  [10, [16]],
  [16, [28]],
  [26, [44]],
  [18, [32, 32]],
  [24, [43, 43]],
  [16, [27, 27, 27, 27]],
  [18, [31, 31, 31, 31]],
  [22, [38, 38, 39, 39]],
  [22, [36, 36, 36, 37, 37]],
  [26, [43, 43, 43, 43, 44]],
];
const ALIGN = [
  null,
  [],
  [6, 18],
  [6, 22],
  [6, 26],
  [6, 30],
  [6, 34],
  [6, 22, 38],
  [6, 24, 42],
  [6, 26, 46],
  [6, 28, 50],
];
const MAX_VERSION = 10;
const LEVEL_M = 0b00; // format bits: L 01, M 00, Q 11, H 10

// GF(256) with the QR polynomial x^8 + x^4 + x^3 + x^2 + 1.
const EXP = new Uint8Array(512);
const LOG = new Uint8Array(256);
for (let i = 0, x = 1; i < 255; i++, x = x & 0x80 ? ((x << 1) ^ 0x11d) & 0xff : x << 1) {
  EXP[i] = x;
  LOG[x] = i;
}
for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255];
const mul = (a, b) => (a && b ? EXP[LOG[a] + LOG[b]] : 0);

/** Reed-Solomon EC codewords for `data` (the remainder of data·x^n by the generator). */
function ecCodewords(data, n) {
  let gen = [1];
  for (let i = 0; i < n; i++) {
    const next = new Array(gen.length + 1).fill(0);
    for (let j = 0; j < gen.length; j++) {
      next[j] ^= gen[j];
      next[j + 1] ^= mul(gen[j], EXP[i]);
    }
    gen = next;
  }
  const rem = new Array(n).fill(0);
  for (const byte of data) {
    const f = byte ^ rem.shift();
    rem.push(0);
    for (let j = 0; j < n; j++) rem[j] ^= mul(gen[j + 1], f);
  }
  return rem;
}

/** The final codeword sequence: data bits padded, split into blocks, EC added, interleaved. */
function codewords(bytes, version) {
  const [ecLen, blocks] = BLOCKS_M[version];
  const capacity = blocks.reduce((a, b) => a + b, 0);
  const bits = [];
  const put = (v, n) => {
    for (let i = n - 1; i >= 0; i--) bits.push((v >>> i) & 1);
  };
  put(0b0100, 4); // byte mode
  put(bytes.length, version < 10 ? 8 : 16);
  for (const b of bytes) put(b, 8);
  put(0, Math.min(4, capacity * 8 - bits.length)); // terminator
  put(0, (8 - (bits.length % 8)) % 8);
  const data = [];
  for (let i = 0; i < bits.length; i += 8)
    data.push(bits.slice(i, i + 8).reduce((a, b) => (a << 1) | b, 0));
  for (let pad = 0xec; data.length < capacity; pad ^= 0xec ^ 0x11) data.push(pad);

  const split = [];
  let at = 0;
  for (const len of blocks) {
    const d = data.slice(at, at + len);
    at += len;
    split.push({ d, ec: ecCodewords(d, ecLen) });
  }
  const out = [];
  for (let i = 0; i < Math.max(...blocks); i++)
    for (const b of split) if (i < b.d.length) out.push(b.d[i]);
  for (let i = 0; i < ecLen; i++) for (const b of split) out.push(b.ec[i]);
  return out;
}

/** 15 format bits (level M, mask): BCH(15,5), XOR 0x5412. */
function formatBits(mask) {
  const data = (LEVEL_M << 3) | mask;
  let rem = data;
  for (let i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
  return ((data << 10) | (rem & 0x3ff)) ^ 0x5412;
}

/** 18 version bits (versions 7 and up): BCH(18,6). */
function versionBits(version) {
  let rem = version;
  for (let i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25);
  return (version << 12) | (rem & 0xfff);
}

const MASKS = [
  (x, y) => (x + y) % 2 === 0,
  (_x, y) => y % 2 === 0,
  (x) => x % 3 === 0,
  (x, y) => (x + y) % 3 === 0,
  (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0,
  (x, y) => ((x * y) % 2) + ((x * y) % 3) === 0,
  (x, y) => (((x * y) % 2) + ((x * y) % 3)) % 2 === 0,
  (x, y) => (((x + y) % 2) + ((x * y) % 3)) % 2 === 0,
];

/** The matrix (rows of booleans, true = dark) for `bytes` at `version` with `mask`. */
function build(bytes, version, mask) {
  const size = 17 + 4 * version;
  const dark = Array.from({ length: size }, () => new Array(size).fill(false));
  const fixed = Array.from({ length: size }, () => new Array(size).fill(false));
  const set = (x, y, on) => {
    dark[y][x] = on;
    fixed[y][x] = true;
  };
  for (let i = 0; i < size; i++) {
    set(6, i, i % 2 === 0);
    set(i, 6, i % 2 === 0);
  }
  for (const [cx, cy] of [
    [3, 3],
    [size - 4, 3],
    [3, size - 4],
  ]) {
    for (let dy = -4; dy <= 4; dy++) {
      for (let dx = -4; dx <= 4; dx++) {
        const x = cx + dx;
        const y = cy + dy;
        const d = Math.max(Math.abs(dx), Math.abs(dy));
        if (x >= 0 && x < size && y >= 0 && y < size) set(x, y, d !== 2 && d !== 4);
      }
    }
  }
  const al = ALIGN[version];
  const last = al.length - 1;
  for (let i = 0; i < al.length; i++) {
    for (let j = 0; j < al.length; j++) {
      if ((i === 0 && j === 0) || (i === 0 && j === last) || (i === last && j === 0)) continue;
      for (let dy = -2; dy <= 2; dy++)
        for (let dx = -2; dx <= 2; dx++)
          set(al[i] + dx, al[j] + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
    }
  }
  const fmt = formatBits(mask);
  const bit = (v, i) => ((v >>> i) & 1) === 1;
  for (let i = 0; i <= 5; i++) set(8, i, bit(fmt, i));
  set(8, 7, bit(fmt, 6));
  set(8, 8, bit(fmt, 7));
  set(7, 8, bit(fmt, 8));
  for (let i = 9; i < 15; i++) set(14 - i, 8, bit(fmt, i));
  for (let i = 0; i < 8; i++) set(size - 1 - i, 8, bit(fmt, i));
  for (let i = 8; i < 15; i++) set(8, size - 15 + i, bit(fmt, i));
  set(8, size - 8, true); // the dark module
  if (version >= 7) {
    const v = versionBits(version);
    for (let i = 0; i < 18; i++) {
      const a = size - 11 + (i % 3);
      const b = Math.floor(i / 3);
      set(a, b, bit(v, i));
      set(b, a, bit(v, i));
    }
  }

  // Data, two columns at a time from the bottom right, zigzagging up and down.
  const cw = codewords(bytes, version);
  let i = 0;
  for (let right = size - 1; right >= 1; right -= 2) {
    if (right === 6) right = 5;
    const up = ((right + 1) & 2) === 0;
    for (let v = 0; v < size; v++) {
      const y = up ? size - 1 - v : v;
      for (let j = 0; j < 2; j++) {
        const x = right - j;
        if (fixed[y][x]) continue;
        const on = i < cw.length * 8 && bit(cw[i >>> 3], 7 - (i & 7));
        i++;
        dark[y][x] = on !== MASKS[mask](x, y);
      }
    }
  }
  return dark;
}

/** Penalty score of a matrix (lower scans better): runs, 2x2 blocks, finder look-alikes, balance. */
function penalty(m) {
  const size = m.length;
  let score = 0;
  const line = (get) => {
    let s = 0;
    let run = 1;
    for (let i = 1; i <= size; i++) {
      if (i < size && get(i) === get(i - 1)) run++;
      else {
        if (run >= 5) s += run - 2;
        run = 1;
      }
    }
    // 1:1:3:1:1 with four light modules on one side
    for (let i = 0; i + 7 <= size; i++) {
      const finder = [1, 0, 1, 1, 1, 0, 1].every((b, k) => get(i + k) === (b === 1));
      if (!finder) continue;
      const lightBefore = [1, 2, 3, 4].every((k) => i - k < 0 || !get(i - k));
      const lightAfter = [0, 1, 2, 3].every((k) => i + 7 + k >= size || !get(i + 7 + k));
      if (lightBefore || lightAfter) s += 40;
    }
    return s;
  };
  for (let k = 0; k < size; k++) {
    score += line((i) => m[k][i]);
    score += line((i) => m[i][k]);
  }
  let darkCount = 0;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      if (m[y][x]) darkCount++;
      if (x < size - 1 && y < size - 1) {
        const c = m[y][x];
        if (m[y][x + 1] === c && m[y + 1][x] === c && m[y + 1][x + 1] === c) score += 3;
      }
    }
  }
  const total = size * size;
  score += Math.floor(Math.abs(darkCount * 20 - total * 10) / total) * 10;
  return score;
}

/**
 * QR code for `text` (UTF-8): rows of "0"/"1" (1 = dark), without the quiet zone; leave four
 * light modules around it. Throws if the text is longer than version 10 holds.
 * `mask` forces a mask pattern (tests); by default the best-scoring one is used.
 */
export function qrRows(text, mask) {
  const bytes = [...new TextEncoder().encode(text)];
  let version = 1;
  const fits = (v) =>
    4 + (v < 10 ? 8 : 16) + bytes.length * 8 <= BLOCKS_M[v][1].reduce((a, b) => a + b, 0) * 8;
  while (version <= MAX_VERSION && !fits(version)) version++;
  if (version > MAX_VERSION)
    throw new Error(`QR: ${bytes.length} bytes is too long for a join code`);
  let best = null;
  for (const k of mask === undefined ? [0, 1, 2, 3, 4, 5, 6, 7] : [mask]) {
    const m = build(bytes, version, k);
    const score = penalty(m);
    if (!best || score < best.score) best = { m, score };
  }
  return best.m.map((row) => row.map((on) => (on ? "1" : "0")).join(""));
}
