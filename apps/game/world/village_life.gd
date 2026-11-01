extends Node3D
## Village life on the Swiss loop: things that make the village busy, without touching the race.
##  - A crowd of toy racers parked along the roads (start line, main street, church hill, by the
##    mill and the dairy, the square), facing the oncoming karts at an angle. As a kart comes they
##    turn their heads to it; as it goes by they cheer, wave, clap or whoop (and the crowd's cheer
##    plays for the kart the music follows).
##  - Red and white bunting strung across the main street, the start line and the square,
##    fluttering harder in the wind.
##  - Pigeons on the roundabout's island that take off as a kart comes round, circle the fountain
##    and settle again.
##  - Two hot-air balloons drifting over the valley.
## The crowd: the kit's sample racers in mock mode; the session's own racers in server mode (each
## ready racer stands in up to CROWD_COPIES places), nobody until there are some.
## tools/village_life_shots.gd shoots each part close up.
## main.gd builds it with the course and sim, then calls place() once the village plan is laid out
## (the same plan the camera blockers wait for) and add_racer() for each racer of the crowd.

const Course = preload("res://sim/course.gd")
const Route = preload("res://sim/route.gd")
const VillageKit = preload("res://world/village/village_kit.gd")

const CROWD_SEGS := ["start", "hills1", "hills2", "mill", "cobbles", "bends"]
const CROWD_STEP := 5.0          # metres between candidate places along a road
const CROWD_OUT := 2.8           # metres beyond the road's half width a spectator parks
const CROWD_GAP := 15.0          # metres between two groups
const CROWD_GROUPS := 14
const CROWD_PAIR := 2.2          # metres between the two of a group, along the road
const CROWD_COPIES := 3
const CROWD_SEEN_M := 75.0       # spectators further from the camera are not drawn
const LOOK_M := 22.0             # a kart this close: the spectator watches it
const CHEER_M := 9.0             # this close: a cheer, a wave, a clap ...
const CHEER_AGAIN_S := 5.0
const CHEERS := ["cheer", "wave", "clap", "whoop", "fist_pump", "wave"]
const BUNTING := [["start", 6.0], ["hills1", 9.0], ["hills1", 23.0], ["hills1", 37.0], ["cobbles", 14.0],
	["bends", 9.0], ["bends", -22.0]]   # [segment, s (negative: from its end)]
const BUNTING_UP := 5.2          # string height over the road at its ends
const BUNTING_SAG := 0.7
const BUNTING_OUT := 2.3         # poles this far beyond the road's half width
const PENNANT_EVERY := 0.42
const PENNANT_W := 0.3
const PENNANT_H := 0.42
const PENNANT_COLORS := [Color("#e3262f"), Color("#ffffff"), Color("#e3262f"), Color("#ffd23a")]
const PIGEONS := 12
const PIGEON_SIZE := 1.8         # toy pigeons, bigger than life so the chase camera sees them
const PIGEON_SCARE_M := 13.0
const PIGEON_FLY_S := Vector2(6.0, 10.0)
const WING_FOLD := 1.25          # radians: wings folded down along the body on the ground
const BALLOONS := [[Color("#e3262f"), Color("#ffffff")], [Color("#ffd23a"), Color("#2f7de1")]]

