// Real play on the big screen: the phone site built and served by the server (no Vite, no file
// watching) and the game's release build (scripts/game-export.js) connected to it.
// The game is exported first when its build is missing or older than the game's files.
// Ctrl+C, or quitting the game (⌘Q), stops both; if either one stops, the other is stopped too.
// Extra arguments go to the game, e.g. `bun run play -- --quality=high`.
import { join } from "node:path";
import { exportGame, gameBinary, staleReason } from "./game-export.js";
import { freePort } from "./ports.js";

const ROOT = join(import.meta.dir, "..");

function fail(message) {
  console.error(`[play] ERROR: ${message}`);
  process.exit(1);
}

let game;
try {
  const reason = staleReason();
  if (reason) {
    console.log(`[play] ${reason}: exporting the game first`);
    exportGame();
  }
  game = gameBinary();
  // A server left over from an earlier bun run dev or play is stopped; anything else fails here.
  await freePort(Number(process.env.PORT ?? 8080), "server");
} catch (err) {
  fail(err.message);
}

const build = Bun.spawnSync(["bun", "run", "build:web"], {
  cwd: ROOT,
  stdout: "inherit",
  stderr: "inherit",
});
if (build.exitCode !== 0) fail(`building the phone site failed with exit code ${build.exitCode}`);

// The game connects to ws://localhost:8080/ws unless PORT says otherwise.
const server = process.env.PORT ? `--server=ws://localhost:${process.env.PORT}/ws` : "--server";
const procs = [
  ["server", ["bun", "src/index.js"], join(ROOT, "apps", "server")],
  ["game", [game, "--", server, ...process.argv.slice(2)], ROOT],
].map(([name, cmd, cwd]) => ({
  name,
  proc: Bun.spawn(cmd, { cwd, stdout: "inherit", stderr: "inherit" }),
}));

let stopping = false;
async function stopAll(code) {
  if (stopping) return;
  stopping = true;
  for (const { proc } of procs) proc.kill();
  await Promise.all(procs.map(({ proc }) => proc.exited));
  process.exit(code);
}

for (const { name, proc } of procs) {
  proc.exited.then((code) => {
    if (stopping) return;
    const how = code === 0 ? "stopped" : `exited with code ${code}`;
    (code === 0 ? console.log : console.error)(`[play] the ${name} ${how}; stopping everything`);
    stopAll(code ?? 1);
  });
}

process.on("SIGINT", () => stopAll(0));
process.on("SIGTERM", () => stopAll(0));
