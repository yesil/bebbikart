extends SceneTree
## Windowed review of the ride reactions (ride_motion.gd) and the start-grid / social moments:
## one racer per ride base, one PNG per racer and scene (a 3/4 front view, the scene's name and
## the racer's title on it). Tile them into a sheet with ffmpeg (see --sheet in the README).
##
##   godot --path apps/game --resolution 480x360 --script res://racer_kit/tools/ride_shots.gd \
##     -- --out=<dir> [--only=finish,land] [--racers=<spec file>,<spec file>…]
##
## Needs a window (headless has no renderer); exits 1 if a spec is missing or a scene is unknown.

const SCENES := ["rest", "grid", "green", "jump", "land", "bend", "boost", "finish", "idle", "wind", "water", "rain"]
const DEFAULT := [
	"res://racer_kit/samples/monster_kart.json",
	"../../packages/asset-pipeline/out-v6/girl-car.spec.json",
	"res://racer_kit/samples/bunny_bike.json",
	"res://racer_kit/samples/dragon_board.json",
	"res://racer_kit/samples/knight_pony.json",
	"res://racer_kit/samples/owl_flyer.json",
	"res://racer_kit/samples/robot_rocket.json",
	"res://racer_kit/samples/duck_boat.json",
	"../../packages/asset-pipeline/out-v6/pair06-blob-boat.spec.json",
	"res://racer_kit/samples/jelly_wizard.json",
]

var out_dir := ""
var scenes: Array = []
var specs: Array = []
var stage: Node3D
var cam: Camera3D
var label: Label
var racer: ToyRacer
var scene_i := 0
var spec_i := -1
var t := 0.0
var shot_at := 0.0
var fired := false


func _initialize() -> void:
	var only := ""
	var list := DEFAULT.duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--racers="):
			list = Array(a.trim_prefix("--racers=").split(",", false))
	if out_dir == "":
		push_error("ride_shots: --out=<dir> is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	scenes = SCENES.duplicate() if only == "" else Array(only.split(",", false))
	for p in list:
		var path: String = p if p.begins_with("res://") or p.begins_with("/") else ProjectSettings.globalize_path("res://").path_join(p).simplify_path()
		var raw := RacerSpec.load_file(path)
		if raw.is_empty():
			push_error("ride_shots: cannot read spec " + path)
			quit(1)
			return
		specs.append(raw)
	_build_stage()
	_next()


func _build_stage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#bfe6ff")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.9, 0.9, 1.0)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -150, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(30, 0.1, 30)
	floor_mi.mesh = box
	floor_mi.position.y = -0.05
	KitMaterial.paint(floor_mi, Color("#9ad86b"), 0.0)
	stage.add_child(floor_mi)
	cam = Camera3D.new()
	cam.fov = 36
	stage.add_child(cam)
	cam.look_at_from_position(Vector3(-3.7, 1.7, -3.3), Vector3(0, 1.0, 0))
	cam.make_current()
	label = Label.new()
	label.position = Vector2(30, 20)
	# The project stretches the UI from 1920x1080: sized for a small review window.
	label.add_theme_font_size_override("font_size", 1920 * 22 / maxi(1, DisplayServer.window_get_size().x))
	label.add_theme_color_override("font_color", Color("#2b2140"))
	label.add_theme_color_override("font_outline_color", Color.WHITE)
	label.add_theme_constant_override("outline_size", 1920 * 6 / maxi(1, DisplayServer.window_get_size().x))
	var ui := CanvasLayer.new()
	ui.add_child(label)
	stage.add_child(ui)


func _next() -> void:
	if racer:
		racer.queue_free()
		racer = null
	spec_i += 1
	if spec_i >= specs.size():
		spec_i = 0
		scene_i += 1
	if scene_i >= scenes.size():
		quit(0)
		return
	racer = RacerBuilder.build(specs[spec_i])
	if racer == null:
		push_error("ride_shots: spec %d does not build: %s" % [spec_i, ", ".join(RacerBuilder.last_errors)])
		quit(1)
		return
	racer.show_name_tag(false)
	stage.add_child(racer)
	label.text = "%s · %s (%s)" % [scenes[scene_i], specs[spec_i].get("title", "?"), specs[spec_i].ride.base]
	t = 0.0
	fired = false
	shot_at = 99.0


## Sets the scene's state once; returns when to take the picture (s after firing).
func _fire(r: ToyRacer, scene: String) -> float:
	match scene:
		"rest":
			return 0.4
		"grid":
			r.gestures.hold(ToyRacer.Gestures.G.READY, true)  # leaning in on 3-2-1
			r.ride.crouch(1.0)
			return 0.9
		"green":
			r.gestures.play(ToyRacer.Gestures.G.WHOOP, 0, 0.9)
			r.ride.go()
			r.speed = 4.0
			return 0.3
		"finish":
			r.finish()
			return 0.6
		"jump":
			r.airborne = true
			r.big_air = true
			r.speed = 10.0
			r.vy = -2.5
			return 0.45
		"land":
			r.airborne = true
			r.big_air = true
			r.vy = -3.0
			r.speed = 8.0
			create_timer(0.4).timeout.connect(func() -> void:
				r.airborne = false
				r.big_air = false
				r.vy = 0.0
				r.land())
			return 0.55
		"bend":
			r.speed = 14.0
			r.turn = 0.9
			r.ahead_turn = 0.6
			return 1.1
		"boost":
			r.speed = 12.0
			r.boost = true
			return 0.22
		"idle":
			return 1.3  # standing: the first tail swish peaks, an ear has flicked, a rocket has coughed
		"wind":
			r.wind = Vector3(-0.9, 0.0, 0.2)  # from the racer's right: the sail swings out to its left
			return 1.4
		"water":
			r.in_water = true  # into the pond: the splash is up
			return 0.18
		"rain":
			r.rain = 1.0
			return 0.8
	push_error("ride_shots: unknown scene " + scene)
	quit(1)
	return 0.0


func _process(delta: float) -> bool:
	if racer == null:
		return false
	t += delta
	if not fired and t > 0.25:
		fired = true
		shot_at = t + _fire(racer, scenes[scene_i])
	if fired and t >= shot_at:
		var img := root.get_texture().get_image()
		var path := out_dir.path_join("%02d_%s_%02d.png" % [scene_i, scenes[scene_i], spec_i])
		img.save_png(path)
		print("shot: ", path)
		_next()
	return false
