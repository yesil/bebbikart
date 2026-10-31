#!/usr/bin/env bun
// bun run design <character> <vehicle> [--out out] [--name n] [--mock] [--reroll] [--skip-check]
// bun run design --samples [--mock] [--out out]
import { existsSync } from "node:fs";
import { basename, dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { runDesignJob } from "./design.js";
import { createMockClient, SAMPLE_RUNS } from "./mock.js";

const SAMPLES_DIR = join(dirname(fileURLToPath(import.meta.url)), "..", "samples");

const USAGE = `Usage:
  bun run design <character.jpg> <vehicle.jpg> [options]   design one racer
  bun run design --samples [options]                       design every sample pair

Options:
  --out <dir>     folder for <name>.spec.json files (default: out)
  --name <name>   spec file name (default: from the vehicle file name)
  --mock          use hand-written replies instead of Claude (no API key needed)
  --reroll        "try another look": ask for a different design
  --skip-check    facilitator approved the photos: never reject
  --quiet         don't print the spec JSON
  --jobs <n>      design n racers at the same time (default 1)

Env: ANTHROPIC_API_KEY (required without --mock), CLAUDE_DESIGN_MODEL (default claude-sonnet-5-5),
     CLAUDE_EFFORT, CLAUDE_PASS_EFFORT (design,review), BK_REVIEW_ROUNDS, BK_GODOT_BIN`;

async function main(argv) {
  const [command, ...rest] = argv;
  if (command !== "design") return fail(USAGE);
  const { values, positionals } = parseArgs({
    args: rest,
    allowPositionals: true,
    options: {
      out: { type: "string", default: "out" },
      name: { type: "string" },
      mock: { type: "boolean", default: false },
      reroll: { type: "boolean", default: false },
      "skip-check": { type: "boolean", default: false },
      samples: { type: "boolean", default: false },
      quiet: { type: "boolean", default: false },
      jobs: { type: "string", default: "1" },
      help: { type: "boolean", short: "h", default: false },
    },
  });
  if (values.help) return console.log(USAGE);

  if (!values.mock && !process.env.ANTHROPIC_API_KEY) {
    return fail("ANTHROPIC_API_KEY is not set. Put it in .env (never commit it) or use --mock.");
  }

  const runs = values.samples
    ? SAMPLE_RUNS.map(([name, c, v]) => ({
        name,
        character: join(SAMPLES_DIR, c),
        vehicle: join(SAMPLES_DIR, v),
      }))
    : positionals.length === 2
      ? [
          {
            name: values.name ?? basename(positionals[1], extname(positionals[1])),
            character: positionals[0],
            vehicle: positionals[1],
          },
        ]
      : null;
  if (!runs) return fail(USAGE);
  for (const r of runs) {
    for (const f of [r.character, r.vehicle])
      if (!existsSync(f)) return fail(`File not found: ${f}`);
  }

  const outDir = resolve(values.out);
  const client = values.mock ? createMockClient() : undefined;
  const summary = { ready: 0, rejected: 0, other: 0 };

  const one = async (r) => {
    const started = Date.now();
    const result = await runDesignJob(
      {
        jobId: r.name,
        playerId: "cli",
        name: r.name,
        characterPath: r.character,
        vehiclePath: r.vehicle,
        outDir,
        reroll: values.reroll,
        skipCheck: values["skip-check"],
      },
      undefined,
      { client, log: (m) => console.error(`  … ${r.name} ${m}`) },
    );
    report(r, result, ((Date.now() - started) / 1000).toFixed(1));
  };
  const report = (r, result, secs) => {
    if (result.status === "ready") {
      summary.ready++;
      console.log(`✔ ${r.name}: "${result.spec.title}" → ${result.file} (${secs}s)`);
      if (result.critique?.scores)
        console.log(
          `  critique: ${Object.entries(result.critique.scores)
            .map(([k, v]) => `${k} ${v}`)
            .join(", ")}; ${result.critique.issues.length} issue(s) for the refine pass`,
        );
      if (result.fixes.length) console.log(`  repaired: ${result.fixes.join("; ")}`);
      if (!values.quiet && runs.length === 1) console.log(JSON.stringify(result.spec, null, 2));
    } else if (result.status === "rejected") {
      summary.rejected++;
      console.log(
        `✖ ${r.name}: rejected ${result.image} photo (${result.reason}) — "${result.message}"${result.seen ? ` [saw: ${result.seen}]` : ""}`,
      );
    } else {
      summary.other++;
      console.log(`! ${r.name}: ${result.status} — ${result.error ?? result.notes}`);
    }
  };
  const queue = [...runs];
  const workers = Array.from({ length: Math.max(1, Number(values.jobs) || 1) }, async () => {
    while (queue.length) await one(queue.shift());
  });
  await Promise.all(workers);
  if (runs.length > 1)
    console.log(
      `\n${summary.ready} ready, ${summary.rejected} rejected, ${summary.other} failed → ${outDir}`,
    );
  if (summary.other) process.exitCode = 1;
}

function fail(msg) {
  console.error(msg);
  process.exitCode = 2;
}

await main(process.argv.slice(2));
