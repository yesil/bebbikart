# BebbiKart game (WS3a/3b): grey-box course + 60 Hz driving sim, running in mock mode.
#   godot --path apps/game                      windowed, 20 mock racers
#   godot --path apps/game -- --racers=12 --seed=4 --weather=storm --duration=60
#   godot --headless --path apps/game -- --duration=30 --log=full
# Real server (phones race on the big screen):
#   godot --path apps/game -- --server                     ws://localhost:8080/ws, key "bebbikart-dev"
#   godot --path apps/game -- --server=ws://host:8080/ws --game-key=KEY   (or env BK_GAME_KEY)
# Options (after --): --mock (default), --server[=URL], --game-key=KEY, --racers=N, --seed=N,
#   --weather=calm|rain|wind|storm (forced), --duration=SEC (quit after), --speed=X,
#   --track=countryside|village (mock mode; with --server the session config picks the track),
#   --screenshot=path.png [--shot-at=SEC] [--cam=follow|wide|forks], --log=none|summary|full,
#   --kit (mock mode: fake racers built with the racer kit from res://racer_kit/samples, in turn),
#   --cam-cycle=SEC (switch racer every SEC s, 0 = never; default: options menu pick, else 8),
#   --inset=face|side|off (second camera; default: options menu pick, else face),
#   --quality=low|medium|high (default: last pick in the options menu, else medium),
#   --language=en|de (default: last pick in the options menu, else config.language; server mode
#   sends it to the server so every phone follows it)
# Keys: C camera mode, Tab / Shift+Tab next / previous racer, A automatic racer switching on/off,
#   V second camera (face / side / off), F next fork shot, R/W start next rain/wind phase,
#   K toggle forced calm, B boost the followed racer, H hide overlay,
#   Esc or ⌘, options menu (fullscreen, language, track, quit), ⌃⌘F or F11 fullscreen, ⌘Q quit.
extends Node3D

const Course = preload("res://sim/course.gd")
const VillageCourse = preload("res://sim/village_course.gd")
const VILLAGE_WORLD_SCENE := "res://world/village/village_world.tscn"
const VILLAGE_DECOR_SCENE := "res://world/village/village_decor.tscn"
const Sim = preload("res://sim/sim.gd")
const Racer = preload("res://sim/racer.gd")
const Messages = preload("res://net/messages.gd")
const MockNet = preload("res://net/mock_net.gd")
const ServerNet = preload("res://net/server_net.gd")
const RosterAssets = preload("res://net/roster_assets.gd")
const KitRacerView = preload("res://racer_kit/kit_racer_view.gd")
const WORLD_SCENE := "res://world/course_world.tscn"
const DECOR_SCENE := "res://world/decor.tscn"
const LIGHTING_SCENE := "res://world/environment.tscn"
const Viewpoints = preload("res://world/viewpoints.gd")
const RacerView = preload("res://world/racer_view.gd")
const WeatherFx = preload("res://world/weather_fx.gd")
const CameraRig = preload("res://world/camera_rig.gd")
const CameraDirector = preload("res://world/camera_director.gd")
const CameraHud = preload("res://ui/camera_hud.gd")
const OptionsMenu = preload("res://ui/options_menu.gd")
const I18n = preload("res://ui/i18n.gd")
const AudioDirector = preload("res://audio/audio_director.gd")

## Graphics presets (options menu, --quality=low|medium|high). render_height caps the 3D
## resolution (0 = native; upscaled with MetalFX on Metal, FSR elsewhere), so a fullscreen 5K
## Retina window does not render 15 M pixels a frame; veg scales the vegetation visibility ranges.
const QUALITY := {
	"low": {"render_height": 720, "shadow_atlas": 2048, "soft_shadows": 0, "shadow_distance": 70.0, "ssao": false, "glow": false, "veg": 0.5},
	"medium": {"render_height": 1080, "shadow_atlas": 4096, "soft_shadows": 1, "shadow_distance": 120.0, "ssao": false, "glow": true, "veg": 0.75},
	"high": {"render_height": 0, "shadow_atlas": 8192, "soft_shadows": 3, "shadow_distance": 170.0, "ssao": true, "glow": true, "veg": 1.0},
}
const DEFAULT_QUALITY := "medium"
const SETTINGS_PATH := "user://settings.cfg"
const FPS_CAP := 60          # also caps 120 Hz ProMotion displays
const FPS_UNFOCUSED := 30    # window in the background: still smooth enough for a big screen

