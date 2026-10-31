extends SceneTree
## Headless checks for the baked world; exits 1 on any failure:
##   godot --headless --path apps/game --script res://tools/world_check.gd
## Fails on:
##   - any scattered instance (ProtonScatter cache or Terrain3D instancer) inside a road corridor
##     (road + SCATTER_CLEAR), in the pond or stream, or in the jump dip
##   - any scattered instance or landmark (decor.tscn) more than GROUND_TOL off the terrain
##   - terrain poking through a road surface (sampled across every road, not under decks)
##   - a missing dependency of the world, decor or lighting scenes

const Course = preload("res://sim/course.gd")
const Route = preload("res://sim/route.gd")
const Landscape = preload("res://world/landscape.gd")
const TerrainShape = preload("res://world/terrain_shape.gd")

const SCENES := ["res://world/course_world.tscn", "res://world/decor.tscn", "res://world/environment.tscn"]
const CACHE := "res://world/vegetation/scatter_cache.res"
const GROUND_TOL := 0.3
## Top-level decor nodes that stand on the ground (their origin must sit on the terrain).
const GROUNDED := ["Signpost_", "Flag_", "Grandstand"]

var fails: PackedStringArray = []
var course: Course
var land: Landscape
var shape: TerrainShape
var terrain: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _fail(msg: String) -> void:
	fails.append(msg)


func _run() -> void:
	for p in SCENES:
		_check_deps(p)
	if not fails.is_empty():
		_finish()
		return
	course = Course.new()
	land = Landscape.new(course)
	shape = TerrainShape.new(course, land)
	shape.build()
	var world: Node3D = (load(SCENES[0]) as PackedScene).instantiate()
	get_root().add_child(world)
	var decor: Node3D = (load(SCENES[1]) as PackedScene).instantiate()
	get_root().add_child(decor)
	for i in 5:
		await process_frame
	terrain = world.get_node_or_null("Terrain")
	if terrain == null:
		_fail("course_world.tscn has no Terrain")
		_finish()
		return
	_check_scatter_cache()
	_check_instancer()
	_check_roads()
	_check_decor(decor)
	_finish()


func _finish() -> void:
	if fails.is_empty():
		print("WORLD CHECK PASSED")
		quit(0)
		return
	var shown := 0
	for f in fails:
		if shown < 40:
			print("  FAIL ", f)
		shown += 1
	print("WORLD CHECK FAILED: %d problems" % fails.size())
	quit(1)


func _check_deps(path: String, seen := {}) -> void:
	if seen.has(path):
		return
	seen[path] = true
	if not ResourceLoader.exists(path):
		_fail("missing asset: %s" % path)
		return
	for dep in ResourceLoader.get_dependencies(path):
		var p: String = dep.get_slice("::", dep.get_slice_count("::") - 1)
		if p.begins_with("uid://"):
			var id := ResourceUID.text_to_id(p)
			if not ResourceUID.has_id(id):
				_fail("missing asset (unknown uid %s) used by %s" % [p, path])
				continue
			p = ResourceUID.get_id_path(id)
		_check_deps(p, seen)


## Height of the rendered terrain surface (get_surface_height follows the mesh triangles; plain
## get_height interpolates the height grid and differs by up to ~0.9 m on steep slopes).
func _ground(p: Vector3) -> float:
	return float(terrain.get("data").call("get_surface_height", p))


## Why a scattered plant/rock may not be at p, or "" if it may.
func _placement_problem(p: Vector3) -> String:
	var e := shape.road_edge_at(p.x, p.z)
	if e < 0.5:
		return "on a road (%.1f m from the edge)" % e
	var q := Vector2(p.x, p.z)
	if land.in_pond(q):
		return "in the pond"
	if land.stream_dist(q) < Landscape.STREAM_HALF_WIDTH:
		return "in the stream"
	var dy := p.y - _ground(p)
	if absf(dy) > GROUND_TOL:
		return "%.2f m %s the terrain" % [absf(dy), "above" if dy > 0.0 else "below"]
	return ""


