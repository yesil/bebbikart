extends RefCounted
## Mock network layer (game.md "Mock mode"): stands in for the server + phones so the game
## runs with no backend. Same shape as a real client: `poll()` returns server -> game
## messages (envelopes per contracts §7), `send()` takes game -> server messages and logs them.
##
## Fake players get random builds, join the line (contracts §2i) a few seconds after their
## last lap, steer with their thumb (§2g: skilled players steer onto the boost arrows, everyone
## picks a way at each fork, now and then the other one than their stars like, and some just
## wiggle) and sometimes re-roll their build between runs.
## Like the server: the two halves each take the first in line when free (left first; only the
## left while the screen isn't split), one lap each, with the result held for duelResultMs; the
## champion (best lap) waits behind everyone else. The screen splits once two players play and
## stays split until nobody has for splitHoldMs. The game gets queue.updated like from the server.

const Messages = preload("res://net/messages.gd")
const Builds = preload("res://sim/builds.gd")

const NAMES := [
	"Bebbi", "Zoe", "Mia", "Noah", "Lio", "Ella", "Ben", "Lina", "Tim", "Nora", "Max", "Ava",
	"Leo", "Emma", "Finn", "Lou", "Sam", "Ida", "Jan", "Yara", "Kai", "Mila", "Oli", "Rosa",
]

var cfg: Dictionary
var rng := RandomNumberGenerator.new()
var players: Array = []           # Dictionary per fake player
var by_run := {}                  # runId -> player dict
var inbox: Array = []             # pending server -> game envelopes
var log_mode := "summary"         # none | summary | full
var time := 0.0
var sent_counts := {}
var finished := 0
var failed := 0
## Optional Course (sim/course.gd or sim/village_course.gd).
var course = null
## Optional sim (sim/sim.gd): mock players read their racer to know where to steer.
var sim = null
## The line, the halves, the champion (contracts §2i).
var line: Array = []              # player dicts waiting, in the order they joined
var halves := {"left": {"run": "", "free_at": 0.0}, "right": {"run": "", "free_at": 0.0}}
var record := {"key": "", "tries": 0}
var last_lap := {}                # playerId -> mock time their last lap ended
var split := false                # queue.updated split
var _queue_json := ""


## A random RacerSpec.sound for a fake player (real racers get theirs from the spec).
func _make_sound() -> Dictionary:
	var engines := KitCatalog.names("engineSounds")
	var horns := KitCatalog.names("hornSounds")
	var pitch: Array = KitCatalog.limit("soundPitch")
	if engines.is_empty() or horns.is_empty():
		push_error("mock: racer kit has no sounds (%s)" % KitCatalog.load_error())
		return {}
	return {"engine": engines[rng.randi() % engines.size()], "horn": horns[rng.randi() % horns.size()],
		"pitch": rng.randf_range(float(pitch[0]), float(pitch[1]))}


func sound_of(player_id: String) -> Dictionary:
	for p in players:
		if p["playerId"] == player_id:
			return p["sound"]
	return {}


func _init(config: Dictionary, n_players: int, seed_: int) -> void:
	cfg = config
	rng.seed = seed_
	for i in n_players:
		var pid := Messages.make_id("ply", rng)
		var build := _make_build(pid)
		players.append({
			"playerId": pid,
			"nickname": NAMES[i % NAMES.size()] + ("" if i < NAMES.size() else str(i / NAMES.size() + 1)),
			"connected": true,
			"status": "ready",
			"assetBaseUrl": "",
			"build": build,
			"skill": rng.randf(),          # steering skill 0..1
			"wait": rng.randf_range(0.2, 6.0),  # first launch staggered over a few seconds
			"runId": "",
			"bestTimeMs": 0,
			"bestAt": 0.0,
			"steer_x": null,
			"steer_t": 0.0,
			"minds": {},
			"sound": _make_sound(),
		})
	# roster.updated carries a bare RosterEntry[] (contracts §7).
	inbox.append(Messages.make_msg(Messages.ROSTER_UPDATED, roster()))


func roster() -> Array:
	var out: Array = []
	for p in players:
		var e := {"playerId": p["playerId"], "nickname": p["nickname"], "connected": true,
			"status": p["status"], "assetBaseUrl": ""}
		if int(p["bestTimeMs"]) > 0:
			e["bestTimeMs"] = p["bestTimeMs"]
		out.append(e)
	return out


func player(player_id: String) -> Dictionary:
	for p in players:
		if p["playerId"] == player_id:
			return p
	return {}


func _make_build(pid: String) -> Dictionary:
	var b := Builds.random_build(rng)
	b["id"] = Messages.make_id("bld", rng)
	b["playerId"] = pid
	b["createdAt"] = Messages.now_iso()
	return b


## Advance mock time and return server -> game messages that are due. (free_slots: the
## server's interface; the two halves are the only limit here.)
func poll(dt: float, _free_slots: int) -> Array:
	time += dt
	for p in players:
		if p["status"] == "racing":
			_drive_steer(p, dt)
			continue
		if line.has(p):
			continue
		p["wait"] = float(p["wait"]) - dt
		if float(p["wait"]) <= 0.0:
			line.append(p)  # Go joins the line
	_fill_halves()
	_push_queue()
	var out := inbox
	inbox = []
	return out


