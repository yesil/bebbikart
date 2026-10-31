// The server's state and rules: session, players, builds, runs, leaderboard (game-server.md).
// Transport-free: REST and WS handlers call these methods, and outgoing messages go through `hub`.
import {
  abortTip,
  coachTip,
  DEFAULT_BUILD,
  LOOP_TRACKS,
  mergeConfig,
  newId,
  parseBuildInput,
  routesFor,
  SECTION_IDS,
  SIDES,
  TRACK_STRETCHES,
  validateStars,
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
/**
 * Every complete pass of a run over its stretches, with the lap it was (an index into run.laps):
 * each lap on a loop, a finished point-to-point run (lap 0).
 */
function stretchPasses(run) {
  if (isLoop(run.track))
    return (run.lapStretches ?? []).map((stretches, lap) => ({ stretches, lap }));
  return run.outcome === "finished" && run.stretches ? [{ stretches: run.stretches, lap: 0 }] : [];
}
/**
 * The weather a lap of a run was raced in (contracts §2f): the lap's own on loop tracks, the run's
 * on point-to-point ones. Loop runs recorded before laps carried their weather have only the
 * run's, which is what they get.
 */
function lapWeather(run, lap) {
  if (isLoop(run.track) && run.lapWeather) {
    const w = run.lapWeather[lap];
    if (!w) throw new Error(`lapWeather: run ${run.id} has no weather for lap ${lap}`);
    return w;
  }
  return run.weatherSeen ?? [];
}
/** coachTip compares elapsedMs; on loops that is the best lap (a run that failed after laps
 * still gets the fail tip, naming where it ended). */
function forCoach(run) {
  if (!run || !isLoop(run.track) || run.bestLapMs === undefined) return run;
  return { ...run, elapsedMs: run.bestLapMs };
}

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
  /** Ties go to whoever set the time first (README rule 12): the earlier best run's end. */
  function setAt(p) {
    return runs.get(p.bestRunId)?.endedAt ?? p.createdAt;
  }
  function ranks() {
    const ranked = [...players.values()]
      .filter((p) => p.bestTimeMs !== undefined)
      .sort((a, b) => a.bestTimeMs - b.bestTimeMs || (setAt(a) < setAt(b) ? -1 : 1));
    return new Map(ranked.map((p, i) => [p.id, i + 1]));
  }
  /** The session's fastest racer (rank 1): the duel's champion (contracts §2i). */
  function champion() {
    let best;
    for (const p of players.values()) {
      if (p.bestTimeMs === undefined) continue;
      if (!best || p.bestTimeMs < best.bestTimeMs) best = p;
      else if (p.bestTimeMs === best.bestTimeMs && setAt(p) < setAt(best)) best = p;
    }
    return best;
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
        setAt: setAt(p),
        setup: bestSetup(p),
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
    const stage = p.status === "processing" ? latestJob(p.id)?.stage : undefined;
    if (stage) e.stage = stage;
    if (p.bestTimeMs !== undefined) e.bestTimeMs = p.bestTimeMs;
    return e;
  }
  const roster = () => [...players.values()].map(rosterEntry);
  function runStart(run) {
    const p = players.get(run.playerId);
    const out = { runId: run.id, playerId: run.playerId, build: builds.get(run.buildId) };
    if (run.lapsPerRun) out.lapsPerRun = run.lapsPerRun;
    if (run.side) out.side = run.side;
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
    pushPaddock();
    pushQueue(); // a racer joining, leaving or getting ready can split the big screen
  }
  /** Who else is here, for the phones: the kids waiting for their racer see their friends'. */
  function paddock() {
    return [...players.values()].map((p) => {
      const e = {
        playerId: p.id,
        nickname: p.nickname,
        status: p.status,
        connected: p.connected,
        racing: !!activeRun(p.id),
      };
      const stage = p.status === "processing" ? latestJob(p.id)?.stage : undefined;
      if (stage) e.stage = stage;
      const avatar = manifests.get(p.id)?.renders.avatar_happy;
      if (avatar) e.avatarUrl = avatar;
      return e;
    });
  }
  let paddockTimer = null;
  function pushPaddock() {
    clearTimeout(paddockTimer);
    paddockTimer = setTimeout(() => hub.toPhones("paddock.updated", paddock()), 400);
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
    endTimer = setTimeout(timeUp, Math.max(0, Math.min(ms, 2 ** 31 - 1)));
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
  // The session's time ran out. With autostart (the default) the next session opens right
  // away, so phones can always race; with BK_AUTOSTART=0 the facilitator starts the next one.
  function timeUp() {
    endSession();
    log(`[session] ${session.id} time is up`);
    if (settings.autoStart) startSession(config.sessionMinutes * 60_000);
    else log("[session] waiting for the game manager or the admin to start the next session");
  }
  function endSession() {
    if (session.status === "ended") return session;
    clearTimeout(endTimer);
    saveSession({ ...session, status: "ended", endsAt: session.endsAt ?? now() });
    pushSession();
    closeLine("session ended"); // runs on track finish; the podium shows
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
  /** Two kids called Mia are "Mia" and "Mia 2" everywhere (big screen, leaderboard, phones). */
  function uniqueNickname(nickname, exceptId) {
    const taken = new Set();
    for (const p of players.values()) if (p.id !== exceptId) taken.add(p.nickname.toLowerCase());
    if (!taken.has(nickname.toLowerCase())) return nickname;
    for (let n = 2; ; n++) {
      const suffix = ` ${n}`;
      const name = nickname.slice(0, 16 - suffix.length).trimEnd() + suffix;
      if (!taken.has(name.toLowerCase())) return name;
    }
  }
  function createPlayer(deviceId, nicknameRaw) {
    if (deviceId && playerForDevice(deviceId))
      throw new ApiError("player_exists", "This phone already has a racer", 409);
    if (players.size >= config.maxPlayers)
      throw new ApiError("server_full", "The track is full right now", 409);
    const cleaned = cleanNickname(nicknameRaw);
    if (!cleaned) throw new ApiError("bad_request", "Pick a racer name", 400);
    const nickname = uniqueNickname(cleaned);
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
    const cleaned = cleanNickname(nicknameRaw);
    if (!cleaned) throw new ApiError("bad_request", "Pick a racer name", 400);
    const nickname = uniqueNickname(cleaned, playerId);
    savePlayer({ ...p, nickname });
    pushPlayer(playerId);
    pushRoster();
    if (p.bestTimeMs !== undefined) pushLeaderboard();
    return playerView(playerId);
  }
  function saveBuild(playerId, input) {
    // Stars choose the routes (contracts §2h); there is no driving style any more.
    const b = {
      id: newId("build"),
      playerId,
      stars: { ...input.stars },
      routes: routesFor(input.stars),
      createdAt: now(),
    };
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
  /** Quit (the phone) or delete (admin): out of any race or queue, off the big screen and the
   *  leaderboard, and the phone goes back to the join screen. */
  function removePlayer(playerId, reason = "player_deleted") {
    const p = players.get(playerId);
    if (!p) throw new ApiError("not_found", "No such racer", 404);
    const run = activeRun(playerId);
    if (run) abortRun(run, reason);
    dropFromLine(playerId);
    hub.toPhone(playerId, "player.removed", { playerId }); // before the delete: routed by player
    players.delete(playerId);
    manifests.delete(playerId);
    db.del("player", playerId);
    hub.toAdmins("player.removed", { playerId });
    pushRoster();
    pushLeaderboard();
    log(`[player] ${p.nickname} (${playerId}) removed: ${reason}`);
  }
  /** Hub tells us a device's phone socket count went to/from zero. */
  function setDeviceOnline(deviceId, online) {
    const p = playerForDevice(deviceId);
    if (!p || p.connected === online) return;
    if (!online) releasePush(p.id); // a thumb can't hold Push on a phone that is gone (§2g)
    savePlayer({ ...p, connected: online });
    hub.toAdmins("player.updated", playerView(p.id));
    pushRoster();
  }
  /** The big screen (re)connected or loaded its track: duel halves can fill again. */
  function gameChanged() {
    fillHalves();
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
    fillHalves(); // waiting in the line for a new look
  }
  function setRender(playerId, key, url) {
    const m = manifests.get(playerId);
    if (!m) throw new ApiError("not_found", "Racer has no asset package yet", 404);
    manifests.set(playerId, { ...m, renders: { ...m.renders, [key]: url }, updatedAt: now() });
    savePlayer(players.get(playerId));
    pushPlayer(playerId);
    pushPaddock(); // the avatar for the other phones
    if (players.get(playerId).bestTimeMs !== undefined) pushLeaderboard();
  }

  // ------------------------------------------------------------------ runs
  const isDuel = () => config.mode === "duel";
  /** What every launch needs: a running session and a racer that is ready and not racing. */
  function mustLaunchable(playerId) {
    const p = players.get(playerId);
    if (!p) throw new ApiError("not_found", "No such racer", 404);
    if (session.status !== "running")
      throw new ApiError("session_not_running", "The race isn't open right now", 409);
    if (p.status !== "ready") throw new ApiError("not_ready", "Your racer isn't ready yet", 409);
    if (activeRun(playerId))
      throw new ApiError("run_in_progress", "Your racer is still on the track", 409);
    return p;
  }
  /** A build saved under an older star budget can't race: the player sets their stars again. */
  function mustRaceableBuild(playerId) {
    const build = latestBuild(playerId);
    const stars = validateStars(build.stars, config);
    if (!stars.ok)
      throw new ApiError("invalid_build", `Set your stars again: ${stars.errors.join("; ")}`, 400);
    return build;
  }
  /** The big screen must be there, with the session's track loaded. */
  function gameReady() {
    // After a track switch the big screen loads the new world once its track is empty, then says
    // hello again with it. A run before that would race the old course.
    return hub.gameOnline() && !(hub.gameTrack() && hub.gameTrack() !== config.track);
  }
  /**
   * Go: a free race starts at once (contracts §2c); a duel joins the line (§2i) and returns the
   * line instead of a run.
   */
  function launch(playerId) {
    if (isDuel()) return joinLine(playerId);
    const p = mustLaunchable(playerId);
    const last = playerRuns(playerId).find((r) => r.status === "done");
    const readyAt = last?.endedAt ? Date.parse(last.endedAt) + config.launchCooldownMs : 0;
    if (Date.now() < readyAt)
      throw new ApiError("cooldown", "Catch your breath! Ready in a moment", 409);
    if (!hub.gameOnline())
      throw new ApiError("game_offline", "The big screen isn't connected", 409);
    if (!gameReady())
      throw new ApiError(
        "track_changing",
        "The big screen is changing track, try again in a moment",
        409,
      );
    const running = [...runs.values()].filter((r) => r.status !== "done").length;
    if (running >= config.maxConcurrentRuns)
      throw new ApiError("run_in_progress", "The track is full, try again in a moment", 409);
    return startRun(p, mustRaceableBuild(playerId));
  }
  function startRun(p, build, side) {
    const run = {
      id: newId("run"),
      playerId: p.id,
      buildId: build.id,
      status: "queued",
      queuedAt: now(),
      track: config.track,
    };
    // The laps travel with the run (big screen and phone show and race this, not their config).
    // A duel is one lap (§2i).
    if (isLoop(config.track)) run.lapsPerRun = side ? 1 : config.lapsPerRun;
    if (side) run.side = side;
    saveRun(run);
    hub.toGame("run.start", runStart(run));
    hub.toPhone(p.id, "run.queued", { run });
    pushPlayer(p.id);
    pushPaddock();
    log(`[run] ${run.id} queued for "${p.nickname}"${side ? ` on the ${side}` : ""}`);
    return run;
  }
  // Push (contracts §2g): held down or let go on the phone, relayed to the game. The server
  // remembers who holds it, so a phone that disconnects mid-hold lets go.
  const pushing = new Set(); // runIds with Push held
  function push(playerId, runId, on) {
    const run = activeRun(playerId);
    if (!run || run.id !== runId) return false;
    if (on) pushing.add(run.id);
    else pushing.delete(run.id);
    hub.toGame("run.push", { runId: run.id, on });
    return true;
  }
  function releasePush(playerId) {
    const run = activeRun(playerId);
    if (run && pushing.delete(run.id)) hub.toGame("run.push", { runId: run.id, on: false });
  }
  // ------------------------------------------------------------------ duel (contracts §2i)
  // King of the hill: the champion (rank 1) rests; the others take turns in the line, one lap
  // each, on the two halves of the big screen. Go joins the line; a free half launches its head.
  const line = []; // playerIds in join order (lineOrder puts the champion last)
  const skipped = new Set(); // out of the line: their phone was offline at their turn
  const halves = Object.fromEntries(SIDES.map((side) => [side, { runId: null, freeAt: 0 }]));
  let record = { key: "", tries: 0 }; // the champion's time, and duel laps by others since
  let fillTimer = null;
  let lastQueue = "";
  function joinLine(playerId) {
    const p = mustLaunchable(playerId);
    if (line.includes(playerId)) throw new ApiError("in_line", "You're already in the line", 409);
    mustRaceableBuild(playerId);
    line.push(playerId);
    skipped.delete(playerId);
    log(`[duel] "${p.nickname}" joined the line (${line.length} waiting)`);
    pushQueue();
    fillHalves();
    return queueState();
  }
  function leaveLine(playerId) {
    if (dropFromLine(playerId)) log(`[duel] ${players.get(playerId)?.nickname} left the line`);
    return queueState();
  }
  function dropFromLine(playerId) {
    const i = line.indexOf(playerId);
    if (i < 0) return false;
    line.splice(i, 1);
    pushQueue();
    return true;
  }
  function closeLine(why) {
    if (!line.length && !skipped.size) return pushQueue();
    log(`[duel] the line closes (${why}): ${line.length} waiting`);
    line.length = 0;
    skipped.clear();
    pushQueue();
  }
  /** Launch order: as they joined, but the champion rests behind everyone else. */
  function lineOrder() {
    const champ = champion()?.id;
    return [...line.filter((id) => id !== champ), ...line.filter((id) => id === champ)];
  }
  /** The record and how many have tried it; a new record (or a better own time) starts at 0. */
  function recordState() {
    const c = champion();
    const key = c ? `${c.id}:${c.bestTimeMs}` : "";
    if (key !== record.key) record = { key, tries: 0 };
    return c;
  }
  function queueState() {
    const nick = (id) => players.get(id)?.nickname ?? "?";
    const racing = [];
    for (const side of SIDES) {
      const r = halves[side].runId && runs.get(halves[side].runId);
      if (r && r.status !== "done")
        racing.push({ side, playerId: r.playerId, nickname: nick(r.playerId), runId: r.id });
    }
    const out = {
      line: lineOrder().map((id) => ({ playerId: id, nickname: nick(id) })),
      racing,
      split: [...players.values()].filter((p) => p.status === "ready").length >= 2,
      skipped: [...skipped],
    };
    const c = recordState();
    if (c)
      out.champion = {
        playerId: c.id,
        nickname: c.nickname,
        timeMs: c.bestTimeMs,
        tries: record.tries,
      };
    return out;
  }
  /** queue.updated to phones, admins and the game, when something changed (duel mode only). */
  function pushQueue() {
    if (!isDuel() && !lastQueue) return;
    const q = isDuel() ? queueState() : { line: [], racing: [], split: false, skipped: [] };
    const json = JSON.stringify(q);
    if (json === lastQueue) return;
    lastQueue = isDuel() ? json : "";
    hub.toPhones("queue.updated", q);
    hub.toAdmins("queue.updated", q);
    hub.toGame("queue.updated", q);
  }
  /** Each free half takes the first in line who can race now. */
  function fillHalves() {
    clearTimeout(fillTimer);
    if (!isDuel() || session.status !== "running" || !gameReady()) return;
    let wakeAt = Number.POSITIVE_INFINITY;
    for (const side of SIDES) {
      const half = halves[side];
      if (half.runId) continue;
      if (Date.now() < half.freeAt) {
        wakeAt = Math.min(wakeAt, half.freeAt);
        continue;
      }
      for (const id of lineOrder()) {
        const p = players.get(id);
        if (!p) {
          dropFromLine(id);
          continue;
        }
        // No silent waiting: an offline phone loses its turn, loudly (facilitator racers never).
        if (p.deviceId && !p.connected) {
          dropFromLine(id);
          skipped.add(id);
          log(`[duel] "${p.nickname}" skipped: their phone is offline`);
          hub.toPhone(id, "error", {
            code: "not_ready",
            message: "Your phone was offline at your turn. Join the line again!",
          });
          continue;
        }
        if (p.status !== "ready" || activeRun(id)) continue; // e.g. a new look being made
        let build;
        try {
          build = mustRaceableBuild(id);
        } catch (err) {
          dropFromLine(id);
          hub.toPhone(id, "error", { code: err.code, message: err.message });
          continue;
        }
        line.splice(line.indexOf(id), 1);
        half.runId = startRun(p, build, side).id;
        break;
      }
    }
    pushQueue();
    if (wakeAt < Number.POSITIVE_INFINITY)
      fillTimer = setTimeout(fillHalves, Math.max(0, wakeAt - Date.now()));
  }
  /** A run ended: its half shows the result for duelResultMs, then takes the next in line. */
  function runDone(run, recordBefore) {
    pushing.delete(run.id);
    if (!run.side) return;
    const half = halves[run.side];
    if (half.runId !== run.id) return;
    half.runId = null;
    half.freeAt = Date.now() + (run.outcome === "aborted" ? 0 : config.duelResultMs);
    // A lap by someone else against a record that still stands is one more try.
    const after = recordState();
    if (
      run.outcome !== "aborted" &&
      recordBefore &&
      after?.id === recordBefore.id &&
      run.playerId !== recordBefore.id
    )
      record.tries++;
    pushQueue();
    fillHalves();
  }
  /** run.ended's duel part: judged against the record as it stood when the lap ended. */
  function duelResult(run, time, recordBefore, rank) {
    const out = { newChampion: rank === 1 && recordBefore?.id !== run.playerId };
    if (recordBefore) {
      out.recordNickname = recordBefore.nickname;
      if (time !== undefined) out.gapMs = Math.round(time - recordBefore.bestTimeMs);
    }
    return out;
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
  /** "Show me on the big screen": the game queues the racer for one of its next camera cuts. */
  function watch(playerId, runId) {
    const run = activeRun(playerId);
    if (!run || (runId && run.id !== runId)) return false;
    hub.toGame("run.watch", { runId: run.id });
    return true;
  }
  function abortRun(run, reason) {
    if (run.status === "done") return;
    const done = { ...run, status: "done", outcome: "aborted", endedAt: now() };
    saveRun(done);
    hub.toGame("run.abort", { runId: run.id, reason });
    hub.toPhone(run.playerId, "run.ended", {
      run: done,
      isPersonalBest: false,
      coach: abortTip(config.language),
      stretches: [],
    });
    pushPlayer(run.playerId);
    runGreen.delete(run.id);
    pushHeat(run.id);
    pushPaddock();
    runDone(done);
  }

  // ------------------------------------------------------------------ heats
  // Runs that left the start within HEAT_WINDOW_MS of each other raced each other (the start
  // countdown sends a group off together). Each time one of them ends, every phone in the heat
  // gets the places so far (run.heat); the last one home makes it done.
  // Runs from the same start countdown are one heat however many rows it took to release them
  // (16 karts leave over ~2.7 s); without a countdown, starts within HEAT_WINDOW_MS are.
  const HEAT_WINDOW_MS = 2_500;
  const heats = new Map(); // heatId (its first run's id) -> { id, startedAt, green, runIds }
  const runHeat = new Map(); // runId -> heatId
  const runGreen = new Map(); // runId -> its countdown's green time (game.run.grid)
  function joinHeat(runId) {
    const t = Date.now();
    const green = runGreen.get(runId);
    runGreen.delete(runId);
    let heat = [...heats.values()].find((h) =>
      green !== undefined
        ? h.green === green
        : h.green === undefined && t - h.startedAt <= HEAT_WINDOW_MS,
    );
    if (!heat) {
      heat = { id: runId, startedAt: t, green, runIds: [] };
      heats.set(heat.id, heat);
    }
    heat.runIds.push(runId);
    runHeat.set(runId, heat.id);
  }
  /** Where a run is among its heat right now: racers home with a time first, then by distance. */
  function heatPlace(r) {
    const heat = heats.get(runHeat.get(r.id));
    if (!heat || heat.runIds.length < 2) return undefined;
    const members = heat.runIds
      .map((id) => runs.get(id))
      .filter((m) => m && players.has(m.playerId));
    let ahead = 0;
    for (const m of members) {
      if (m.id === r.id) continue;
      if (m.status === "done") ahead += rankTime(m) !== undefined ? 1 : 0;
      else if ((m.liveDist ?? 0) > (r.liveDist ?? 0)) ahead++;
    }
    return { place: ahead + 1, of: members.length };
  }
  function pushHeat(runId) {
    const heat = heats.get(runHeat.get(runId));
    if (!heat) return;
    const members = heat.runIds
      .map((id) => runs.get(id))
      .filter((r) => r && players.has(r.playerId));
    const done = members.every((r) => r.status === "done");
    if (members.length >= 2) {
      const timed = members
        .filter((r) => r.status === "done" && rankTime(r) !== undefined)
        .sort((a, b) => rankTime(a) - rankTime(b));
      const racing = members.filter((r) => r.status !== "done");
      const out = members.filter((r) => r.status === "done" && rankTime(r) === undefined);
      const entries = [...timed, ...racing, ...out].map((r) => {
        const e = { playerId: r.playerId, nickname: players.get(r.playerId).nickname };
        const avatar = manifests.get(r.playerId)?.renders.avatar_happy;
        if (avatar) e.avatarUrl = avatar;
        const i = timed.indexOf(r);
        if (i >= 0) Object.assign(e, { place: i + 1, timeMs: rankTime(r) });
        if (r.status === "done") e.outcome = r.outcome;
        if (r.failReason) e.failReason = r.failReason;
        return e;
      });
      for (const r of members)
        hub.toPhone(r.playerId, "run.heat", { heatId: heat.id, done, entries });
    }
    if (done) {
      heats.delete(heat.id);
      for (const id of heat.runIds) runHeat.delete(id);
    }
  }
  /** The game went away: its runs can't finish. */
  function abortAllRuns(reason) {
    for (const r of runs.values()) {
      if (r.status === "done") continue;
      const done = { ...r, status: "done", outcome: "aborted", endedAt: now() };
      saveRun(done);
      hub.toPhone(r.playerId, "run.ended", {
        run: done,
        isPersonalBest: false,
        coach: abortTip(config.language),
        stretches: [],
      });
      pushPlayer(r.playerId);
      pushHeat(r.id);
      pushPaddock();
      runDone(done);
      log(`[run] ${r.id} aborted (${reason})`);
    }
  }
  let grid = null; // the open start countdown: { goAt, playerIds } (grid.updated)
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
        joinHeat(r.id);
        hub.toPhone(r.playerId, "run.started", { run: started });
        pushPlayer(r.playerId);
        return;
      }
      case "game.run.grid": {
        // On the start grid in a countdown: the phone counts down to green with the big screen,
        // and every other phone hears who is on the grid, so friends can join that race.
        const r = gameRun(pl.runId);
        if (!r) return;
        hub.toPhone(r.playerId, "run.grid", pl);
        const goAt = Date.now() + pl.goInMs;
        if (!grid || Math.abs(grid.goAt - goAt) > 300) grid = { goAt, playerIds: [] };
        runGreen.set(r.id, grid.goAt);
        if (!grid.playerIds.includes(r.playerId)) grid.playerIds.push(r.playerId);
        const racers = grid.playerIds
          .filter((id) => players.has(id))
          .map((id) => ({ playerId: id, nickname: players.get(id).nickname }));
        hub.toPhones("grid.updated", { goInMs: pl.goInMs, racers });
        return;
      }
      case "game.run.progress": {
        const r = gameRun(pl.runId);
        if (!r) return;
        r.liveDist = (pl.lap ? pl.lap - 1 : 0) + pl.progress; // laps + progress on loops
        const out = { ...pl };
        const hp = heatPlace(r);
        if (hp) Object.assign(out, hp);
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
        r.liveLapStretches = [...(r.liveLapStretches ?? []), pl.stretches];
        r.liveLapWeather = [...(r.liveLapWeather ?? []), pl.weatherSeen];
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
      case "game.camera": {
        // Every phone hears who is on the big screen; the racer's own phone shows it.
        const r = pl.runId ? runs.get(pl.runId) : undefined;
        hub.toPhones("camera.updated", r ? { playerId: r.playerId, runId: r.id } : {});
        return;
      }
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
    const { liveSplits, liveLaps, liveLapStretches, liveLapWeather, liveDist, ...base } = r;
    const run = {
      ...base,
      status: "done",
      outcome: ok ? "finished" : "failed",
      startedAt: r.startedAt ?? r.queuedAt,
      endedAt: now(),
      splits: pl.splits,
      stretches: pl.stretches,
      events: pl.events,
      boostsUsed: pl.boostsUsed,
      weatherSeen: pl.weatherSeen,
    };
    if (ok) run.elapsedMs = pl.elapsedMs;
    else
      Object.assign(run, {
        failReason: pl.reason,
        failSection: pl.section,
        failStretch: pl.stretch,
      });
    if (isLoop(run.track)) {
      run.lapStretches = liveLapStretches ?? [];
      run.lapWeather = liveLapWeather ?? [];
    }
    if (pl.laps) run.laps = pl.laps;
    if (pl.bestLapMs !== undefined) run.bestLapMs = pl.bestLapMs;
    if (isLoop(run.track) && run.laps?.length && run.bestLapMs === undefined)
      run.bestLapMs = Math.min(...run.laps);
    saveRun(run);
    const p = players.get(r.playerId);
    const prevBest = bestRunOf(r.playerId);
    const recordBefore = run.side ? champion() : undefined; // what a duel lap is judged against
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
    const stretches = stretchResults(run);
    const coach = coachTip(
      forCoach(run),
      builds.get(run.buildId),
      forCoach(prevBest),
      config.language,
      stretches,
    );
    const rank = ranks().get(r.playerId);
    const ended = { run, isPersonalBest, ...(rank ? { rank } : {}), coach, stretches };
    if (run.side) ended.duel = duelResult(run, time, recordBefore, rank);
    hub.toPhone(r.playerId, "run.ended", ended);
    pushHeat(run.id);
    pushPaddock();
    pushPlayer(r.playerId);
    if (isPersonalBest) {
      pushLeaderboard();
      pushRoster();
    }
    runDone(run, recordBefore);
    log(
      `[run] ${run.id} ${run.outcome} "${p?.nickname}" ${ok ? `${(run.elapsedMs / 1000).toFixed(2)} s` : `${run.failReason} @${run.failSection}`}${run.laps ? ` laps ${run.laps.map((l) => (l / 1000).toFixed(2)).join("/")}` : ""}${isPersonalBest ? " (best)" : ""}`,
    );
  }
  /** The setup a lap of a run was raced with (contracts §2f): its build and that lap's weather. */
  function setupOf(run, lap) {
    const b = builds.get(run.buildId);
    if (!b) throw new Error(`setupOf: run ${run.id} has no build ${run.buildId}`);
    return {
      stars: { ...b.stars },
      routes: { ...(b.routes ?? routesFor(b.stars)) },
      weather: lapWeather(run, lap),
    };
  }
  /** A ranked player's best: the setup of the run (on a loop, the lap) that set it. */
  function bestSetup(p) {
    const run = runs.get(p.bestRunId);
    if (!run) throw new Error(`bestSetup: ${p.nickname} has a best time but no best run`);
    const lap = isLoop(run.track) ? run.laps.indexOf(run.bestLapMs) : 0;
    return setupOf(run, lap);
  }
  /**
   * The run's stretches for its phone (contracts §2d): with the player's best on each from earlier
   * runs and the session's fastest (any racer, this run included), over the session's runs on
   * this track. A stretch the track doesn't know is a bug, so it throws.
   */
  function stretchResults(run) {
    const known = TRACK_STRETCHES[run.track];
    if (!known) throw new Error(`stretchResults: no stretches for track "${run.track}"`);
    const since = session.startedAt ?? "";
    const best = new Map(); // id -> ms, this player's earlier runs
    const fastest = new Map(); // id -> { ms, playerId, setup }
    for (const other of runs.values()) {
      if (other.status !== "done" || other.track !== run.track || other.queuedAt < since) continue;
      for (const pass of stretchPasses(other)) {
        for (const st of pass.stretches) {
          const f = fastest.get(st.id);
          if (!f || st.ms < f.ms)
            fastest.set(st.id, { ms: st.ms, playerId: other.playerId, run: other, lap: pass.lap });
          if (other.playerId === run.playerId && other.id !== run.id) {
            best.set(st.id, Math.min(best.get(st.id) ?? Number.POSITIVE_INFINITY, st.ms));
          }
        }
      }
    }
    return (run.stretches ?? []).map((st) => {
      const meta = known.find((k) => k.id === st.id);
      if (!meta) throw new Error(`stretchResults: "${st.id}" is not a ${run.track} stretch`);
      const out = { ...st, ability: meta.ability };
      if (best.has(st.id)) out.bestMs = best.get(st.id);
      const f = fastest.get(st.id);
      if (f) {
        out.fastestMs = f.ms;
        out.fastestPlayerId = f.playerId;
        const who = players.get(f.playerId);
        if (who) out.fastestNickname = who.nickname;
        out.fastestSetup = setupOf(f.run, f.lap);
      }
      // A fork piece: the session's fastest through the same fork the other way (§2f).
      const alt = meta.fork && known.find((k) => k.fork === meta.fork && k.choice !== meta.choice);
      const fo = alt && fastest.get(alt.id);
      const whoAlt = fo && players.get(fo.playerId);
      if (whoAlt) {
        out.other = {
          id: alt.id,
          ms: fo.ms,
          playerId: fo.playerId,
          nickname: whoAlt.nickname,
          setup: setupOf(fo.run, fo.lap),
        };
      }
      return out;
    });
  }

  // Runs the game never reports back on (e.g. it crashed mid-run).
  const capTimer = setInterval(() => {
    for (const r of runs.values()) {
      // runTimeCapMs applies per lap on loop tracks.
      const limit = config.runTimeCapMs * (isLoop(r.track) ? r.lapsPerRun : 1) + 30_000;
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
    if (next.mode !== config.mode && session.status === "running")
      throw new ApiError("mode_locked", "End the session before changing the mode", 409);
    const modeChanged = next.mode !== config.mode;
    config = next;
    if (modeChanged) closeLine(`mode is now ${config.mode}`);
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
  // Autostart: a session that ended (or ran out while the server was down) is followed by a
  // new one at boot, never left ended.
  if (settings.autoStart && session.status !== "running")
    startSession(config.sessionMinutes * 60_000);
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
    paddock,
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
    pushRoster,
    setPlayerStatus,
    setManifest,
    setRender,
    // runs
    launch,
    boost,
    stop,
    watch,
    push,
    abortRun,
    abortAllRuns,
    onGameMessage,
    // duel
    leaveLine,
    gameChanged,
    queueState,
    fillHalves,
    // session & admin
    startSession,
    endSession,
    resetSession,
    patchConfig,
    managerCommand,
    close() {
      clearInterval(capTimer);
      clearTimeout(fillTimer);
      clearTimeout(endTimer);
      clearTimeout(rosterTimer);
      clearTimeout(paddockTimer);
    },
  };
}
