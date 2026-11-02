// Starts server, phone site and the Godot game (connected to the server) together. Ctrl+C or kill
// stops all three, and so does any one of them stopping (quitting the game, a server crash).
// Extra arguments go to the game, e.g. `bun run dev -- --mode=duel` (king of the hill, split screen).
// The game is imported first when Godot doesn't know all its classes yet (a fresh clone), and a
// server or Vite left over from an earlier run is stopped first (scripts/ports.js).
import { ensureImported } from "./godot-import.js";
import { freePort } from "./ports.js";

const VITE_PORT = 5173; // apps/web/vite.config.js

function fail(message) {
  console.error(`[dev] ERROR: ${message}`);
  process.exit(1);
}

try {
  ensureImported();
  await freePort(Number(process.env.PORT ?? 8080), "server");
  await freePort(VITE_PORT, "phone site's Vite");
} catch (err) {
  fail(err.message);
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

for (const [name, cmd, extraEnv] of [
  // The server sends phones (the big screen's QR code) to Vite, which has the phone site.
  ["server", ["bun", "run", "--cwd", "apps/server", "dev"], { BK_PHONE_VITE_PORT: `${VITE_PORT}` }],
  ["web", ["bun", "run", "--cwd", "apps/web", "dev"]],
  ["game", ["godot", "--path", "apps/game", "--", server, ...process.argv.slice(2)]],
]) {
  try {
    const env = { ...process.env, ...extraEnv };
    procs.push({ name, proc: Bun.spawn(cmd, { env, stdout: "inherit", stderr: "inherit" }) });
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
process.on("SIGTERM", () => stopAll(0));
