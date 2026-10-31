extends Node3D
## Racer Viewer: watches folders of RacerSpec JSON files and shows each racer on a turntable,
## cycling through animation states and moods. New or changed files are picked up within a
## second, so it can sit next to the WS5 designer CLI while tuning the kit and prompt.
##
##   godot --path apps/game res://racer_viewer/racer_viewer.tscn [-- --specs=<dir>[,<dir>]]
##   (or BEBBI_SPECS_DIR=<dir>). Always watched: res://racer_kit/samples and
##   <repo>/packages/asset-pipeline/out.  Extra: --shot=<png> saves a screenshot and quits.

const HELP := "←/→ racer   A auto-demo   Space next action   1-6 mood (0 auto)   T turntable   N name tag   G lineup   R render avatars"
const ACTIONS := ["idle", "drive", "boost", "airborne", "bump", "celebrate", "wave", "fail", "fast lean"]

var dirs := PackedStringArray()
var files := PackedStringArray()
var index := 0
var racer: ToyRacer
var lineup: Array[ToyRacer] = []
var auto_demo := true
var turntable := true
var action := 0

var _stamps := {}
var _poll := 0.0
var _act_t := 0.0
var _pivot: Node3D
var _cam: Camera3D
var _info: Label
var _warn: Label
var _renderer: AvatarRenderer
var _shot_path := ""
var _shot_t := 2.5
var _last_render := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	dirs = SpecFolders.dirs(args)
	for a in args:
		if a.begins_with("--shot="):
			_shot_path = a.trim_prefix("--shot=")
		elif a.begins_with("--index="):
			index = int(a.trim_prefix("--index="))
		elif a == "--lineup":
			call_deferred("_toggle_lineup")
	_build_stage()
	_renderer = AvatarRenderer.new()
	add_child(_renderer)
	_rescan()
	_show(index)


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#bfe6ff")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.9, 0.9, 1.0)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 2.2
	disc.bottom_radius = 2.3
	disc.height = 0.1
	floor_mi.mesh = disc
	floor_mi.position.y = -0.05
	KitMaterial.paint(floor_mi, Color("#9ad86b"), 0.0)
	add_child(floor_mi)
	_pivot = Node3D.new()
	add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 40
	add_child(_cam)
	_frame(1.6)
	var ui := CanvasLayer.new()
	add_child(ui)
	_info = Label.new()
	_info.position = Vector2(16, 12)
	_info.add_theme_font_size_override("font_size", 18)
	_info.add_theme_color_override("font_color", Color("#2b2140"))
	ui.add_child(_info)
	_warn = Label.new()
	_warn.position = Vector2(16, 150)
	_warn.add_theme_font_size_override("font_size", 15)
	_warn.add_theme_color_override("font_color", Color("#b3261e"))
	ui.add_child(_warn)


func _frame(height: float) -> void:
	var d := maxf(3.2, height * 2.3)
	_cam.look_at_from_position(Vector3(0, height * 0.75 + 0.4, -d), Vector3(0, height * 0.45, 0))


# --- folder watching ---

func _rescan() -> void:
	var list := PackedStringArray()
	for d in dirs:
		list.append_array(SpecFolders.list(d))
	var current := files[index] if index < files.size() else ""
	var stamps := SpecFolders.stamp(list)
	var newest := ""
	for f in list:
		if not _stamps.has(f) and not _stamps.is_empty():
			newest = f
	var changed := false
	for f in stamps:
		if _stamps.has(f) and _stamps[f] != stamps[f] and f == current:
			changed = true
	files = list
	_stamps = stamps
	if newest != "":
		_show(files.find(newest))
	elif changed or (current != "" and files.find(current) == -1):
		_show(maxi(0, files.find(current)))


func _process(delta: float) -> void:
	_poll += delta
	if _poll > 1.0:
		_poll = 0.0
		_rescan()
	if turntable:
		_pivot.rotation.y += delta * 0.5
	if auto_demo and racer:
		_act_t -= delta
		if _act_t <= 0.0:
			_next_action()
	if _shot_path != "":
		_shot_t -= delta
		if _shot_t <= 0.0:
			get_viewport().get_texture().get_image().save_png(_shot_path)
			print("screenshot: ", _shot_path)
			get_tree().quit()


# --- racer display ---

