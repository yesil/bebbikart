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
#   --screenshot=path.png [--shot-at=SEC], --log=none|summary|full,
#   --kit (mock mode: fake racers built with the racer kit from res://racer_kit/samples, in turn),
#   --quality=low|medium|high (default: last pick in the options menu, else medium),
#   --language=en|de (default: last pick in the options menu, else config.language; server mode
#   sends it to the server so every phone follows it)
# One way to race (contracts §2i, king of the hill): the racers take turns from a line, one lap
# each against the clock, two at a time; the screen splits once two people play.
# Keys: R/W start next rain/wind phase, K toggle forced calm (these three only in debug runs,
#   not in the release build of `bun run play`),
#   H hide overlay, Esc or ⌘, options menu (fullscreen, language, track, session, quit),
#   ⌃⌘F or F11 fullscreen, ⌘Q quit.
extends Node3D

const Course = preload("res://sim/course.gd")
const VillageCourse = preload("res://sim/village_course.gd")
const VILLAGE_WORLD_SCENE := "res://world/village/village_world.tscn"
const VILLAGE_DECOR_SCENE := "res://world/village/village_decor.tscn"
const VILLAGE_LIGHTING_SCENE := "res://world/village/village_environment.tscn"
const Sim = preload("res://sim/sim.gd")
const Racer = preload("res://sim/racer.gd")
const Tuning = preload("res://sim/tuning.gd")
const Messages = preload("res://net/messages.gd")
const MockNet = preload("res://net/mock_net.gd")
const ServerNet = preload("res://net/server_net.gd")
const RosterAssets = preload("res://net/roster_assets.gd")
const KitRacerView = preload("res://racer_kit/kit_racer_view.gd")
const RaceReactions = preload("res://racer_kit/race_reactions.gd")
const WORLD_SCENE := "res://world/course_world.tscn"
const DECOR_SCENE := "res://world/decor.tscn"
const LIGHTING_SCENE := "res://world/environment.tscn"
const Viewpoints = preload("res://world/viewpoints.gd")
const RacerView = preload("res://world/racer_view.gd")
const ToyFootprint = preload("res://world/toy_footprint.gd")
const WeatherFx = preload("res://world/weather_fx.gd")
const CameraRig = preload("res://world/camera_rig.gd")
const CameraBlockers = preload("res://world/camera_blockers.gd")
const RaceHud = preload("res://ui/race_hud.gd")
const OptionsMenu = preload("res://ui/options_menu.gd")
const I18n = preload("res://ui/i18n.gd")
const AudioDirector = preload("res://audio/audio_director.gd")
const DuelScreen = preload("res://world/duel_screen.gd")
const DuelHud = preload("res://ui/duel_hud.gd")
const SteerMarks = preload("res://world/steer_marks.gd")

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
## Split screen draws the world twice (two cameras, two sets of shadow cascades), so the halves
## keep their shadows closer (in two cascades) and their vegetation a little shorter than the
## full-screen preset. Each half has half the pixels, so the screen's pixel count stays the same.
const SPLIT_SHADOW_M := 80.0
const FRONT_LOOK_S := 1.6     # a racer looks into its camera this long as the front shot starts
const SPLIT_VEG := 0.8

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
var leaving := {}          # runId -> KitRacerView still on screen after its run (finish cheer, crash slump)
var colors := {}           # playerId -> Color (the race HUD's distinct palette, in join order)
var nicks := {}            # playerId -> nickname
var making := {}           # playerId -> design stage last shown (roster stage)
var results: Array = []    # recent finished/failed lines
var camera: CameraRig
var kit_specs: Array = []      # --kit: sample RacerSpecs for the fake racers
var footprints := {}           # RacerSpec hash -> ToyFootprint result (the sim's size for that toy)
var hud: RaceHud               # problems for the facilitator, the podium at session end
var fx: WeatherFx
var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var overlay: Label
var follow_run := ""        # the newest run on the track: the music and engines follow it
var run_time := 0.0
var shot_taken := false
var next_shot := 0.0       # --shots=DIR: time of the next periodic screenshot
var shots_failed := 0      # screenshots that could not be saved: the run exits 1
var _shots_pending := 0    # screenshots waiting for their frame to be drawn
var forced_calm := false
var menu: OptionsMenu
var quitting := false
var quality := ""
var audio: AudioDirector
## Language sent to the server and not yet echoed in config.updated (other updates are stale).
var language_sent := ""
var _village_plan = null   # world/village/village_plan.gd, built on a worker for the camera blockers
var _plan_task := -1       # WorkerThreadPool task building it; -1 when none is running
var _plan_terrain: Node = null
## The line and the halves (contracts §2i).
var duel_screen: DuelScreen          # the split screen's halves and their cameras
var duel_hud: DuelHud                # names, times, lights, verdicts per half; the crown and the line
var duel_sides := {}                 # runId -> "left" | "right" (run.start side), newest last
var queue_state := {}                # last queue.updated
var bests := {}                      # playerId -> best time (on a loop, best lap) in ms this session
var _front_was := {}                 # side -> its camera showed the racer from the front last frame


