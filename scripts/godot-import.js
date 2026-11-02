// Godot's import of the game, run before the game starts from source (bun run dev, dev:game,
// game:mock, maps:*). Godot keeps the project's class names (class_name Protocol, RacerSpec, …) in
// apps/game/.godot/global_script_class_cache.cfg, which only the editor's import writes. A fresh
// clone has no .godot/, and a pull can add or move a class_name script; the game then fails with
// 'Identifier "Protocol" not declared in the current scope'. So this imports whenever that cache
// misses a class the scripts declare, and throws when the import fails or still leaves one out.
//   bun run game:import    check, and import when needed
// The release build (bun run play / game:export) needs none of this: exporting imports first.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";

const GAME_DIR = join(import.meta.dir, "..", "apps", "game");
const CLASS_CACHE = join(GAME_DIR, ".godot", "global_script_class_cache.cfg");

/** "Name res://path.gd" for every class_name the game's scripts declare. Like Godot, it skips
 * dot folders and folders with a .gdignore. */
function declaredClasses(dir = GAME_DIR, found = new Set()) {
  const entries = readdirSync(dir, { withFileTypes: true });
  if (entries.some((entry) => entry.name === ".gdignore")) return found;
  for (const entry of entries) {
    if (entry.name.startsWith(".")) continue;
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      declaredClasses(path, found);
    } else if (entry.isFile() && entry.name.endsWith(".gd")) {
      const m = readFileSync(path, "utf8").match(/^(?:@\w+\s+)*class_name\s+(\w+)/m);
      if (m) found.add(`${m[1]} res://${relative(GAME_DIR, path)}`);
    }
  }
  return found;
}

/** "Name res://path.gd" for every class in Godot's class cache (empty when there is none). */
function cachedClasses() {
  if (!existsSync(CLASS_CACHE)) return new Set();
  const text = readFileSync(CLASS_CACHE, "utf8");
  // Each entry lists its keys in order: base, class, icon, is_abstract, is_tool, language, path.
  const entries = text.matchAll(/"class": &"(\w+)",[^}]*?"path": "([^"]+)"/g);
  return new Set([...entries].map(([, name, path]) => `${name} ${path}`));
}

/** The declared classes Godot's class cache lacks, or has at another path. */
export function missingClasses() {
  const cached = cachedClasses();
  return [...declaredClasses()].filter((entry) => !cached.has(entry));
}

/** Imports the game when Godot's class cache misses a declared class. Throws when that fails. */
export function ensureImported() {
  const missing = missingClasses();
  if (missing.length === 0) return;
  const why = existsSync(CLASS_CACHE)
    ? `Godot's class cache lacks ${missing.map((entry) => entry.split(" ")[0]).join(", ")}`
    : "it was never imported (a fresh clone); this takes under a minute";
  console.log(`[import] importing the game: ${why}`);
  let proc;
  try {
    proc = Bun.spawnSync(["godot", "--headless", "--path", GAME_DIR, "--import"], {
      stdout: "inherit",
      stderr: "inherit",
    });
  } catch (err) {
    throw new Error(`could not run godot (is it on the PATH?): ${err.message}`);
  }
  if (proc.exitCode !== 0) {
    throw new Error(`godot --import failed with exit code ${proc.exitCode} (its errors are above)`);
  }
  const still = missingClasses();
  if (still.length > 0) {
    throw new Error(
      `godot --import finished, but its class cache still lacks: ${still.join(", ")}`,
    );
  }
  console.log("[import] done");
}

if (import.meta.main) {
  try {
    ensureImported();
  } catch (err) {
    console.error(`[import] ERROR: ${err.message}`);
    process.exit(1);
  }
}
