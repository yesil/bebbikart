// runDesignJob: photos → one DeepSeek check + design call → validated RacerSpec file (asset-pipeline.md §1, §5).
import { mkdir, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { clampRacerSpec } from "@bebbikart/shared";
import { createDeepSeekClient } from "./deepseek.js";
import { normaliseDrawing, UnsupportedFileError } from "./normalise.js";
import { buildMessages, PROMPT_VERSION, REJECT_MESSAGES } from "./prompt.js";

const IMAGES = /** @type {const} */ (["character", "vehicle"]);

/**
 * @typedef {{ complete: (messages: object[], opts?: object, ctx?: object) => Promise<string>, name: string }} DesignClient
 * @param {{ jobId: string, playerId: string, characterPath: string, vehiclePath: string, outDir: string,
 *           skipCheck?: boolean, reroll?: boolean, name?: string }} input
 * @param {(s: string) => void} [onStatus]
 * @param {{ client?: DesignClient, log?: (msg: string) => void }} [deps] client defaults to DeepSeek from env
 */
export async function runDesignJob(input, onStatus = () => {}, deps = {}) {
  const log = deps.log ?? (() => {});
  const name = input.name ?? input.jobId;

  // 1 · Normalise
  const imgs = {};
  for (const kind of IMAGES) {
    try {
      imgs[kind] = await normaliseDrawing(
        kind === "character" ? input.characterPath : input.vehiclePath,
      );
    } catch (err) {
      if (err instanceof UnsupportedFileError) return reject("unsupported_file", kind);
      return { status: "failed", error: String(err?.message ?? err) };
    }
  }

  let client = deps.client;
  if (!client) {
    try {
      client = createDeepSeekClient();
    } catch (err) {
      return { status: "failed", error: err.message };
    }
  }

  // 2 · Check + design (one call, plus one retry if the reply doesn't validate)
  onStatus("designing");
  const ctx = {
    characterPath: input.characterPath,
    vehiclePath: input.vehiclePath,
    reroll: !!input.reroll,
  };
  let errors = null;
  let notes = "";
  let result = null;
  for (let attempt = 1; attempt <= 2 && !result; attempt++) {
    const messages = buildMessages({
      characterDataUrl: imgs.character.dataUrl,
      vehicleDataUrl: imgs.vehicle.dataUrl,
      reroll: input.reroll,
      previousErrors: errors,
    });
    let content;
    try {
      content = await client.complete(
        messages,
        { temperature: input.reroll ? 1.1 : 0.8 },
        { ...ctx, attempt },
      );
    } catch (err) {
      // No fallbacks: a failed call fails the job, loudly, with the reason.
      return { status: "failed", error: `DeepSeek call failed: ${err.message}` };
    }

    const reply = parseReply(content);
    if (!reply.ok) {
      errors = [reply.error];
      log(`attempt ${attempt}: ${reply.error}`);
      continue;
    }
    notes = typeof reply.value.notes === "string" ? reply.value.notes : "";

    // Rejections only count on the first attempt and when the facilitator hasn't approved the photos.
    if (!input.skipCheck) {
      for (const kind of IMAGES) {
        const c = reply.value.check?.[kind];
        if (c && c.ok === false && c.reason && c.reason in REJECT_MESSAGES)
          return reject(c.reason, kind, c.seen);
      }
    }

    const clamped = clampRacerSpec(reply.value.spec);
    if (clamped.ok) {
      result = { spec: clamped.spec, fixes: clamped.fixes, attempts: attempt };
    } else {
      errors =
        reply.value.spec == null ? ['"spec" is missing: design the racer anyway'] : clamped.errors;
      log(
        `attempt ${attempt}: ${errors.length} validation error(s): ${errors.slice(0, 3).join("; ")}`,
      );
    }
  }

  // 3 · Still broken → fail. No default racer: the drawing must drive the racer or we say so.
  if (!result) {
    return {
      status: "failed",
      error: `DeepSeek reply was invalid twice: ${(errors ?? []).slice(0, 3).join("; ")}`,
    };
  }

  const file = await writeSpec(input.outDir, name, result.spec, {
    jobId: input.jobId,
    playerId: input.playerId,
    model: client.name,
    promptVersion: PROMPT_VERSION,
    reroll: !!input.reroll,
    notes,
    ...result,
    spec: undefined,
  });
  onStatus("ready");
  return {
    status: "ready",
    spec: result.spec,
    fixes: result.fixes,
    notes,
    file,
  };

  function reject(reason, image, seen) {
    onStatus("rejected");
    return {
      status: "rejected",
      reason,
      image,
      message: REJECT_MESSAGES[reason],
      ...(seen ? { seen } : {}),
    };
  }
}

/** Parses the model's JSON reply (tolerates code fences and surrounding text). */
export function parseReply(content) {
  const text = String(content ?? "").trim();
  if (!text) return { ok: false, error: "reply was empty; reply with one JSON object" };
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end < start) return { ok: false, error: "reply contained no JSON object" };
  try {
    const value = JSON.parse(text.slice(start, end + 1));
    if (!value || typeof value !== "object")
      return { ok: false, error: "reply is not a JSON object" };
    return { ok: true, value };
  } catch (err) {
    return { ok: false, error: `reply is not valid JSON: ${err.message}` };
  }
}

/**
 * Writes `<outDir>/<name>.spec.json` (a bare RacerSpec, what the Racer Viewer loads) atomically,
 * plus `<outDir>/_meta/<name>.json` with notes, fixes and model info for tuning.
 */
export async function writeSpec(outDir, name, spec, meta) {
  const safe = String(name).replace(/[^a-zA-Z0-9._-]+/g, "_");
  await mkdir(join(outDir, "_meta"), { recursive: true });
  const file = join(outDir, `${safe}.spec.json`);
  const tmp = join(outDir, `.${safe}.spec.json.tmp`);
  await writeFile(tmp, `${JSON.stringify(spec, null, 2)}\n`);
  await rename(tmp, file);
  await writeFile(
    join(outDir, "_meta", `${safe}.json`),
    `${JSON.stringify({ ...meta, writtenAt: new Date().toISOString() }, null, 2)}\n`,
  );
  return file;
}
