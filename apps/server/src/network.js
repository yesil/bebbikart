// Can phones reach the server? The address they open, what is known to stop them, and whether a
// phone has got through yet (game-server.md "Networking").
// The server can't see a phone that can't reach it: a Wi-Fi with client isolation (usual on guest
// Wi-Fi) drops the phone's packets before they get to the Mac. So until a phone gets through, the
// server says the address is unproven and why it may not work, instead of claiming it does.
import { realpathSync } from "node:fs";
import { networkInterfaces } from "node:os";

/** What the big screen shows under the code (GET /api/join `network`). */
export const NETWORK = /** @type {const} */ ({
  noNetwork: "no_network", // the Mac has no network address: no code to show
  firewall: "firewall", // the macOS firewall stops phones
  noPhoneYet: "no_phone_yet", // nothing known to stop phones, but none has got through yet
  phoneSeen: "phone_seen", // a phone opened the server on this address
});

export const ISOLATION_HINT =
  "If a phone on the same Wi-Fi can't open it, that Wi-Fi keeps its devices apart (client isolation, " +
  "usual on guest Wi-Fi) and the server can't see the phone at all. Put the Mac and the phones on " +
  "another network, such as a phone's hotspot or a travel router (docs/local-testing.md).";

/**
 * The Mac's address on the local network: the first non-internal IPv4, preferring Ethernet over
 * en0/en1 (Wi-Fi on a Mac). A self-assigned 169.254 address doesn't count: the Mac got no
 * address from it, and phones can't use it. Null when there is none.
 * @returns {{ ip: string, iface: string } | null}
 */
export function lanAddress(nets = networkInterfaces()) {
  const names = Object.keys(nets).sort((a, b) => rank(a) - rank(b));
  for (const name of names) {
    for (const n of nets[name] ?? []) {
      if (n.family === "IPv4" && !n.internal && !n.address.startsWith("169.254."))
        return { ip: n.address, iface: name };
    }
  }
  return null;
}
const rank = (name) => (name === "en0" ? 1 : name === "en1" ? 2 : name.startsWith("en") ? 0 : 3);

const SOCKETFILTERFW = "/usr/libexec/ApplicationFirewall/socketfilterfw";
const FIREWALL_SETTINGS = "System Settings › Network › Firewall › Options";

/** The output of a read-only system tool; throws when it fails. */
async function output(cmd) {
  const proc = Bun.spawn(cmd, { stdout: "pipe", stderr: "pipe" });
  const [out, err, code] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  if (code !== 0) throw new Error(`${cmd.join(" ")} exited ${code}: ${err.trim()}`);
  return out;
}
const socketfilterfw = (...args) => output([SOCKETFILTERFW, ...args]);

/**
 * What the macOS firewall does to phones connecting to `program` (read only, no admin rights):
 * `blocked` says why it stops them, `note` what to expect when it is on but lets them in.
 * Throws when the firewall's answer can't be read.
 * @returns {Promise<{ blocked: string | null, note: string | null }>}
 */
export async function firewallState(program = process.execPath, run = socketfilterfw) {
  if (process.platform !== "darwin") return { blocked: null, note: null };
  const global = await run("--getglobalstate"); // "Firewall is enabled. (State = 1)"
  const state = global.match(/State = (\d)/)?.[1];
  if (state === undefined) throw new Error(`unexpected firewall state: ${global.trim()}`);
  if (state === "0") return { blocked: null, note: null };
  if (state === "2" || /set to enabled/.test(await run("--getblockall")))
    return {
      blocked: `the macOS firewall blocks all incoming connections (${FIREWALL_SETTINGS}: turn off "Block all incoming connections")`,
      note: null,
    };
  const path = realpathSync(program);
  if (/is blocked/.test(await run("--getappblocked", path)))
    return {
      blocked: `the macOS firewall blocks incoming connections to ${path} (${FIREWALL_SETTINGS}: set it to "Allow incoming connections")`,
      note: null,
    };
  return {
    blocked: null,
    note: `the macOS firewall is on: if this Mac asks whether ${path} may accept incoming connections, click Allow`,
  };
}