func _ready() -> void:
	# Window close and the app menu's Quit (⌘Q) go through _quit so the run summary prints.
	get_tree().auto_accept_quit = false
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if (args.has("shots") or args.has("screenshot")) and DisplayServer.get_name() == "headless":
		push_error("--shots and --screenshot need a window: headless draws no frames")
		get_tree().quit(1)
		return
	# --shots=DIR is the output asked for: make the folder.
	if args.has("shots"):
		var mk := DirAccess.make_dir_recursive_absolute(String(args["shots"]))
		if mk != OK:
			push_error("shots: can't create the folder %s (%s)" % [args["shots"], error_string(mk)])
			get_tree().quit(1)
			return
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
	sim.solo = true  # every run has its own start lights in its half; karts pass through each other
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
		# A new look for a racer (the designer keeps improving it) waits until their kart is off the track.
		assets.is_racing = func(pid: String) -> bool: return sim.racers.any(func(r): return r.player_id == pid)
		assets.problem.connect(func(text: String): _result(I18n.f("log.error", [text])))
		print("BebbiKart server mode: %s (protocol v%d)" % [url, Protocol.PROTOCOL_VERSION])
	else:
		if args.has("kit") and not _load_kit_samples():
			return
		net = MockNet.new(config, n_racers, seed_)
		net.sim = sim  # mock players read their racer to know where to steer
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
	if track == "village":
		camera.fork_shots = _village_fork_shots()
	else:
		camera.fork_shots = Viewpoints.fork_shots(course)  # one shot per fork split
	_setup_race_hud()
	# The boost arrows on the road, the signs over the forks, the rings ahead of steered karts.
	var marks := SteerMarks.new()
	add_child(marks)
	var marks_err := marks.setup(course, sim)
	if marks_err != "":
		push_error("steering marks: " + marks_err)
		_result(("steering marks: " + marks_err).left(160))
		hud.problem("steering marks: " + marks_err)
	fx = WeatherFx.new()
	add_child(fx)
	fx.setup(sim.weather, env, sun)
	fx.follow = camera
	_setup_halves()
	audio = AudioDirector.new()
	audio.sound_of = func(pid: String) -> Dictionary:
		return assets.spec_for(pid).get("sound", {}) if assets != null else net.sound_of(pid)
	add_child(audio)
	if not audio.setup(sim, track, camera, args.has("mute")):
		_result(I18n.t("log.audio_failed"))
		hud.problem(I18n.t("log.audio_failed"))
	add_child(RaceReactions.new(self))  # drivers react to overtakes, near bumps and the weather
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	# The race HUD shows names, places, results and problems; this debug text starts hidden
	# (H shows it, or --overlay at start).
	panel.visible = args.has("overlay")
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


