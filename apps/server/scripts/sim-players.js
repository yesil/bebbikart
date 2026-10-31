// Multi-player harness: N scripted phones over real HTTP + WebSocket, exactly like the phone app.
//   bun run sim-players -- --players 4                     (server on http://localhost:8080)
//   bun run sim-players -- --players 8 --url http://localhost:8090 --races 3 --stagger 1500
// Each phone gets a device cookie, creates a racer, uploads a sample drawing pair, waits for the
// design job (real Claude) and the big screen's renders, sets a random build, presses Go (all at
// once, or --stagger ms apart), taps Boost, waits for the result and races again (--races).
// It logs a timeline and ends with timings (join → racer ready, Go → on track, boost tap → seen,
// finish → result on the phone), message counts per phone and every error. Exit 1 on any error.
//
// Racers are kept between runs: device ids go to --state (default .sim-players.json next to the
// data dir you pass with --state), so a second run reuses the racers instead of designing new
// ones. New designs are capped by --max-new (default 8): real Claude calls cost money.
//
// Flags: --players N (4) --url URL --races N (2) --stagger MS (0) --join-stagger MS (0)
//   --waves N --wave-gap MS (1, 20000): Go in N groups, wave-gap apart (a second group lines up
//   while the first is still racing, e.g. lapping past the start line)
//   --state FILE --fresh (forget saved racers) --max-new N (8) --names A,B,C --seed N (1)
//   --renders 0 (don't wait for the game's hero/avatar renders, e.g. with fake-game)
//   --track countryside|village (switches via the admin API: ends the session, new leaderboard)
//   --pit (loop tracks: tap Pit in after the first lap) --boosts N (taps per race, 3)
//   --pin PIN (BK_ADMIN_PIN, 1234) --json FILE (write the full report) --quiet (no timeline)
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { ABILITIES, DRIVING_STYLES, FORK_CHOICES, LOOP_TRACKS, makeMsg } from "@bebbikart/shared";
import { REPO_ROOT } from "../src/env.js";

const SAMPLES = join(REPO_ROOT, "packages/asset-pipeline/samples");
const PAIRS = [
  ["pair01-character-cat.jpg", "pair01-vehicle-kart.jpg"],
  ["pair02-character-robot.jpg", "pair02-vehicle-rocket-shoe.jpg"],
  ["pair03-character-dino.jpg", "pair03-vehicle-bike.jpg"],
  ["pair04-character-girl-crown.jpg", "pair04-vehicle-horse.jpg"],
  ["pair05-character-alien.jpg", "pair05-vehicle-dragon.jpg"],
  ["pair06-character-blob-monster.jpg", "pair06-vehicle-boat.jpg"],
];
const NAMES = ["Mia", "Noah", "Lina", "Ben", "Ella", "Finn", "Zoe", "Leo", "Ava", "Max"];

// ------------------------------------------------------------------ args
const args = {};
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (!a.startsWith("--")) continue;
  const [k, v] = a.slice(2).split("=", 2);
  if (v !== undefined) args[k] = v;
  else if (process.argv[i + 1] && !process.argv[i + 1].startsWith("--"))
    args[k] = process.argv[++i];
  else args[k] = "1";
}
const N = Number(args.players ?? 4);
const BASE = (args.url ?? "http://localhost:8080").replace(/\/$/, "");
const RACES = Number(args.races ?? 2);
const STAGGER = Number(args.stagger ?? 0);
const WAVES = Math.max(1, Number(args.waves ?? 1));
const WAVE_GAP = Number(args["wave-gap"] ?? 20_000);
const JOIN_STAGGER = Number(args["join-stagger"] ?? 0);
const MAX_NEW = Number(args["max-new"] ?? 8);
const WAIT_RENDERS = args.renders !== "0";
const BOOST_TAPS = Number(args.boosts ?? 3);
const PIN = args.pin ?? process.env.BK_ADMIN_PIN ?? "1234";
const QUIET = !!args.quiet;
const STATE = args.state ?? join(REPO_ROOT, "apps/server/data/.sim-players.json");
const names = args.names ? args.names.split(",") : NAMES;

