extends SceneTree
## Windowed: runs the mock race (main.tscn) and photographs the kit drivers' reactions close up:
## the start grid (leaning in on the lights, a fidget, the whoop on green), overtakes, a rival
## alongside (wave or taunt), a flinch at a crash, finishes (the signature gesture, then the
## wave), two racers finishing together, and crashes (spin, slump). main.gd reads the same user
## args, so pass --kit.
##
##   godot --path apps/game --resolution 1920x1080 --script res://racer_kit/tools/race_gesture_shots.gd \
##     -- --kit --racers=12 --seed=4 --speed=2 --out=<dir> [--want=2] [--limit=90] [--clip=<moments.txt>]
##
## --clip: the close-up camera stays CLIP_S on each moment and its start (seconds since the start,
## as Godot's --write-movie counts them) goes into the file, one "time kind" per line, so ffmpeg
## can cut the best moments out of the recording. Exits 1 if it could not catch every kind of
## moment within --limit seconds.

const KitRacerView = preload("res://racer_kit/kit_racer_view.gd")
const DELAY := {"grid": 0.15, "fidget": 0.55, "go": 0.35, "overtake": 0.4, "alongside": 0.55, "flinch": 0.3,
	"finished": 0.75, "finished_wave": 1.75, "together": 0.7, "failed": 1.0}
const CLIP_S := 2.6

var out_dir := ""
var want := 2
var limit := 90.0
var clip_path := ""
var clip_lines := PackedStringArray()
var main: Node
var cam: Camera3D
var taken := {"grid": 0, "fidget": 0, "go": 0, "overtake": 0, "alongside": 0, "flinch": 0, "finished": 0,
	"finished_wave": 0, "together": 0, "failed": 0}
var seen := {}          # view -> kinds already photographed
var cur := {}           # {view, other (or null), kind, at, until}
var _hud_was := {}      # HUD node -> visible before the close-ups
var t := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--want="):
			want = int(a.trim_prefix("--want="))
		elif a.begins_with("--limit="):
			limit = float(a.trim_prefix("--limit="))
		elif a.begins_with("--clip="):
			clip_path = a.trim_prefix("--clip=")
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
		if clip_path != "":
			var f := FileAccess.open(clip_path, FileAccess.WRITE)
			f.store_string("\n".join(clip_lines) + "\n")
		if not missing.is_empty():
			push_error("race_gesture_shots: not caught in %.0f s: %s" % [limit, ", ".join(missing)])
		quit(0 if missing.is_empty() else 1)
		return false
	if cur.is_empty():
		_pick()
	if cur.is_empty():
		return false
	var v = cur.view
	if not is_instance_valid(v) or (cur.other != null and not is_instance_valid(cur.other)):
		_end()
		return false
	_aim(v, cur.other, cur.kind)
	if not cur.shot and t >= cur.at:
		var path := out_dir.path_join("%s_%d.png" % [cur.kind, taken[cur.kind] + 1])
		root.get_texture().get_image().save_png(path)
		print("shot: ", path)
		taken[cur.kind] += 1
		cur.shot = true
		if cur.kind == "finished" and taken.finished_wave < _want("finished_wave"):
			cur.kind = "finished_wave"
			cur.at = t + DELAY.finished_wave - DELAY.finished
			cur.shot = false
	if cur.shot and t >= cur.until:
		_end()
	return false


func _end() -> void:
	cur = {}
	main.camera.make_current()
	_huds(true)


## The race HUD, the camera HUD and the overlay cover the close-ups: off while one runs.
func _huds(on: bool) -> void:
	for n in [main.hud, main.cam_hud, main.overlay]:
		if n == null:
			continue
		if on:
			n.visible = _hud_was.get(n, n.visible)
		else:
			if not _hud_was.has(n):
				_hud_was[n] = n.visible
			n.visible = false