## The race HUD (ui/race_hud.gd): problems for the facilitator and the podium. Racer colours come
## from its palette.
func _setup_race_hud() -> void:
	hud = RaceHud.new()
	hud.local_bests = assets == null
	if assets != null:
		hud.avatar_of = assets.avatar_for
		assets.problem.connect(func(text: String): hud.problem(text))
	add_child(hud)
	if assets == null:
		hud.set_roster(net.players)
	for pid in colors.keys():
		colors[pid] = hud.color_for(pid)


## The options menu, (re)built in the current language.
func _make_menu() -> void:
	if menu != null:
		menu.queue_free()
	menu = OptionsMenu.new()
	add_child(menu)
	menu.setup(track, assets != null)
	menu.fullscreen_toggled.connect(_toggle_fullscreen)
	menu.track_chosen.connect(_switch_track)
	menu.new_session_pressed.connect(_new_session)
	menu.quit_pressed.connect(_quit)
	menu.quality_chosen.connect(func(id: String): apply_quality(id); _save_setting("graphics", "quality", id))
	menu.language_chosen.connect(_choose_language)
	if quality != "":
		menu.set_quality(quality)
	if assets != null:
		menu.set_session(net.session_status)
		menu.set_join_server(net.http_base())  # the phone address and QR code (GET /api/join)


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
	var split := duel_screen.split
	sun.directional_shadow_max_distance = minf(q["shadow_distance"], SPLIT_SHADOW_M) if split else q["shadow_distance"]
	# Each half renders the sun's shadow cascades again: two cascades over the shorter distance
	# instead of the sun's own (usually four).
	if not sun.has_meta("shadow_mode"):
		sun.set_meta("shadow_mode", sun.directional_shadow_mode)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if split else sun.get_meta("shadow_mode")
	env.ssao_enabled = q["ssao"]
	env.glow_enabled = q["glow"]
	_scale_visibility(self, q["veg"] * (SPLIT_VEG if split else 1.0))
	duel_screen.apply_quality(int(q["render_height"]))
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


## Track picked in the options menu (one click, no question). Mock mode reloads on it. Server
## mode asks the server (the game manager owns the options): the running session ends, the
## track is set and a new session starts. The server stops the karts on the old track
## (run.abort), so config.updated reloads the course via _check_track right away.
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


## Options menu, any time, one click: start over on the same track. The running session ends
## (the podium shows, the server stops the karts on the track) and a new one starts at once:
## empty leaderboard, the racers stay.
func _new_session() -> void:
	if assets == null:
		push_error("new session: mock mode has no server session")
		menu.show_session_error(I18n.t("menu.session_mock"))
		return
	if net.status != "online":
		push_error("new session: server is %s" % net.status)
		menu.show_session_error(I18n.f("error.offline_session", [I18n.t("net." + net.status)]))
		return
	print("session: starting over on %s (options menu, session %s)" % [track, net.session_status])
	if net.session_status == "running":
		net.send("game.session.end", {})
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
	if not _use_lighting(LIGHTING_SCENE):
		return false
	var terrain := world.get_node_or_null("Terrain")
	if terrain == null:
		push_error("%s has no Terrain node; re-run tools/bake_world.gd" % WORLD_SCENE)
		get_tree().quit(1)
		return false
	terrain.call("set_camera", camera)
	return true


## Swaps in a track's lighting scene (WorldEnvironment and Sun nodes) for the default sky and
## sun. Returns false (and quits with an error) if the scene lacks either node.
func _use_lighting(path: String) -> bool:
	var lighting: Node = (load(path) as PackedScene).instantiate()
	var we: WorldEnvironment = lighting.get_node_or_null("WorldEnvironment")
	var lit_sun: DirectionalLight3D = lighting.get_node_or_null("Sun")
	if we == null or lit_sun == null:
		push_error("%s needs WorldEnvironment and Sun nodes" % path)
		lighting.free()
		get_tree().quit(1)
		return false
	world_env.queue_free()
	sun.queue_free()
	add_child(lighting)
	world_env = we
	env = we.environment
	sun = lit_sun
	return true


