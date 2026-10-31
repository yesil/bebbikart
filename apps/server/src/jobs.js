// Asset jobs: uploads on disk → runDesignJob (packages/asset-pipeline) → asset package (contracts §5).
import { mkdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { normaliseDrawing, runDesignJob } from "@bebbikart/asset-pipeline";
import { JOB_STAGES, newId } from "@bebbikart/shared";
import { ApiError } from "./errors.js";

const MAX_UPLOAD = 15 * 1024 * 1024;
const MAX_REROLLS = 3;
const now = () => new Date().toISOString();

export function createJobs({ game, settings, log = console.log, logError = console.error }) {
  const queue = [];
  let active = 0;
  // Claude from env (ANTHROPIC_API_KEY). Tests inject a client; there is no mock or fallback at runtime.
  const client = settings.designClient;
  const uploadsDir = join(settings.dataDir, "uploads");
  const assetsDir = join(settings.dataDir, "assets");
  const workDir = join(settings.dataDir, "jobs");

  function newJob(playerId, uploads, extra = {}) {
    const t = now();
    const job = {
      id: newId("job"),
      playerId,
      status: "queued",
      createdAt: t,
      updatedAt: t,
      uploads,
      rerolls: 0,
      ...extra,
    };
    game.saveJob(job);
    game.setPlayerStatus(playerId, "processing");
    queue.push(job.id);
    pump();
    return game.publicJob(job);
  }

  function pump() {
    while (active < settings.designConcurrency && queue.length) {
      const id = queue.shift();
      active++;
      run(id)
        .catch((err) => log(`[job] ${id} crashed: ${err.stack ?? err}`))
        .finally(() => {
          active--;
          pump();
        });
    }
  }

  function update(job, patch) {
    const next = { ...job, ...patch, updatedAt: now() };
    game.saveJob(next);
    return next;
  }

  async function run(id) {
    let job = game.jobs.get(id);
    if (!job || !game.players.has(job.playerId)) return;
    job = update(job, { status: "designing" });
    game.setPlayerStatus(job.playerId, "processing");
    const started = Date.now();
    const input = {
      jobId: job.id,
      playerId: job.playerId,
      characterPath: job.uploads.character,
      vehiclePath: job.uploads.vehicle,
      outDir: join(workDir, job.id),
      skipCheck: !!job.skipCheck,
      reroll: !!job.reroll,
      name: "spec",
    };
    // Stage updates (looking → designing → critiquing → refining) go to the phone.
    const onStatus = (stage) => {
      if (!JOB_STAGES.includes(stage) || done) return;
      job = update(game.jobs.get(job.id) ?? job, { stage });
      game.pushPlayer(job.playerId);
      game.pushRoster(); // the big screen shows who is being made, and the step
      log(`[job] ${job.id} ${stage}…`);
    };
    let result;
    let done = false;
    let timer;
    try {
      result = await Promise.race([
        runDesignJob(input, onStatus, { client, log: (m) => log(`[job] ${job.id} ${m}`) }),
        new Promise((_, rej) => {
          timer = setTimeout(
            () => rej(new Error(`timed out after ${settings.jobTimeoutMs / 1000} s`)),
            settings.jobTimeoutMs,
          );
        }),
      ]);
    } catch (err) {
      result = { status: "failed", error: err.message };
    } finally {
      done = true;
      clearTimeout(timer);
    }
    const { stage: _stage, ...latest } = game.jobs.get(job.id) ?? job;
    job = latest;
    if (!game.players.has(job.playerId)) return; // removed meanwhile
    const secs = ((Date.now() - started) / 1000).toFixed(1);
    if (result.status === "ready") {
      const manifest = await writePackage(job, result);
      update(job, { status: "ready" });
      game.setManifest(job.playerId, manifest);
      log(`[job] ${job.id} ready in ${secs} s: "${manifest.spec.title}"`);
    } else if (result.status === "rejected") {
      update(job, { status: "rejected", rejectReason: result.reason, rejectedImage: result.image });
      game.setPlayerStatus(job.playerId, "rejected");
      log(`[job] ${job.id} rejected: ${result.reason} (${result.image})`);
    } else if (result.status === "needs_review") {
      update(job, { status: "needs_review", error: result.notes });
      game.setPlayerStatus(job.playerId, "needs_review");
      logError(`[job] ${job.id} needs review: ${result.notes}`);
    } else {
      update(job, { status: "failed", error: result.error ?? "unknown error" });
      // The phone shows job.error. A racer that already had a look keeps it (it is theirs, from
      // their earlier drawings); otherwise back to the photo step.
      game.setPlayerStatus(job.playerId, game.manifests.has(job.playerId) ? "ready" : "draft");
      logError(`[job] ${job.id} FAILED after ${secs} s: ${result.error}`);
    }
    await rm(input.outDir, { recursive: true, force: true }).catch(() => {});
  }

  async function writePackage(job, result) {
    const packageId = newId("package");
    const dir = join(assetsDir, packageId);
    await mkdir(dir, { recursive: true });
    await writeFile(join(dir, "spec.json"), `${JSON.stringify(result.spec, null, 2)}\n`);
    // Downscaled copies only; full-size originals are never served.
    for (const kind of ["character", "vehicle"]) {
      const { jpeg } = await normaliseDrawing(job.uploads[kind]);
      await writeFile(join(dir, `drawing_${kind}.jpg`), jpeg);
    }
    const base = `/assets/${packageId}`;
    return {
      packageId,
      playerId: job.playerId,
      updatedAt: now(),
      spec: result.spec,
      drawings: {
        character: `${base}/drawing_character.jpg`,
        vehicle: `${base}/drawing_vehicle.jpg`,
      },
      renders: {},
    };
  }

  return {
    /** POST …/drawings: both files required. */
    async upload(playerId, form) {
      const files = {};
      for (const kind of ["character", "vehicle"]) {
        const f = form.get(kind);
        if (!f || typeof f === "string")
          throw new ApiError("bad_request", `Missing the ${kind} photo`, 400);
        if (f.size > MAX_UPLOAD)
          throw new ApiError("bad_request", `The ${kind} photo is too big`, 400);
        files[kind] = f;
      }
      const dir = join(uploadsDir, playerId);
      await mkdir(dir, { recursive: true });
      const stamp = Date.now();
      const uploads = {};
      for (const [kind, f] of Object.entries(files)) {
        const ext = (f.name?.match(/\.(jpe?g|png|heic|heif|webp)$/i)?.[1] ?? "jpg").toLowerCase();
        uploads[kind] = join(dir, `${stamp}-${kind}.${ext}`);
        await Bun.write(uploads[kind], f);
      }
      return newJob(playerId, uploads);
    },
    reroll(playerId) {
      const last = game.latestJob(playerId);
      if (!last?.uploads) throw new ApiError("not_ready", "Send your drawings first", 409);
      if (last.status === "queued" || last.status === "designing")
        throw new ApiError("not_ready", "Still working on your racer", 409);
      if ((last.rerolls ?? 0) >= MAX_REROLLS)
        throw new ApiError("reroll_limit", "That's all the new looks for now", 409);
      return newJob(playerId, last.uploads, {
        reroll: true,
        rerolls: (last.rerolls ?? 0) + 1,
        skipCheck: true,
      });
    },
    approve(playerId) {
      const last = game.latestJob(playerId);
      if (!last?.uploads) throw new ApiError("not_found", "No drawings to approve", 404);
      return newJob(playerId, last.uploads, { skipCheck: true, rerolls: last.rerolls ?? 0 });
    },
    async deleteAll() {
      await rm(uploadsDir, { recursive: true, force: true });
      await rm(assetsDir, { recursive: true, force: true });
    },
  };
}
