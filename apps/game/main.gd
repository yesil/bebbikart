# BebbiKart game (WS3a/3b): grey-box course + 60 Hz driving sim, running in mock mode.
#   godot --path apps/game                      windowed, 20 mock racers
#   godot --path apps/game -- --racers=12 --seed=4 --weather=storm --duration=60
#   godot --headless --path apps/game -- --duration=30 --log=full
# Real server (phones race on the big screen):
#   godot --path apps/game -- --server                     ws://localhost:8080/ws, key "bebbikart-dev"
#   godot --path apps/game -- --server=ws://host:8080/ws --game-key=KEY   (or env BK_GAME_KEY)
# Options (after --): --mock (default), --server[=URL], --game-key=KEY, --racers=N, --seed=N,
#   --weather=calm|rain|wind|storm (forced), --duration=SEC (quit after), --speed=X,
#   --screenshot=path.png [--shot-at=SEC] [--cam=follow|wide|forks], --log=none|summary|full
# Keys: C camera mode, Tab next racer, F next fork shot, R/W start next rain/wind phase,
#   K toggle forced calm, B boost the followed racer, H hide overlay.
extends Node3D

const Course = preload("res://sim/course.gd")
const Sim = preload("res://sim/sim.gd")
const Racer = preload("res://sim/racer.gd")
const Messages = preload("res://net/messages.gd")
const MockNet = preload("res://net/mock_net.gd")
const ServerNet = preload("res://net/server_net.gd")
const RosterAssets = preload("res://net/roster_assets.gd")
const KitRacerView = preload("res://racer_kit/kit_racer_view.gd")
const WORLD_SCENE := "res://world/course_world.tscn"
const DECOR_SCENE := "res://world/decor.tscn"
const RacerView = preload("res://world/racer_view.gd")
const WeatherFx = preload("res://world/weather_fx.gd")
const CameraRig = preload("res://world/camera_rig.gd")

const FORCED := {"calm": [0.0, 0.0], "rain": [1.0, 0.0], "wind": [0.0, 0.8], "storm": [1.0, 0.8]}

var args := {}
var course: Course
var config: Dictionary
var sim: Sim
var net                    # net/mock_net.gd or net/server_net.gd (same interface)
var assets = null          # net/roster_assets.gd, server mode only
var views := {}            # runId -> RacerView
var colors := {}           # playerId -> Color
var nicks := {}            # playerId -> nickname
var results: Array = []    # recent finished/failed lines
var camera: CameraRig
var fx: WeatherFx
var overlay: Label
var follow_run := ""
var run_time := 0.0
var shot_taken := false
var forced_calm := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var seed_ := int(args.get("seed", str(randi() % 100000)))
	var n_racers := int(args.get("racers", "20"))
	# Godot scales the physics delta (not the tick count) with time_scale, so speed up by ticking more often.
	var speed := clampf(float(args.get("speed", "1")), 0.1, 16.0)
	Engine.physics_ticks_per_second = int(Protocol.SIM_TICK_HZ * speed)
	Engine.max_physics_steps_per_frame = maxi(8, int(8 * speed))
	config = Messages.default_config()
	course = Course.new()
	sim = Sim.new(course, config, seed_)
	if args.has("weather"):
		var w: Array = FORCED.get(args["weather"], [0.0, 0.0])
		sim.weather.force(w[0], w[1], 30.0)
	if args.has("server"):
		var url: String = args["server"] if String(args["server"]).begins_with("ws") else "ws://localhost:8080/ws"
		var key: String = args.get("game-key", OS.get_environment("BK_GAME_KEY") if OS.has_environment("BK_GAME_KEY") else "bebbikart-dev")
		net = ServerNet.new(config, url, key)
		assets = RosterAssets.new()
		assets.http_base = net.http_base()
		assets.game_key = key
		add_child(assets)
		assets.racer_ready.connect(_on_racer_ready)
		assets.problem.connect(func(text: String): _result("ERROR " + text))
		print("BebbiKart server mode: %s (protocol v%d)" % [url, Protocol.PROTOCOL_VERSION])
	else:
		net = MockNet.new(config, n_racers, seed_)
		print("BebbiKart mock mode: protocol v%d, %d fake players, seed %d, course %s" % [
			Protocol.PROTOCOL_VERSION, n_racers, seed_, JSON.stringify(course.all_route_lengths())])
	net.course = course
	net.log_mode = args.get("log", "summary")
	for i in net.players.size():
		var p: Dictionary = net.players[i]
		colors[p["playerId"]] = Color.from_hsv(float(i) / maxf(1.0, net.players.size()), 0.75, 0.95)
		nicks[p["playerId"]] = p["nickname"]
	_build_scene()