## The sim's size for a racer (half width, half length): its built toy's footprint, measured once
## per RacerSpec. A toy that can't be measured is an error on the big screen, never a default:
## returns Vector2.ZERO after reporting it.
func _footprint(pl: Dictionary, spec: Dictionary) -> Vector2:
	var key := JSON.stringify(spec).hash()
	if not footprints.has(key):
		footprints[key] = ToyFootprint.of_spec(spec)
	var fp: Dictionary = footprints[key]
	if fp.has("error"):
		var err := I18n.f("log.no_footprint", [pl["runId"], nicks.get(pl["playerId"], "?"), fp["error"]])
		push_error(err)
		_result(err.left(160))
		hud.problem(err.left(300))
		return Vector2.ZERO
	return fp["size"]


## Course for a TrackId, or null after reporting an unknown track and quitting.
func _make_course(id: String):
	match id:
		"countryside":
			var cc := Course.new()
			if not cc.errors.is_empty():
				push_error("countryside course is broken: %s" % "; ".join(cc.errors))
				get_tree().quit(1)
				return null
			return cc
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
	# The village's alpine sky, sun and fog replace the default ones.
	if not ResourceLoader.exists(VILLAGE_LIGHTING_SCENE):
		push_error("%s is missing; run tools/seed_village_environment.gd" % VILLAGE_LIGHTING_SCENE)
		get_tree().quit(1)
		return false
	if not _use_lighting(VILLAGE_LIGHTING_SCENE):
		return false
	var terrain := world.get_node_or_null("Terrain")
	if terrain == null:
		push_error("%s has no Terrain node; re-run tools/bake_village.gd" % VILLAGE_WORLD_SCENE)
		get_tree().quit(1)
		return false
	terrain.call("set_camera", camera)
	return _village_blockers(terrain)


## The houses and the covered bridge's roof the cameras keep out of (world/camera_blockers.gd), on
## the baked terrain's ground. The village plan behind them takes about 2 s to lay out, so it is
## built on a worker thread and the cameras get their boxes when it is done (well before the
## first racer leaves the grid); _finish_village_blockers picks it up.
func _village_blockers(terrain: Node) -> bool:
	if terrain.get("data") == null:
		push_error("camera blockers: the village terrain has no height data; re-run tools/bake_village.gd")
		get_tree().quit(1)
		return false
	_plan_terrain = terrain
	_plan_task = WorkerThreadPool.add_task(func() -> void: _village_plan = CameraBlockers.VillagePlan.new(course),
		false, "village plan for the camera blockers")
	return true


