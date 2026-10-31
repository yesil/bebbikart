extends SceneTree
## Windowed review of RacerGestures: a row of racers caught mid-gesture, one PNG per gesture.
##
##   godot --path apps/game --resolution 1920x1080 --script res://racer_kit/tools/gesture_shots.gd \
##     -- --out=<dir> [--only=cheer,wave] [--racers=<spec file>,<spec file>…] [--at=SEC]
## --at: take every scene's picture SEC after its gesture starts (the wind-up, the held key pose).
##
## Default racers: a mix of every ride base with hair, hats and ears from the samples and the
## designer output. Needs a window (headless has no renderer); exits 1 if a spec is missing.

const SCENES := ["rest", "cheer", "wave", "fist_pump", "slump", "dizzy", "rain", "head_shake", "wind",
	"wheee", "tuck", "hair", "corner", "surprised", "flail", "glance_back", "brace"]
const DEFAULT := [
	"res://racer_kit/samples/bunny_bike.json",
	"../../packages/asset-pipeline/out-v4/third.spec.json",
	"res://racer_kit/samples/dragon_board.json",
]
const SPACING := 2.1

var out_dir := ""
var scenes: Array = []
var specs: Array = []
var stage: Node3D
var cam: Camera3D
var title: Label
var racers: Array[ToyRacer] = []
var scene_i := -1
var t := 0.0
var shot_at := 0.0
var fired := false
var at := -1.0


func _initialize() -> void:
	var only := ""
	var list := DEFAULT.duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--at="):
			at = float(a.trim_prefix("--at="))
		elif a.begins_with("--racers="):
			list = Array(a.trim_prefix("--racers=").split(",", false))
	if out_dir == "":
		push_error("gesture_shots: --out=<dir> is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	scenes = SCENES.duplicate() if only == "" else Array(only.split(",", false))
	for p in list:
		var path: String = p if p.begins_with("res://") or p.begins_with("/") else ProjectSettings.globalize_path("res://").path_join(p).simplify_path()
		var raw := RacerSpec.load_file(path)
		if raw.is_empty():
			push_error("gesture_shots: cannot read spec " + path)
			quit(1)
			return
		specs.append(raw)
	_build_stage()
	_next_scene()


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
	box.size = Vector3(40, 0.1, 12)
	floor_mi.mesh = box
	floor_mi.position.y = -0.05
	KitMaterial.paint(floor_mi, Color("#9ad86b"), 0.0)
	stage.add_child(floor_mi)
	cam = Camera3D.new()
	cam.fov = 34
	stage.add_child(cam)
	var w := (specs.size() - 1) * SPACING
	var dist := (w * 0.5 + 1.3) / tan(deg_to_rad(28.0))
	cam.look_at_from_position(Vector3(0.5, 1.0 + dist * 0.16, -dist), Vector3(0, 0.95, 0))
	cam.make_current()
	title = Label.new()
	title.position = Vector2(24, 16)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#2b2140"))
	var ui := CanvasLayer.new()
	ui.add_child(title)
	stage.add_child(ui)


func _next_scene() -> void:
	for r in racers:
		r.queue_free()
	racers.clear()
	scene_i += 1
	if scene_i >= scenes.size():
		quit(0)
		return
	var w := (specs.size() - 1) * SPACING
	for i in specs.size():
		var r := RacerBuilder.build(specs[i])
		if r == null:
			push_error("gesture_shots: spec %d does not build: %s" % [i, ", ".join(RacerBuilder.last_errors)])
			quit(1)
			return
		r.position = Vector3(w * 0.5 - i * SPACING, 0, 0)  # racer's left is -X: first spec on screen left
		r.show_name_tag(false)
		stage.add_child(r)
		racers.append(r)
	title.text = scenes[scene_i]
	t = 0.0
	fired = false
	shot_at = 1.0


## Sets the scene's state once, then returns when to take the picture (s after the start).
func _fire(r: ToyRacer, scene: String) -> float:
	match scene:
		"rest":
			return 0.6
		"cheer":
			r.celebrate(3)
			return 0.62
		"whoop":
			r.gesture("whoop")
			return 0.4
		"taunt":
			r.gesture("taunt")
			return 0.4
		"wave":
			r.wave()
			r.look_at_node(cam, 2.0)
			return 0.75
		"fist_pump":
			r.gesture("fist_pump")
			return 0.38
		"slump":
			r.fail()
			return 1.45
		"dizzy":
			r.gesture("dizzy")
			return 0.5
		"rain":
			r.rain = 1.0
			return 1.4
		"head_shake":
			r.gesture("head_shake")
			return 0.3
		"wind":
			r.wind = Vector3(-0.9, 0, 0.2)
			return 1.3
		"wheee", "tuck":
			r.gestures.air_pose = ToyRacer.Gestures.G.WHEEE if scene == "wheee" else ToyRacer.Gestures.G.TUCK
			r.airborne = true
			r.big_air = true
			r.speed = 10.0
			return 0.6
		"hair":
			r.speed = 16.0
			return 1.2
		"corner":
			r.speed = 14.0
			r.turn = 0.9
			r.ahead_turn = 0.6
			return 1.0
		"surprised":
			r.gesture("surprised")
			return 0.3
		"flail":
			r.slipping = true
			return 0.5
		"glance_back":
			r.gesture("glance_back", 1)
			return 0.45
		"brace":
			r.gesture("brace")
			return 0.12
	push_error("gesture_shots: unknown scene " + scene)
	quit(1)
	return 0.0


func _process(delta: float) -> bool:
	if racers.is_empty():
		return false
	t += delta
	var scene: String = scenes[scene_i]
	if not fired and t > 0.3:
		fired = true
		for r in racers:
			shot_at = 0.3 + (at if at >= 0.0 else _fire(r, scene))
			if at >= 0.0:
				_fire(r, scene)
	if fired and t >= shot_at:
		var img := root.get_texture().get_image()
		var path := out_dir.path_join("%02d_%s.png" % [scene_i, scene])
		img.save_png(path)
		print("shot: ", path)
		_next_scene()
	return false