func _check_scatter_cache() -> void:
	var cache: Resource = load(CACHE)
	if cache == null:
		_fail("missing scatter cache %s" % CACHE)
		return
	var total := 0
	var data: Dictionary = cache.get("data")
	for node_path in data:
		for t: Transform3D in data[node_path]:
			total += 1
			var why := _placement_problem(t.origin)
			if why != "":
				_fail("scatter %s at (%.1f, %.1f, %.1f): %s" % [node_path, t.origin.x, t.origin.y, t.origin.z, why])
	print("checked %d scattered instances" % total)


func _check_instancer() -> void:
	var data: Object = terrain.get("data")
	var rs: int = int(terrain.get("region_size"))
	var total := 0
	for region in data.call("get_regions_active"):
		var loc: Vector2i = region.get("location")
		var inst: Dictionary = region.get("instances")
		for mesh_id in inst:
			var cells: Dictionary = inst[mesh_id]
			for cell in cells:
				for t: Transform3D in cells[cell][0]:
					total += 1
					var p := t.origin + Vector3(loc.x * rs, 0, loc.y * rs)
					var why := _placement_problem(p)
					if why != "":
						_fail("ground cover mesh %d at (%.1f, %.1f, %.1f): %s" % [mesh_id, p.x, p.y, p.z, why])
	print("checked %d ground-cover instances" % total)


## Terrain must stay under every road surface (except where the road is a deck over open
## ground: the stone bridge and the causeway, and the jump's flight over the dip).
func _check_roads() -> void:
	var samples := 0
	for id in course.ordered_ids:
		var seg: Dictionary = course.segments[id]
		var r: Route = seg["route"]
		var hw: float = seg["half_width"]
		var s := 0.5
		while s < r.length - 0.5:
			var target := shape.corridor_target(seg, s)
			var rp: Dictionary = seg["ramp"]
			var in_flight: bool = not rp.is_empty() and s > float(rp["kick_a"]) and s < float(rp["land_s"])
			if not is_nan(target) and not in_flight:
				var y := r.pos_at(s).y
				for k in 5:
					var d := lerpf(-hw + 0.3, hw - 0.3, k / 4.0)
					var p := r.world_at(s, d)
					var g := _ground(p)
					samples += 1
					if g > y + 0.02 and not _covered(p, g, id):
						_fail("terrain %.2f m above the %s road at s=%.1f d=%.1f" % [g - y, id, s, d])
			s += 1.0
	print("checked %d road surface samples" % samples)


## True if p lies on another road whose surface is at or above the ground there: in a Y-split
## the detour is drawn over the direct road, so ground under it can't show through.
func _covered(p: Vector3, g: float, except: String) -> bool:
	for id in course.ordered_ids:
		if id == except:
			continue
		var seg: Dictionary = course.segments[id]
		var r: Route = seg["route"]
		var best := INF
		var best_s := 0.0
		var s := 0.0
		while s <= r.length:
			var q := r.pos_at(s)
			var dd := Vector2(q.x - p.x, q.z - p.z).length()
			if dd < best:
				best = dd
				best_s = s
			s += 0.5
		if best <= float(seg["half_width"]) and r.pos_at(best_s).y >= g - 0.02:
			return true
	return false


func _check_decor(decor: Node) -> void:
	var n := 0
	var nodes: Array[Node3D] = []
	for c in decor.get_children():
		if GROUNDED.any(func(g): return String(c.name).begins_with(g)):
			nodes.append(c)
	var posts := decor.get_node_or_null("FordPosts")
	if posts != null:
		for c in posts.get_children():
			nodes.append(c)
	for node in nodes:
		var p := node.global_position
		if node.get_parent() == posts:
			p.y -= 0.4  # node = post centre: 1.6 m post sunk 0.4 m on purpose, so centre is 0.4 m up
		var dy := p.y - _ground(p)
		n += 1
		if absf(dy) > GROUND_TOL:
			_fail("decor %s is %.2f m %s the terrain" % [decor.get_path_to(node), absf(dy), "above" if dy > 0.0 else "below"])
	print("checked %d grounded landmarks" % n)