## Once the worker has laid out the village plan: build the boxes on the terrain's ground and hand
## them to both cameras. Quits with an error if a house has no ground under it.
func _finish_village_blockers() -> void:
	if _plan_task < 0 or not WorkerThreadPool.is_task_completed(_plan_task):
		return
	WorkerThreadPool.wait_for_task_completion(_plan_task)
	_plan_task = -1
	var data = _plan_terrain.get("data")
	var b := CameraBlockers.new()
	if not b.add_village(course, func(x: float, z: float) -> float: return float(data.call("get_height", Vector3(x, 0.0, z))), _village_plan):
		push_error("camera blockers: %s" % "; ".join(b.errors))
		get_tree().quit(1)
		return
	camera.blockers = b
	duel_screen.set_blockers(b)
	duel_hud.set_blockers(b)


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
			# A loop run races the laps the server gave it (run.start lapsPerRun), never a default.
			var laps := int(pl.get("lapsPerRun", 0))
			if course.get("loop") == true and laps <= 0:
				var lerr := I18n.f("log.no_laps", [pl["runId"], nicks.get(pl["playerId"], "?")])
				push_error(lerr)
				_result(lerr)
				hud.problem(lerr)
				return
			var v  # server: KitRacerView from the player's RacerSpec; mock: placeholder RacerView
			if assets != null:
				var spec: Dictionary = assets.spec_for(pl["playerId"])
				if spec.is_empty():
					# No fallback racer: say so loudly and don't race a stand-in.
					var err := I18n.f("log.no_spec", [pl["runId"], pl["playerId"], nicks.get(pl["playerId"], "?")])
					push_error(err)
					_result(err)
					hud.problem(err)
					return
				var checked: Dictionary = RacerSpec.validate(spec)
				if not (checked["errors"] as PackedStringArray).is_empty():
					var err := I18n.f("log.invalid_spec", [pl["runId"], nicks.get(pl["playerId"], "?"), "; ".join(checked["errors"])])
					push_error(err)
					_result(err.left(160))
					hud.problem(err.left(300))
					return
				var size := _footprint(pl, spec)
				if size == Vector2.ZERO:
					return
				var r: Racer = sim.add_run(pl["runId"], pl["playerId"], pl["build"], size, laps)
				v = KitRacerView.new()
				add_child(v)
				v.setup(r, spec, assets.drawing_for(pl["playerId"]), nicks.get(pl["playerId"], "?"))
			elif not kit_specs.is_empty():
				var i: int = net.players.map(func(p): return p["playerId"]).find(pl["playerId"])
				var kspec: Dictionary = kit_specs[maxi(i, 0) % kit_specs.size()]
				var size := _footprint(pl, kspec)
				if size == Vector2.ZERO:
					return
				var r: Racer = sim.add_run(pl["runId"], pl["playerId"], pl["build"], size, laps)
				v = KitRacerView.new()
				add_child(v)
				v.setup(r, kspec, null, nicks.get(pl["playerId"], "?"))
			else:
				# Mock placeholder boxes: the default kart size, on purpose.
				var r: Racer = sim.add_run(pl["runId"], pl["playerId"], pl["build"], Tuning.DEFAULT_SIZE, laps)
				v = RacerView.new()
				add_child(v)
				v.setup(r, colors.get(pl["playerId"], Color.WHITE), nicks.get(pl["playerId"], "?"))
			v.show_name_tag(false)  # the race HUD draws the tags
			views[pl["runId"]] = v
			net.remember_run(pl["runId"], nicks.get(pl["playerId"], "?"))
			var side := String(pl.get("side", ""))
			if not Protocol.SIDES.has(side):
				var serr := I18n.f("log.no_side", [pl["runId"], nicks.get(pl["playerId"], "?"), side])
				push_error(serr)
				_result(serr)
				hud.problem(serr)
				side = "left"  # it still races (it is on the track already), in the left half
			duel_sides.erase(pl["runId"])
			duel_sides[pl["runId"]] = side  # newest last: the run a half shows
			duel_hud.set_side(pl["runId"], side)
			_tag_side_layers(v, side)
		Messages.RUN_STEER:
			sim.steer(pl["runId"], pl.get("x"))
		Messages.QUEUE_UPDATED:
			queue_state = pl
			duel_hud.set_queue(pl)
			_set_split(bool(pl.get("split", false)))
		Messages.RUN_ABORT:
			sim.abort(pl["runId"])
		Messages.ROSTER_UPDATED:
			_on_roster(pl)
		"session.updated":
			menu.set_session(String(pl.get("status", "?")))
			hud.set_session(String(pl.get("status", "?")))
		"leaderboard.updated":
			hud.set_leaderboard(pl)
			bests.clear()  # a new session starts with an empty leaderboard
			for e in pl:
				bests[String(e["playerId"])] = int(e["bestTimeMs"])
		Messages.WELCOME:
			# The big screen's language wins: a fresh server (or one an admin changed) gets ours.
			var server_lang := String(pl.get("config", {}).get("language", ""))
			if server_lang != I18n.language:
				print("language: server has %s, the big screen %s; sending it" % [server_lang, I18n.language])
				language_sent = I18n.language
				net.send("game.config.set", {"language": I18n.language})
			# The game owns the weather: a server that just met it (its start, a reconnect) gets the
			# weather now, not at the next phase change; a forced --weather reaches the phones too.
			net.send(Messages.GAME_WEATHER, sim.weather.state())
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
			hud.problem(err)
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
	hud.set_roster(roster)
	for pid in colors.keys():
		if not still.has(pid):
			colors.erase(pid)
	for e in roster:
		var pid: String = e["playerId"]
		nicks[pid] = e["nickname"]
		colors[pid] = hud.color_for(pid)
	if assets != null:
		assets.update(roster)