const PENNANT_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float wind = 0.0;
varying vec3 col;
void vertex() {
	// UV.x: where along the string (a phase), UV.y: 0 at the string, 1 at the pennant's tip.
	float flap = sin(TIME * (3.5 + wind * 7.0) + UV.x * 9.0);
	VERTEX += NORMAL * flap * (0.04 + wind * 0.2) * UV.y;
	col = COLOR.rgb;
}
void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
"""

const BALLOON_SHADER := """
shader_type spatial;
uniform vec3 a = vec3(1.0, 0.0, 0.0);
uniform vec3 b = vec3(1.0);
void fragment() {
	// Eight gores round the envelope.
	ALBEDO = mod(floor(UV.x * 8.0), 2.0) < 1.0 ? a : b;
	ROUGHNESS = 0.7;
}
"""

var course
var sim
var placed := false
var _slots: Array = []           # {pos: Vector3, yaw: float, group: int, nth (in its group), pid: String, toy: Node3D or null}
var groups: Array = []           # {pos: Vector3, cheered: {runId: secs}} (the shots tool reads them)
var _specs := {}                 # pid -> spec (racers waiting for a place until placed)
var _pennant_mat: ShaderMaterial
var _pigeons: Array = []         # {node, wings: [l, r], home: Vector3, state, t, angle, radius, height}
var pigeon_centre := Vector3.ZERO
var balloons: Array = []         # {node, centre, radius, angle, speed, height}
var _rng := RandomNumberGenerator.new()
## Called with no arguments when a group cheers a kart the music follows (main.gd: the crowd's
## cheer in the audio director).
var on_cheer: Callable
var follow_run := ""


func setup(p_course, p_sim) -> void:
	course = p_course
	sim = p_sim
	_rng.seed = 2026
	_pennant_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = PENNANT_SHADER
	_pennant_mat.shader = sh
	_build_balloons()


## Lays out the crowd's places, the bunting and the pigeons on the village plan (VillagePlan) and
## the terrain (height: Callable(x, z) -> ground y). Returns "" or why it couldn't.
func place(plan, height: Callable) -> String:
	var err := _place_crowd(plan, height)
	if err != "":
		return err
	_build_bunting(plan, height)
	err = _build_pigeons(plan, height)
	if err != "":
		return err
	placed = true
	for pid in _specs.keys():
		_fill(pid)
	var filled := _slots.filter(func(sl): return sl["toy"] != null).size()
	print("village life: %d crowd places in %d groups (%d taken by %d racers), %d pigeons, %d balloons" % [
		_slots.size(), groups.size(), filled, _specs.size(), _pigeons.size(), balloons.size()])
	return ""


## A racer for the crowd (pid: its player, or the sample's file in mock mode). It takes up to
## CROWD_COPIES free places (once the places are laid out).
func add_racer(pid: String, spec: Dictionary) -> void:
	if _specs.has(pid):
		return
	_specs[pid] = spec
	if placed:
		_fill(pid)


## The racers in the crowd (player ids, or sample files in mock mode).
func racers() -> Array:
	return _specs.keys()


## A racer that left the session leaves the crowd.
func remove_racer(pid: String) -> void:
	_specs.erase(pid)
	for sl in _slots:
		if sl["pid"] == pid:
			if sl["toy"] != null:
				(sl["toy"] as Node).queue_free()
			sl["toy"] = null
			sl["pid"] = ""


func _fill(pid: String) -> void:
	var have := 0
	for sl in _slots:
		if sl["pid"] == pid:
			have += 1
	# Every group's first place before any group's second: a racer's copies stand in different groups.
	var order := _slots.duplicate()
	order.sort_custom(func(a, b): return int(a["nth"]) < int(b["nth"]) or (int(a["nth"]) == int(b["nth"]) and int(a["group"]) < int(b["group"])))
	for sl in order:
		if have >= CROWD_COPIES:
			return
		if sl["pid"] != "":
			continue
		var toy: Node3D = RacerBuilder.build(_specs[pid])
		if toy == null:
			push_error("village life: %s's racer could not be built: %s" % [pid, "; ".join(RacerBuilder.last_errors)])
			return
		add_child(toy)
		toy.position = sl["pos"]
		toy.rotation.y = float(sl["yaw"])
		if toy.has_method("show_name_tag"):
			toy.show_name_tag(false)
		_cull(toy)
		sl["pid"] = pid
		sl["toy"] = toy
		have += 1


## Far spectators aren't drawn (each racer is a few dozen small meshes).
func _cull(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		g.visibility_range_end = CROWD_SEEN_M
		g.visibility_range_end_margin = 8.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for c in n.get_children():
		_cull(c)


# ---------------------------------------------------------------- the crowd's places

func _place_crowd(plan, height: Callable) -> String:
	var cands: Array = []        # [seg id, s, side]
	for id in CROWD_SEGS:
		var seg: Dictionary = course.segments.get(id, {})
		if seg.is_empty():
			return "the course has no segment %s for the crowd" % id
		var r: Route = seg["route"]
		var s := 2.0
		while s < r.length - 2.0:
			for side in [-1.0, 1.0]:
				cands.append([id, s, side])
			s += CROWD_STEP
	# Shuffled, then the first free ones far enough from each other.
	for i in range(cands.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = cands[i]
		cands[i] = cands[j]
		cands[j] = t
	for c in cands:
		if groups.size() >= CROWD_GROUPS:
			break
		var seg: Dictionary = course.segments[c[0]]
		var r: Route = seg["route"]
		var out := float(seg["half_width"]) + CROWD_OUT
		var spots: Array = []
		for ds in [-CROWD_PAIR * 0.5, CROWD_PAIR * 0.5]:
			var s := clampf(float(c[1]) + ds, 0.5, r.length - 0.5)
			var p := r.world_at(s, float(c[2]) * out)
			var p2 := Vector2(p.x, p.z)
			if not VillageKit._free(plan, p2, 1.0) or _on_a_road(p2, 0.4):
				spots.clear()
				break
			var y: float = height.call(p.x, p.z)
			if absf(float(height.call(p.x + 1.0, p.z)) - y) > 0.35 or absf(float(height.call(p.x, p.z + 1.0)) - y) > 0.35:
				spots.clear()
				break
			# Facing the oncoming karts, turned a little towards the road (a toy faces -Z).
			var back := -r.tangent_at(s)
			var to_road := -r.normal_at(s) * float(c[2])
			var look := (back + to_road * 0.6).normalized()
			spots.append({"pos": Vector3(p.x, y, p.z), "yaw": atan2(-look.x, -look.z)})
		if spots.is_empty():
			continue
		var centre: Vector3 = (spots[0]["pos"] + spots[1]["pos"]) * 0.5
		var near := false
		for g in groups:
			if (g["pos"] as Vector3).distance_to(centre) < CROWD_GAP:
				near = true
				break
		if near:
			continue
		var gi := groups.size()
		groups.append({"pos": centre, "cheered": {}})
		for k in spots.size():
			_slots.append({"pos": spots[k]["pos"], "yaw": spots[k]["yaw"], "group": gi, "nth": k, "pid": "", "toy": null})
	if groups.is_empty():
		return "no free place for the crowd along %s" % ", ".join(CROWD_SEGS)
	return ""


## Whether ground point p is in any road's drivable corridor grown by `margin` (Course.corridor_half),
## the roundabout's extra circle included.
func _on_a_road(p: Vector2, margin: float) -> bool:
	for id in course.segments:
		var seg: Dictionary = course.segments[id]
		var r: Route = seg["route"]
		var lim := Course.corridor_half(seg) + margin
		var s := 0.0
		while s <= r.length:
			var q := r.pos_at(s)
			# Points 2 m apart: the true distance is at most 1 m below the sampled one.
			if Vector2(q.x, q.z).distance_to(p) < lim + 1.0:
				var t := maxf(0.0, s - 2.0)
				while t <= minf(r.length, s + 2.0):
					var u := r.pos_at(t)
					if Vector2(u.x, u.z).distance_to(p) < lim:
						return true
					t += 0.1
			s += 2.0
	return false


# ---------------------------------------------------------------- bunting

func _build_bunting(plan, height: Callable) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var poles := MeshBatchless.new()
	for bt in BUNTING:
		var seg: Dictionary = course.segments[bt[0]]
		var r: Route = seg["route"]
		var s: float = float(bt[1]) if float(bt[1]) >= 0.0 else r.length + float(bt[1])
		var out := float(seg["half_width"]) + BUNTING_OUT
		var ends: Array[Vector3] = []
		for side in [-1.0, 1.0]:
			var p := r.world_at(s, side * out)
			var g: float = height.call(p.x, p.z)
			ends.append(Vector3(p.x, maxf(g, r.pos_at(s).y) + BUNTING_UP, p.z))
			# A pole where the ground is free (a house wall holds the string otherwise).
			if VillageKit._free(plan, Vector2(p.x, p.z), 0.3):
				poles.add(Vector3(p.x, g, p.z), BUNTING_UP + 0.3)
		_string(st, ends[0], ends[1])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Bunting"
	mi.mesh = st.commit()
	mi.material_override = _pennant_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	add_child(poles.commit())


## A sagging string from a to b with pennants hanging from it.
func _string(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var span := a.distance_to(b)
	var n := int(span / PENNANT_EVERY)
	for i in n:
		var f0 := (i + 0.1) / n
		var f1 := (i + 0.9) / n
		var p0 := _sag(a, b, f0)
		var p1 := _sag(a, b, f1)
		var tip := (p0 + p1) * 0.5 + Vector3.DOWN * PENNANT_H
		var col: Color = PENNANT_COLORS[i % PENNANT_COLORS.size()]
		var ph := float(i) / n
		for v in [[p0, 0.0], [p1, 0.0], [tip, 1.0]]:
			st.set_color(col)
			st.set_uv(Vector2(ph, v[1]))
			st.add_vertex(v[0])
	# The string itself: a thin strip.
	for i in 16:
		var q0 := _sag(a, b, i / 16.0)
		var q1 := _sag(a, b, (i + 1) / 16.0)
		var dn := Vector3.DOWN * 0.03
		for v in [q0, q1, q1 + dn, q0, q1 + dn, q0 + dn]:
			st.set_color(Color(0.25, 0.2, 0.15))
			st.set_uv(Vector2(0.0, 0.0))
			st.add_vertex(v)


static func _sag(a: Vector3, b: Vector3, f: float) -> Vector3:
	return a.lerp(b, f) + Vector3.DOWN * BUNTING_SAG * 4.0 * f * (1.0 - f)


## Wooden poles as one mesh.
class MeshBatchless:
	var st := SurfaceTool.new()
	var n := 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func add(base: Vector3, h: float) -> void:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.08
		cyl.height = h
		cyl.radial_segments = 8
		st.append_from(cyl, 0, Transform3D(Basis(), base + Vector3.UP * h * 0.5))
		n += 1

	func commit() -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.name = "BuntingPoles"
		if n > 0:
			mi.mesh = st.commit()
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.45, 0.3, 0.18)
			m.roughness = 0.9
			mi.material_override = m
		return mi


# ---------------------------------------------------------------- pigeons

func _build_pigeons(plan, height: Callable) -> String:
	var island: PackedVector2Array = plan.square
	if island.size() < 3:
		return "the village plan has no roundabout island for the pigeons"
	var c := Vector2.ZERO
	for q in island:
		c += q
	c /= island.size()
	pigeon_centre = Vector3(c.x, float(height.call(c.x, c.y)), c.y)
	var body_m := StandardMaterial3D.new()
	body_m.albedo_color = Color(0.55, 0.58, 0.66)
	body_m.roughness = 0.8
	var wing_m := StandardMaterial3D.new()
	wing_m.albedo_color = Color(0.45, 0.47, 0.55)
	wing_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var made := 0
	var tries := 0
	while made < PIGEONS and tries < 400:
		tries += 1
		var p := c + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-6.0, 6.0))
		if not Geometry2D.is_point_in_polygon(p, island) or p.distance_to(plan.fountain) < 2.6 or p.distance_to(plan.lime_tree) < 1.4:
			continue
		var bird := Node3D.new()
		var body := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.1
		sm.height = 0.2
		body.mesh = sm
		body.scale = Vector3(0.8, 0.8, 1.5)
		body.position.y = 0.1
		body.material_override = body_m
		bird.add_child(body)
		var head := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.06
		hm.height = 0.12
		head.mesh = hm
		head.position = Vector3(0, 0.2, -0.13)
		head.material_override = body_m
		bird.add_child(head)
		var wings: Array = []
		for side in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.07, 0.14, 0.0)
			var w := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.24, 0.12)
			w.mesh = q
			w.material_override = wing_m
			w.rotation.x = -PI * 0.5
			w.position.x = side * 0.12
			pivot.add_child(w)
			bird.add_child(pivot)
			wings.append(pivot)
		var home := Vector3(p.x, float(height.call(p.x, p.y)) + 0.05, p.y)
		bird.scale = Vector3.ONE * PIGEON_SIZE
		bird.position = home
		bird.rotation.y = _rng.randf() * TAU
		add_child(bird)
		_pigeons.append({"node": bird, "wings": wings, "home": home, "state": "ground", "t": _rng.randf() * 3.0,
			"angle": _rng.randf() * TAU, "radius": _rng.randf_range(6.0, 11.0), "height": _rng.randf_range(5.0, 9.0),
			"fly_s": 0.0})
		made += 1
	if made == 0:
		return "no room on the roundabout island for the pigeons"
	return ""


func _update_pigeons(delta: float) -> void:
	var near := false
	for r in sim.racers:
		var p: Vector3 = r.world_pos()
		if Vector2(p.x - pigeon_centre.x, p.z - pigeon_centre.z).length() < PIGEON_SCARE_M + 8.0:
			near = true
			break
	for b in _pigeons:
		var node: Node3D = b["node"]
		b["t"] = float(b["t"]) + delta
		var t := float(b["t"])
		match String(b["state"]):
			"ground":
				# Pecking: a little bob, now and then a turn.
				node.position = b["home"] + Vector3.UP * maxf(0.0, sin(t * 7.0)) * 0.02
				(b["wings"][0] as Node3D).rotation.z = WING_FOLD
				(b["wings"][1] as Node3D).rotation.z = -WING_FOLD
				if near:
					b["state"] = "fly"
					b["t"] = 0.0
					b["fly_s"] = _rng.randf_range(PIGEON_FLY_S.x, PIGEON_FLY_S.y)
			"fly":
				# Up and round the fountain, wings beating.
				b["angle"] = float(b["angle"]) + delta * 0.9
				var a := float(b["angle"])
				var up := minf(1.0, t / 1.2)
				var target := pigeon_centre + Vector3(cos(a) * float(b["radius"]), float(b["height"]) * up, sin(a) * float(b["radius"]))
				var from: Vector3 = node.position
				node.position = from.lerp(target, minf(1.0, delta * 2.5))
				var dir := node.position - from
				if dir.length() > 0.001:
					node.rotation.y = atan2(-dir.x, -dir.z)
				var beat := sin(t * 22.0) * 0.9
				(b["wings"][0] as Node3D).rotation.z = beat
				(b["wings"][1] as Node3D).rotation.z = -beat
				if t > float(b["fly_s"]) and not near:
					b["state"] = "land"
					b["t"] = 0.0
			"land":
				var home: Vector3 = b["home"]
				node.position = node.position.lerp(home, minf(1.0, delta * 1.6))
				var beat := sin(t * 14.0) * 0.6
				(b["wings"][0] as Node3D).rotation.z = beat
				(b["wings"][1] as Node3D).rotation.z = -beat
				if node.position.distance_to(home) < 0.05:
					node.position = home
					b["state"] = "ground"
					b["t"] = 0.0
				elif near:
					b["state"] = "fly"
					b["t"] = 0.5


# ---------------------------------------------------------------- balloons

func _build_balloons() -> void:
	var sh := Shader.new()
	sh.code = BALLOON_SHADER
	var start: Vector3 = course.segments["start"]["route"].pos_at(0.0)
	for i in BALLOONS.size():
		var root := Node3D.new()
		var env := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 5.0
		sm.height = 12.0
		sm.radial_segments = 32
		env.mesh = sm
		var m := ShaderMaterial.new()
		m.shader = sh
		var cols: Array = BALLOONS[i]
		m.set_shader_parameter("a", Vector3(cols[0].r, cols[0].g, cols[0].b))
		m.set_shader_parameter("b", Vector3(cols[1].r, cols[1].g, cols[1].b))
		env.material_override = m
		root.add_child(env)
		var basket := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 1.2, 1.6)
		basket.mesh = bm
		basket.position.y = -8.5
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.5, 0.33, 0.18)
		basket.material_override = wm
		root.add_child(basket)
		add_child(root)
		balloons.append({"node": root, "centre": start + Vector3(40.0 - 90.0 * i, 0.0, 60.0 + 70.0 * i),
			"radius": 130.0 + 50.0 * i, "angle": 1.3 + 2.7 * i, "speed": 0.012 - 0.004 * i, "height": 85.0 + 25.0 * i})


func _update_balloons(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for b in balloons:
		b["angle"] = float(b["angle"]) + delta * float(b["speed"])
		var a := float(b["angle"])
		(b["node"] as Node3D).position = b["centre"] + Vector3(cos(a) * float(b["radius"]),
			float(b["height"]) + 3.0 * sin(t * 0.15 + a * 5.0), sin(a) * float(b["radius"]))


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if sim == null:
		return
	_pennant_mat.set_shader_parameter("wind", float(sim.weather.wind_strength()))
	_update_balloons(delta)
	if not placed:
		return
	_update_pigeons(delta)
	_update_crowd(delta)


func _update_crowd(delta: float) -> void:
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var cheered: Dictionary = g["cheered"]
		for id in cheered.keys():
			cheered[id] = float(cheered[id]) - delta
			if float(cheered[id]) <= 0.0:
				cheered.erase(id)
		for r in sim.racers:
			var p: Vector3 = r.world_pos()
			var dist := p.distance_to(g["pos"])
			if dist > LOOK_M:
				continue
			var cheer := dist < CHEER_M and not cheered.has(r.run_id)
			if cheer:
				cheered[r.run_id] = CHEER_AGAIN_S
				if r.run_id == follow_run and on_cheer.is_valid():
					on_cheer.call()
			for sl in _slots:
				if int(sl["group"]) != gi or sl["toy"] == null:
					continue
				var toy = sl["toy"]
				toy.look_at_point(p + Vector3.UP * 0.8, 0.4)
				if cheer:
					if _rng.randf() < 0.35:
						toy.celebrate(2)
					else:
						toy.gesture(CHEERS[_rng.randi() % CHEERS.size()])