/**
 * What on this Mac may stop phones without the server being able to read it: a VPN carrying its
 * traffic (many drop local-network connections unless their app allows them), and CrowdStrike
 * Falcon, whose firewall IT sets and which can block incoming connections on networks it doesn't
 * trust. Throws when the system can't be asked.
 * @returns {Promise<{ what: string, advice: string }[]>}
 */
export async function suspectsOnMac(run = output) {
  if (process.platform !== "darwin") return [];
  const found = [];
  let route = "";
  try {
    route = await run(["/sbin/route", "-n", "get", "default"]);
  } catch (err) {
    if (!/not in table/.test(err.message)) throw err; // no default route: no network at all
  }
  const iface = route.match(/interface: (\S+)/)?.[1];
  if (iface && /^(utun|ipsec|ppp|tun|tap)/.test(iface))
    found.push({
      what: `a VPN (${iface})`,
      advice: `a VPN carries this Mac's traffic (${iface}), and many stop phones on the local network: allow LAN connections in the VPN app (Proton VPN: "Allow LAN connections") or disconnect it`,
    });
  const extensions = await run(["/usr/bin/systemextensionsctl", "list"]);
  if (
    extensions.split("\n").some((l) => /crowdstrike/i.test(l) && l.includes("[activated enabled]"))
  )
    found.push({
      what: "CrowdStrike Falcon",
      advice:
        "CrowdStrike Falcon runs on this Mac; its firewall is set by IT, can block incoming connections on networks it doesn't trust, and the server can't read it. If phones can't open the page even on a phone's hotspot, it is Falcon: use a Mac without it, or ask IT",
    });
  return found;
}

/** Where phones open the site: the server itself, or Vite under bun run dev (phoneVitePort), which
 * serves the phone site from source and forwards the rest to the server. */
export function phoneUrl(settings) {
  if (!settings.phoneVitePort) return settings.publicUrl;
  const url = new URL(settings.publicUrl);
  url.port = String(settings.phoneVitePort);
  return url.origin;
}

const LOOPBACK = new Set(["127.0.0.1", "::1"]);
const plain = (ip) => ip.replace(/^::ffff:/, "");

/** Who sent `req`: the peer's address, or under bun run dev the phone Vite forwarded it for. */
export function clientAddress(req, srv) {
  const peer = srv.requestIP(req)?.address;
  if (!peer) return null;
  const forwarded = req.headers.get("x-forwarded-for");
  // Only Vite on this Mac forwards; a forwarded-for header from anyone else is ignored.
  if (forwarded && LOOPBACK.has(plain(peer))) return plain(forwarded.split(",")[0].trim());
  return plain(peer);
}

/**
 * Keeps the phone address up to date and says what it knows about phones reaching it.
 * With `settings.lanAuto` (no PUBLIC_URL), the address follows the Mac's network: when the Mac
 * moves to another Wi-Fi or loses it, `settings.publicUrl` changes and the log says so loudly.
 * `sawClient(ip)` is called for every request; the first one from another device proves the
 * address works on this network.
 */
