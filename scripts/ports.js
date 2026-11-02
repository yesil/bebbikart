// Frees the ports bun run dev and bun run play listen on when a leftover of an earlier run of this
// clone still holds them: its server (apps/server) or Vite (apps/web), whose bun run dev or play is
// gone (it crashed, or was killed) so nothing will ever stop it. Whatever else holds the port (a
// running bun run dev or play, something started from a terminal, another app) is left alone and
// named in the error.
import { join, sep } from "node:path";

const ROOT = join(import.meta.dir, "..");
const OWN_DIRS = [join(ROOT, "apps", "server"), join(ROOT, "apps", "web")];

const output = (cmd) => Bun.spawnSync(cmd).stdout.toString();

/** The pid listening on a TCP port, or 0 when it is free. */
function listener(port) {
  return Number(output(["lsof", "-nP", `-iTCP:${port}`, "-sTCP:LISTEN", "-t"]).split("\n")[0]);
}

/** { ppid, args } of a running process, or null when it is gone. */
function processInfo(pid) {
  const m = output(["ps", "-o", "ppid=,args=", "-p", String(pid)]).match(/^\s*(\d+)\s+(.*)$/m);
  return m ? { ppid: Number(m[1]), args: m[2] } : null;
}

const cwdOf = (pid) =>
  output(["lsof", "-a", "-p", String(pid), "-d", "cwd", "-Fn"]).match(/^n(.*)$/m)?.[1] ?? "";
const isBun = (args) => ["bun", "node"].includes(args.split(/\s+/)[0].split("/").pop());
const insideRoot = (dir) => `${dir}${sep}`.startsWith(`${ROOT}${sep}`);

/** The leftover process chain holding the port, from the listener up to the process launchd
 * adopted, or { blocker, stop } saying who holds it, and which pid to stop, when that isn't a
 * leftover of this clone. */
function holder(pid) {
  const listening = processInfo(pid);
  if (!listening) return { chain: [] };
  if (!isBun(listening.args) || !OWN_DIRS.includes(cwdOf(pid))) {
    return { blocker: `${listening.args} (pid ${pid})`, stop: pid };
  }
  const chain = [];
  for (let p = pid, info = listening; info; p = info.ppid, info = processInfo(p)) {
    if (/scripts\/(dev|play)\.js/.test(info.args)) {
      // Ctrl+C in its terminal or a kill: either way dev.js and play.js stop what they started.
      const script = info.args.match(/(dev|play)\.js/)[1];
      return { blocker: `a running bun run ${script} (pid ${p})`, stop: p };
    }
    if (!isBun(info.args) || !insideRoot(cwdOf(p))) {
      return {
        blocker: `${listening.args} (pid ${pid}), started from ${info.args} (pid ${p})`,
        stop: pid,
      };
    }
    chain.push(p);
    if (info.ppid <= 1) return { chain };
  }
  return { chain };
}

/** Makes sure `port` is free for `name`: stops a leftover of an earlier run of this clone, and
 * throws naming anything else that holds it. */
export async function freePort(port, name) {
  const pid = listener(port);
  if (!pid) return;
  const { chain, blocker, stop } = holder(pid);
  if (blocker) {
    throw new Error(
      `port ${port} (the ${name}) is in use by ${blocker}. Stop it first: kill ${stop}`,
    );
  }
  console.log(
    `[ports] port ${port} (the ${name}) is held by a leftover of an earlier run, ` +
      `${processInfo(pid)?.args} (pid ${pid}): stopping it`,
  );
  for (const p of chain.reverse()) {
    try {
      process.kill(p, "SIGTERM");
    } catch (err) {
      // ESRCH: already gone, as stopping its parent can take it down first.
      if (err.code !== "ESRCH") throw err;
    }
  }
  for (let i = 0; i < 50; i++) {
    if (!listener(port)) return;
    await Bun.sleep(100);
  }
  throw new Error(
    `the leftover on port ${port} (pid ${pid}) did not stop; stop it with: kill -9 ${pid}`,
  );
}