## Close up: in front of the driver, a little to the side; wider in front of the grid; both
## racers from the side for the pair moments.
func _aim(v, other, kind: String) -> void:
	var f: Vector3 = v.forward()
	var right := f.cross(Vector3.UP).normalized()
	var p: Vector3 = v.global_position
	if other != null and v.leaving != "":
		# Two finishers: past the line the road ends among trees, so from the side over the road.
		var m2: Vector3 = (p + other.global_position) * 0.5
		var rt2 = v._leave_seg["route"]
		var to_mid2: Vector3 = rt2.world_at(minf(v._leave_ls, rt2.length), 0.0) - m2
		to_mid2.y = 0.0
		var side2: Vector3 = right if right.dot(to_mid2) >= 0.0 else -right
		cam.look_at_from_position(m2 + f * 2.0 + side2 * (4.0 + p.distance_to(other.global_position) * 0.5) + Vector3.UP * 1.7,
			m2 + Vector3.UP * 0.85)
	elif other != null:
		var m: Vector3 = (p + other.global_position) * 0.5
		var gap: float = p.distance_to(other.global_position)
		# From ahead of the pair, a little to the side: both faces and the arms between them.
		var side := right if right.dot(p - other.global_position) > 0.0 else -right
		cam.look_at_from_position(m + f * (4.5 + gap * 0.6) + side * 1.2 + Vector3.UP * 1.7, m + Vector3.UP * 0.85)
	elif kind == "grid":
		cam.look_at_from_position(p + f * 6.5 + right * 1.5 + Vector3.UP * 2.2, p + Vector3.UP * 0.8)
	elif v.leaving != "":
		# Past the line the road ends among trees: from the side over the road, a little ahead.
		var rt = v._leave_seg["route"]
		var s: float = minf(v._leave_ls, rt.length)
		var to_mid: Vector3 = rt.world_at(s, 0.0) - p
		to_mid.y = 0.0
		var side: Vector3 = right if right.dot(to_mid) >= 0.0 else -right
		cam.look_at_from_position(p + f * 2.0 + side * 3.6 + Vector3.UP * 1.5, p + Vector3.UP * 0.85)
	else:
		cam.look_at_from_position(p + f * 4.4 + right * 2.0 + Vector3.UP * 1.7, p + Vector3.UP * 0.85)


func _done() -> bool:
	for k in taken:
		if taken[k] < _want(k):
			return false
	return clip_path == "" or t > limit * 0.5


## Crashes are rare (about one run in forty), so one is enough.
func _want(kind: String) -> int:
	return 1 if kind in ["failed", "flinch"] else want


func _pick() -> void:
	var rr := main.get_node_or_null("RaceReactions")
	if rr != null:
		for e in rr.events:
			match e.type:
				"go":
					if _free("go", e.view):
						_start(e.view, null, "go")
						return
				"overtake":
					if _free("overtake", e.passer):
						_start(e.passer, null, "overtake")
						return
				"alongside":
					if e.gesture >= 0 and _free("alongside", e.by):
						_start(e.by, e.to, "alongside")
						return
				"flinch":
					if _free("flinch", e.view):
						_start(e.view, null, "flinch")
						return
				"finish_together":
					if _free("together", e.views[0]):
						_start(e.views[0], e.views[1], "together")
						return
	for k in main.views:
		var v = main.views[k]
		if v.get_script() != KitRacerView or not v.parked:
			continue
		var go_in := float(int(main.sim.go_tick.get(k, main.sim.tick)) - main.sim.tick) / 60.0
		if v.grid_ready and go_in < 1.1 and go_in > 0.6 and _free("grid", v):
			_start(v, null, "grid")
			return
		if v.grid_t > 0.0 and v.grid_t < v.grid_next and v.toy.reaction_weight() > 0.05 and go_in > 1.6 and _free("fidget", v):
			_start(v, null, "fidget")
			return
	for c in main.get_children():
		if c.get_script() == KitRacerView and c.leaving != "" and _free(c.leaving, c):
			_start(c, null, c.leaving)
			return


func _free(kind: String, v) -> bool:
	return is_instance_valid(v) and taken[kind] < _want(kind) and not (seen.get(v, []) as Array).has(kind)


func _start(v, other, kind: String) -> void:
	if not seen.has(v):
		seen[v] = []
	seen[v].append(kind)
	cur = {"view": v, "other": other, "kind": kind, "at": t + DELAY[kind], "shot": false,
		"until": t + (CLIP_S if clip_path != "" else DELAY[kind]) + (1.0 if kind == "finished" else 0.0)}
	clip_lines.append("%.2f %s" % [t, kind])
	cam.make_current()
	_huds(false)
	if kind == "finished":
		v.toy.gestures.look_at_camera(2.0)  # the finisher waves at the active camera: here, this close-up
