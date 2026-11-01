// Starts server, phone site and the Godot game (connected to the server) together. Ctrl+C stops all three.
// Extra arguments go to the game, e.g. `bun run dev -- --mode=duel` (king of the hill, split screen).
const procs = [
  ["server", ["bun", "run", "--cwd", "apps/server", "dev"]],
  ["web", ["bun", "run", "--cwd", "apps/web", "dev"]],
  ["game", ["godot", "--path", "apps/game", "--", "--server", ...process.argv.slice(2)]],
].map(([name, cmd]) => {
  const proc = Bun.spawn(cmd, { stdout: "inherit", stderr: "inherit" });
  proc.exited.then((code) => console.log(`[dev] ${name} exited with code ${code}`));
  return proc;
});

process.on("SIGINT", () => {
  for (const proc of procs) proc.kill();
  process.exit(0);
});
