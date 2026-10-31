// The server's state and rules: session, players, builds, runs, leaderboard (game-server.md).
// Transport-free: REST and WS handlers call these methods, and outgoing messages go through `hub`.
import {
  coachTip,
  DEFAULT_BUILD,
  LOOP_TRACKS,
  mergeConfig,
  newId,
  parseBuildInput,
  SECTION_IDS,
} from "@bebbikart/shared";
import { ApiError, cleanNickname } from "./errors.js";

const now = () => new Date().toISOString();
const CALM_WEATHER = () => ({
  rain: { phase: "calm", intensity: 0 },
  wind: { phase: "calm", strength: 0, dirDeg: 0 },
  changedAt: now(),
});
/** Loop tracks rank by best lap (contracts §2a). */
const isLoop = (track) => LOOP_TRACKS.includes(track);
/** What ranks a done run: best lap on loops (failed runs with laps count), else a finished time. */
function rankTime(run) {
  if (isLoop(run.track)) return run.bestLapMs;
  return run.outcome === "finished" ? run.elapsedMs : undefined;
}
/** coachTip compares elapsedMs; on loops that is the best lap. */
function forCoach(run) {
  if (!run || !isLoop(run.track) || run.bestLapMs === undefined) return run;
  return { ...run, elapsedMs: run.bestLapMs, outcome: "finished" };
}
const ABORT_TIP = { key: "aborted", text: "That race was stopped. Press Go! to try again." };

/**
 * @param {{ db: ReturnType<import("./db.js").openDb>, settings: object, hub: object, log?: Function }} deps
 */