func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_light_color = Color(0.6, 0.63, 0.7)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-140), 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)
	camera = CameraRig.new()
	add_child(camera)
	camera.make_current()
	if not _load_countryside_world():
		return
	camera.mode = {"follow": CameraRig.Mode.FOLLOW, "wide": CameraRig.Mode.WIDE, "forks": CameraRig.Mode.FORKS}.get(args.get("cam", "follow"), CameraRig.Mode.FOLLOW)
	camera.fork_shots = [
		[Vector3(18, 9, 60), Vector3(3, 0, 78)],      # ramp: jump vs around
		[Vector3(25, 14, 145), Vector3(-10, 0, 170)], # pond: water vs bridge
		[Vector3(-14, 9, 230), Vector3(6, 1, 252)],   # crossing: exposed vs sheltered
	]
	fx = WeatherFx.new()
	add_child(fx)
	fx.setup(sim.weather, env, sun)
	fx.follow = camera
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	overlay = Label.new()
	overlay.add_theme_font_size_override("font_size", 18)
	overlay.add_theme_font_override("font", SystemFont.new())
	(overlay.get_theme_font("font") as SystemFont).font_names = PackedStringArray(["Menlo", "Monaco", "monospace"])
	panel.add_child(overlay)


## The countryside course world: baked from course.gd by tools/bake_world.gd, plus the
## hand-placed landmarks in decor.tscn. Returns false (and quits with an error) if it is broken.
func _load_countryside_world() -> bool:
	var world: Node3D = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(world)
	if ResourceLoader.exists(DECOR_SCENE):
		add_child((load(DECOR_SCENE) as PackedScene).instantiate())
	var terrain := world.get_node_or_null("Terrain")
	if terrain == null:
		push_error("%s has no Terrain node; re-run tools/bake_world.gd" % WORLD_SCENE)
		get_tree().quit(1)
		return false
	terrain.call("set_camera", camera)
	return true


# ---------------------------------------------------------------- sim loop (60 Hz)

func _physics_process(_delta: float) -> void:
	var free_slots := int(config["maxConcurrentRuns"]) - sim.active_count()
	for msg in net.poll(1.0 / float(Protocol.SIM_TICK_HZ), free_slots):
		_handle(msg)
	sim.step()
	for m in sim.outbox:
		_outgoing(m["type"], m["payload"])
	sim.outbox.clear()


func _handle(msg: Dictionary) -> void:
	var pl = msg["payload"]  # Dictionary, or a bare Array for roster.updated
	match msg["type"]:
		Messages.RUN_START:
			var v  # server: KitRacerView from the player's RacerSpec; mock: placeholder RacerView
			if assets != null:
				var spec: Dictionary = assets.spec_for(pl["playerId"])
				if spec.is_empty():
					# No fallback racer: say so loudly and don't race a stand-in.
					var err := "ERROR run %s: no RacerSpec for player %s (%s) in the roster" % [pl["runId"], pl["playerId"], nicks.get(pl["playerId"], "?")]
					push_error(err)
					_result(err)
					return
				var checked: Dictionary = RacerSpec.validate(spec)
				if not (checked["errors"] as PackedStringArray).is_empty():
					var err := "ERROR run %s: invalid RacerSpec for %s: %s" % [pl["runId"], nicks.get(pl["playerId"], "?"), "; ".join(checked["errors"])]
					push_error(err)
					_result(err.left(160))
					return
				var r: Racer = sim.add_run(pl["runId"], pl["playerId"], pl["build"])
				v = KitRacerView.new()
				add_child(v)
				v.setup(r, spec, assets.drawing_for(pl["playerId"]), nicks.get(pl["playerId"], "?"))
			else:
				var r: Racer = sim.add_run(pl["runId"], pl["playerId"], pl["build"])
				v = RacerView.new()
				add_child(v)
				v.setup(r, colors.get(pl["playerId"], Color.WHITE), nicks.get(pl["playerId"], "?"))
			views[pl["runId"]] = v
			net.remember_run(pl["runId"], nicks.get(pl["playerId"], "?"))
		Messages.RUN_BOOST:
			sim.boost(pl["runId"])
		Messages.RUN_ABORT:
			sim.abort(pl["runId"])
		Messages.ROSTER_UPDATED:
			_on_roster(pl)


## Server roster: names and colours for racers, and their kit assets (spec, drawing, renders).
func _on_roster(roster: Array) -> void:
	for e in roster:
		var pid: String = e["playerId"]
		nicks[pid] = e["nickname"]
		if not colors.has(pid):
			colors[pid] = Color.from_hsv(float(absi(hash(pid)) % 360) / 360.0, 0.75, 0.95)
	if assets != null:
		assets.update(roster)


func _on_racer_ready(player_id: String) -> void:
	var title: String = assets.spec_for(player_id).get("title", "")
	_result("NEW  %s · %s" % [assets.nickname(player_id), title])


