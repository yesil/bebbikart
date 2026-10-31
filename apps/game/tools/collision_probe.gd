extends SceneTree
## Drives a crowd through the real baked world and measures where karts pass through things:
##   godot --path apps/game --resolution 160x90 --script res://tools/collision_probe.gd -- --track=village
## Not headless: the dummy renderer forgets MultiMesh transforms (every scattered tree, house and
## prop would read back at the origin), so it opens a small window.
## Every obstacle mesh of the world and decor (buildings, props, trees, rails, gantries) gets a
## trimesh collider; every few ticks each kart's body box is tested against them, its wheels
## against the terrain, and every pair of karts against each other.
## Flags: --track=countryside|village --seconds=N (sim time) --racers=N --seed=N --every=N (ticks)
##        --weather=calm|rain|wind|storm --max=N (problems listed) --strict (exit 1 on any hit)

const Course = preload("res://sim/course.gd")
const VillageCourse = preload("res://sim/village_course.gd")
const Sim = preload("res://sim/sim.gd")
const Racer = preload("res://sim/racer.gd")
const Builds = preload("res://sim/builds.gd")
const Messages = preload("res://net/messages.gd")
const Tuning = preload("res://sim/tuning.gd")

const SCENES := {
	"countryside": ["res://world/course_world.tscn", "res://world/decor.tscn"],
	"village": ["res://world/village/village_world.tscn", "res://world/village/village_decor.tscn"],
}
## Kart body (placeholder racer_view.gd chassis; the kit rides are about the same size), as half
## extents. The box starts BODY_LIFT above the wheels' contact point so the deck it drives on
## doesn't count.
const HALF := Vector3(0.5, 0.35, 0.75)
const BODY_LIFT := 0.25
## Things the kart drives on or through on purpose.
const SKIP_PREFIX := ["Terrain", "Roads", "Water", "StartLine", "FinishLine", "Flower", "Gables"]
const SURFACES := ["Kicker", "KickerLip", "LandingWedge", "CausewayPiers", "Square"]
const WEATHERS := {"calm": [0.0, 0.0], "rain": [1.0, 0.0], "wind": [0.0, 0.8], "storm": [1.0, 0.8]}

var args := {}
var track := "countryside"
var course
var terrain: Node
var space: RID
var box := BoxShape3D.new()
var owners := {}          # collider RID -> obstacle name
var shapes: Array[Shape3D] = []  # keeps the shape resources (and their RIDs) alive
var hits := {}            # kind -> {count, samples: []}
var kart_ticks := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	track = String(args.get("track", "countryside"))
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("collision_probe: run it without --headless (MultiMesh transforms read back as identity)")
		quit(2)
		return
	if not SCENES.has(track):
		push_error("unknown track %s" % track)
		quit(2)
		return
	course = VillageCourse.new() if track == "village" else Course.new()
	for p in SCENES[track]:
		if p.ends_with("village_decor.tscn") and not ResourceLoader.exists(p):
			continue  # optional, as in main.gd
		if not ResourceLoader.exists(p):
			push_error("collision_probe: %s is missing" % p)
			quit(2)
			return
		get_root().add_child((load(p) as PackedScene).instantiate())
	for i in 5:
		await process_frame
	terrain = get_root().find_child("Terrain", true, false)
	if terrain == null:
		push_error("collision_probe: no Terrain in the world")
		quit(2)
		return
	space = get_root().get_world_3d().space
	var n := _add_colliders(get_root())
	print("colliders: %d obstacle bodies" % n)
	await physics_frame
	await physics_frame
	box.size = HALF * 2.0
	_drive()
	_report()


# ---------------------------------------------------------------- colliders