const FORCED := {"calm": [0.0, 0.0], "rain": [1.0, 0.0], "wind": [0.0, 0.8], "storm": [1.0, 0.8]}

var args := {}
var course                 # sim/course.gd or sim/village_course.gd (loop)
var track := ""            # TrackId of the loaded course and world
## Track to load after a reload (config.track changed while the game was running).
static var next_track := ""
## The "Options…" item is added to the macOS app menu once; it outlives scene reloads.
static var native_menu_added := false
static var native_menu_idx := -1
var config: Dictionary
var sim: Sim
var net                    # net/mock_net.gd or net/server_net.gd (same interface)
var assets = null          # net/roster_assets.gd, server mode only
var views := {}            # runId -> RacerView
var colors := {}           # playerId -> Color
var nicks := {}            # playerId -> nickname
var making := {}           # playerId -> design stage last shown (roster stage)
var results: Array = []    # recent finished/failed lines
var camera: CameraRig
var kit_specs: Array = []      # --kit: sample RacerSpecs for the fake racers
var director: CameraDirector   # which racer the camera follows, and when it switches
var cam_hud: CameraHud         # on-camera name, cut pop, picture-in-picture second camera
var fx: WeatherFx
var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var overlay: Label
var follow_run := ""
var run_time := 0.0
var shot_taken := false
var next_shot := 0.0       # --shots=DIR: time of the next periodic screenshot
var forced_calm := false
var menu: OptionsMenu
var quitting := false
var quality := ""
var audio: AudioDirector
## Language sent to the server and not yet echoed in config.updated (other updates are stale).
var language_sent := ""


func _ready() -> void:
	# Window close and the app menu's Quit (⌘Q) go through _quit so the run summary prints.
	get_tree().auto_accept_quit = false
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
	# Big-screen language: --language, else the last pick in the options menu, else the default.
	var lang_err := I18n.set_language(String(config["language"]))
	if lang_err == "":
		lang_err = I18n.set_language(String(args.get("language", _saved_setting("ui", "language", config["language"]))))
	if lang_err != "":
		push_error("language: " + lang_err)
		get_tree().quit(1)
		return
	print("language: ", I18n.language)
	track = next_track if next_track != "" else String(args.get("track", config["track"]))
	config["track"] = track
	course = _make_course(track)
	if course == null:
		return
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
		assets.problem.connect(func(text: String): _result(I18n.f("log.error", [text])))
		print("BebbiKart server mode: %s (protocol v%d)" % [url, Protocol.PROTOCOL_VERSION])
	else:
		if args.has("kit") and not _load_kit_samples():
			return
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
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_light_color = Color(0.6, 0.63, 0.7)
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-140), 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)
	camera = CameraRig.new()
	add_child(camera)
	camera.make_current()
	if not (_load_village_world() if track == "village" else _load_countryside_world()):
		return
	camera.mode = {"follow": CameraRig.Mode.FOLLOW, "wide": CameraRig.Mode.WIDE, "forks": CameraRig.Mode.FORKS}.get(args.get("cam", "follow"), CameraRig.Mode.FOLLOW)
	if track == "village":
		camera.fork_shots = _village_fork_shots()
	else:
		camera.fork_shots = Viewpoints.fork_shots(course)  # one shot per fork split
	if not _setup_camera_director():
		return
	fx = WeatherFx.new()
	add_child(fx)
	fx.setup(sim.weather, env, sun)
	fx.follow = camera
	audio = AudioDirector.new()
	audio.sound_of = func(pid: String) -> Dictionary:
		return assets.spec_for(pid).get("sound", {}) if assets != null else net.sound_of(pid)
	add_child(audio)
	if not audio.setup(sim, track, camera, args.has("mute")):
		_result(I18n.t("log.audio_failed"))
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
	_make_menu()
	_add_native_menu()
	var q: String = args.get("quality", _saved_setting("graphics", "quality", DEFAULT_QUALITY))
	if not QUALITY.has(q):
		push_error("unknown quality \"%s\" (known: %s)" % [q, ", ".join(QUALITY.keys())])
		get_tree().quit(1)
		return
	apply_quality(q)
	get_viewport().size_changed.connect(_apply_render_scale)
	Engine.max_fps = FPS_CAP