func _show(i: int) -> void:
	_clear_lineup()
	if racer:
		racer.queue_free()
		racer = null
	if files.is_empty():
		_info.text = "No spec files found in:\n  " + "\n  ".join(dirs) + "\n\n" + HELP
		return
	index = posmod(i, files.size())
	var path := files[index]
	var raw := RacerSpec.load_file(path)
	racer = RacerBuilder.build(raw, SpecFolders.drawing_for(path))
	_pivot.add_child(racer)
	var box := RacerBuilder._aabb(racer, Transform3D.IDENTITY)
	_frame(box.size.y)
	action = 0
	_act_t = 0.0
	if raw.is_empty():
		racer.warnings.append("could not read %s; showing defaults" % path.get_file())
	_update_ui()


func _update_ui() -> void:
	if racer == null:
		return
	var s := racer.spec
	_info.text = "%s  (%d/%d)  %s\n%s  ·  ride: %s  ·  %s\naction: %s   mood: %s%s\n%s\n%s" % [
		s.title, index + 1, files.size(), files[index].get_file(),
		", ".join(s.personality), s.ride.base, ", ".join(s.palette),
		ACTIONS[action], racer.get_mood(), "" if not racer._mood_locked else " (locked)",
		HELP, _last_render]
	_warn.text = ("Spec fixes:\n- " + "\n- ".join(racer.warnings)) if racer.warnings.size() > 0 else ""


func _next_action() -> void:
	action = (action + 1) % ACTIONS.size()
	_act_t = 2.5
	_apply_action(racer)
	for r in lineup:
		_apply_action(r)
	_update_ui()


func _apply_action(r: ToyRacer) -> void:
	r.set_state({"speed": 0.0, "lean": 0.0, "airborne": false, "boost": false})
	match ACTIONS[action]:
		"drive": r.set_state({"speed": 8.0, "lean": 0.0})
		"boost": r.set_state({"speed": 18.0, "boost": true})
		"airborne": r.set_state({"speed": 10.0, "airborne": true})
		"bump": r.set_state({"speed": 6.0}); r.bump()
		"celebrate": r.celebrate(3)
		"wave": r.wave()
		"fail": r.fail()
		"fast lean": r.set_state({"speed": 14.0, "lean": 0.8})


func _toggle_lineup() -> void:
	if not lineup.is_empty():
		_show(index)
		return
	if racer:
		racer.queue_free()
		racer = null
	var n := files.size()
	var cols := ceili(sqrt(n))
	for i in n:
		var r := RacerBuilder.build(RacerSpec.load_file(files[i]), SpecFolders.drawing_for(files[i]))
		r.position = Vector3((i % cols - (cols - 1) * 0.5) * 2.2, 0, (i / cols) * 2.4)
		_pivot.add_child(r)
		lineup.append(r)
	turntable = false
	_pivot.rotation.y = 0
	var rows := ceili(float(n) / cols)
	_cam.look_at_from_position(Vector3(0, 3.0 + rows, -3.5 - cols * 1.3), Vector3(0, 0.6, (rows - 1) * 1.1))
	_info.text = "Lineup: %d racers  (G to go back)\n%s" % [n, HELP]
	_warn.text = ""


func _clear_lineup() -> void:
	for r in lineup:
		r.queue_free()
	lineup.clear()


func _render_current() -> void:
	if racer == null:
		return
	var pid := files[index].get_file().get_basename().get_basename()
	_last_render = "rendering…"
	_update_ui()
	var paths := await _renderer.render_all(racer.spec, pid, SpecFolders.drawing_for(files[index]))
	await _renderer.upload_all(pid, paths)
	_last_render = "renders: " + (paths.values()[0].get_base_dir() if not paths.is_empty() else "skipped (headless)")
	_update_ui()


func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	match ev.keycode:
		KEY_RIGHT: _show(index + 1)
		KEY_LEFT: _show(index - 1)
		KEY_SPACE: auto_demo = false; _next_action()
		KEY_A: auto_demo = not auto_demo
		KEY_T: turntable = not turntable
		KEY_N:
			if racer: racer.show_name_tag(not racer.name_tag.visible)
		KEY_G: _toggle_lineup()
		KEY_R: _render_current()
		KEY_0:
			if racer: racer.set_auto_mood()
		_:
			var k: int = ev.keycode - KEY_1
			if racer and k >= 0 and k < KitCatalog.MOODS.size():
				racer.set_mood(KitCatalog.MOODS[k])
	_update_ui()