func _on_racer_ready(player_id: String) -> void:
	var title: String = assets.spec_for(player_id).get("title", "")
	_result(I18n.f("log.new", [assets.nickname(player_id), title]))


func _outgoing(type: String, pl: Dictionary) -> void:
	match type:
		"sim.boost", "sim.bump", "sim.fork":
			return
		"sim.removed":
			var v: Node = views.get(pl["runId"])
			if v != null:
				if v.has_method("leave"):
					v.leave(pl["outcome"])  # kit racers cheer or slump a moment, then free themselves
					if v.leaving != "":
						leaving[pl["runId"]] = v
				else:
					v.queue_free()
				views.erase(pl["runId"])
			if pl["outcome"] == "aborted":
				net.run_gone(pl["runId"])
			return  # its half stays a moment on a racer still cheering or slumping
		Messages.GAME_RUN_FINISHED, Messages.GAME_RUN_FAILED:
			var fv = views.get(pl["runId"])
			if fv != null:
				# On a loop the best lap ranks, also for a run that failed after some laps.
				var ms := int(pl["bestLapMs"]) if pl.has("bestLapMs") else int(pl.get("elapsedMs", 0))
				hud.run_result(fv.racer.player_id, type == Messages.GAME_RUN_FINISHED, ms)
				if duel_sides.has(pl["runId"]):
					_duel_verdict(pl["runId"], fv.racer.player_id, type == Messages.GAME_RUN_FINISHED, ms, String(pl.get("reason", "")))
				# Each racer's best (a loop's best lap, also from a run that failed after a lap).
				var pid: String = fv.racer.player_id
				var timed := type == Messages.GAME_RUN_FINISHED or pl.has("bestLapMs")
				if timed and ms > 0 and (not bests.has(pid) or ms < int(bests[pid])):
					bests[pid] = ms
	match type:
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
	var v = _view_of(run_id)
	return v.nickname if v != null else "?"


func _result(line: String) -> void:
	results.push_front(line)
	if results.size() > 8:
		results.resize(8)


# ---------------------------------------------------------------- presentation

func _process(delta: float) -> void:
	run_time += delta
	_finish_village_blockers()
	var racing: Array = sim.racers.duplicate()
	# On a loop, laps first, then position in the lap.
	racing.sort_custom(func(a, b): return a.lap + a.progress() > b.lap + b.progress())
	_update_duel(delta)
	audio.follow_run = follow_run
	for id in views:
		views[id].parked = sim.on_grid(id)
		views[id].sync()
	hud.update(delta)
	_update_overlay(racing)
	var dur := float(args.get("duration", "0"))
	if args.has("screenshot") and not shot_taken and run_time >= float(args.get("shot-at", str(dur - 0.5 if dur > 1 else 12.0))):
		shot_taken = true
		_screenshot(args["screenshot"])
	# --shots=DIR [--shot-every=SEC]: a screenshot every few seconds while racers are on the
	# track (multiplayer harness: start grid, mid-race, finish), named by time and racer count.
	if args.has("shots") and run_time >= next_shot and sim.active_count() > 0:
		next_shot = run_time + float(args.get("shot-every", "2"))
		_screenshot("%s/t%05.1f_r%d.jpg" % [args["shots"], run_time, sim.racers.size()])
	if dur > 0.0 and run_time >= dur:
		_quit()


