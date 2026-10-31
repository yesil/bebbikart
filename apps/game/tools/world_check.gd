extends SceneTree
## Headless checks for the baked world; exits 1 on any failure:
##   godot --headless --path apps/game --script res://tools/world_check.gd
## Fails on:
##   - any scattered instance (ProtonScatter cache or Terrain3D instancer) inside a road corridor
##     (road + SCATTER_CLEAR), in the pond or stream, or in the jump dip
##   - any scattered instance or landmark (decor.tscn) more than GROUND_TOL off the terrain
##   - terrain poking through a road surface (sampled across every road, not under decks)
##   - anything solid inside a road's drivable corridor (Course.corridor_half: the band the sim
##     lets a kart's body reach), from KART_FLOOR to KART_TOP above that road: every mesh of the
##     baked structures and decor (posts, signs, kicker, rails, fences, gantry legs) and every
##     scattered plant or rock, sampled over its triangles. A lane's own rails and ramp
##     (LANE_PARTS) are exempt on that lane only.
##   - sibling road surfaces at different heights (more than SURFACE_TOL) where one lies inside
##     the other's drivable corridor
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
## Height band above a road that a kart occupies: wheels roll over anything lower than
## KART_FLOOR; the driver's head is below KART_TOP.
const KART_FLOOR := 0.15
const KART_TOP := 1.6
## Triangles are sampled at least this densely (metres).
const SAMPLE_STEP := 0.25
const SURFACE_TOL := 0.03
## Node names (or ancestors) that drive with the lane they belong to.
const LANE_PARTS := {
	"Kicker": "ramp_jump", "KickerLip": "ramp_jump", "LandingWedge": "ramp_jump",
	"CausewayRails": "cross_exposed", "CausewayPiers": "cross_exposed",
	"LaneFence": "pond_bridge", "StoneBridge": "pond_bridge",
}
## World nodes that are road surfaces or ground, not obstacles.
const NOT_SOLID := ["Terrain", "Roads", "Water"]

var fails: PackedStringArray = []
var course: Course
var land: Landscape
var shape: TerrainShape
var terrain: Node3D
var corr_box := {}        # segment id -> Rect2 of its corridor (quick reject)
var solid_hits := {}      # "what in which lane" -> [count, example]


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
	_corridor_boxes()
	_check_surfaces()
	_check_solids(world, decor)
	_finish()


func _finish() -> void:
	if fails.is_empty():
		print("WORLD CHECK PASSED")
		quit(0)
		return
	var shown := 0
	for f in fails:
		if shown < 150:
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


# ---------------------------------------------------------------- drivable corridors

func _corridor_boxes() -> void:
	for id in course.ordered_ids:
		var seg: Dictionary = course.segments[id]
		var r: Route = seg["route"]
		var c := Course.corridor_half(seg)
		var box := Rect2(Vector2(r.pos_at(0.0).x, r.pos_at(0.0).z), Vector2.ZERO)
		var s := 0.0
		while s <= r.length:
			box = box.expand(Vector2(r.pos_at(s).x, r.pos_at(s).z))
			s += 1.0
		corr_box[id] = box.grow(c + 1.0)


## [s, lateral distance] of p's perpendicular foot on the segment's centre line, or [] if p
## projects past either end.
func _project(seg: Dictionary, p: Vector2) -> Array:
	var r: Route = seg["route"]
	var best := INF
	var best_s := 0.0
	var s := 0.0
	while s <= r.length:
		var q := r.pos_at(s)
		var dd := Vector2(q.x, q.z).distance_squared_to(p)
		if dd < best:
			best = dd
			best_s = s
		s += 1.0
	var lo := maxf(0.0, best_s - 1.0)
	var hi := minf(r.length, best_s + 1.0)
	s = lo
	while s <= hi:
		var q := r.pos_at(s)
		var dd := Vector2(q.x, q.z).distance_squared_to(p)
		if dd < best:
			best = dd
			best_s = s
		s += 0.05
	if best_s <= 0.05 or best_s >= r.length - 0.05:
		return []
	return [best_s, sqrt(best)]


## True if the segment has no road surface at s (the jump's flight over the pit).
func _in_flight(seg: Dictionary, s: float) -> bool:
	var rp: Dictionary = seg["ramp"]
	return not rp.is_empty() and s > float(rp["lip_s"]) and s < float(rp["land_s"])


## Segment ids whose kart band contains p: [[id, s], ...].
func _corridors_at(p: Vector3) -> Array:
	var out := []
	var xz := Vector2(p.x, p.z)
	for id in course.ordered_ids:
		if not (corr_box[id] as Rect2).has_point(xz):
			continue
		var seg: Dictionary = course.segments[id]
		var pr := _project(seg, xz)
		if pr.is_empty() or float(pr[1]) > Course.corridor_half(seg):
			continue
		var s: float = pr[0]
		var y := course.surface_y(seg, s)
		var top := y + KART_TOP
		if _in_flight(seg, s):
			# Airborne karts sweep everything from the pit up to the arc over it.
			y = (seg["route"] as Route).pos_at(s).y - float(seg["ramp"]["pit_depth"])
			top = (seg["route"] as Route).pos_at(s).y + float(seg["ramp"]["lip_h"]) + KART_TOP
		if p.y > y + KART_FLOOR and p.y < top:
			out.append([id, s])
	return out


