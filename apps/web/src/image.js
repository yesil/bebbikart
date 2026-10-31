// Downscale a camera photo on the phone to a ≤ 2048 px JPEG before upload (faster on bad Wi-Fi).
const MAX = 2048;

export async function downscale(file) {
  let bitmap;
  try {
    bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
  } catch {
    return file; // e.g. HEIC on a browser that can't decode it: let the server try
  }
  const scale = Math.min(1, MAX / Math.max(bitmap.width, bitmap.height));
  const w = Math.round(bitmap.width * scale);
  const h = Math.round(bitmap.height * scale);
  const canvas = document.createElement("canvas");
  canvas.width = w;
  canvas.height = h;
  canvas.getContext("2d").drawImage(bitmap, 0, 0, w, h);
  bitmap.close?.();
  const blob = await new Promise((r) => canvas.toBlob(r, "image/jpeg", 0.85));
  return blob ?? file;
}
