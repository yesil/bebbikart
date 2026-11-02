// The game's release build: Godot's release runtime, so no "(DEBUG)" in the window title, no
// debug checks slowing the scripts down and the test keys (weather, boost) off. It is exported
// with the "macOS" preset in apps/game/export_presets.cfg to apps/game/export/BebbiKart.app
// (git-ignored).
//   bun run game:export    export now
//   bun run play           exports first when the build is missing or older than the game's files
// Needs Godot's export templates for the installed Godot version, once: bun run game:templates.
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative } from "node:path";
import { checkTemplates } from "./godot-templates.js";

const ROOT = join(import.meta.dir, "..");
const GAME_DIR = join(ROOT, "apps", "game");
const PRESET = "macOS";
export const APP = join(GAME_DIR, "export", "BebbiKart.app");
// When the last export finished (written after it succeeds, outside the signed app). Taken when
// Godot is done, so the files Godot itself rewrites while exporting (imports) don't count as changes.
const STAMP = join(GAME_DIR, "export", "BebbiKart.exported.json");

const rel = (path) => relative(ROOT, path);

/** The game's executable inside the exported app (the one Info.plist names). */
export function gameBinary() {
  const plistPath = join(APP, "Contents", "Info.plist");
  if (!existsSync(plistPath)) {
    throw new Error(`${rel(plistPath)} is missing: the export did not produce an app`);
  }
  const m = readFileSync(plistPath, "utf8").match(
    /<key>CFBundleExecutable<\/key>\s*<string>([^<]+)<\/string>/,
  );
  if (!m) throw new Error(`${rel(plistPath)} names no CFBundleExecutable`);
  const bin = join(APP, "Contents", "MacOS", m[1]);
  if (!existsSync(bin)) throw new Error(`${rel(bin)} is missing from the exported app`);
  return bin;
}

/** The newest of the game's own files (dot files, .godot/ and export/ left out). */
function newestGameFile(dir = GAME_DIR, newest = { mtimeMs: 0, path: "" }) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".") || (dir === GAME_DIR && entry.name === "export")) continue;
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      newestGameFile(path, newest);
    } else if (entry.isFile()) {
      const { mtimeMs } = statSync(path);
      if (mtimeMs > newest.mtimeMs) Object.assign(newest, { mtimeMs, path });
    }
  }
  return newest;
}

/** Why the release build needs exporting again, or "" when it is up to date. */
export function staleReason() {
  if (!existsSync(APP) || !existsSync(STAMP)) return "there is no release build of the game yet";
  const { exportedAt } = JSON.parse(readFileSync(STAMP, "utf8"));
  const newest = newestGameFile();
  if (newest.mtimeMs > exportedAt) return `${rel(newest.path)} changed after the last export`;
  return "";
}

/** Exports the release build. Throws with the reason when Godot fails. */
export function exportGame() {
  checkTemplates();
  mkdirSync(dirname(APP), { recursive: true });
  // export/ sits inside the Godot project: without this Godot scans it and packs the app's files.
  writeFileSync(join(dirname(APP), ".gdignore"), "");
  // Never leave an older build behind that could be launched by mistake.
  rmSync(APP, { recursive: true, force: true });
  rmSync(STAMP, { force: true });
  console.log(`[export] exporting the game's release build to ${rel(APP)} (preset "${PRESET}")`);
  let proc;
  try {
    proc = Bun.spawnSync(
      ["godot", "--headless", "--path", GAME_DIR, "--export-release", PRESET, APP],
      {
        stdout: "inherit",
        stderr: "inherit",
      },
    );
  } catch (err) {
    throw new Error(`could not run godot (is it on the PATH?): ${err.message}`);
  }
  if (proc.exitCode !== 0) {
    throw new Error(
      `godot --export-release failed with exit code ${proc.exitCode} (its errors are above). ` +
        "If it says an export template is missing: bun run game:templates.",
    );
  }
  const pck = existsSync(join(APP, "Contents", "Resources"))
    ? readdirSync(join(APP, "Contents", "Resources")).filter((f) => f.endsWith(".pck"))
    : [];
  if (pck.length !== 1) {
    throw new Error(
      `godot reported success but ${rel(APP)} has ${pck.length} .pck files, expected 1`,
    );
  }
  gameBinary();
  writeFileSync(STAMP, `${JSON.stringify({ exportedAt: Date.now(), app: rel(APP) })}\n`);
  console.log(`[export] done: ${rel(APP)}`);
}

if (import.meta.main) {
  try {
    exportGame();
  } catch (err) {
    console.error(`[export] ERROR: ${err.message}`);
    process.exit(1);
  }
}
