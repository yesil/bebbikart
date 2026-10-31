extends SceneTree
## Windowed: runs the mock race (main.tscn) and photographs the kit drivers' reactions close up:
## overtakes (fist pump or wave + glance back), finishes (cheer, wave at the camera) and crashes
## (spin, slump). main.gd reads the same user args, so pass --kit.
##
##   godot --path apps/game --resolution 1920x1080 --script res://racer_kit/tools/race_gesture_shots.gd \
##     -- --kit --racers=12 --seed=4 --speed=2 --out=<dir> [--want=2] [--limit=90]
##
## Exits 1 if it could not catch every kind of moment within --limit seconds.

const KitRacerView = preload("res://racer_kit/kit_racer_view.gd")
const DELAY := {"overtake": 0.4, "finished": 0.75, "finished_wave": 1.55, "failed": 1.0}

var out_dir := ""
var want := 2
var limit := 90.0
var main: Node
var cam: Camera3D
var taken := {"overtake": 0, "finished": 0, "finished_wave": 0, "failed": 0}
var seen := {}          # view -> true once photographed
var cur := {}           # {view, kind, at}
var t := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--want="):
			want = int(a.trim_prefix("--want="))
		elif a.begins_with("--limit="):
			limit = float(a.trim_prefix("--limit="))
	if out_dir == "":
		push_error("race_gesture_shots: --out=<dir> is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 38
	root.add_child(cam)


func _process(delta: float) -> bool:
	t += delta
	if t > limit or _done():
		var missing := PackedStringArray()
		for k in taken:
			if taken[k] < _want(k):
				missing.append("%s %d/%d" % [k, taken[k], _want(k)])
		if not missing.is_empty():
			push_error("race_gesture_shots: not caught in %.0f s: %s" % [limit, ", ".join(missing)])
		quit(0 if missing.is_empty() else 1)
		return false
	if cur.is_empty():
		_pick()
	if cur.is_empty():
		return false
	var v = cur.view
	if not is_instance_valid(v):
		cur = {}
		main.camera.make_current()
		return false
	var f: Vector3 = v.forward()
	var right := f.cross(Vector3.UP).normalized()
	var p: Vector3 = v.global_position
	cam.look_at_from_position(p + f * 4.4 + right * 2.0 + Vector3.UP * 1.7, p + Vector3.UP * 0.85)
	if t >= cur.at:
		var path := out_dir.path_join("%s_%d.png" % [cur.kind, taken[cur.kind] + 1])
		root.get_texture().get_image().save_png(path)
		print("shot: ", path)
		taken[cur.kind] += 1
		if cur.kind == "finished" and taken.finished_wave < _want("finished_wave"):
			cur = {"view": v, "kind": "finished_wave", "at": t + DELAY.finished_wave - DELAY.finished}
		else:
			cur = {}
			main.camera.make_current()
	return false


func _done() -> bool:
	for k in taken:
		if taken[k] < _want(k):
			return false
	return true


## Crashes are rare (about one run in forty), so one is enough.
func _want(kind: String) -> int:
	return 1 if kind == "failed" else want


func _pick() -> void:
	var reactions := main.get_node_or_null("RaceReactions")
	if reactions != null and taken.overtake < _want("overtake"):
		for e in reactions.events:
			if e.type == "overtake" and is_instance_valid(e.passer) and not seen.has(e.passer):
				_start(e.passer, "overtake")
				return
	for c in main.get_children():
		if c.get_script() == KitRacerView and c.leaving != "" and not seen.has(c) and taken[c.leaving] < _want(c.leaving):
			_start(c, c.leaving)
			return


func _start(v, kind: String) -> void:
	seen[v] = true
	cur = {"view": v, "kind": kind, "at": t + DELAY[kind]}
	cam.make_current()
	if kind == "finished":
		v.toy.gestures.look_at_camera(2.0)  # the finisher waves at the active camera: here, this close-up