func _outgoing(type: String, pl: Dictionary) -> void:
	match type:
		"sim.boost", "sim.bump":
			return
		"sim.removed":
			var v: Node = views.get(pl["runId"])
			if v != null:
				v.queue_free()
				views.erase(pl["runId"])
			if pl["outcome"] == "aborted":
				net.run_gone(pl["runId"])
			if follow_run == pl["runId"]:
				follow_run = ""
			return
		Messages.GAME_RUN_FINISHED:
			_result("%-6s %6.2f s" % [_nick_of(pl["runId"]), int(pl["elapsedMs"]) / 1000.0])
		Messages.GAME_RUN_FAILED:
			_result("%-6s FAIL %s @%s" % [_nick_of(pl["runId"]), pl["reason"], pl["section"]])
	net.send(type, pl)


func _nick_of(run_id: String) -> String:
	var v = views.get(run_id)
	return v.nickname if v != null else "?"


func _result(line: String) -> void:
	results.push_front(line)
	if results.size() > 8:
		results.resize(8)


# ---------------------------------------------------------------- presentation

func _process(delta: float) -> void:
	run_time += delta
	var racing: Array = sim.racers.duplicate()
	racing.sort_custom(func(a, b): return a.progress() > b.progress())
	if follow_run == "" or not views.has(follow_run):
		follow_run = racing[0].run_id if not racing.is_empty() else ""
	camera.target = views.get(follow_run)
	camera.targets = views.values()
	for v in views.values():
		v.sync()
	_update_overlay(racing)
	var dur := float(args.get("duration", "0"))
	if args.has("screenshot") and not shot_taken and run_time >= float(args.get("shot-at", str(dur - 0.5 if dur > 1 else 12.0))):
		shot_taken = true
		_screenshot(args["screenshot"])
	if dur > 0.0 and run_time >= dur:
		_quit()


func _update_overlay(racing: Array) -> void:
	if overlay == null or not overlay.is_visible_in_tree():
		return
	var w := sim.weather
	var lines: PackedStringArray = []
	var mode := "MOCK" if assets == null else "SERVER %s · %d racers" % [net.status, assets.entries.size()]
	lines.append("BebbiKart · %s · t %5.1f s · tick %d" % [mode, sim.tick / 60.0, sim.tick])
	lines.append("rain %-8s %.2f   wind %-8s %.2f → %d°%s" % [w.phase("rain"), w.rain_intensity(), w.phase("wind"),
		w.wind_strength(), int(w.wind["dir_deg"]), "  (forced)" if w.forced else ""])
	lines.append("racing %d · queued %d · done %d · failed %d" % [sim.racers.size(), sim.queue.size(), net.finished, net.failed])
	lines.append("")
	for i in mini(10, racing.size()):
		var r: Racer = racing[i]
		var mark := "▶" if r.run_id == follow_run else " "
		lines.append("%s%-6s %-8s %5.1f s  %3d%%  %4.1f m/s  ⚡%d%s" % [mark, _nick_of(r.run_id), r.section,
			r.elapsed_ms() / 1000.0, int(r.progress() * 100), r.v, r.boosts_left, "  BOOST" if r.boost_t > 0 else ""])
	if not results.is_empty():
		lines.append("")
		lines.append("recent:")
		for l in results:
			lines.append("  " + l)
	lines.append("")
	lines.append("C cam  Tab racer  F fork  R rain  W wind  K calm  B boost  H hide")
	overlay.text = "\n".join(lines)


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match (e as InputEventKey).keycode:
		KEY_C:
			camera.cycle_mode()
		KEY_F:
			camera.mode = CameraRig.Mode.FORKS
			camera.fork_idx += 1
		KEY_TAB:
			var ids: Array = views.keys()
			if not ids.is_empty():
				follow_run = ids[(ids.find(follow_run) + 1) % ids.size()]
		KEY_R:
			sim.weather.advance("rain")
		KEY_W:
			sim.weather.advance("wind")
		KEY_K:
			forced_calm = not forced_calm
			if forced_calm:
				sim.weather.force(0.0, 0.0)
			else:
				sim.weather.forced = false
		KEY_B:
			if follow_run != "":
				sim.boost(follow_run)
		KEY_H:
			overlay.get_parent().visible = not overlay.get_parent().visible


func _screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("screenshot: no image (headless?)")
		return
	img.save_png(path)
	print("screenshot saved to ", path)


func _quit() -> void:
	set_process(false)
	set_physics_process(false)
	print("mock summary: %.1f s wall, %d sim ticks, finished %d, failed %d, sent %s" % [
		run_time, sim.tick, net.finished, net.failed, JSON.stringify(net.sent_counts)])
	if args.has("screenshot") and not shot_taken:
		shot_taken = true
		await _screenshot(args["screenshot"])
	get_tree().quit()