let seed = Number(args.seed ?? 1) >>> 0;
const rand = () => {
  seed = (seed + 0x6d2b79f5) >>> 0;
  let t = seed;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const pick = (list) => list[Math.floor(rand() * list.length)];

// ------------------------------------------------------------------ log + errors
const T0 = performance.now();
const since = () => performance.now() - T0;
const errors = [];
function line(who, text) {
  if (!QUIET) console.log(`[${(since() / 1000).toFixed(1).padStart(6)}s] ${who.padEnd(8)} ${text}`);
}
function fail(who, text) {
  errors.push(`${who}: ${text}`);
  console.error(`[${(since() / 1000).toFixed(1).padStart(6)}s] ${who.padEnd(8)} ERROR ${text}`);
}

async function rest(method, path, { cookie, body, form, admin } = {}) {
  const headers = {};
  if (cookie) headers.cookie = cookie;
  if (admin) headers["x-admin-pin"] = PIN;
  if (body !== undefined) headers["content-type"] = "application/json";
  const res = await fetch(BASE + path, {
    method,
    headers,
    body: form ?? (body !== undefined ? JSON.stringify(body) : undefined),
  });
  const data = res.status === 204 ? null : await res.json().catch(() => null);
  if (!res.ok) {
    const e = new Error(
      `${method} ${path} → ${res.status} ${data?.error?.code}: ${data?.error?.message}`,
    );
    e.code = data?.error?.code;
    throw e;
  }
  return data;
}

/** A random build that follows the star rules of the server's config. */
function randomBuild(config) {
  const stars = Object.fromEntries(ABILITIES.map((a) => [a, 0]));
  for (let left = config.starsTotal; left > 0; ) {
    const a = pick(ABILITIES);
    if (stars[a] < config.starsMaxPerAbility) {
      stars[a]++;
      left--;
    }
  }
  const routes = Object.fromEntries(Object.entries(FORK_CHOICES).map(([f, c]) => [f, pick(c)]));
  return { stars, routes, style: pick(DRIVING_STYLES) };
}

// ------------------------------------------------------------------ one phone
class Phone {
  constructor(i, saved) {
    this.i = i;
    this.name = names[i % names.length];
    this.tag = `${this.name}#${i + 1}`;
    this.deviceId = saved?.deviceId;
    this.counts = {}; // message type -> count
    this.bytes = 0;
    this.waiters = [];
    this.me = null;
    this.config = null;
    this.t = {}; // timings (ms)
    this.races = [];
    this.stages = [];
    this.heats = []; // run.heat payloads (+ at)
  }

  get cookie() {
    return `bk_device=${this.deviceId}`;
  }

  async connect() {
    const d = await rest("POST", "/api/device", {
      cookie: this.deviceId ? this.cookie : undefined,
    });
    if (this.deviceId && d.deviceId !== this.deviceId)
      line(this.tag, `saved device ${this.deviceId} is unknown to this server; new device`);
    this.deviceId = d.deviceId;
    this.ws = new WebSocket(`${BASE.replace(/^http/, "ws")}/ws`, {
      headers: { cookie: this.cookie },
    });
    this.ws.onmessage = (e) => this.onMessage(String(e.data));
    this.ws.onclose = (e) => {
      if (!this.closing) fail(this.tag, `socket closed ${e.code} ${e.reason}`);
    };
    await new Promise((res, rej) => {
      this.ws.onopen = res;
      this.ws.onerror = () => rej(new Error("WebSocket error"));
    });
    this.send("hello", { role: "phone" });
    const w = await this.wait("welcome", () => true, 5000);
    this.config = w.config;
    this.me = w.me ?? null;
  }

  send(type, payload) {
    this.ws.send(JSON.stringify(makeMsg("phoneToServer", type, payload)));
  }

  onMessage(raw) {
    const m = JSON.parse(raw);
    const at = performance.now();
    this.bytes += raw.length;
    this.counts[m.type] = (this.counts[m.type] ?? 0) + 1;
    const p = m.payload;
    if (m.type === "player.updated") {
      const prevStage = this.me?.job?.stage;
      this.me = p;
      if (p.job?.stage && p.job.stage !== prevStage && p.status === "processing") {
        this.stages.push([p.job.stage, at]);
        line(this.tag, `making: ${p.job.stage}`);
      }
    } else if (m.type === "run.heat") this.heats.push({ ...p, at });
    else if (m.type === "config.updated") this.config = p;
    else if (m.type === "player.removed") fail(this.tag, "the racer was removed");
    else if (m.type === "error" && p.code !== "track_changing")
      fail(this.tag, `server error ${p.code}: ${p.message}`);
    this.race?.onMessage(m, at);
    for (const w of [...this.waiters]) {
      if (w.type !== m.type || !w.pred(p)) continue;
      this.waiters.splice(this.waiters.indexOf(w), 1);
      w.res(p);
    }
  }

  wait(type, pred, ms) {
    return new Promise((res, rej) => {
      const w = { type, pred, res };
      this.waiters.push(w);
      setTimeout(() => {
        if (!this.waiters.includes(w)) return;
        this.waiters.splice(this.waiters.indexOf(w), 1);
        rej(new Error(`no ${type} within ${ms / 1000} s`));
      }, ms);
    });
  }

  /** Waits until `me` satisfies pred (it may already). */
  async waitMe(pred, ms, what) {
    if (this.me && pred(this.me)) return this.me;
    try {
      return await this.wait("player.updated", pred, ms);
    } catch {
      throw new Error(`${what}: still ${this.me?.status} after ${ms / 1000} s`);
    }
  }

  /** Join + racer: reuses a ready racer, otherwise designs one from a sample pair. */
  async makeRacer(budget) {
    const t = performance.now();
    if (!this.me) {
      this.me = await rest("POST", "/api/players", {
        cookie: this.cookie,
        body: { nickname: this.name },
      });
      this.t.joinMs = performance.now() - t;
      line(
        this.tag,
        `joined as "${this.me.nickname}" (${this.me.id}) in ${this.t.joinMs.toFixed(0)} ms`,
      );
    } else line(this.tag, `back as "${this.me.nickname}" (${this.me.status})`);
    if (this.me.status !== "ready") {
      if (this.me.status !== "processing") {
        if (budget.left <= 0)
          throw new Error(`would design a new racer, but --max-new ${MAX_NEW} is used up`);
        budget.left--;
        const [c, v] = PAIRS[this.i % PAIRS.length];
        const form = new FormData();
        form.append("character", Bun.file(join(SAMPLES, c)), c);
        form.append("vehicle", Bun.file(join(SAMPLES, v)), v);
        const up = performance.now();
        await rest("POST", "/api/players/me/drawings", { cookie: this.cookie, form });
        this.t.uploadMs = performance.now() - up;
        line(this.tag, `drawings ${c} + ${v} uploaded in ${this.t.uploadMs.toFixed(0)} ms`);
      }
      const d0 = performance.now();
      const me = await this.waitMe((p) => p.status !== "processing", 420_000, "design");
      if (me.status !== "ready")
        throw new Error(
          `design ended ${me.status}: ${me.job?.error ?? me.job?.rejectReason ?? "?"}`,
        );
      this.t.designMs = performance.now() - d0;
      line(
        this.tag,
        `racer ready: "${me.asset?.spec?.title}" after ${(this.t.designMs / 1000).toFixed(1)} s`,
      );
    }
    if (WAIT_RENDERS) {
      const r0 = performance.now();
      const hasAll = (p) =>
        ["hero", "avatar_happy", "avatar_excited", "avatar_sad"].every(
          (k) => p.asset?.renders?.[k],
        );
      await this.waitMe(hasAll, 120_000, "renders from the big screen");
      this.t.rendersMs = performance.now() - r0;
      line(this.tag, `renders on the phone after ${(this.t.rendersMs / 1000).toFixed(1)} s`);
    }
    this.t.readyMs = performance.now() - t;
  }

  async setBuild() {
    const build = randomBuild(this.config);
    await rest("PUT", "/api/players/me/build", { cookie: this.cookie, body: build });
    this.build = build;
  }

  close() {
    this.closing = true;
    this.ws?.close();
  }
}

// ------------------------------------------------------------------ one race for one phone
class Race {
  constructor(phone, n) {
    this.phone = phone;
    this.n = n;
    this.r = { race: n, progress: 0, boosts: [], lostBoosts: 0, laps: 0 };
    this.taps = [];
    this.pending = null; // { at, before }
    this.boostsLeft = phone.config.boostsPerRun;
    this.loop = LOOP_TRACKS.includes(phone.config.track);
  }

  async go() {
    const { phone } = this;
    phone.race = this;
    this.goAt = performance.now();
    phone.send("phone.go", {});
    const capMs = phone.config.runTimeCapMs * (this.loop ? phone.config.lapsPerRun : 1) + 60_000;
    // Like a kid: the big screen still loading a new track says "try again in a moment".
    let q;
    for (let attempt = 0; !q; attempt++) {
      try {
        q = await new Promise((res, rej) => {
          phone.wait("run.queued", () => true, 5000).then(res, rej);
          phone
            .wait("error", () => true, 5000)
            .then(
              (e) =>
                rej(
                  Object.assign(new Error(`Go refused: ${e.code} ${e.message}`), { code: e.code }),
                ),
              () => {},
            );
        });
      } catch (err) {
        if (err.code !== "track_changing" || attempt >= 30) throw err;
        if (attempt === 0) line(phone.tag, "the big screen is changing track; Go again every 1 s");
        await Bun.sleep(1000);
        this.goAt = performance.now();
        phone.send("phone.go", {});
      }
    }
    this.runId = q.run.id;
    this.r.goToQueuedMs = performance.now() - this.goAt;
    await phone.wait("run.started", (p) => p.run.id === this.runId, 60_000);
    this.startedAt = performance.now();
    this.r.goToStartedMs = this.startedAt - this.goAt;
    // Start countdown (contracts §2c): how far the phone's green was from the real release.
    if (this.greenAt !== undefined) this.r.greenToStartedMs = this.startedAt - this.greenAt;
    line(
      phone.tag,
      `on track after ${(this.r.goToStartedMs / 1000).toFixed(2)} s${this.greenAt !== undefined ? ` (countdown, ${Math.round(this.r.greenToStartedMs)} ms after green)` : ""}`,
    );
    this.scheduleTaps();
    const ended = await phone.wait("run.ended", (p) => p.run.id === this.runId, capMs);
    this.onEnded(ended);
    phone.race = null;
    return this.r;
  }

  scheduleTaps() {
    // Spread the taps over the expected run (~25 s point to point, ~50 s per lap on loops).
    const span = this.loop ? 40_000 : 20_000;
    for (let k = 0; k < BOOST_TAPS; k++) {
      const at = 1500 + (span / BOOST_TAPS) * k + rand() * 2000;
      this.taps.push(setTimeout(() => this.tap(), at));
    }
  }

  tap() {
    if (this.done || this.boostsLeft <= 0) return;
    if (this.pending) {
      this.r.lostBoosts++;
      fail(
        this.phone.tag,
        `boost tap not seen by the game within ${(performance.now() - this.pending.at).toFixed(0)} ms`,
      );
    }
    this.pending = { at: performance.now(), before: this.boostsLeft };
    this.phone.send("phone.boost", { runId: this.runId });
  }

  onMessage(m, at) {
    const p = m.payload;
    // Only this race's run (not one still going from before, e.g. on the same device elsewhere).
    if (!this.runId || (p?.runId ?? p?.run?.id) !== this.runId) return;
    if (m.type === "run.grid") {
      this.greenAt = at + p.goInMs;
      this.r.gridGoInMs = p.goInMs;
    } else if (m.type === "run.progress") {
      this.r.progress++;
      this.lastProgressAt = at;
      this.firstProgressAt ??= at;
      if (this.pending && p.boostsLeft < this.pending.before) {
        this.r.boosts.push(at - this.pending.at);
        this.pending = null;
      }
      this.boostsLeft = p.boostsLeft;
      if (p.place) Object.assign(this.r, { lastPlace: p.place, of: p.of });
      if (this.loop && p.lap > 1 && args.pit && !this.pitSent) {
        this.pitSent = true;
        this.phone.send("phone.stop", { runId: this.runId });
        line(this.phone.tag, "Pit in");
      }
    } else if (m.type === "run.lap") {
      this.r.laps++;
      line(
        this.phone.tag,
        `lap ${p.lap} ${(p.lapMs / 1000).toFixed(2)} s${p.isLapBest ? " (best)" : ""}`,
      );
    } else if (m.type === "run.ended") {
      this.r.endedWireMs = Date.now() - Date.parse(m.ts);
      this.r.endedAfterLastProgressMs = this.lastProgressAt ? at - this.lastProgressAt : undefined;
    }
  }

  onEnded(e) {
    this.done = true;
    for (const t of this.taps) clearTimeout(t);
    const run = e.run;
    Object.assign(this.r, {
      outcome: run.outcome,
      failReason: run.failReason,
      timeMs: this.loop ? run.bestLapMs : run.elapsedMs,
      rank: e.rank,
      pb: e.isPersonalBest,
      coach: e.coach?.text,
      endedAt: performance.now(),
      startedAt: this.startedAt,
      wallMs: performance.now() - this.startedAt,
      progressHz: this.firstProgressAt
        ? (this.r.progress * 1000) / Math.max(1, this.lastProgressAt - this.firstProgressAt)
        : 0,
    });
    if (this.pending) this.r.lostBoosts++;
    if (run.outcome === "aborted") fail(this.phone.tag, `race ${this.n} aborted`);
    const what =
      run.outcome === "finished" || (this.loop && run.bestLapMs !== undefined)
        ? `${(this.r.timeMs / 1000).toFixed(2)} s`
        : `${run.outcome} ${run.failReason ?? ""}@${run.failSection ?? ""}`;
    line(
      this.phone.tag,
      `result: ${what}${this.r.lastPlace ? ` (last seen ${this.r.lastPlace} of ${this.r.of})` : ""}${e.rank ? ` rank #${e.rank}` : ""}${e.isPersonalBest ? " PB" : ""} · "${e.coach?.text}"`,
    );
  }
}

// ------------------------------------------------------------------ main
const ms = (x) => (x >= 10_000 ? `${(x / 1000).toFixed(1)}s` : `${Math.round(x)}ms`);
const stats = (xs, f = ms) => {
  const a = xs.filter((x) => Number.isFinite(x)).sort((p, q) => p - q);
  if (!a.length) return "–";
  const q = (k) => a[Math.min(a.length - 1, Math.floor(k * a.length))];
  return `min ${f(a[0])} · median ${f(q(0.5))} · p95 ${f(q(0.95))} · max ${f(a[a.length - 1])} (n=${a.length})`;
};

/** Group results on the phones (run.heat): every racer of a heat gets the same, complete result. */
function checkHeats(phones, n, lastEnd) {
  // Racers who left within 2.5 s of each other are a heat (the server's rule); one who left
  // alone (e.g. pressed Go after the countdown went green) gets no group result.
  const starts = phones
    .map((ph) => ({ ph, at: ph.races.find((r) => r.race === n)?.startedAt }))
    .filter((x) => x.at !== undefined)
    .sort((a, b) => a.at - b.at);
  const alone = new Set();
  for (let i = 0; i < starts.length; ) {
    let j = i;
    while (j + 1 < starts.length && starts[j + 1].at - starts[i].at <= 2500) j++;
    if (j === i) alone.add(starts[i].ph);
    i = j + 1;
  }
  const byHeat = new Map();
  for (const ph of phones) {
    if (alone.has(ph)) {
      line(ph.tag, `race ${n}: left alone, no group result expected`);
      continue;
    }
    const h = ph.heats.filter((x) => x.done).at(-1);
    if (!h || h.at < lastEnd - 120_000) {
      fail(ph.tag, `race ${n}: no complete group result (run.heat done) on the phone`);
      continue;
    }
    if (!h.entries.some((e) => e.playerId === ph.me.id))
      fail(ph.tag, `race ${n}: the group result doesn't list me`);
    if (!byHeat.has(h.heatId)) byHeat.set(h.heatId, []);
    byHeat.get(h.heatId).push({ ph, h });
  }
  for (const [id, list] of byHeat) {
    const first = JSON.stringify(list[0].h.entries);
    for (const { ph, h } of list)
      if (JSON.stringify(h.entries) !== first)
        fail(ph.tag, `race ${n}: heat ${id} differs between phones`);
    // From this heat's own last result (a later wave may still have been racing).
    const heatEnd = Math.max(
      ...list.map(({ ph }) => ph.races.find((r) => r.race === n)?.endedAt ?? 0),
    );
    const lag = Math.max(...list.map(({ h }) => h.at)) - heatEnd;
    const names = list[0].h.entries
      .map((e) => `${e.place ? `${e.place}.` : e.outcome ? "oops" : "?"} ${e.nickname}`)
      .join(", ");
    console.log(
      `  heat ${id}: ${list.length} phones, complete ${Math.round(lag)} ms after the last result · ${names}`,
    );
  }
}

async function switchTrack(track) {
  const st = await rest("GET", "/api/state");
  if (st.config.track === track) return;
  line("admin", `track ${st.config.track} → ${track} (new session)`);
  if (st.session.status === "running")
    await rest("POST", "/api/admin/session/end", { admin: true });
  await rest("PATCH", "/api/admin/config", { admin: true, body: { track } });
  await rest("POST", "/api/admin/session/start", { admin: true, body: {} });
}

async function main() {
  let saved = {};
  if (!args.fresh && existsSync(STATE)) saved = JSON.parse(readFileSync(STATE, "utf8"));
  const key = BASE;
  const slots = saved[key] ?? [];
  if (args.track) await switchTrack(args.track);
  const phones = Array.from({ length: N }, (_, i) => new Phone(i, slots[i]));
  const budget = { left: MAX_NEW };

  console.log(`sim-players: ${N} phones → ${BASE}, ${RACES} race(s), Go stagger ${STAGGER} ms`);
  // Join: all at once (or --join-stagger apart), like a group scanning the QR code together.
  const joined = await Promise.allSettled(
    phones.map(async (ph, i) => {
      await Bun.sleep(i * JOIN_STAGGER);
      await ph.connect();
      await ph.makeRacer(budget);
      await ph.setBuild();
    }),
  );
  writeFileSync(
    STATE,
    `${JSON.stringify({ ...saved, [key]: [...phones.map((p) => ({ deviceId: p.deviceId, name: p.name })), ...slots.slice(N)] }, null, 2)}\n`,
  );
  const ready = phones.filter((ph, i) => {
    if (joined[i].status === "fulfilled") return true;
    fail(ph.tag, `could not get a racer: ${joined[i].reason?.message}`);
    return false;
  });
  console.log(`\n${ready.length}/${N} racers ready.`);

  for (let n = 1; n <= RACES && ready.length; n++) {
    console.log(
      `\n--- race ${n}: ${ready.length} racers, Go ${STAGGER ? `${STAGGER} ms apart` : "all at once"}`,
    );
    // Wait out the launch cooldown from the previous race.
    if (n > 1) await Bun.sleep(ready[0].config.launchCooldownMs + 500);
    const results = await Promise.allSettled(
      ready.map(async (ph, i) => {
        const per = Math.ceil(ready.length / WAVES);
        await Bun.sleep(Math.floor(i / per) * WAVE_GAP + (i % per) * STAGGER);
        const r = await new Race(ph, n).go();
        ph.races.push(r);
        return r;
      }),
    );
    results.forEach((res, i) => {
      if (res.status === "rejected") fail(ready[i].tag, `race ${n}: ${res.reason?.message}`);
    });
    const ends = ready.flatMap((ph) => ph.races.filter((r) => r.race === n).map((r) => r.endedAt));
    if (ends.length > 1)
      console.log(
        `  results reached the phones within ${((Math.max(...ends) - Math.min(...ends)) / 1000).toFixed(1)} s of each other`,
      );
    await Bun.sleep(400); // the last finisher's heat update follows its result
    checkHeats(ready, n, Math.max(...ends));
  }
  await Bun.sleep(300);
  for (const ph of phones) ph.close();

  // ---------------------------------------------------------------- report
  const all = ready.flatMap((p) => p.races);
  console.log("\n=== timings");
  console.log(`join (POST /api/players)     ${stats(phones.map((p) => p.t.joinMs))}`);
  console.log(`design (upload → ready)      ${stats(phones.map((p) => p.t.designMs))}`);
  console.log(`renders (ready → on phone)   ${stats(phones.map((p) => p.t.rendersMs))}`);
  console.log(`join → racer ready           ${stats(phones.map((p) => p.t.readyMs))}`);
  console.log(`Go → run.queued              ${stats(all.map((r) => r.goToQueuedMs))}`);
  console.log(`Go → on track (run.started)  ${stats(all.map((r) => r.goToStartedMs))}`);
  console.log(`countdown green → on track   ${stats(all.map((r) => r.greenToStartedMs))}`);
  console.log(
    `boost tap → seen on phone    ${stats(all.flatMap((r) => r.boosts))}  (includes ≤200 ms progress interval)`,
  );
  console.log(`last progress → result       ${stats(all.map((r) => r.endedAfterLastProgressMs))}`);
  console.log(`run.ended wire latency       ${stats(all.map((r) => r.endedWireMs))}`);
  console.log(
    `run.progress rate per phone  ${stats(
      all.map((r) => r.progressHz),
      (x) => `${x.toFixed(1)}Hz`,
    )}`,
  );
  console.log("\n=== per phone");
  for (const p of phones) {
    const rs = p.races
      .map(
        (r) =>
          `${r.outcome === "finished" ? `${(r.timeMs / 1000).toFixed(1)}s` : r.outcome}${r.rank ? `#${r.rank}` : ""}`,
      )
      .join(" ");
    const msgs = Object.entries(p.counts)
      .sort((a, b) => b[1] - a[1])
      .map(([t, c]) => `${t}:${c}`)
      .join(" ");
    console.log(`${p.tag.padEnd(9)} ${rs.padEnd(24)} ${(p.bytes / 1024).toFixed(0)} KB  ${msgs}`);
  }
  const outcomes = {};
  for (const r of all) outcomes[r.outcome] = (outcomes[r.outcome] ?? 0) + 1;
  console.log(
    `\noutcomes: ${JSON.stringify(outcomes)} · lost boosts ${all.reduce((s, r) => s + r.lostBoosts, 0)}`,
  );
  if (args.json)
    writeFileSync(
      args.json,
      JSON.stringify(
        { base: BASE, players: N, phones: phones.map(({ ws, waiters, race, ...p }) => p), errors },
        null,
        2,
      ),
    );
  if (errors.length) {
    console.log(`\n=== ${errors.length} error(s)`);
    for (const e of errors) console.log(`  ${e}`);
    process.exit(1);
  }
  console.log("\nno errors");
  process.exit(0);
}

main().catch((err) => {
  console.error(`sim-players: ${err.stack ?? err}`);
  process.exit(1);
});