func _launch(p: Dictionary, side: String) -> void:
	var run_id := Messages.make_id("run", rng)
	p["status"] = "racing"
	p["runId"] = run_id
	p["steer_x"] = null
	p["steer_t"] = 0.0
	p["minds"] = {}
	by_run[run_id] = p
	var payload := {"runId": run_id, "playerId": p["playerId"], "build": p["build"], "side": side}
	if course != null and course.get("loop") == true:
		payload["lapsPerRun"] = 1  # like the server: the laps travel with the run, one lap (§2i)
	inbox.append(Messages.make_msg(Messages.RUN_START, payload))


## Steer like a kid (contracts §2g), re-decided every few tenths of a second (quicker with more
## skill): near a fork, hands off (the autopilot takes the stars' way), or steering to the stars'
## way or the other one; else onto the boost arrows coming up (skilled players more often); the
## less skilled wiggle now and then. Otherwise the thumb is off the pad and the autopilot drives.
func _drive_steer(p: Dictionary, dt: float) -> void:
	if sim == null:
		return
	var r = sim.by_run.get(p["runId"])
	if r == null:
		return
	p["steer_t"] = float(p["steer_t"]) - dt
	if float(p["steer_t"]) > 0.0:
		return
	var skill := float(p["skill"])
	p["steer_t"] = lerpf(0.5, 0.15, skill) + rng.randf() * 0.15
	var x = null
	if r.state == "racing":
		var hint: Dictionary = r.fork_hint()
		var minds: Dictionary = p["minds"]
		if not hint.is_empty() and not minds.has(hint["id"]):
			# Hands off (the stars' way), steers to the stars' way, or to the other one.
			var roll := rng.randf()
			minds[hint["id"]] = "off" if roll < 0.35 else ("stars" if roll < 0.75 else "other")
		if not hint.is_empty() and int(hint["inM"]) < 40 and minds[hint["id"]] != "off":
			x = r.bot_lane(false, true)
			if x != null and minds[hint["id"]] == "other":
				x = -float(x)
		elif not hint.is_empty() and minds[hint["id"]] == "off":
			x = null
		else:
			x = r.bot_lane(rng.randf() < 0.3 + 0.7 * skill, false)
		if x == null and rng.randf() < 0.15 * (1.0 - skill):
			x = rng.randf_range(-1.0, 1.0)
	if x != null:
		x = snappedf(float(x), 0.01)
	if x == p["steer_x"]:
		return
	p["steer_x"] = x
	inbox.append(Messages.make_msg(Messages.RUN_STEER, {"runId": p["runId"], "x": x}))


# ---------------------------------------------------------------- the line (contracts §2i)

## The champion: the best time (on a loop, the best lap), the first to set it on a tie.
func _champion() -> Dictionary:
	var best := {}
	for p in players:
		var t := int(p["bestTimeMs"])
		if t <= 0:
			continue
		if best.is_empty() or t < int(best["bestTimeMs"]) or (t == int(best["bestTimeMs"]) and float(p["bestAt"]) < float(best["bestAt"])):
			best = p
	return best


## Launch order: everyone in the order they joined, the champion last.
func _line_order() -> Array:
	var champ := _champion()
	var out: Array = line.filter(func(p): return p != champ)
	if line.has(champ):
		out.append(champ)
	return out


## Who plays: on a half, in the line, or back from a lap less than splitHoldMs ago.
func _playing() -> int:
	var ids := {}
	for p in line:
		ids[p["playerId"]] = true
	for side in Protocol.SIDES:
		var rid: String = halves[side]["run"]
		if rid != "" and by_run.has(rid):
			ids[by_run[rid]["playerId"]] = true
	var hold_s := maxf(float(cfg.get("splitHoldMs", 30000)), float(cfg.get("duelResultMs", 5000))) / 1000.0
	for pid in last_lap.keys():
		if time - float(last_lap[pid]) < hold_s:
			ids[pid] = true
		else:
			last_lap.erase(pid)
	return ids.size()


## Split once a second player plays; whole again only when nobody does.
func _update_split() -> bool:
	var n := _playing()
	if n >= 2:
		split = true
	elif n == 0:
		split = false
	return split


## A free half (its result shown for duelResultMs) takes the first in line; left first, and
## only the left while the screen isn't split.
func _fill_halves() -> void:
	for side in Protocol.SIDES:
		if side != "left" and not _update_split():
			break
		var h: Dictionary = halves[side]
		if h["run"] != "" or time < float(h["free_at"]) or line.is_empty():
			continue
		var p: Dictionary = _line_order()[0]
		line.erase(p)
		_launch(p, side)
		h["run"] = p["runId"]


