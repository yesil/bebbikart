// runDesignJob: photos → two Claude passes → validated RacerSpec file (asset-pipeline.md §1, §5).
//   design (vision: check, look, write the spec) → render in Godot → review (vision: drawings + render → patch)
import { mkdir, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { clampRacerSpec, JOB_STAGES } from "@bebbikart/shared";
import { createClaudeClient } from "./claude.js";
import { normaliseDrawing, UnsupportedFileError } from "./normalise.js";
import {
  buildDesignMessages,
  buildReviewMessages,
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
 * Claude effort per pass (adaptive thinking; ilyas asked for Sonnet 5.5 at high effort).
 * Measured 2026-10-31 on three real drawings: high/high 30–60 s; medium/medium 20–30 s but visibly
 * less faithful (a winged two-wheeler lost its wheels, a yellow car turned orange), so high stays.
 * Override with CLAUDE_PASS_EFFORT="design,review", each low|medium|high|xhigh|max.
 */
export const DESIGN_EFFORT = effortFromEnv(process.env.CLAUDE_PASS_EFFORT) ?? {
  design: "high",
  review: "high",
};

function effortFromEnv(v) {
  if (!v) return null;
  const parts = v.split(",").map((s) => s.trim());
  const ok = ["low", "medium", "high", "xhigh", "max"];
  if (parts.length !== 2 || parts.some((p) => !ok.includes(p)))
    throw new Error(
      `CLAUDE_PASS_EFFORT must be 2 of ${ok.join("|")} for design,review; got "${v}"`,
    );
  const [design, review] = parts;
  return { design, review };
}

/** Tries per pass; each retry carries the validation errors. */
const ATTEMPTS = 3;

class StageFailed extends Error {}

/**
 * @typedef {{ complete: (messages: object[], opts?: object, ctx?: object) => Promise<string>, name: string }} DesignClient
 * @param {{ jobId: string, playerId: string, characterPath: string, vehiclePath: string, outDir: string,
 *           skipCheck?: boolean, reroll?: boolean, name?: string }} input
 * @param {(s: string) => void} [onStatus] called with each of STAGES, then "ready" or "rejected"
 * @param {{ client?: DesignClient, log?: (msg: string) => void, renderer?: { name: string, render: Function } | null }} [deps]
 *   client defaults to Claude from env (ANTHROPIC_API_KEY). renderer builds the first design in Godot so the critique
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
      client = createClaudeClient();
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
    for (let attempt = 1; attempt <= ATTEMPTS; attempt++) {
      let content;
      let usage = null;
      try {
        content = await client.complete(
          messages(errors),
          { ...opts, onUsage: (u) => (usage = u) },
          { ...ctx, stage, attempt },
        );
      } catch (err) {
        // No fallbacks: a failed call fails the job, loudly, with the reason.
        throw new StageFailed(`Claude ${stage} call failed: ${err.message}`);
      }
      const reply = parseReply(content);
      const v = reply.ok ? validate(reply.value) : { ok: false, errors: [reply.error] };
      if (v.ok) {
        timings[stage] = Date.now() - started;
        log(
          `${stage}: ok in ${((Date.now() - started) / 1000).toFixed(1)} s${usage ? ` (${usage.output_tokens} output tokens, ${usage.cache_read_input_tokens ?? 0} cached)` : ""}`,
        );
        return v.value;
      }
      errors = v.errors;
      log(`${stage} attempt ${attempt}: ${errors.slice(0, 3).join("; ")}`);
    }
    throw new StageFailed(
      `Claude ${stage} reply was invalid ${ATTEMPTS} times: ${(errors ?? []).slice(0, 3).join("; ")}`,
    );
  }

  try {
    // 2 · Design: Claude sees both drawings, checks them, looks closely and writes the spec.
    // Thinking is reported as "looking", the written reply as "designing".
    onStatus("looking");
    const design = await pass(
      "design",
      (errors) =>
        buildDesignMessages({
          characterDataUrl: imgs.character.dataUrl,
          vehicleDataUrl: imgs.vehicle.dataUrl,
          approved: !!input.skipCheck,
          reroll: input.reroll,
          previousErrors: errors,
        }),
      { vision: true, effort: DESIGN_EFFORT.design, onText: () => onStatus("designing") },
      (v) => validateDesignReply(v, !!input.skipCheck),
    );
    if (design.rejected)
      return reject(design.rejected.reason, design.rejected.image, design.rejected.seen);

    // 3 · Review: render the racer, show it next to the drawings, apply the reviewer's patch.
    onStatus("critiquing");
    let renders = null;
    if (renderer) {
      const started = Date.now();
      try {
        renders = await renderer.render(design.spec);
      } catch (err) {
        throw new StageFailed(`render for the review failed: ${err.message}`);
      }
      timings.render = Date.now() - started;
      log(`render: ok in ${((Date.now() - started) / 1000).toFixed(1)} s`);
    }
    const shown = {
      observations: design.observations,
      featureMap: design.featureMap,
      spec: design.spec,
    };
    const review = await pass(
      "review",
      (errors) =>
        buildReviewMessages({
          characterDataUrl: imgs.character.dataUrl,
          vehicleDataUrl: imgs.vehicle.dataUrl,
          design: shown,
          renders,
          previousErrors: errors,
        }),
      { vision: true, effort: DESIGN_EFFORT.review, onText: () => onStatus("refining") },
      (v) => validateReview(v, design.spec),
    );

    const fixes = [...design.fixes, ...review.fixes];
    const file = await writeSpec(input.outDir, name, review.spec, {
      jobId: input.jobId,
      playerId: input.playerId,
      model: client.name,
      promptVersion: PROMPT_VERSION,
      reroll: !!input.reroll,
      notes: review.notes || design.notes,
      fixes,
      timingsMs: timings,
      observations: design.observations,
      featureMap: design.featureMap,
      firstDesign: design.spec,
      critique: { scores: review.scores, issues: review.issues },
      patch: review.patch,
    });
    onStatus("ready");
    return {
      status: "ready",
      spec: review.spec,
      fixes,
      notes: review.notes || design.notes,
      critique: { scores: review.scores, issues: review.issues },
      patch: review.patch,
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

/** Design reply → { rejected } or the clamped spec with observations and the featureMap. */
function validateDesignReply(v, approved) {
  if (!approved) {
    const errors = [];
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
    if (errors.length) return { ok: false, errors };
  }
  const d = validateDesign(v);
  if (!d.ok) return d;
  const observations = v.observations && typeof v.observations === "object" ? v.observations : {};
  return { ok: true, value: { ...d.value, observations } };
}

/** Review reply → the patched, clamped spec. */
function validateReview(v, spec) {
  if (!Array.isArray(v.issues)) return { ok: false, errors: ['"issues" must be a list'] };
  if (!Array.isArray(v.patch))
    return { ok: false, errors: ['"patch" must be a list (empty is fine)'] };
  const patched = applyPatch(spec, v.patch);
  if (!patched.ok) return { ok: false, errors: patched.errors };
  const d = validateDesign({ spec: patched.spec });
  if (!d.ok) return { ok: false, errors: d.errors.map((e) => `after your patch, ${e}`) };
  return {
    ok: true,
    value: {
      spec: d.value.spec,
      fixes: d.value.fixes,
      scores: v.scores ?? {},
      issues: v.issues,
      patch: v.patch,
      notes: typeof v.notes === "string" ? v.notes : "",
    },
  };
}

/**
 * Applies the reviewer's patch ops to a copy of the spec. Paths are dot-separated, array items by
 * index; indices refer to the spec as given (sets first, then removes from the highest index, then
 * adds).
 * @returns {{ ok: true, spec: object } | { ok: false, errors: string[] }}
 */
export function applyPatch(spec, ops) {
  const out = structuredClone(spec);
  const errors = [];
  const walk = (path) => {
    const keys = String(path ?? "")
      .split(".")
      .filter(Boolean)
      .map((k) => (/^\d+$/.test(k) ? Number(k) : k));
    if (!keys.length) return null;
    let parent = out;
    for (const k of keys.slice(0, -1)) {
      if (parent == null || typeof parent !== "object" || !(k in parent)) return null;
      parent = parent[k];
    }
    if (parent == null || typeof parent !== "object") return null;
    return { parent, key: keys.at(-1) };
  };
  const order = { set: 0, remove: 1, add: 2 };
  const sorted = ops
    .map((op, i) => ({ op, i }))
    .sort((a, b) => {
      const d = (order[a.op?.op] ?? 9) - (order[b.op?.op] ?? 9);
      if (d) return d;
      if (a.op?.op === "remove") {
        const ka = Number(String(a.op.path).split(".").at(-1));
        const kb = Number(String(b.op.path).split(".").at(-1));
        return (Number.isNaN(kb) ? 0 : kb) - (Number.isNaN(ka) ? 0 : ka);
      }
      return a.i - b.i;
    });
  for (const { op, i } of sorted) {
    const where = `patch[${i}] ${op?.op} ${op?.path}`;
    const at = walk(op?.path);
    if (!at) {
      errors.push(`${where}: path not found`);
      continue;
    }
    const { parent, key } = at;
    if (op.op === "set") {
      if (Array.isArray(parent) && !(typeof key === "number" && key < parent.length))
        errors.push(`${where}: index out of range`);
      else parent[key] = op.value;
    } else if (op.op === "remove") {
      if (Array.isArray(parent)) {
        if (typeof key === "number" && key < parent.length) parent.splice(key, 1);
        else errors.push(`${where}: index out of range`);
      } else if (key in parent) delete parent[key];
      else errors.push(`${where}: nothing to remove`);
    } else if (op.op === "add") {
      if (Array.isArray(parent[key])) parent[key].push(op.value);
      else errors.push(`${where}: "add" needs a path to a list`);
    } else errors.push(`patch[${i}]: unknown op "${op?.op}" (use set, remove or add)`);
  }
  return errors.length ? { ok: false, errors } : { ok: true, spec: out };
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