# ---------------------------------------------------------------- the line and the halves (contracts §2i)

## The split screen's halves (one camera each) and their HUD; full screen until two people play.
func _setup_halves() -> void:
	duel_screen = DuelScreen.new()
	add_child(duel_screen)
	duel_screen.setup(camera, camera.fork_shots)
	duel_hud = DuelHud.new()
	add_child(duel_hud)
	duel_hud.bests = bests
	duel_hud.result_s = float(config.get("duelResultMs", 5000)) / 1000.0
	duel_hud.set_queue(queue_state)


## queue.updated split: a half per racer (two people play) or the full screen for one.
func _set_split(on: bool) -> void:
	if duel_screen.split == on:
		return
	duel_screen.set_split(on)
	if quality != "":
		apply_quality(quality)  # the halves keep their shadows closer (SPLIT_SHADOW_M)




## Per frame: each half's camera on its racer (the newest run of that side, also while
## it cheers after its lap), the weather around both cameras, the duel HUD.
func _update_duel(delta: float) -> void:
	var on_side := {}       # side -> racer view in that half
	var runs := {}          # side -> its Racer (on the grid or racing)
	var fronts := {}        # side -> show its racer from the front (on the grid, after its lap)
	for rid in duel_sides.keys():
		var v = _view_of(rid)
		var r = sim.by_run.get(rid)
		if v == null and r == null:
			duel_sides.erase(rid)
			continue
		var side: String = duel_sides[rid]
		if v != null:
			on_side[side] = v
			fronts[side] = _shows_front(rid, v, r)
		runs[side] = r
	if not duel_screen.split:
		# One person plays: the whole screen is theirs (the server races them on the left).
		var only_side := "left" if on_side.get("left", null) != null else "right"
		var only = on_side.get(only_side, null)
		on_side = {"left": only} if only != null else {}
		fronts = {"left": bool(fronts.get(only_side, false))}
		var only_r = runs.get("left", null) if runs.get("left", null) != null else runs.get("right", null)
		runs = {"left": only_r}
	var cams: Array = duel_screen.update(delta, on_side, views.values(), fronts)
	# As its camera comes round to the front, the character looks into it (its half's camera:
	# in a split the main camera is only the middle of the two).
	for side in fronts:
		if fronts[side] and on_side.has(side) and not _front_was.get(side, false):
			var toy = on_side[side].get("toy")
			if toy != null:
				toy.look_at_node(duel_screen.camera_of(side), FRONT_LOOK_S)
	_front_was = fronts
	fx.followers = cams if duel_screen.split else []
	# The music and engines follow the newest racer on the track.
	follow_run = ""
	for rid in duel_sides:
		if sim.by_run.has(rid):
			follow_run = rid
	var rects := {"left": duel_screen.rect_of("left")}
	if duel_screen.split:
		rects["right"] = duel_screen.rect_of("right")
	duel_hud.update(delta, sim, rects, runs, func(pid: String) -> String: return String(nicks.get(pid, "?")), on_side)


## Whether a half's camera shows its racer from the front: while it waits on the grid for its
## lights, and while it cheers or slumps after its lap (a kit racer's leave()). Never while it
## races: the kid steering needs to see the road ahead.
func _shows_front(rid: String, v, r) -> bool:
	var leaving_as = v.get("leaving")  # kit views only; "" while racing
	if leaving_as != null and String(leaving_as) != "":
		return true
	return r != null and (sim.on_grid(rid) or r.state == "queued")


## A racer's meshes go on its half's render layer only (DuelScreen.SIDE_LAYER), so the other
## half's front shot and face cam can leave it out: in a duel both racers can wait in the same
## grid spot.
func _tag_side_layers(n: Node, side: String) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = DuelScreen.SIDE_LAYER[side]
	for c in n.get_children():
		_tag_side_layers(c, side)