## The options menu, (re)built in the current language.
func _make_menu() -> void:
	if menu != null:
		menu.queue_free()
	menu = OptionsMenu.new()
	add_child(menu)
	menu.setup(track, assets != null)
	menu.fullscreen_toggled.connect(_toggle_fullscreen)
	menu.track_chosen.connect(_switch_track)
	menu.quit_pressed.connect(_quit)
	menu.quality_chosen.connect(func(id: String): apply_quality(id); _save_setting("graphics", "quality", id))
	menu.language_chosen.connect(_choose_language)
	menu.cam_cycle_chosen.connect(_choose_cam_cycle)
	menu.inset_chosen.connect(_choose_inset)
	if quality != "":
		menu.set_quality(quality)
	if director != null:
		menu.set_camera(director.cycle_s, cam_hud.inset)
	if assets != null:
		menu.set_session(net.session_status)


## --kit: every sample RacerSpec in res://racer_kit/samples, validated. False (and quits with the
## reasons) if there are none or one is broken: no stand-in racers.
func _load_kit_samples() -> bool:
	var problems: PackedStringArray = []
	for path in SpecFolders.list(SpecFolders.SAMPLES):
		var spec = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(spec) != TYPE_DICTIONARY:
			problems.append("%s is not a JSON object" % path)
			continue
		var errs: PackedStringArray = RacerSpec.validate(spec)["errors"]
		if not errs.is_empty():
			problems.append("%s: %s" % [path, "; ".join(errs)])
			continue
		kit_specs.append(spec)
	if kit_specs.is_empty():
		problems.append("no sample specs in " + SpecFolders.SAMPLES)
	if not problems.is_empty():
		push_error("--kit: " + " | ".join(problems))
		get_tree().quit(1)
		return false
	print("--kit: %d sample racers" % kit_specs.size())
	return true


## The camera director (which racer the camera follows and how often it switches) and the camera
## HUD with the second camera. --cam-cycle / --inset win over the options menu's saved picks.
## Returns false (and quits with an error) on a bad value.
func _setup_camera_director() -> bool:
	director = CameraDirector.new()
	var cycle := str(args.get("cam-cycle", _saved_setting("camera", "cycle_s", CameraDirector.DEFAULT_CYCLE_S)))
	if not cycle.is_valid_float() or float(cycle) < 0.0:
		push_error("camera: --cam-cycle must be seconds >= 0 (0 = never switch), not \"%s\"" % cycle)
		get_tree().quit(1)
		return false
	director.cycle_s = float(cycle)
	cam_hud = CameraHud.new()
	add_child(cam_hud)
	var inset := str(args.get("inset", _saved_setting("camera", "inset", "face")))
	if not cam_hud.set_inset(inset):
		get_tree().quit(1)
		return false
	print("camera: switch racer every %s, second camera %s" % [
		("%.0f s" % director.cycle_s) if director.cycle_s > 0.0 else "never", inset])
	return true


## Options menu: how often the camera switches racer (0 = never).
func _choose_cam_cycle(seconds: float) -> void:
	director.cycle_s = seconds
	_save_setting("camera", "cycle_s", seconds)


## Options menu or V: the second camera (face / side / off).
func _choose_inset(id: String) -> void:
	if not cam_hud.set_inset(id):
		menu.show_error(I18n.f("log.error", ["inset " + id]))
		return
	_save_setting("camera", "inset", id)
	menu.set_camera(director.cycle_s, id)


## A setting from user://settings.cfg (the options menu's picks), or `default` if never saved.
func _saved_setting(section: String, key: String, default: Variant) -> Variant:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err == ERR_FILE_NOT_FOUND:
		return default
	if err != OK:
		push_error("could not read %s (%s); using the default %s" % [SETTINGS_PATH, error_string(err), key])
		_result(I18n.f("log.settings_unreadable", [error_string(err)]))
		return default
	return cfg.get_value(section, key, default)


