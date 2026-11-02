// Godot's export templates for the installed Godot version, which bun run play and game:export
// need. Installs them once: the release's .tpz (1.3 GB) from GitHub, checked against the release's
// SHA512-SUMS.txt and unpacked into ~/Library/Application Support/Godot/export_templates/<version>/.
//   bun run game:templates
import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
} from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

/** The installed Godot's version, as its templates folder names it ("4.7.2.stable") and as its
 * GitHub release is tagged ("4.7.2-stable"). */
export function godotVersion() {
  let proc;
  try {
    proc = Bun.spawnSync(["godot", "--version"]);
  } catch (err) {
    throw new Error(`could not run godot (is it on the PATH?): ${err.message}`);
  }
  const out = proc.stdout.toString().trim().split("\n").pop() ?? "";
  const m = out.match(/^(\d+\.\d+(?:\.\d+)?)\.([a-z]+\d*)\./);
  if (proc.exitCode !== 0 || !m) throw new Error(`godot --version gave "${out}", not a version`);
  if (out.includes(".mono."))
    throw new Error(`godot is the .NET build (${out}); use the standard one`);
  return { folder: `${m[1]}.${m[2]}`, tag: `${m[1]}-${m[2]}` };
}

export const templatesDir = (folder) =>
  join(homedir(), "Library", "Application Support", "Godot", "export_templates", folder);

/** Throws, saying how to install them, when the templates the macOS export uses are missing. */
export function checkTemplates() {
  const { folder } = godotVersion();
  const zip = join(templatesDir(folder), "macos.zip");
  if (!existsSync(zip)) {
    throw new Error(
      `Godot's export templates for ${folder} are missing (no ${zip}). ` +
        "Install them once with: bun run game:templates (a 1.3 GB download)",
    );
  }
}

async function sha512(path) {
  const hash = createHash("sha512");
  for await (const chunk of Bun.file(path).stream()) hash.update(chunk);
  return hash.digest("hex");
}

function run(cmd) {
  const proc = Bun.spawnSync(cmd, { stdout: "inherit", stderr: "inherit" });
  if (proc.exitCode !== 0)
    throw new Error(`${cmd.join(" ")} failed with exit code ${proc.exitCode}`);
}

async function installTemplates() {
  const { folder, tag } = godotVersion();
  const dest = templatesDir(folder);
  if (existsSync(join(dest, "macos.zip"))) {
    console.log(`[templates] Godot's export templates for ${folder} are already in ${dest}`);
    return;
  }
  const release = `https://github.com/godotengine/godot/releases/download/${tag}`;
  const name = `Godot_v${tag}_export_templates.tpz`;
  const sums = await fetch(`${release}/SHA512-SUMS.txt`);
  if (!sums.ok) throw new Error(`${release}/SHA512-SUMS.txt answered ${sums.status}`);
  const expected = (await sums.text()).match(new RegExp(`^([0-9a-f]{128})\\s+${name}$`, "m"))?.[1];
  if (!expected) throw new Error(`${release}/SHA512-SUMS.txt lists no ${name}`);

  // Next to the destination, so the unpacked files only need renaming into place.
  mkdirSync(join(dest, ".."), { recursive: true });
  const work = mkdtempSync(join(dest, "..", `.download-${folder}-`));
  try {
    const tpz = join(work, name);
    console.log(`[templates] downloading ${release}/${name} (1.3 GB)`);
    run(["curl", "-fL", "--progress-bar", "-o", tpz, `${release}/${name}`]);
    console.log("[templates] checking its SHA-512");
    const got = await sha512(tpz);
    if (got !== expected)
      throw new Error(`${name} has SHA-512 ${got}, the release lists ${expected}`);
    run(["unzip", "-q", tpz, "-d", work]);
    const version = readFileSync(join(work, "templates", "version.txt"), "utf8").trim();
    if (version !== folder)
      throw new Error(`${name} holds templates for ${version}, not ${folder}`);
    mkdirSync(dest, { recursive: true });
    for (const file of readdirSync(join(work, "templates"))) {
      renameSync(join(work, "templates", file), join(dest, file));
    }
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
  checkTemplates();
  console.log(`[templates] installed Godot's export templates for ${folder} in ${dest}`);
}

if (import.meta.main) {
  try {
    await installTemplates();
  } catch (err) {
    console.error(`[templates] ERROR: ${err.message}`);
    process.exit(1);
  }
}
