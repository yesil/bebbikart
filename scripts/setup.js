import { createHash } from "node:crypto";
import { existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const GAME = join(ROOT, "apps/game");
const BUILD = join(ROOT, ".build");
const TEXTURES = {
  Grass004: "4b63495f459db8481f4d5144e4e9069345c81cf898cc71f2216f5dd3bb344469",
  Ground037: "4e69db2b7251b1736fa70fe6fe4ab80d64bd220117dd5dd4c7caaead51c2574e",
  Ground054: "b325ec2f167dce95a0fabc61a2104641288cf20915419578c3efdb46200c563e",
  Gravel022: "7049ff2bd4d8f87317c26bbffb8c5621208fbfcc615765038eef92fd227c220f",
  Ground048: "3decfdd20e6c8f8c1ff02840cbd336922fca678e23987111af4bebb0a7a89c96",
  Rock030: "2fd0bc2d214e2487c19062ed0798a85dd135b41cfc12bbaed42d5acae238f989",
};

function run(cmd) {
  const result = Bun.spawnSync(cmd, { cwd: ROOT, stdout: "inherit", stderr: "inherit" });
  if (result.exitCode !== 0) throw new Error(`${cmd.join(" ")} failed (${result.exitCode})`);
}

async function download(url, name, expected) {
  const path = join(BUILD, name);
  if (!existsSync(path)) {
    console.log(`[setup] downloading ${name}`);
    const response = await fetch(url, { signal: AbortSignal.timeout(180_000) });
    if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
    await Bun.write(path, response);
  }
  const hash = createHash("sha256");
  for await (const chunk of Bun.file(path).stream()) hash.update(chunk);
  if (hash.digest("hex") !== expected) {
    throw new Error(`${path}: SHA-256 mismatch; remove this download and retry`);
  }
  return path;
}

function godot(script) {
  run(["godot", "--headless", "--path", GAME, "--script", `res://tools/${script}.gd`]);
}

async function setup() {
  for (const tool of ["godot", "unzip", "fluidsynth", "ffmpeg"]) {
    if (!Bun.which(tool)) throw new Error(`Install ${tool} before running setup (see README.md)`);
  }
  if (!process.env.SOUNDFONT || !existsSync(process.env.SOUNDFONT)) {
    throw new Error("Set SOUNDFONT in .env to MuseScore_General.sf2 (see README.md)");
  }
  const encoders = Bun.spawnSync(["ffmpeg", "-hide_banner", "-encoders"]);
  if (encoders.exitCode !== 0 || !encoders.stdout.toString().includes("libvorbis")) {
    throw new Error("FFmpeg must include the libvorbis encoder (see README.md)");
  }
  mkdirSync(BUILD, { recursive: true });
  const terrain = await download(
    "https://github.com/TokisanGames/Terrain3D/releases/download/v1.1.0-stable/Terrain3D_v1.1.0-stable.zip",
    "Terrain3D_v1.1.0-stable.zip",
    "51b78bc758f5759cbc8eaaab14e5cf4e8661717e265fdd760f5abf945f15b243",
  );
  run(["unzip", "-o", "-q", terrain, "addons/terrain_3d/bin/*", "-d", GAME]);
  for (const [name, hash] of Object.entries(TEXTURES)) {
    const file = `${name}_1K-JPG.zip`;
    const zip = await download(`https://ambientcg.com/get?file=${file}`, file, hash);
    const dir = join(BUILD, "textures", name);
    mkdirSync(dir, { recursive: true });
    run(["unzip", "-o", "-q", zip, "*.jpg", "-d", dir]);
  }
  run([
    "godot",
    "--headless",
    "--script",
    join(GAME, "tools/pack_textures.gd"),
    "--",
    join(BUILD, "textures"),
    join(GAME, "assets/textures/terrain"),
  ]);
  run(["bun", "run", "kit:export"]);
  run(["bun", "run", "--cwd", "packages/asset-pipeline", "samples"]);
  run(["bun", "run", "audio:cues"]);
  run(["godot", "--headless", "--path", GAME, "--import"]);
  mkdirSync(join(ROOT, "packages/shared/src/track-maps"), { recursive: true });
  godot("export_track_maps");
  godot("bake_world");
  godot("bake_village");
  run(["godot", "--headless", "--path", GAME, "--import"]);
  console.log("[setup] ready: bun run dev or bun run play");
}

try {
  await setup();
} catch (error) {
  console.error(`[setup] ${error.message}`);
  process.exit(1);
}