export function createGame({ db, settings, hub, log = console.log }) {
  let config = settings.config;
  let weather = CALM_WEATHER();
  /** @type {any} */
  let session = null;
  const devices = new Map(); // deviceId -> { id, playerId?, createdAt }
  const players = new Map();
  const builds = new Map();
  const runs = new Map();
  const jobs = new Map(); // jobId -> AssetJob (+ private fields stripped in views)
  const traces = new Map(); // runId -> GhostTrace
  const manifests = new Map(); // playerId -> AssetManifest

  // ------------------------------------------------------------------ persistence helpers
  function savePlayer(p) {
    players.set(p.id, p);
    const asset = manifests.get(p.id);
    db.put("player", { ...p, ...(asset ? { asset } : {}) });
    return p;
  }
  function saveRun(r) {
    runs.set(r.id, r);
    db.put("run", r);
  }
  function saveJob(j) {
    jobs.set(j.id, j);
    db.put("asset_job", j);
  }
  function saveSession(s) {
    session = s;
    db.put("session", s);
  }

  // ------------------------------------------------------------------ views
  function latestBuild(playerId) {
    let latest;
    for (const b of builds.values()) {
      if (b.playerId === playerId && (!latest || b.createdAt >= latest.createdAt)) latest = b;
    }
    return latest;
  }
  function playerRuns(playerId) {
    return [...runs.values()]
      .filter((r) => r.playerId === playerId)
      .sort((a, b) => (a.queuedAt < b.queuedAt ? 1 : -1));
  }
  function activeRun(playerId) {
    return playerRuns(playerId).find((r) => r.status !== "done");
  }
  function latestJob(playerId) {
    let latest;
    for (const j of jobs.values()) {
      if (j.playerId === playerId && (!latest || j.createdAt >= latest.createdAt)) latest = j;
    }
    return latest;
  }
  function publicJob(j) {
    if (!j) return undefined;
    const { uploads, rerolls, ...pub } = j;
    return pub;
  }
  function ranks() {
    const ranked = [...players.values()]
      .filter((p) => p.bestTimeMs !== undefined)
      .sort((a, b) => a.bestTimeMs - b.bestTimeMs || (a.bestRunId < b.bestRunId ? -1 : 1));
    return new Map(ranked.map((p, i) => [p.id, i + 1]));
  }
  function playerView(id, rankMap = ranks()) {
    const p = players.get(id);
    if (!p) return undefined;
    const all = playerRuns(id);
    const current = all.find((r) => r.status !== "done");
    const last = all.find((r) => r.status === "done");
    const best = p.bestRunId ? runs.get(p.bestRunId) : undefined;
    const view = { ...p, build: latestBuild(id) };
    const job = publicJob(latestJob(id));
    if (job) view.job = job;
    const asset = manifests.get(id);
    if (asset) view.asset = asset;
    if (current) view.currentRun = current;
    if (last) view.lastRun = last;
    if (best) view.bestRun = best;
    const rank = rankMap.get(id);
    if (rank) view.rank = rank;
    return view;
  }
  function leaderboard() {
    const rankMap = ranks();
    return [...rankMap.entries()].slice(0, 20).map(([id, rank]) => {
      const p = players.get(id);
      const a = manifests.get(id);
      const entry = {
        rank,
        playerId: id,
        nickname: p.nickname,
        avatarUrl: a?.renders.avatar_happy ?? "",
        bestTimeMs: p.bestTimeMs,
        setAt: runs.get(p.bestRunId)?.endedAt ?? p.createdAt,
      };
      if (a) entry.racerTitle = a.spec.title;
      return entry;
    });
  }
  function rosterEntry(p) {
    const e = {
      playerId: p.id,
      nickname: p.nickname,
      connected: p.connected,
      status: p.status,
      assetBaseUrl: p.assetPackageId
        ? `${settings.publicUrl}/assets/${p.assetPackageId}/`
        : `${settings.publicUrl}/assets/pkg_default/`,
    };
    const a = manifests.get(p.id);
    if (a) e.asset = a;
    if (p.bestTimeMs !== undefined) e.bestTimeMs = p.bestTimeMs;
    return e;
  }
  const roster = () => [...players.values()].map(rosterEntry);
  function runStart(run) {
    const p = players.get(run.playerId);
    const out = { runId: run.id, playerId: run.playerId, build: builds.get(run.buildId) };
    const best = p?.bestRunId ? runs.get(p.bestRunId) : undefined;
    if (best?.splits) out.bestSplits = best.splits;
    const trace = best && config.ghostEnabled ? traces.get(best.id) : undefined;
    if (trace) out.bestTrace = trace;
    return out;
  }

  // ------------------------------------------------------------------ broadcasts
  function pushPlayer(id) {
    const view = playerView(id);
    if (!view) return;
    hub.toPhone(id, "player.updated", view);
    hub.toAdmins("player.updated", view);
  }
  let rosterTimer = null;
  function pushRoster() {
    clearTimeout(rosterTimer);
    rosterTimer = setTimeout(() => hub.toGame("roster.updated", roster()), 250);
  }
  function pushLeaderboard() {
    const lb = leaderboard();
    hub.toPhones("leaderboard.updated", lb);
    hub.toAdmins("leaderboard.updated", lb);
    hub.toGame("leaderboard.updated", lb);
  }
  function pushSession() {
    hub.toPhones("session.updated", session);
    hub.toAdmins("session.updated", session);
    hub.toGame("session.updated", session);
  }

  // ------------------------------------------------------------------ session
  let endTimer = null;
  function newSession() {
    clearTimeout(endTimer);
    saveSession({
      id: newId("session"),
      status: "idle",
      durationMs: config.sessionMinutes * 60_000,
    });
  }
  function scheduleEnd() {
    clearTimeout(endTimer);
    if (session.status !== "running" || !session.endsAt) return;
    const ms = Date.parse(session.endsAt) - Date.now();
    endTimer = setTimeout(endSession, Math.max(0, Math.min(ms, 2 ** 31 - 1)));
  }
  // A session that ended is over: starting again opens a new session with a fresh
  // leaderboard (racers stay). Bests from another track or session never carry over.
  function startSession(durationMs = session.durationMs) {
    if (session.status === "ended") {
      const prev = session.id;
      newSession();
      clearBests();
      log(`[session] ${prev} ended; new session ${session.id} on ${config.track}`);
    }
    const t = Date.now();
    saveSession({
      ...session,
      status: "running",
      durationMs,
      startedAt: new Date(t).toISOString(),
      endsAt: new Date(t + durationMs).toISOString(),
    });
    scheduleEnd();
    pushSession();
    log(`[session] ${session.id} running for ${Math.round(durationMs / 60000)} min`);
    return session;
  }
  function clearBests() {
    for (const p of players.values()) {
      if (p.bestRunId === undefined && p.bestTimeMs === undefined) continue;
      const { bestRunId, bestTimeMs, ...rest } = p;
      savePlayer(rest);
    }
    traces.clear();
    db.clear("best_trace");
    pushRoster();
    pushLeaderboard();
    for (const id of players.keys()) pushPlayer(id);
  }
  function endSession() {
    if (session.status === "ended") return session;
    clearTimeout(endTimer);
    saveSession({ ...session, status: "ended", endsAt: session.endsAt ?? now() });
    pushSession();
    return session;
  }

  // ------------------------------------------------------------------ devices & players
  function ensureDevice(deviceId) {
    if (deviceId && devices.has(deviceId)) return devices.get(deviceId);
    const d = { id: newId("device"), createdAt: now() };
    devices.set(d.id, d);
    db.put("device", d);
    return d;
  }
  function playerForDevice(deviceId) {
    if (!deviceId) return undefined;
    for (const p of players.values()) if (p.deviceId === deviceId) return p;
    return undefined;
  }
  function mustPlayer(deviceId) {
    const p = playerForDevice(deviceId);
    if (!p) throw new ApiError("not_found", "Create your racer first", 404);
    return p;
  }
  function createPlayer(deviceId, nicknameRaw) {
    if (deviceId && playerForDevice(deviceId))
      throw new ApiError("player_exists", "This phone already has a racer", 409);
    if (players.size >= config.maxPlayers)
      throw new ApiError("server_full", "The track is full right now", 409);
    const nickname = cleanNickname(nicknameRaw);
    if (!nickname) throw new ApiError("bad_request", "Pick a racer name", 400);
    const p = {
      id: newId("player"),
      sessionId: session.id,
      deviceId: deviceId ?? "",
      nickname,
      status: "draft",
      connected: !!deviceId && hub.deviceOnline(deviceId),
      createdAt: now(),
    };
    savePlayer(p);
    saveBuild(p.id, DEFAULT_BUILD);
    pushPlayer(p.id);
    pushRoster();
    log(`[player] ${p.id} "${nickname}" joined`);
    return playerView(p.id);
  }
  function rename(playerId, nicknameRaw) {
    const p = players.get(playerId);
    const nickname = cleanNickname(nicknameRaw);
    if (!nickname) throw new ApiError("bad_request", "Pick a racer name", 400);
    savePlayer({ ...p, nickname });
    pushPlayer(playerId);
    pushRoster();
    if (p.bestTimeMs !== undefined) pushLeaderboard();
    return playerView(playerId);
  }
  function saveBuild(playerId, input) {
    const b = { id: newId("build"), playerId, ...structuredClone(input), createdAt: now() };
    builds.set(b.id, b);
    db.put("build", b);
    return b;
  }
  function setBuild(playerId, body) {
    const parsed = parseBuildInput(body, config);
    if (!parsed.ok) throw new ApiError("invalid_build", parsed.errors.join("; "), 400);
    const b = saveBuild(playerId, parsed.build);
    pushPlayer(playerId);
    return b;
  }
  function removePlayer(playerId) {
    const p = players.get(playerId);
    if (!p) throw new ApiError("not_found", "No such racer", 404);
    const run = activeRun(playerId);
    if (run) abortRun(run, "player_deleted");
    players.delete(playerId);
    manifests.delete(playerId);
    db.del("player", playerId);
    hub.toAdmins("player.removed", { playerId });
    pushRoster();
    pushLeaderboard();
  }
  /** Hub tells us a device's phone socket count went to/from zero. */
  function setDeviceOnline(deviceId, online) {
    const p = playerForDevice(deviceId);
    if (!p || p.connected === online) return;
    savePlayer({ ...p, connected: online });
    hub.toAdmins("player.updated", playerView(p.id));
    pushRoster();
  }

  // ------------------------------------------------------------------ assets (called by jobs.js)
  function setPlayerStatus(playerId, status) {
    const p = players.get(playerId);
    if (!p) return;
    savePlayer({ ...p, status });
    pushPlayer(playerId);
    pushRoster();
  }
  function setManifest(playerId, manifest) {
    const p = players.get(playerId);
    if (!p) return;
    manifests.set(playerId, manifest);
    savePlayer({ ...p, assetPackageId: manifest.packageId, status: "ready" });
    pushPlayer(playerId);
    pushRoster();
  }
  function setRender(playerId, key, url) {
    const m = manifests.get(playerId);
    if (!m) throw new ApiError("not_found", "Racer has no asset package yet", 404);
    manifests.set(playerId, { ...m, renders: { ...m.renders, [key]: url }, updatedAt: now() });
    savePlayer(players.get(playerId));
    pushPlayer(playerId);
    if (players.get(playerId).bestTimeMs !== undefined) pushLeaderboard();
  }

  // ------------------------------------------------------------------ runs
  function launch(playerId) {
    const p = players.get(playerId);
    if (!p) throw new ApiError("not_found", "No such racer", 404);
    if (session.status !== "running")
      throw new ApiError("session_not_running", "The race isn't open right now", 409);
    if (p.status !== "ready") throw new ApiError("not_ready", "Your racer isn't ready yet", 409);
    if (activeRun(playerId))
      throw new ApiError("run_in_progress", "Your racer is still on the track", 409);
    const last = playerRuns(playerId).find((r) => r.status === "done");
    const readyAt = last?.endedAt ? Date.parse(last.endedAt) + config.launchCooldownMs : 0;
    if (Date.now() < readyAt)
      throw new ApiError("cooldown", "Catch your breath! Ready in a moment", 409);
    if (!hub.gameOnline())
      throw new ApiError("game_offline", "The big screen isn't connected", 409);
    const running = [...runs.values()].filter((r) => r.status !== "done").length;
    if (running >= config.maxConcurrentRuns)
      throw new ApiError("run_in_progress", "The track is full, try again in a moment", 409);
    const build = latestBuild(playerId);
    const run = {
      id: newId("run"),
      playerId,
      buildId: build.id,
      status: "queued",
      queuedAt: now(),
      track: config.track,
    };
    saveRun(run);
    hub.toGame("run.start", runStart(run));
    hub.toPhone(playerId, "run.queued", { run });
    pushPlayer(playerId);
    log(`[run] ${run.id} queued for "${p.nickname}"`);
    return run;
  }
  function boost(playerId, runId) {
    const run = activeRun(playerId);
    if (!run || (runId && run.id !== runId)) return false;
    hub.toGame("run.boost", { runId: run.id });
    return true;
  }
  /** "Pit in" on a loop track: the game finishes the run at the next line crossing. */
  function stop(playerId, runId) {
    const run = activeRun(playerId);
    if (!run || (runId && run.id !== runId)) return false;
    if (!isLoop(run.track))
      throw new ApiError("bad_request", "Pit in only works on a loop track", 400);
    hub.toGame("run.stop", { runId: run.id });
    return true;
  }
  function abortRun(run, reason) {
    if (run.status === "done") return;
    const done = { ...run, status: "done", outcome: "aborted", endedAt: now() };
    saveRun(done);
    hub.toGame("run.abort", { runId: run.id, reason });
    hub.toPhone(run.playerId, "run.ended", { run: done, isPersonalBest: false, coach: ABORT_TIP });
    pushPlayer(run.playerId);
  }
  /** The game went away: its runs can't finish. */
  function abortAllRuns(reason) {
    for (const r of runs.values()) {
      if (r.status === "done") continue;
      const done = { ...r, status: "done", outcome: "aborted", endedAt: now() };
      saveRun(done);
      hub.toPhone(r.playerId, "run.ended", { run: done, isPersonalBest: false, coach: ABORT_TIP });
      pushPlayer(r.playerId);
      log(`[run] ${r.id} aborted (${reason})`);
    }
  }
  function gameRun(runId) {
    const r = runs.get(runId);
    return r && r.status !== "done" ? r : undefined;
  }
  function onGameMessage(type, pl) {
    switch (type) {
      case "game.run.started": {
        const r = gameRun(pl.runId);
        if (!r) return;
        const started = { ...r, status: "running", startedAt: now() };
        saveRun(started);
        hub.toPhone(r.playerId, "run.started", { run: started });
        pushPlayer(r.playerId);
        return;
      }
      case "game.run.progress": {
        const r = gameRun(pl.runId);
        if (!r) return;
        const out = { ...pl };
        const best = bestRunOf(r.playerId);
        if (best?.splits) {
          // vs best at the same point: compare elapsed with best's time for completed sections.
          const idx = SECTION_IDS.indexOf(pl.section);
          const doneSections = SECTION_IDS.slice(0, idx);
          const mine = r.liveSplits ?? {};
          if (doneSections.every((s) => mine[s] !== undefined && best.splits[s] !== undefined)) {
            const delta = doneSections.reduce((d, s) => d + mine[s] - best.splits[s], 0);
            if (doneSections.length) out.deltaVsBestMs = Math.round(delta);
          }
        }
        hub.toPhone(r.playerId, "run.progress", out);
        return;
      }
      case "game.run.section": {
        const r = gameRun(pl.runId);
        if (!r) return;
        r.liveSplits = { ...(r.liveSplits ?? {}), [pl.section]: pl.splitMs };
        const out = { ...pl };
        const bestSplit = bestRunOf(r.playerId)?.splits?.[pl.section];
        if (bestSplit !== undefined) out.bestSplitMs = bestSplit;
        hub.toPhone(r.playerId, "run.section", out);
        return;
      }
      case "game.run.lap": {
        const r = gameRun(pl.runId);
        if (!r) return;
        const prev = [players.get(r.playerId)?.bestTimeMs, ...(r.liveLaps ?? [])].filter(
          (x) => x !== undefined,
        );
        const bestBefore = prev.length ? Math.min(...prev) : undefined;
        r.liveLaps = [...(r.liveLaps ?? []), pl.lapMs];
        r.liveSplits = {}; // section splits restart each lap
        const out = {
          runId: pl.runId,
          lap: pl.lap,
          lapMs: pl.lapMs,
          isLapBest: bestBefore === undefined || pl.lapMs < bestBefore,
        };
        if (bestBefore !== undefined) out.deltaVsBestLapMs = Math.round(pl.lapMs - bestBefore);
        hub.toPhone(r.playerId, "run.lap", out);
        return;
      }
      case "game.run.finished":
      case "game.run.failed":
        return finishRun(type === "game.run.finished", pl);
      case "game.weather":
        weather = pl;
        hub.toPhones("weather.updated", pl);
        hub.toAdmins("weather.updated", pl);
        return;
      default:
    }
  }
  function bestRunOf(playerId) {
    const p = players.get(playerId);
    return p?.bestRunId ? runs.get(p.bestRunId) : undefined;
  }
  function finishRun(ok, pl) {
    const r = gameRun(pl.runId);
    if (!r) return;
    const { liveSplits, liveLaps, ...base } = r;
    const run = {
      ...base,
      status: "done",
      outcome: ok ? "finished" : "failed",
      startedAt: r.startedAt ?? r.queuedAt,
      endedAt: now(),
      splits: pl.splits,
      events: pl.events,
      boostsUsed: pl.boostsUsed,
      weatherSeen: pl.weatherSeen,
    };
    if (ok) run.elapsedMs = pl.elapsedMs;
    else Object.assign(run, { failReason: pl.reason, failSection: pl.section });
    if (pl.laps) run.laps = pl.laps;
    if (pl.bestLapMs !== undefined) run.bestLapMs = pl.bestLapMs;
    if (isLoop(run.track) && run.laps?.length && run.bestLapMs === undefined)
      run.bestLapMs = Math.min(...run.laps);
    saveRun(run);
    const p = players.get(r.playerId);
    const prevBest = bestRunOf(r.playerId);
    const time = rankTime(run);
    const isPersonalBest =
      time !== undefined && (p.bestTimeMs === undefined || time < p.bestTimeMs);
    if (isPersonalBest) {
      if (prevBest) {
        traces.delete(prevBest.id);
        db.del("best_trace", prevBest.id);
      }
      if (pl.trace) {
        traces.set(run.id, pl.trace);
        db.put("best_trace", { id: run.id, trace: pl.trace });
      }
      savePlayer({ ...p, bestRunId: run.id, bestTimeMs: time });
    }
    const coach = coachTip(forCoach(run), builds.get(run.buildId), forCoach(prevBest));
    const rank = ranks().get(r.playerId);
    hub.toPhone(r.playerId, "run.ended", { run, isPersonalBest, ...(rank ? { rank } : {}), coach });
    pushPlayer(r.playerId);
    if (isPersonalBest) {
      pushLeaderboard();
      pushRoster();
    }
    log(
      `[run] ${run.id} ${run.outcome} "${p?.nickname}" ${ok ? `${(run.elapsedMs / 1000).toFixed(2)} s` : `${run.failReason} @${run.failSection}`}${run.laps ? ` laps ${run.laps.map((l) => (l / 1000).toFixed(2)).join("/")}` : ""}${isPersonalBest ? " (best)" : ""}`,
    );
  }
  // Runs the game never reports back on (e.g. it crashed mid-run).
  const capTimer = setInterval(() => {
    for (const r of runs.values()) {
      // runTimeCapMs applies per lap on loop tracks.
      const limit = config.runTimeCapMs * (isLoop(r.track) ? config.lapsPerRun : 1) + 30_000;
      if (r.status !== "done" && Date.now() - Date.parse(r.queuedAt) > limit)
        abortRun(r, "timeout");
    }
  }, 5_000);

  // ------------------------------------------------------------------ admin
  function resetSession() {
    for (const r of runs.values()) if (r.status !== "done") abortRun(r, "session_reset");
    for (const t of ["player", "build", "run", "asset_job", "best_trace"]) db.clear(t);
    players.clear();
    builds.clear();
    runs.clear();
    jobs.clear();
    traces.clear();
    manifests.clear();
    newSession();
    if (settings.autoStart) startSession();
    else pushSession();
    pushRoster();
    pushLeaderboard();
    return session;
  }
  function patchConfig(next) {
    if (next.track !== config.track && session.status === "running")
      throw new ApiError("track_locked", "End the session before changing the track", 409);
    config = next;
    hub.toPhones("config.updated", config);
    hub.toAdmins("config.updated", config);
    hub.toGame("config.updated", config);
    return config;
  }

  // Options set by the game manager on the big screen (game.config.set, game.session.*).
  function managerCommand(type, pl) {
    if (type === "game.config.set") {
      const next = patchConfig(mergeConfig(config, pl));
      log(`[config] set from the game: ${JSON.stringify(pl)}`);
      return next;
    }
    if (type === "game.session.end") return endSession();
    if (type === "game.session.start") {
      if (session.status === "running")
        throw new ApiError("bad_request", "The session is already running", 400);
      return startSession(config.sessionMinutes * 60_000);
    }
    throw new ApiError("bad_request", `Unknown command ${type}`, 400);
  }

  // ------------------------------------------------------------------ boot
  for (const s of db.all("session")) session = s;
  for (const d of db.all("device")) devices.set(d.id, d);
  for (const p of db.all("player")) {
    const { asset, ...rest } = p;
    players.set(p.id, { ...rest, connected: false });
    if (asset) manifests.set(p.id, asset);
  }
  for (const b of db.all("build")) builds.set(b.id, b);
  for (const j of db.all("asset_job")) jobs.set(j.id, j);
  for (const t of db.all("best_trace")) traces.set(t.id, t.trace);
  for (const r of db.all("run")) {
    if (r.status !== "done")
      Object.assign(r, { status: "done", outcome: "aborted", endedAt: now() });
    runs.set(r.id, r);
    db.put("run", r);
  }
  for (const j of jobs.values()) {
    if (j.status === "queued" || j.status === "designing") {
      Object.assign(j, { status: "failed", error: "server restarted", updatedAt: now() });
      saveJob(j);
      const p = players.get(j.playerId);
      if (p?.status === "processing") savePlayer({ ...p, status: "draft" });
    }
  }
  if (!session) newSession();
  if (settings.autoStart && session.status === "idle") startSession();
  else if (session.status === "running") scheduleEnd();

  return {
    get config() {
      return config;
    },
    get session() {
      return session;
    },
    get weather() {
      return weather;
    },
    players,
    jobs,
    manifests,
    // views
    playerView,
    leaderboard,
    roster,
    activeRunStarts: () => [...runs.values()].filter((r) => r.status !== "done").map(runStart),
    allPlayerViews: () => {
      const rm = ranks();
      return [...players.keys()].map((id) => playerView(id, rm));
    },
    playerRuns,
    latestJob,
    publicJob,
    // devices & players
    ensureDevice,
    playerForDevice,
    mustPlayer,
    createPlayer,
    rename,
    setBuild,
    removePlayer,
    setDeviceOnline,
    // assets
    saveJob,
    pushPlayer,
    setPlayerStatus,
    setManifest,
    setRender,
    // runs
    launch,
    boost,
    stop,
    abortRun,
    abortAllRuns,
    onGameMessage,
    // session & admin
    startSession,
    endSession,
    resetSession,
    patchConfig,
    managerCommand,
    close() {
      clearInterval(capTimer);
      clearTimeout(endTimer);
      clearTimeout(rosterTimer);
    },
  };
}