func _add_colliders(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		if SKIP_PREFIX.any(func(p): return String(c.name).begins_with(p)):
			continue
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and (c as MeshInstance3D).visible:
			n += _body(c.name, (c as MeshInstance3D).mesh, (c as MeshInstance3D).global_transform)
		elif c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh != null:
			var mm := (c as MultiMeshInstance3D).multimesh
			if mm.mesh == null:
				continue
			var gt := (c as MultiMeshInstance3D).global_transform
			var shape := mm.mesh.create_trimesh_shape()
			var count := mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
			for i in count:
				n += _body_shape(_label(c), shape, gt * mm.get_instance_transform(i))
		n += _add_colliders(c)
	return n


## "Vegetation/Woodland/Pine_1" style name for scattered nodes, plain name otherwise.
func _label(c: Node) -> String:
	var p := c.get_parent()
	if p != null and p.get_parent() != null and String(p.name) != "Buildings" and String(p.name) != "Props":
		return "%s/%s" % [p.name, c.name]
	return String(c.name)


func _body(name: String, mesh: Mesh, xf: Transform3D) -> int:
	return _body_shape(name, mesh.create_trimesh_shape(), xf)


func _body_shape(name: String, shape: Shape3D, xf: Transform3D) -> int:
	if shape == null:
		return 0
	shapes.append(shape)
	var b := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(b, shape.get_rid())
	PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer3D.body_set_space(b, space)
	owners[b] = name
	return 1


# ---------------------------------------------------------------- drive

func _drive() -> void:
	var cfg: Dictionary = Messages.default_config()
	if track == "village":
		cfg["lapsPerRun"] = 2
	var seed_ := int(args.get("seed", "7"))
	var sim := Sim.new(course, cfg, seed_)
	var w: Array = WEATHERS[String(args.get("weather", "calm"))]
	sim.weather.force(w[0], w[1], 40.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var racers := int(args.get("racers", "20"))
	var ticks := int(float(args.get("seconds", "150")) * 60.0)
	var every := int(args.get("every", "3"))
	var launched := 0
	var pdss := PhysicsServer3D.space_get_direct_state(space)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collide_with_areas = false
	var q2 := PhysicsShapeQueryParameters3D.new()
	q2.shape = box
	for t in ticks:
		if sim.active_count() < racers and t % 30 == 0:
			sim.add_run("r%d" % launched, "p%d" % launched, Builds.random_build(rng), Tuning.DEFAULT_SIZE)
			launched += 1
		for o in sim.racers:
			var r: Racer = o
			if r.boosts_left > 0 and r.boost_t <= 0.0 and not r.airborne and Course.in_ranges(r.seg["boosts"], r.ls):
				r.boost(sim)
		sim.step()
		sim.outbox.clear()
		if t % every != 0:
			continue
		var list: Array = sim.racers
		for i in list.size():
			var r: Racer = list[i]
			kart_ticks += 1
			var xf := _kart_xf(r)
			# Body vs obstacles.
			q.transform = xf * Transform3D(Basis(), Vector3(0, BODY_LIFT + HALF.y, 0))
			for h in pdss.intersect_shape(q, 8):
				var name: String = owners.get(h["rid"], "")
				if name == "":
					name = String(h["collider"].name) if h["collider"] != null else "?"  # Terrain3D's own collision
				var lift := 0.35 if SURFACES.has(name) else 0.0
				if lift > 0.0:
					# A drivable structure: only count it if it is in the body well above the wheels.
					q2.transform = xf * Transform3D(Basis(), Vector3(0, BODY_LIFT + lift + HALF.y, 0))
					if pdss.intersect_shape(q2, 1).is_empty():
						continue
				_hit("obstacle " + name, r, "")
			# Wheels vs terrain.
			var worst := -INF
			for c in [Vector3(-HALF.x, 0, -HALF.z), Vector3(HALF.x, 0, -HALF.z), Vector3(-HALF.x, 0, HALF.z), Vector3(HALF.x, 0, HALF.z)]:
				var p: Vector3 = xf * c
				var g := float(terrain.get("data").call("get_surface_height", p))
				if not is_nan(g):
					worst = maxf(worst, g - p.y)
			if worst > BODY_LIFT:
				_hit("terrain above the wheels", r, "%.2f m" % worst)
			# Kart vs kart.
			for j in range(i + 1, list.size()):
				var o: Racer = list[j]
				var a := r.world_pos()
				var b := o.world_pos()
				if absf(a.y - b.y) > 0.9:
					continue
				var rel := xf.affine_inverse() * b
				if absf(rel.x) < HALF.x * 2.0 - 0.1 and absf(rel.z) < HALF.z * 2.0 - 0.1:
					var kind := "kart overlap, same piece" if r.seg_id == o.seg_id else "kart overlap, different pieces"
					_hit(kind, r, "%s(%s) vs %s(%s)" % [r.run_id, r.seg_id, o.run_id, o.seg_id])


func _kart_xf(r: Racer) -> Transform3D:
	var b := Basis.from_euler(Vector3(r.pitch(), r.yaw(), r.roll()), EULER_ORDER_YXZ)
	return Transform3D(b, r.world_pos())


func _hit(kind: String, r: Racer, extra: String) -> void:
	if not hits.has(kind):
		hits[kind] = {"count": 0, "spots": {}}
	var h: Dictionary = hits[kind]
	h["count"] = int(h["count"]) + 1
	# Bucket by segment and 5 m of road.
	var key := "%s s=%d" % [r.seg_id, int(r.ls / 5.0) * 5]
	if not h["spots"].has(key):
		var p := r.world_pos()
		h["spots"][key] = {"n": 0, "ex": "d=%.2f hw=%.1f air=%s pos=(%.1f,%.1f,%.1f) %s" % [r.d, r.half_width(), r.airborne, p.x, p.y, p.z, extra]}
	h["spots"][key]["n"] = int(h["spots"][key]["n"]) + 1


func _report() -> void:
	print("== %s: %d kart samples ==" % [track, kart_ticks])
	var maxn := int(args.get("max", "12"))
	var total := 0
	for kind in hits:
		var h: Dictionary = hits[kind]
		total += int(h["count"])
		print("%-40s %6d samples (%.2f%%)" % [kind, h["count"], 100.0 * h["count"] / maxf(1, kart_ticks)])
		var spots: Array = h["spots"].keys()
		spots.sort_custom(func(a, b): return int(h["spots"][a]["n"]) > int(h["spots"][b]["n"]))
		for k in spots.slice(0, maxn):
			print("    %5d  %-24s %s" % [h["spots"][k]["n"], k, h["spots"][k]["ex"]])
	if total == 0:
		print("COLLISION PROBE CLEAN")
	quit(1 if total > 0 and args.has("strict") else 0)
