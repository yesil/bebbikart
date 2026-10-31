extends RefCounted
## Mock network layer (game.md "Mock mode"): stands in for the server + phones so the game
## runs with no backend. Same shape as a real client: `poll()` returns server -> game
## messages (envelopes per contracts §7), `send()` takes game -> server messages and logs them.
##
## Fake players get random builds, launch runs after the cooldown, tap Boost (skilled
## players aim for boost zones using the progress they are sent, others tap at random)
## and sometimes re-roll their build between runs.

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
## Optional Course (sim/course.gd); skilled mock players use it to aim taps at boost zones.
var course = null


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
			"skill": rng.randf(),          # boost timing skill 0..1
			"wait": rng.randf_range(0.2, 6.0),  # first launch staggered over a few seconds
			"runId": "",
			"taps": [],
			"bestTimeMs": 0,
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


## Advance mock time and return server -> game messages that are due.
func poll(dt: float, free_slots: int) -> Array:
	time += dt
	for p in players:
		if p["status"] == "racing":
			continue
		p["wait"] = float(p["wait"]) - dt
		if float(p["wait"]) <= 0.0 and free_slots > 0:
			free_slots -= 1
			_launch(p)
	var out := inbox
	inbox = []
	return out


func _launch(p: Dictionary) -> void:
	var run_id := Messages.make_id("run", rng)
	p["status"] = "racing"
	p["runId"] = run_id
	p["taps"] = []
	p["hints"] = _boost_hints(p["build"])
	by_run[run_id] = p
	var payload := {"runId": run_id, "playerId": p["playerId"], "build": p["build"]}
	inbox.append(Messages.make_msg(Messages.RUN_START, payload))


## Boost zones as progress fractions [from, to] along this build's path.
func _boost_hints(build: Dictionary) -> Array:
	var out: Array = []
	if course == null:
		return out
	var path: Array[String] = course.path_for(build["routes"])
	var total: float = course.path_length(path)
	var acc := 0.0
	for id in path:
		var seg: Dictionary = course.segments[id]
		for z in seg["boosts"]:
			out.append([(acc + float(z[0])) / total, (acc + float(z[1])) / total])
		acc += float(seg["route"].length)
	return out


func _tap(p: Dictionary) -> void:
	inbox.append(Messages.make_msg(Messages.RUN_BOOST, {"runId": p["runId"]}))


## Game -> server.
func send(type: String, payload: Dictionary) -> void:
	var msg := Messages.make_msg(type, payload)
	sent_counts[type] = int(sent_counts.get(type, 0)) + 1
	var p: Dictionary = by_run.get(String(payload.get("runId", "")), {})
	match type:
		Messages.GAME_RUN_PROGRESS:
			if not p.is_empty():
				_maybe_boost(p, float(payload["progress"]), int(payload["boostsLeft"]))
		Messages.GAME_RUN_FINISHED, Messages.GAME_RUN_FAILED:
			if not p.is_empty():
				_run_over(p, type == Messages.GAME_RUN_FINISHED, payload)
	_log(msg)


func _maybe_boost(p: Dictionary, progress: float, boosts_left: int) -> void:
	if boosts_left <= 0:
		return
	var skill := float(p["skill"])
	# Skilled players tap inside boost zones; everyone else taps at random now and then.
	for z in p.get("hints", []):
		if progress >= float(z[0]) and progress <= float(z[1]) and not (p["taps"] as Array).has(z):
			(p["taps"] as Array).append(z)
			if rng.randf() < skill:
				_tap(p)
				return
	if rng.randf() < 0.012 * (1.0 - skill):
		_tap(p)


func _run_over(p: Dictionary, ok: bool, payload: Dictionary) -> void:
	by_run.erase(p["runId"])
	p["status"] = "ready"
	p["runId"] = ""
	if ok:
		finished += 1
		var ms := int(payload["elapsedMs"])
		if int(p["bestTimeMs"]) == 0 or ms < int(p["bestTimeMs"]):
			p["bestTimeMs"] = ms
	else:
		failed += 1
	p["wait"] = float(cfg.get("launchCooldownMs", 2000)) / 1000.0 + rng.randf_range(1.0, 6.0)
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
	var who := ""
	var p: Dictionary = by_run.get(String(pl.get("runId", "")), {})
	if not p.is_empty():
		who = String(p["nickname"])
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