export function createReach({
  settings,
  log,
  logError,
  nets = networkInterfaces,
  firewall = firewallState,
  suspects = suspectsOnMac,
  everyMs = 3000,
}) {
  let lan = settings.lanAuto ? lanAddress(nets()) : null;
  let fw = { blocked: null, note: null };
  let maybe = []; // suspectsOnMac(): what may stop phones, unreadable
  let phoneFrom = null; // the first other device that opened the server on this address
  let guardChecks = 0;
  let started = false; // the first check goes into the banner, later changes into the log

  /** Where phones open the site now; null when the Mac has no network address. */
  const url = () => (settings.lanAuto && !lan ? null : phoneUrl(settings));

  function network() {
    if (url() === null) return NETWORK.noNetwork;
    if (fw.blocked) return NETWORK.firewall;
    return phoneFrom ? NETWORK.phoneSeen : NETWORK.noPhoneYet;
  }

  /** Why phones can't use the address, or what is still unproven, as log lines. */
  function problemLines() {
    if (url() === null)
      return [
        "NO PHONE ADDRESS: this Mac has no network address, so phones can't reach the server. Join a Wi-Fi: the server picks the address up by itself.",
      ];
    if (fw.blocked) return [`PHONES ARE BLOCKED: ${fw.blocked}.`];
    if (phoneFrom) return [];
    return [
      `No phone has opened it yet. ${ISOLATION_HINT}`,
      ...maybe.map((m) => `MAY BLOCK PHONES: ${m.advice}.`),
    ];
  }

  /** Reads the firewall and the suspects; after start-up, says what changed. */
  async function checkGuards() {
    const was = fw.blocked;
    try {
      fw = await firewall();
    } catch (err) {
      logError(`[network] ERROR: can't read the macOS firewall state: ${err.message}`);
    }
    const before = maybe;
    try {
      maybe = await suspects();
    } catch (err) {
      logError(
        `[network] ERROR: can't check this Mac for a VPN or security software: ${err.message}`,
      );
    }
    if (!started) {
      started = true;
      return;
    }
    if (fw.blocked && fw.blocked !== was)
      logError(`[network] ERROR: phones can't reach the server: ${fw.blocked}.`);
    else if (!fw.blocked && was) log("[network] the macOS firewall lets phones in again");
    for (const m of maybe)
      if (!before.some((b) => b.what === m.what) && !phoneFrom)
        logError(`[network] MAY BLOCK PHONES: ${m.advice}.`);
    for (const b of before)
      if (!maybe.some((m) => m.what === b.what)) log(`[network] ${b.what} is gone`);
  }

  function checkAddress() {
    if (!settings.lanAuto) return;
    const next = lanAddress(nets());
    if (next?.ip === lan?.ip) return;
    const before = url();
    lan = next;
    phoneFrom = null;
    if (!lan) {
      settings.publicUrl = `http://localhost:${settings.port}`;
      logError(
        `[network] ERROR: this Mac left the network (${before} is gone), so phones can't reach the server. Join a Wi-Fi: the server picks the new address up by itself.`,
      );
      return;
    }
    settings.publicUrl = `http://${lan.ip}:${settings.port}`;
    logError(
      `[network] THE PHONE ADDRESS CHANGED: phones now open ${url()} (${lan.iface})${before ? `, not ${before}` : ""}. Phones on the old address must scan the new code on the big screen.`,
    );
    for (const line of problemLines()) logError(`[network] ${line}`);
    checkGuards();
  }

  const ready = checkGuards();
  const timer = setInterval(() => {
    checkAddress();
    // The firewall and the suspects are read through programs, so less often than the address.
    if (++guardChecks % 10 === 0) checkGuards();
  }, everyMs);

  return {
    /** Resolves once the firewall and the suspects have been read the first time. */
    ready,
    url,
    network,
    /** The phone lines of the start-up banner. */
    banner() {
      const lines = problemLines();
      if (fw.note && !fw.blocked) lines.push(`Note: ${fw.note}.`);
      return lines;
    },
    /** Reads the address again (the timer does this every `everyMs`). */
    check: checkAddress,
    sawClient(ip) {
      if (phoneFrom || !ip || LOOPBACK.has(ip)) return;
      const own = Object.values(nets())
        .flat()
        .map((n) => plain(n.address));
      if (own.includes(ip)) return;
      phoneFrom = ip;
      log(
        `[network] a phone got through (${ip} opened the server): phones can reach ${url() ?? settings.publicUrl}`,
      );
    },
    stop() {
      clearInterval(timer);
    },
  };
}