func _queue_state() -> Dictionary:
	var racing: Array = []
	for side in Protocol.SIDES:
		var rid: String = halves[side]["run"]
		if rid != "" and by_run.has(rid):
			var p: Dictionary = by_run[rid]
			racing.append({"side": side, "playerId": p["playerId"], "nickname": p["nickname"], "runId": rid})
	var q := {
		"line": _line_order().map(func(p): return {"playerId": p["playerId"], "nickname": p["nickname"]}),
		"racing": racing,
		"split": _update_split(),
		"skipped": [],
	}
	var champ := _champion()
	if not champ.is_empty():
		var key := "%s:%d" % [champ["playerId"], int(champ["bestTimeMs"])]
		if key != record["key"]:
			record = {"key": key, "tries": 0}
		q["champion"] = {"playerId": champ["playerId"], "nickname": champ["nickname"],
			"timeMs": int(champ["bestTimeMs"]), "tries": int(record["tries"])}
	return q


## queue.updated whenever the state changes (like the server: only on a change).
func _push_queue() -> void:
	var q := _queue_state()
	var json := JSON.stringify(q)
	if json == _queue_json:
		return
	_queue_json = json
	inbox.append(Messages.make_msg(Messages.QUEUE_UPDATED, q))


## A run ended: its half shows the result for duelResultMs; a lap by someone else than the
## champion counts as a try.
func _duel_done(p: Dictionary, run_id: String) -> void:
	var champ := _champion()
	last_lap[p["playerId"]] = time
	for side in Protocol.SIDES:
		var h: Dictionary = halves[side]
		if h["run"] == run_id:
			h["run"] = ""
			h["free_at"] = time + float(cfg.get("duelResultMs", 5000)) / 1000.0
	if not champ.is_empty() and champ != p:
		record["tries"] = int(record["tries"]) + 1


## Game -> server.
func send(type: String, payload: Dictionary) -> void:
	var msg := Messages.make_msg(type, payload)
	sent_counts[type] = int(sent_counts.get(type, 0)) + 1
	var p: Dictionary = by_run.get(String(payload.get("runId", "")), {})
	match type:
		Messages.GAME_RUN_FINISHED, Messages.GAME_RUN_FAILED:
			if not p.is_empty():
				_run_over(p, type == Messages.GAME_RUN_FINISHED, payload)
	_log(msg)


func _run_over(p: Dictionary, ok: bool, payload: Dictionary) -> void:
	var run_id: String = p["runId"]
	_duel_done(p, run_id)
	by_run.erase(run_id)
	p["status"] = "ready"
	p["runId"] = ""
	# On a loop the best lap ranks (also from a run that failed after some laps), like the server.
	var ms := int(payload.get("bestLapMs", payload.get("elapsedMs", 0) if ok else 0))
	if ms > 0 and (int(p["bestTimeMs"]) == 0 or ms < int(p["bestTimeMs"])):
		p["bestTimeMs"] = ms
		p["bestAt"] = time
	if ok:
		finished += 1
	else:
		failed += 1
	p["wait"] = rng.randf_range(3.0, 8.0)  # setting the stars, then Go again
	if rng.randf() < 0.3:
		p["build"] = _make_build(p["playerId"])


## Called by main when a run ends without a finished/failed message (e.g. aborted).
func run_gone(run_id: String) -> void:
	var p: Dictionary = by_run.get(run_id, {})
	if not p.is_empty():
		_run_over(p, false, {})


func _log(msg: Dictionary) -> void:
	if log_mode == "none":
		return
	var type: String = msg["type"]
	var pl: Dictionary = msg["payload"]
	if log_mode == "full":
		var copy := pl.duplicate(true)
		if copy.has("trace"):
			copy["trace"]["samples"] = "<%d floats>" % (copy["trace"]["samples"] as Array).size()
		print("[mock<-game] ", JSON.stringify({"v": msg["v"], "type": type, "id": msg["id"], "ts": msg["ts"], "payload": copy}))
		return
	match type:
		Messages.GAME_RUN_PROGRESS, Messages.GAME_RUN_SECTION, Messages.GAME_RUN_STARTED:
			pass
		Messages.GAME_RUN_FINISHED:
			print("[mock<-game] %s finished %s %.2f s  boosts %d  splits %s  events %d  trace %d samples" % [
				pl["runId"], _nick(pl), int(pl["elapsedMs"]) / 1000.0, int(pl["boostsUsed"]),
				JSON.stringify(pl["splits"]), (pl["events"] as Array).size(), (pl["trace"]["samples"] as Array).size() / 5])
		Messages.GAME_RUN_FAILED:
			print("[mock<-game] %s failed %s %s in %s at %.2f s  events %s" % [
				pl["runId"], _nick(pl), pl["reason"], pl["section"], int(pl["elapsedMs"]) / 1000.0, JSON.stringify(pl["events"])])
		Messages.GAME_WEATHER:
			print("[mock<-game] weather ", JSON.stringify(pl))
		_:
			print("[mock<-game] %s %s" % [type, JSON.stringify(pl)])


var _nicks := {}


func _nick(pl: Dictionary) -> String:
	return String(_nicks.get(String(pl.get("runId", "")), ""))


func remember_run(run_id: String, nickname: String) -> void:
	_nicks[run_id] = nickname
