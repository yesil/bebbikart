// runDesignJob: photos → four DeepSeek passes → validated RacerSpec file (asset-pipeline.md §1, §5).
//   look (vision: check + describe) → design (spec) → critique (vision: compare with the drawings) → refine (final spec)
import { mkdir, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { clampRacerSpec, JOB_STAGES } from "@bebbikart/shared";
import { createDeepSeekClient } from "./deepseek.js";
import { normaliseDrawing, UnsupportedFileError } from "./normalise.js";
import {
  buildCritiqueMessages,
  buildDesignMessages,
  buildLookMessages,
  buildRefineMessages,
  PROMPT_VERSION,
  REJECT_MESSAGES,
} from "./prompt.js";
import { createGodotRenderer } from "./render.js";

const IMAGES = /** @type {const} */ (["character", "vehicle"]);

/** Progress stages reported through onStatus (JOB_STAGES in shared), then "ready" / "rejected". */
export const STAGES = JOB_STAGES;

/** Fields the designer must always write for new racers (optional in the stored schema for old ones). */
const REQUIRED_NEW = ["tagline", "motion", "sound"];

/**
 * Thinking effort per pass. Measured on deepseek-flash (2026-10-31, 4 racers at a time):
 *   look      high/max 12–37 s
 *   design    off 7–20 s · low 55–80 s, timed out at 150 s on a real drawing · high 50–145 s
 *   critique  off ~10 s · low/high 40–120 s
 *   refine    off ~10 s · low 10–60 s
 * Thinking on the text passes gave no clear gain once the look pass had described the drawings in
 * detail, so only the look pass thinks: ~45–60 s per racer.
 * Override with DEEPSEEK_EFFORT="look,design,critique,refine", e.g. "max,low,off,off".
 */
export const DESIGN_EFFORT = effortFromEnv(process.env.DEEPSEEK_EFFORT) ?? {
  look: "high",
  design: "off",
  critique: "off",
  refine: "off",
};

function effortFromEnv(v) {
  if (!v) return null;
  const parts = v.split(",").map((s) => s.trim());
  const ok = ["off", "low", "high", "max"];
  if (parts.length !== 4 || parts.some((p) => !ok.includes(p)))
    throw new Error(
      `DEEPSEEK_EFFORT must be 4 of ${ok.join("|")} for look,design,critique,refine; got "${v}"`,
    );
  const [look, design, critique, refine] = parts;
  return { look, design, critique, refine };
}

class StageFailed extends Error {}

/**
 * @typedef {{ complete: (messages: object[], opts?: object, ctx?: object) => Promise<string>, name: string }} DesignClient
 * @param {{ jobId: string, playerId: string, characterPath: string, vehiclePath: string, outDir: string,
 *           skipCheck?: boolean, reroll?: boolean, name?: string }} input
 * @param {(s: string) => void} [onStatus] called with each of STAGES, then "ready" or "rejected"
 * @param {{ client?: DesignClient, log?: (msg: string) => void, renderer?: { name: string, render: Function } | null }} [deps]
 *   client defaults to DeepSeek from env. renderer builds the first design in Godot so the critique
 *   sees the real racer; it defaults to the Godot renderer, except with an injected client (tests,
 *   --mock), where the default is none. A failing render fails the job.
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

  const renderer =
    deps.renderer !== undefined ? deps.renderer : deps.client ? null : createGodotRenderer();

  const ctx = {
    characterPath: input.characterPath,
    vehiclePath: input.vehiclePath,
    reroll: !!input.reroll,
  };
  const timings = {};

  /**
   * One pass: call, parse, validate; one retry with the validation errors. Throws StageFailed.
   * @param {string} stage
   * @param {(errors: string[] | null) => object[]} messages
   * @param {object} opts
   * @param {(value: any) => { ok: true, value: any } | { ok: false, errors: string[] }} validate
   */
  async function pass(stage, messages, opts, validate) {
    const started = Date.now();
    let errors = null;
    for (let attempt = 1; attempt <= 2; attempt++) {
      let content;
      try {
        content = await client.complete(messages(errors), opts, { ...ctx, stage, attempt });
      } catch (err) {
        // No fallbacks: a failed call fails the job, loudly, with the reason.
        throw new StageFailed(`DeepSeek ${stage} call failed: ${err.message}`);
      }
      const reply = parseReply(content);
      const v = reply.ok ? validate(reply.value) : { ok: false, errors: [reply.error] };
      if (v.ok) {
        timings[stage] = Date.now() - started;
        log(`${stage}: ok in ${((Date.now() - started) / 1000).toFixed(1)} s`);
        return v.value;
      }
      errors = v.errors;
      log(`${stage} attempt ${attempt}: ${errors.slice(0, 3).join("; ")}`);
    }
    throw new StageFailed(
      `DeepSeek ${stage} reply was invalid twice: ${(errors ?? []).slice(0, 3).join("; ")}`,
    );
  }

  try {
    // 2 · Look: check both photos and describe them.
    onStatus("looking");
    const look = await pass(
      "look",
      (errors) =>
        buildLookMessages({
          characterDataUrl: imgs.character.dataUrl,
          vehicleDataUrl: imgs.vehicle.dataUrl,
          approved: !!input.skipCheck,
          previousErrors: errors,
        }),
      { vision: true, effort: DESIGN_EFFORT.look, temperature: 0.3 },
      (v) => validateLook(v, !!input.skipCheck),
    );
    if (look.rejected) return reject(look.rejected.reason, look.rejected.image, look.rejected.seen);
    const observations = { character: look.value.character, vehicle: look.value.vehicle };

    // 3 · Design the racer from the description.
    onStatus("designing");
    const design = await pass(
      "design",
      (errors) =>
        buildDesignMessages({ observations, reroll: input.reroll, previousErrors: errors }),
      { effort: DESIGN_EFFORT.design, temperature: input.reroll ? 1.1 : 0.9 },
      validateDesign,
    );

    // 4 · Critique the design against the real drawings (and the racer it builds, when rendered).
    onStatus("critiquing");
    let renders = null;
    if (renderer) {
      const started = Date.now();
      try {
        renders = await renderer.render(design.spec);
      } catch (err) {
        throw new StageFailed(`render for the critique failed: ${err.message}`);
      }
      timings.render = Date.now() - started;
      log(`render: ok in ${((Date.now() - started) / 1000).toFixed(1)} s`);
    }
    const critique = await pass(
      "critique",
      () =>
        buildCritiqueMessages({
          characterDataUrl: imgs.character.dataUrl,
          vehicleDataUrl: imgs.vehicle.dataUrl,
          observations,
          design: { featureMap: design.featureMap, spec: design.spec, notes: design.notes },
          renders,
        }),
      { vision: true, effort: DESIGN_EFFORT.critique, temperature: 0.4 },
      validateCritique,
    );

    // 5 · Refine: apply the critique.
    onStatus("refining");
    const final = await pass(
      "refine",
      (errors) =>
        buildRefineMessages({
          observations,
          design: { featureMap: design.featureMap, spec: design.spec, notes: design.notes },
          critique,
          previousErrors: errors,
        }),
      { effort: DESIGN_EFFORT.refine, temperature: 0.7 },
      validateDesign,
    );

    const file = await writeSpec(input.outDir, name, final.spec, {
      jobId: input.jobId,
      playerId: input.playerId,
      model: client.name,
      promptVersion: PROMPT_VERSION,
      reroll: !!input.reroll,
      notes: final.notes,
      fixes: final.fixes,
      timingsMs: timings,
      observations,
      featureMap: final.featureMap,
      firstDesign: design.spec,
      critique,
    });
    onStatus("ready");
    return {
      status: "ready",
      spec: final.spec,
      fixes: final.fixes,
      notes: final.notes,
      critique,
      timingsMs: timings,
      file,
    };
  } catch (err) {
    if (err instanceof StageFailed) return { status: "failed", error: err.message };
    throw err;
  }

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

/** Look reply → { ok, value: { rejected } | { value: { character, vehicle } } }. */
function validateLook(v, approved) {
  const errors = [];
  if (!approved) {
    for (const kind of IMAGES) {
      const c = v.check?.[kind];
      if (!c || typeof c.ok !== "boolean") errors.push(`check.${kind}.ok is missing`);
      else if (c.ok === false) {
        if (!(c.reason in REJECT_MESSAGES))
          errors.push(
            `check.${kind}.reason must be one of ${Object.keys(REJECT_MESSAGES).join(", ")}`,
          );
        else
          return { ok: true, value: { rejected: { reason: c.reason, image: kind, seen: c.seen } } };
      }
    }
  }
  for (const kind of IMAGES) {
    const d = v[kind];
    if (!d || typeof d !== "object")
      errors.push(`"${kind}" description is missing: describe the drawing`);
    else if (!Array.isArray(d.features) || d.features.length === 0)
      errors.push(`${kind}.features is empty: list every visible feature`);
  }
  return errors.length ? { ok: false, errors } : { ok: true, value: { value: v } };
}

/** Design/refine reply → clamped spec with the fields new racers need. */
function validateDesign(v) {
  if (v.spec == null) return { ok: false, errors: ['"spec" is missing: design the racer'] };
  const clamped = clampRacerSpec(v.spec);
  if (!clamped.ok) return { ok: false, errors: clamped.errors };
  const missing = REQUIRED_NEW.filter((k) => clamped.spec[k] == null);
  if (missing.length)
    return { ok: false, errors: missing.map((k) => `spec.${k} is missing: new racers need it`) };
  return {
    ok: true,
    value: {
      spec: clamped.spec,
      fixes: clamped.fixes,
      featureMap: Array.isArray(v.featureMap) ? v.featureMap : [],
      notes: typeof v.notes === "string" ? v.notes : "",
    },
  };
}

function validateCritique(v) {
  if (!Array.isArray(v.issues)) return { ok: false, errors: ['"issues" must be a list'] };
  return {
    ok: true,
    value: { scores: v.scores ?? {}, issues: v.issues, verdict: v.verdict ?? "" },
  };
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