## Every road surface sample of one segment inside another segment's corridor must sit at that
## segment's height: karts on either road would otherwise clip the other road's deck.
func _check_surfaces() -> void:
	var samples := 0
	var bad := {}
	for a in course.ordered_ids:
		var sa: Dictionary = course.segments[a]
		var ra: Route = sa["route"]
		var half := Course.surface_half(sa)
		var s := 0.25
		while s < ra.length - 0.25:
			if not _in_flight(sa, s):
				var ya := course.surface_y(sa, s)
				var d := -half
				while d <= half + 0.001:
					var p := ra.world_at(s, d)
					var xz := Vector2(p.x, p.z)
					for b in course.ordered_ids:
						if b == a or not (corr_box[b] as Rect2).has_point(xz):
							continue
						var sb: Dictionary = course.segments[b]
						var pr := _project(sb, xz)
						if pr.is_empty() or float(pr[1]) > Course.corridor_half(sb) or _in_flight(sb, pr[0]):
							continue
						samples += 1
						var dy := ya - course.surface_y(sb, pr[0])
						if absf(dy) > SURFACE_TOL:
							var key := "%s road at s=%d lies in the %s corridor at s=%d" % [a, int(s), b, int(pr[0])]
							if not bad.has(key) or absf(dy) > absf(bad[key]):
								bad[key] = dy
					d += 0.5
			s += 0.5
	for k in bad:
		_fail("%s, %.2f m %s it" % [k, absf(bad[k]), "above" if bad[k] > 0.0 else "below"])
	print("checked %d overlapping road surface samples" % samples)


func _hit(what: String, id: String, s: float, p: Vector3) -> void:
	var key := "%s in the %s corridor" % [what, id]
	if not solid_hits.has(key):
		solid_hits[key] = [0, "s=%.1f at (%.1f, %.1f, %.1f)" % [s, p.x, p.y, p.z]]
	solid_hits[key][0] += 1


## Points covering a triangle soup at least every SAMPLE_STEP metres.
static func _sample_faces(faces: PackedVector3Array, xf: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(0, faces.size(), 3):
		var a := xf * faces[i]
		var b := xf * faces[i + 1]
		var c := xf * faces[i + 2]
		var n := maxi(1, int(ceil(maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) / SAMPLE_STEP)))
		for u in n + 1:
			for v in n + 1 - u:
				out.append(a + (b - a) * (float(u) / n) + (c - a) * (float(v) / n))
	return out


func _test_points(what: String, lane: String, pts: PackedVector3Array) -> void:
	for p in pts:
		for hit in _corridors_at(p):
			if hit[0] != lane:
				_hit(what, hit[0], hit[1], p)


## Solid parts of the baked world and the decor scene, and every scattered plant or rock.
func _check_solids(world: Node, decor: Node) -> void:
	var meshes := 0
	var nodes: Array[MeshInstance3D] = []
	for root in [world, decor]:
		for c in root.get_children():
			if String(c.name) in NOT_SOLID:
				continue
			for mi in c.find_children("*", "MeshInstance3D", true, false):
				nodes.append(mi)
			if c is MeshInstance3D:
				nodes.append(c)
	for mi in nodes:
		if mi.mesh == null or not mi.visible:
			continue
		var lane := ""
		var n: Node = mi
		while n != null and lane == "":
			lane = LANE_PARTS.get(String(n.name), "")
			n = n.get_parent()
		meshes += 1
		_test_points(String(decor.get_path_to(mi)) if decor.is_ancestor_of(mi) else String(world.get_path_to(mi)),
			lane, _sample_faces(mi.mesh.get_faces(), mi.global_transform))
	var inst := _check_scatter_solids(world)
	var keys := solid_hits.keys()
	keys.sort()
	for k in keys:
		_fail("%s: %d samples, e.g. %s" % [k, solid_hits[k][0], solid_hits[k][1]])
	print("checked %d meshes and %d scattered instances against the drivable corridors" % [meshes, inst])


## Scattered instances from the cache, split over each layer's items the way ProtonScatter
## does (child order, count by proportion), tested with their own mesh.
func _check_scatter_solids(world: Node) -> int:
	var cache: Resource = load(CACHE)
	var data: Dictionary = cache.get("data")
	var faces := {}
	var tested := 0
	for node_path in data:
		var sc: Node3D = world.get_node_or_null(NodePath(node_path))
		if sc == null:
			_fail("scatter cache entry %s has no node in the world" % node_path)
			continue
		var list: Array = data[node_path]
		var items: Array = sc.get_children().filter(func(c): return c.get("proportion") != null and c.get("path") != null)
		var total := 0
		for it in items:
			total += int(it.get("proportion"))
		var offset := 0
		for it in items:
			var path: String = it.get("path")
			if not faces.has(path):
				var res: Resource = load(path)
				var mesh: Mesh = res as Mesh
				if res is PackedScene:
					var inst: Node = (res as PackedScene).instantiate()
					var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false).front() if inst is not MeshInstance3D else inst
					mesh = mi.mesh if mi != null else null
					inst.free()
				if mesh == null:
					_fail("scatter item %s/%s: no mesh at %s" % [node_path, it.name, path])
					faces[path] = [PackedVector3Array(), 0.0]
				else:
					var aabb := mesh.get_aabb()
					faces[path] = [mesh.get_faces(), Vector2(maxf(absf(aabb.position.x), absf(aabb.end.x)), maxf(absf(aabb.position.z), absf(aabb.end.z))).length()]
			var count := int(round(float(it.get("proportion")) / total * list.size()))
			for i in count:
				if offset + i >= list.size():
					break
				var t: Transform3D = sc.global_transform * (it.call("process_transform", list[offset + i]) as Transform3D)
				var reach: float = faces[path][1] * t.basis.get_scale().x
				if shape.road_edge_at(t.origin.x, t.origin.z) > reach + 3.0:
					continue
				tested += 1
				_test_points("scatter %s/%s" % [node_path, it.name], "", _sample_faces(faces[path][0], t))
			offset += count
	return tested