func _save_setting(section: String, key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(section, key, value)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_error("could not save %s: %s" % [SETTINGS_PATH, error_string(err)])
		menu.show_error(I18n.f("error.save_setting", [error_string(err)]))


## Language picked in the options menu: the big screen switches now; in server mode the server
## gets it too, and every phone follows (config.updated).
func _choose_language(id: String) -> void:
	if not _apply_language(id):
		return
	_save_setting("ui", "language", id)
	if assets == null:
		return
	if net.status != "online":
		# The welcome after the reconnect sends it (see _handle).
		push_error("language: server is %s; phones switch once it reconnects" % net.status)
		menu.show_error(I18n.f("error.offline_language", [I18n.t("net." + net.status)]))
		return
	language_sent = id
	net.send("game.config.set", {"language": id})


## Switches every big-screen string to `id` and rebuilds the menu. False (shown) if it can't.
func _apply_language(id: String) -> bool:
	var err := I18n.set_language(id)
	if err != "":
		_result(I18n.f("log.error", [err]))
		menu.show_error(err)
		return false
	print("language: ", id)
	var was_open := menu.is_open()
	_make_menu()
	if native_menu_idx >= 0:
		NativeMenu.set_item_text(NativeMenu.get_system_menu(NativeMenu.APPLICATION_MENU_ID), native_menu_idx, I18n.t("menu.native_item"))
	if was_open:
		open_menu()
	return true


## Applies a QUALITY preset to the viewport, sun, environment and vegetation.
func apply_quality(id: String) -> void:
	var q: Dictionary = QUALITY[id]
	quality = id
	_apply_render_scale()
	RenderingServer.directional_shadow_atlas_set_size(q["shadow_atlas"], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(q["soft_shadows"])
	sun.directional_shadow_max_distance = q["shadow_distance"]
	env.ssao_enabled = q["ssao"]
	env.glow_enabled = q["glow"]
	_scale_visibility(self, q["veg"])
	menu.set_quality(id)


## 3D resolution for the current quality and window size; re-run whenever the window resizes.
func _apply_render_scale() -> void:
	var vp := get_viewport()
	var h := float(get_window().size.y)  # pixels; the visible rect is in stretched 2D units
	var cap := float(QUALITY[quality]["render_height"])
	var k := 1.0 if cap <= 0.0 or h <= cap else cap / h
	vp.scaling_3d_scale = k
	var metal := RenderingServer.get_current_rendering_driver_name() == "metal"
	if k >= 1.0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_SPATIAL if metal else Viewport.SCALING_3D_MODE_FSR
	print("graphics quality: %s, window %dpx tall, 3D at %d%% (%s)" % [quality, int(h), int(k * 100),
		"native" if k >= 1.0 else "MetalFX" if metal else "FSR"])


## Scales every authored visibility_range_end (vegetation, props) by k from its original value.
func _scale_visibility(n: Node, k: float) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		if not g.has_meta("vis_end"):
			g.set_meta("vis_end", g.visibility_range_end)
		var end: float = g.get_meta("vis_end")
		if end > 0.0:
			g.visibility_range_end = end * k
	for c in n.get_children():
		_scale_visibility(c, k)


## macOS: put "Options…  ⌘," in the application menu, next to Quit.
static func _add_native_menu() -> void:
	if native_menu_added or not NativeMenu.has_feature(NativeMenu.FEATURE_GLOBAL_MENU):
		return
	native_menu_added = true
	var app_menu := NativeMenu.get_system_menu(NativeMenu.APPLICATION_MENU_ID)
	native_menu_idx = NativeMenu.add_item(app_menu, I18n.t("menu.native_item"), _open_options_from_menu, Callable(), null, KEY_MASK_META | KEY_COMMA)


static func _open_options_from_menu(_tag) -> void:
	var main = (Engine.get_main_loop() as SceneTree).current_scene
	if main == null or main.get("menu") == null:
		push_error("Options menu: no running game scene to open it in")
		return
	main.open_menu()


func open_menu() -> void:
	if assets != null:
		menu.set_session(net.session_status)  # the welcome may have arrived after setup
	menu.open()


## Track picked in the options menu. Mock mode reloads on it. Server mode asks the server
## (the game manager owns the options): a running session is ended, the track set and a new
## session started; config.updated then reloads the course via _check_track once it is empty.
func _switch_track(id: String) -> void:
	if not Protocol.TRACK_IDS.has(id):
		push_error("track switch: unknown track \"%s\"" % id)
		menu.show_error(I18n.f("error.unknown_track", [id]))
		return
	if assets == null:
		print("track change (options menu): %s -> %s, reloading" % [track, id])
		next_track = id
		get_tree().reload_current_scene()
		return
	if net.status != "online":
		push_error("track switch: server is %s" % net.status)
		menu.show_error(I18n.f("error.offline_track", [I18n.t("net." + net.status)]))
		return
	print("track change (options menu): asking the server for %s (session %s)" % [id, net.session_status])
	if net.session_status == "running":
		net.send("game.session.end", {})
	net.send("game.config.set", {"track": id})
	# Idle or ended (BK_AUTOSTART=0 leaves it ended): start one so players can race on it.
	net.send("game.session.start", {})


## The countryside course world: baked from course.gd by tools/bake_world.gd, plus the
## hand-placed landmarks in decor.tscn. Returns false (and quits with an error) if it is broken.
func _load_countryside_world() -> bool:
	for path in [WORLD_SCENE, DECOR_SCENE, LIGHTING_SCENE]:
		if not ResourceLoader.exists(path):
			push_error("countryside world: %s is missing (see apps/game/README.md, World pipeline)" % path)
			get_tree().quit(1)
			return false
	var world: Node3D = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(world)
	add_child((load(DECOR_SCENE) as PackedScene).instantiate())
	# The countryside sky, sun and post-processing replace the default ones.
	var lighting: Node = (load(LIGHTING_SCENE) as PackedScene).instantiate()
	var we: WorldEnvironment = lighting.get_node_or_null("WorldEnvironment")
	var lit_sun: DirectionalLight3D = lighting.get_node_or_null("Sun")
	if we == null or lit_sun == null:
		push_error("%s needs WorldEnvironment and Sun nodes" % LIGHTING_SCENE)
		get_tree().quit(1)
		return false
	world_env.queue_free()
	sun.queue_free()
	add_child(lighting)
	world_env = we
	env = we.environment
	sun = lit_sun
	var terrain := world.get_node_or_null("Terrain")
	if terrain == null:
		push_error("%s has no Terrain node; re-run tools/bake_world.gd" % WORLD_SCENE)
		get_tree().quit(1)
		return false
	terrain.call("set_camera", camera)
	return true


## Course for a TrackId, or null after reporting an unknown track and quitting.
func _make_course(id: String):
	match id:
		"countryside":
			return Course.new()
		"village":
			var c := VillageCourse.new()
			if not c.errors.is_empty():
				push_error("village course is broken: %s" % "; ".join(c.errors))
				get_tree().quit(1)
				return null
			return c
	push_error("unknown track \"%s\" (known: %s)" % [id, ", ".join(Protocol.TRACK_IDS)])
	get_tree().quit(1)
	return null


## The Swiss village loop: baked from sim/village_course.gd + world/village/village_plan.gd by
## tools/bake_village.gd, plus the hand-placed village_decor.tscn. Returns false (and quits
## with an error) if it is missing or broken.
func _load_village_world() -> bool:
	if not ResourceLoader.exists(VILLAGE_WORLD_SCENE):
		push_error("%s is missing; run tools/bake_village.gd" % VILLAGE_WORLD_SCENE)
		get_tree().quit(1)
		return false
	var world: Node3D = (load(VILLAGE_WORLD_SCENE) as PackedScene).instantiate()
	add_child(world)
	if ResourceLoader.exists(VILLAGE_DECOR_SCENE):
		add_child((load(VILLAGE_DECOR_SCENE) as PackedScene).instantiate())
	var terrain := world.get_node_or_null("Terrain")
	if terrain == null:
		push_error("%s has no Terrain node; re-run tools/bake_village.gd" % VILLAGE_WORLD_SCENE)
		get_tree().quit(1)
		return false
	terrain.call("set_camera", camera)
	return true


## A shot of each village fork from just before its split, looking down both branches.
func _village_fork_shots() -> Array:
	var shots: Array = []
	for pair in [["ramp_jump", "ramp_around"], ["pond_water", "pond_bridge"], ["cross_exposed", "cross_sheltered"]]:
		var a = course.segments[pair[0]]["route"]
		var b = course.segments[pair[1]]["route"]
		var mid: Vector3 = (a.pos_at(a.length * 0.5) + b.pos_at(b.length * 0.5)) * 0.5
		var back: Vector3 = a.pos_at(0.0) - a.tangent_at(0.0) * 14.0
		shots.append([back + Vector3(0, 12, 0), mid])
	return shots


## The server's session config picked another track: reload once the course is empty.
func _check_track() -> void:
	if String(config["track"]) == track or sim.active_count() > 0:
		return
	if not Protocol.TRACK_IDS.has(String(config["track"])):
		push_error("config.track \"%s\" is not a known track" % config["track"])
		_result(I18n.f("log.unknown_track", [config["track"]]))
		config["track"] = track
		return
	print("track change: %s -> %s, reloading" % [track, config["track"]])
	next_track = String(config["track"])
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- sim loop (60 Hz)

func _physics_process(_delta: float) -> void:
	var free_slots := int(config["maxConcurrentRuns"]) - sim.active_count()
	for msg in net.poll(1.0 / float(Protocol.SIM_TICK_HZ), free_slots):
		_handle(msg)
	_check_track()
	sim.step()
	for m in sim.outbox:
		if audio != null:
			audio.on_event(m["type"], m["payload"])
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
					var err := I18n.f("log.no_spec", [pl["runId"], pl["playerId"], nicks.get(pl["playerId"], "?")])
					push_error(err)
					_result(err)
					return
				var checked: Dictionary = RacerSpec.validate(spec)
				if not (checked["errors"] as PackedStringArray).is_empty():
					var err := I18n.f("log.invalid_spec", [pl["runId"], nicks.get(pl["playerId"], "?"), "; ".join(checked["errors"])])
					push_error(err)
					_result(err.left(160))
					return
				var r: Racer = sim.add_run(pl["runId"], pl["playerId"], pl["build"])
				v = KitRacerView.new()
				add_child(v)
				v.setup(r, spec, assets.drawing_for(pl["playerId"]), nicks.get(pl["playerId"], "?"))
			elif not kit_specs.is_empty():
				var r: Racer = sim.add_run(pl["runId"], pl["playerId"], pl["build"])
				var i: int = net.players.map(func(p): return p["playerId"]).find(pl["playerId"])
				v = KitRacerView.new()
				add_child(v)
				v.setup(r, kit_specs[maxi(i, 0) % kit_specs.size()], null, nicks.get(pl["playerId"], "?"))
			else:
				var r: Racer = sim.add_run(pl["runId"], pl["playerId"], pl["build"])
				v = RacerView.new()
				add_child(v)
				v.setup(r, colors.get(pl["playerId"], Color.WHITE), nicks.get(pl["playerId"], "?"))
			views[pl["runId"]] = v
			net.remember_run(pl["runId"], nicks.get(pl["playerId"], "?"))
		Messages.RUN_BOOST:
			sim.boost(pl["runId"])
		Messages.RUN_STOP:
			sim.stop(pl["runId"])
		Messages.RUN_ABORT:
			sim.abort(pl["runId"])
		Messages.RUN_WATCH:
			# A phone's "Show me on the big screen": its racer gets one of the next cuts.
			var wr: Racer = sim.by_run.get(pl["runId"])
			if wr != null and wr.state == "racing" and director.request(pl["runId"]):
				_result(I18n.f("log.watch", [nicks.get(wr.player_id, "?")]))
		Messages.ROSTER_UPDATED:
			_on_roster(pl)
		"session.updated":
			menu.set_session(String(pl.get("status", "?")))
		Messages.WELCOME:
			# The big screen's language wins: a fresh server (or one an admin changed) gets ours.
			var server_lang := String(pl.get("config", {}).get("language", ""))
			if server_lang != I18n.language:
				print("language: server has %s, the big screen %s; sending it" % [server_lang, I18n.language])
				language_sent = I18n.language
				net.send("game.config.set", {"language": I18n.language})
		"config.updated":
			var lang := String(pl.get("language", ""))
			if language_sent != "":
				if lang == language_sent:
					language_sent = ""
				return  # an update from before ours
			if lang != I18n.language:
				print("language: the server switched to %s" % lang)
				if _apply_language(lang):
					_save_setting("ui", "language", lang)
		"error":
			# Refusals of what the game sent, e.g. track_locked for a track change.
			language_sent = ""
			var err := I18n.f("log.server_refused", [pl.get("code", "?"), pl.get("message", "")])
			_result(err)
			menu.show_error(I18n.f("error.server_refused", [pl.get("message", pl.get("code", "?"))]))


## Server roster: names and colours for racers, and their kit assets (spec, drawing, renders).
func _on_roster(roster: Array) -> void:
	# Racers missing from the new roster quit on their phone (or the admin removed them).
	var still := {}
	for e in roster:
		still[String(e["playerId"])] = true
	for pid in nicks.keys():
		if not still.has(pid):
			_result(I18n.f("log.left", [nicks[pid]]))
			nicks.erase(pid)
			making.erase(pid)
	# Racers being made: one line per design step (looking, designing, critiquing, refining).
	for e in roster:
		var mpid := String(e["playerId"])
		var stage := String(e.get("stage", ""))
		if stage != "" and making.get(mpid, "") != stage:
			_result(I18n.f("log.making", [e["nickname"], I18n.t("making." + stage)]))
		making[mpid] = stage
	for e in roster:
		var pid: String = e["playerId"]
		nicks[pid] = e["nickname"]
		if not colors.has(pid):
			colors[pid] = Color.from_hsv(float(absi(hash(pid)) % 360) / 360.0, 0.75, 0.95)
	if assets != null:
		assets.update(roster)


func _on_racer_ready(player_id: String) -> void:
	var title: String = assets.spec_for(player_id).get("title", "")
	_result(I18n.f("log.new", [assets.nickname(player_id), title]))


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
			return  # the camera director moves on from a racer that left on its next update
		Messages.GAME_RUN_FINISHED:
			if pl.has("bestLapMs"):
				_result(I18n.f("log.finished_laps", [_nick_of(pl["runId"]), int(pl["bestLapMs"]) / 1000.0, (pl["laps"] as Array).size()]))
			else:
				_result(I18n.f("log.finished", [_nick_of(pl["runId"]), int(pl["elapsedMs"]) / 1000.0]))
		Messages.GAME_RUN_LAP:
			_result(I18n.f("log.lap", [_nick_of(pl["runId"]), pl["lap"], int(pl["lapMs"]) / 1000.0, " *" if pl["isBest"] else ""]))
		Messages.GAME_RUN_FAILED:
			_result(I18n.f("log.failed", [_nick_of(pl["runId"]), I18n.t("fail." + String(pl["reason"])), I18n.t("section." + String(pl["section"]))]))
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
	# On a loop, laps first, then position in the lap.
	racing.sort_custom(func(a, b): return a.lap + a.progress() > b.lap + b.progress())
	director.update(delta, sim.racers)
	if director.run_id != follow_run:
		follow_run = director.run_id
		_camera_cut()
	camera.target = views.get(follow_run)
	audio.follow_run = follow_run
	camera.targets = views.values()
	for v in views.values():
		v.sync()
	_update_camera_hud()
	_update_overlay(racing)
	var dur := float(args.get("duration", "0"))
	if args.has("screenshot") and not shot_taken and run_time >= float(args.get("shot-at", str(dur - 0.5 if dur > 1 else 12.0))):
		shot_taken = true
		_screenshot(args["screenshot"])
	# --shots=DIR [--shot-every=SEC]: a screenshot every few seconds while racers are on the
	# track (multiplayer harness: start grid, mid-race, finish), named by time and racer count.
	if args.has("shots") and run_time >= next_shot and not sim.racers.is_empty():
		next_shot = run_time + float(args.get("shot-every", "2"))
		_screenshot("%s/t%05.1f_r%d.jpg" % [args["shots"], run_time, sim.racers.size()])
	if dur > 0.0 and run_time >= dur:
		_quit()


## The director cut to another racer (or to nobody): their name pops up, and the server hears
## who is on camera so that racer's phone can say so (game.camera → camera.updated).
func _camera_cut() -> void:
	if follow_run != "" and camera.mode == CameraRig.Mode.FOLLOW:
		cam_hud.pop(_nick_of(follow_run), _color_of(follow_run), director.reason == "phone")
	net.send(Messages.GAME_CAMERA, {"runId": follow_run} if follow_run != "" else {})


func _update_camera_hud() -> void:
	var left := director.next_in()
	cam_hud.show_racer(views.get(follow_run), _nick_of(follow_run), _color_of(follow_run),
		camera.mode == CameraRig.Mode.FOLLOW, left / director.cycle_s if left >= 0.0 else -1.0, not director.auto)


func _color_of(run_id: String) -> Color:
	var r: Racer = sim.by_run.get(run_id)
	return colors.get(r.player_id, Color.WHITE) if r != null else Color.WHITE


func _update_overlay(racing: Array) -> void:
	if overlay == null or not overlay.is_visible_in_tree():
		return
	var w := sim.weather
	var lines: PackedStringArray = []
	var mode := I18n.t("overlay.mock") if assets == null else I18n.f("overlay.server", [I18n.t("net." + net.status), assets.entries.size()])
	lines.append("BebbiKart · %s · %s · t %5.1f s · tick %d" % [mode, I18n.t("track." + track), sim.tick / 60.0, sim.tick])
	lines.append(I18n.f("overlay.weather", [I18n.t("weather." + w.phase("rain")), w.rain_intensity(), I18n.t("weather." + w.phase("wind")),
		w.wind_strength(), int(w.wind["dir_deg"]), I18n.t("overlay.forced") if w.forced else ""]))
	lines.append(I18n.f("overlay.counts", [sim.racers.size(), sim.queue.size(), net.finished, net.failed]))
	lines.append("")
	for i in mini(10, racing.size()):
		var r: Racer = racing[i]
		var mark := "▶" if r.run_id == follow_run else " "
		var timing := "%5.1f s" % (r.elapsed_ms() / 1000.0)
		if r.looping:
			timing = I18n.f("overlay.lap", [r.lap + 1, r.lap_ms() / 1000.0,
				I18n.f("overlay.best", [r.best_lap_ms() / 1000.0]) if r.best_lap >= 0 else ""])
		lines.append("%s%-6s %-8s %s  %3d%%  %4.1f m/s  ⚡%d%s%s" % [mark, _nick_of(r.run_id), I18n.t("section." + r.section), timing,
			int(r.progress() * 100), r.v, r.boosts_left, I18n.t("overlay.boost") if r.boost_t > 0 else "", I18n.t("overlay.pit") if r.pit_requested else ""])
	if not results.is_empty():
		lines.append("")
		lines.append(I18n.t("overlay.recent"))
		for l in results:
			lines.append("  " + l)
	lines.append("")
	lines.append(I18n.t("overlay.keys") + I18n.t("overlay.keys_mac" if OS.get_name() == "macOS" else "overlay.keys_other"))
	overlay.text = "\n".join(lines)


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	var k := e as InputEventKey
	# Window keys: Esc toggles the options menu, ⌘, opens it, ⌘Q quits;
	# F11 or Ctrl+Cmd+F (the macOS shortcut) toggles fullscreen.
	if k.keycode == KEY_ESCAPE:
		if menu.is_open():
			menu.close()
		else:
			open_menu()
		return
	if k.keycode == KEY_COMMA and k.meta_pressed:
		open_menu()
		return
	if k.keycode == KEY_Q and k.meta_pressed:
		_quit()
		return
	if k.keycode == KEY_F11 or (k.keycode == KEY_F and k.ctrl_pressed and k.meta_pressed):
		_toggle_fullscreen()
		return
	if menu.is_open():
		return  # game keys are off while the menu is up
	match k.keycode:
		KEY_C:
			camera.cycle_mode()
		KEY_F:
			camera.mode = CameraRig.Mode.FORKS
			camera.fork_idx += 1
		KEY_TAB:
			director.step(-1 if k.shift_pressed else 1, sim.racers)
		KEY_A:
			director.auto = not director.auto
		KEY_V:
			_choose_inset(cam_hud.cycle_inset())
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


func _toggle_fullscreen() -> void:
	var w := get_window()
	var full := w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	w.mode = Window.MODE_WINDOWED if full else Window.MODE_FULLSCREEN
	menu.sync_fullscreen()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			_quit()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			Engine.max_fps = FPS_UNFOCUSED
		NOTIFICATION_APPLICATION_FOCUS_IN:
			Engine.max_fps = FPS_CAP


func _screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("screenshot: no image (headless?)")
		return
	if path.ends_with(".jpg"):
		img.save_jpg(path, 0.85)
	else:
		img.save_png(path)
	print("screenshot saved to ", path)


func _quit() -> void:
	if quitting:
		return
	quitting = true
	if sim == null:  # startup failed and already reported; nothing to summarise
		get_tree().quit(1)
		return
	set_process(false)
	set_physics_process(false)
	print("mock summary: %.1f s wall, %d sim ticks, finished %d, failed %d, sent %s" % [
		run_time, sim.tick, net.finished, net.failed, JSON.stringify(net.sent_counts)])
	if args.has("screenshot") and not shot_taken:
		shot_taken = true
		await _screenshot(args["screenshot"])
	get_tree().quit()