## A lap ended: its half shows the verdict, judged against the crown as it stood (the
## server's queue.updated with the new champion comes after it).
func _duel_verdict(run_id: String, pid: String, ok: bool, ms: int, reason: String) -> void:
	var side: String = duel_sides[run_id] if duel_screen.split else "left"
	if not ok:
		duel_hud.result(side, I18n.t("hud.oops").to_upper() + "!", I18n.t("fail." + reason) if reason != "" else "", false)
		return
	var c: Dictionary = queue_state.get("champion", {})
	var time := "%.2f s" % (ms / 1000.0)
	var pb := bests.has(pid) and ms < int(bests[pid])  # a new best of their own (not their first lap)
	if c.is_empty() or ms < int(c["timeMs"]):
		var own: bool = not c.is_empty() and String(c["playerId"]) == pid
		duel_hud.result(side, I18n.t("duel.new_record" if own else "duel.new_champion"), time, true)
	elif String(c["playerId"]) == pid:
		duel_hud.result(side, time, I18n.f("duel.keeps", [nicks.get(pid, "?")]), false)
	else:
		var gap := (ms - int(c["timeMs"])) / 1000.0
		duel_hud.result(side, time, I18n.f("duel.new_best_short" if pb else "duel.short", [gap, c["nickname"]]), false)






## A run's view on the track, or still on screen after its run; null if it has none (any more).
func _view_of(run_id: String) -> Node:
	var v = views.get(run_id)
	if v == null and leaving.has(run_id):
		v = leaving[run_id]
		if not is_instance_valid(v):
			leaving.erase(run_id)
			v = null
	return v










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
		lines.append("%s%-6s %-8s %s  %3d%%  %4.1f m/s  ⚡%d%s" % [mark, _nick_of(r.run_id), I18n.t("section." + r.section), timing,
			int(r.progress() * 100), r.v, r.boosts_used, I18n.t("overlay.boost") if r.boost_t > 0 else ""])
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
	if k.keycode == KEY_H:
		overlay.get_parent().visible = not overlay.get_parent().visible
		return
	if not OS.is_debug_build():
		return  # the test keys (weather) are off in the release build (bun run play)
	match k.keycode:
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


## Saves this frame once drawn. A screenshot that can't be saved (no image, a bad path)
## is an error, and the run exits 1 (_quit).
func _screenshot(path: String) -> void:
	_shots_pending += 1
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := ERR_UNAVAILABLE
	if img != null:
		err = img.save_jpg(path, 0.85) if path.ends_with(".jpg") else img.save_png(path)
	_shots_pending -= 1
	if err != OK:
		shots_failed += 1
		push_error("screenshot: can't save %s (%s)" % [path, "no image: windowed only" if img == null else error_string(err)])
		return
	print("screenshot saved to ", path)


func _quit() -> void:
	if quitting:
		return
	quitting = true
	if _plan_task >= 0:  # never leave the worker running into shutdown
		WorkerThreadPool.wait_for_task_completion(_plan_task)
		_plan_task = -1
	if sim == null:  # startup failed and already reported; nothing to summarise
		get_tree().quit(1)
		return
	set_process(false)
	set_physics_process(false)
	print("mock summary: %.1f s wall, %d sim ticks, finished %d, failed %d, sent %s" % [
		run_time, sim.tick, net.finished, net.failed, JSON.stringify(net.sent_counts)])
	print("camera: %s (%.1f s run)" % [duel_screen.summary(), run_time])
	if args.has("screenshot") and not shot_taken:
		shot_taken = true
		await _screenshot(args["screenshot"])
	# A shot saves once its frame is drawn: give the last ones a few frames.
	for i in 30:
		if _shots_pending == 0:
			break
		await get_tree().process_frame
	if _shots_pending > 0:
		shots_failed += _shots_pending
		push_error("screenshots: %d never got a drawn frame" % _shots_pending)
	if shots_failed > 0:
		push_error("screenshots: %d could not be saved" % shots_failed)
		get_tree().quit(1)
		return
	get_tree().quit()
