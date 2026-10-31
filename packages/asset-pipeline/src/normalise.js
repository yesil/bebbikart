// Step 1: normalise a drawing photo with sharp (EXIF rotate, strip metadata, longest side ≤ 1536).
import sharp from "sharp";

export const MAX_SIDE = 1536;

export class UnsupportedFileError extends Error {}

/**
 * @param {string | Buffer} input file path or image bytes
 * @returns {Promise<{ jpeg: Buffer, dataUrl: string, width: number, height: number }>}
 */
export async function normaliseDrawing(input) {
  try {
    // sharp drops all metadata (EXIF, GPS) unless withMetadata() is called.
    const { data, info } = await sharp(input, { failOn: "error" })
      .rotate()
      .resize(MAX_SIDE, MAX_SIDE, { fit: "inside", withoutEnlargement: true })
      .flatten({ background: "#ffffff" })
      .jpeg({ quality: 85 })
      .toBuffer({ resolveWithObject: true });
    return {
      jpeg: data,
      dataUrl: `data:image/jpeg;base64,${data.toString("base64")}`,
      width: info.width,
      height: info.height,
    };
  } catch (err) {
    throw new UnsupportedFileError(`can't read image: ${err.message}`);
  }
}

/**
 * The drawing's main colours, used to recolour the fallback spec. Ignores paper, table and pencil:
 * only fairly saturated pixels count, bucketed coarsely and ranked by area.
 * @param {Buffer[]} images
 * @param {number} count
 * @returns {Promise<string[]>} hex colours, most common first (may be fewer than `count`)
 */
export async function extractPalette(images, count = 5) {
  const buckets = new Map();
  for (const img of images) {
    const { data } = await sharp(img)
      .resize(96, 96, { fit: "inside" })
      .removeAlpha()
      .raw()
      .toBuffer({ resolveWithObject: true });
    for (let i = 0; i < data.length; i += 3) {
      const [r, g, b] = [data[i], data[i + 1], data[i + 2]];
      const max = Math.max(r, g, b);
      const min = Math.min(r, g, b);
      const sat = max === 0 ? 0 : (max - min) / max;
      if (sat < 0.35 || max < 60) continue;
      const key = ((r >> 5) << 6) | ((g >> 5) << 3) | (b >> 5);
      const s = buckets.get(key) ?? { n: 0, r: 0, g: 0, b: 0 };
      s.n++;
      s.r += r;
      s.g += g;
      s.b += b;
      buckets.set(key, s);
    }
  }
  const ranked = [...buckets.values()].sort((a, b) => b.n - a.n);
  const out = [];
  for (const s of ranked) {
    const rgb = [s.r / s.n, s.g / s.n, s.b / s.n];
    // Skip near-duplicates of a colour we already have.
    if (out.some((o) => Math.hypot(o[0] - rgb[0], o[1] - rgb[1], o[2] - rgb[2]) < 60)) continue;
    out.push(rgb);
    if (out.length === count) break;
  }
  return out.map((c) => `#${c.map((v) => Math.round(v).toString(16).padStart(2, "0")).join("")}`);
}
