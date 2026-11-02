// Starts server, phone site and the Godot game (connected to the server) together. Ctrl+C stops all
// three, and so does any one of them stopping (quitting the game, or the server failing to start).
// Extra arguments go to the game, e.g. `bun run dev -- --mode=duel` (king of the hill, split screen).
// The game is imported first when Godot doesn't know all its classes yet (a fresh clone).
import { ensureImported } from "./godot-import.js";

function fail(message) {
  console.error(`[dev] ERROR: ${message}`);
  process.exit(1);
}

try {
  ensureImported();
} catch (err) {
  fail(err.message);
}

// Name whoever holds the server's port before starting anything, instead of running the phone site
// and the game against a server that can't start.
const port = Number(process.env.PORT ?? 8080);
const listener = Bun.spawnSync(["lsof", "-nP", `-iTCP:${port}`, "-sTCP:LISTEN", "-Fpc"]);
const holder = listener.stdout.toString().match(/^p(\d+)\nc(.*)$/m);
if (holder) {
  fail(
    `port ${port} is in use by ${holder[2]} (pid ${holder[1]}), maybe an earlier bun run dev. ` +
      `Stop it with: kill ${holder[1]}`,
  );
}

// The game connects to ws://localhost:8080/ws unless PORT says otherwise.
const server = process.env.PORT ? `--server=ws://localhost:${process.env.PORT}/ws` : "--server";
const procs = [];
let stopping = false;
async function stopAll(code) {
  if (stopping) return;
  stopping = true;
  for (const { proc } of procs) proc.kill();
  await Promise.all(procs.map(({ proc }) => proc.exited));
  process.exit(code);
}

for (const [name, cmd] of [
  ["server", ["bun", "run", "--cwd", "apps/server", "dev"]],
  ["web", ["bun", "run", "--cwd", "apps/web", "dev"]],
  ["game", ["godot", "--path", "apps/game", "--", server, ...process.argv.slice(2)]],
]) {
  try {
    procs.push({ name, proc: Bun.spawn(cmd, { stdout: "inherit", stderr: "inherit" }) });
  } catch (err) {
    // Without this the ones already started would keep running and hold their ports.
    console.error(`[dev] ERROR: could not start the ${name}: ${err.message}`);
    await stopAll(1);
  }
}

for (const { name, proc } of procs) {
  proc.exited.then((code) => {
    if (stopping) return;
    const how = code === 0 ? "stopped" : `exited with code ${code}`;
    (code === 0 ? console.log : console.error)(`[dev] the ${name} ${how}; stopping everything`);
    stopAll(code ?? 1);
  });
}

process.on("SIGINT", () => stopAll(0));
