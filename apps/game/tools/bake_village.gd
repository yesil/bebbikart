extends SceneTree
## Bakes the village loop world from sim/village_course.gd + world/village/village_plan.gd:
##   godot --headless --path apps/game --script res://tools/bake_village.gd [-- --only=terrain,roads,...]
##
## Writes res://world/village/village_world.tscn (never touches village_decor.tscn, which is for
## hand edits, nor anything of the countryside course). Stages:
##   terrain     Terrain3D heights + texture layers (world/village/village_terrain.gd), saved to
##               res://world/village/terrain_data/ with its own material and texture assets.
##   roads       Road Generator containers following the sim centre lines (shared road materials
##               from res://world/materials/).
##   water       Duck pond and brook surfaces.
##   structures  Ski-jump kicker and landing wedge, causeway piers and rails.
##   buildings   Every building of the plan and the covered bridge: a Houses node
##               (world/village/village_houses.gd) keeping a few numbers per building, from
##               which world/village/chalet_builder.gd builds their geometry at load; plus
##               the Kenney props they keep (stalls, banners, the water wheel).
##   props       Fountain, lime tree, fences, flower boxes, lanterns, benches, signposts,
##               orchard, alpine trees, hay bales.
## Re-run after editing the course or the plan; tools/village_world_check.gd checks the result.

const VillageCourse = preload("res://sim/village_course.gd")
const VillagePlan = preload("res://world/village/village_plan.gd")
const VillageTerrain = preload("res://world/village/village_terrain.gd")
const VillageKit = preload("res://world/village/village_kit.gd")
const Course = preload("res://sim/course.gd")
const Route = preload("res://sim/route.gd")
const MeshBatch = preload("res://world/mesh_batch.gd")
const InstancedModel = preload("res://world/village/instanced_model.gd")
const VillageHouses = preload("res://world/village/village_houses.gd")

const SCENE_PATH := "res://world/village/village_world.tscn"
const BAKED := &"baked"
const DIR := "res://world/village/"
const TERRAIN_DIR := "res://world/village/terrain_data"
const TERRAIN_MATERIAL := "res://world/village/terrain_material.tres"
const TERRAIN_ASSETS := "res://world/village/terrain_assets.tres"
const TEX_DIR := "res://assets/textures/terrain/"
const MAT_DIR := "res://world/materials/"
const VMAT_DIR := "res://world/village/materials/"
const BAKED_DIR := "res://world/village/baked/"
## Village copies of shared road materials: the asphalt's stones and red flecks stood out in the
## village's low alpine sun, so its copy is calmer (flatter relief, softer grain, grey).
const VILLAGE_ROAD := {"road_asphalt": VMAT_DIR + "road_asphalt.tres"}
## Per layer: tiling (uv_scale) and tint (lusher alpine grass than the countryside).
const LAYER_LOOK := {
	"grass": [0.12, Color(0.78, 0.9, 0.62)],
	"grass_dirt": [0.14, Color(0.85, 0.92, 0.7)],
	"dirt": [0.2, Color(1.0, 0.95, 0.88)],
	"gravel": [0.35, Color(0.95, 0.95, 0.95)],
	"mud": [0.25, Color(0.8, 0.72, 0.62)],
	"rock": [0.06, Color(1.15, 1.1, 1.04)],    # pale limestone, like the Alps over a valley
	"snow": [0.08, Color(2.2, 2.25, 2.4)],
}
## Snow reuses the gravel textures, brightened (no extra texture download).
const LAYER_TEXTURE := {"snow": "gravel"}

var course: VillageCourse
var plan: VillagePlan
var shape: VillageTerrain
var world: Node3D
var stages: PackedStringArray = ["terrain", "roads", "water", "structures", "buildings", "props"]
var failed := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			stages = a.trim_prefix("--only=").split(",")
	_bake.call_deferred()


func _bake() -> void:
	var t0 := Time.get_ticks_msec()
	course = VillageCourse.new()
	if not course.errors.is_empty():
		push_error("bake: the village course is broken: %s" % "; ".join(course.errors))
		quit(1)
		return
	plan = VillagePlan.new(course)
	if not plan.errors.is_empty():
		push_error("bake: the village plan is broken: %s" % "; ".join(plan.errors))
		quit(1)
		return
	shape = VillageTerrain.new(course, plan)
	shape.build()
	print("bake: terrain shape %dx%d in %d ms" % [shape.w, shape.h, Time.get_ticks_msec() - t0])
	for d in [VMAT_DIR, BAKED_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	world = _load_or_new()
	get_root().add_child(world)
	await process_frame
	if "terrain" in stages:
		await _bake_terrain()
	if "roads" in stages:
		await _bake_roads()
	if "water" in stages:
		_bake_water()
	if "structures" in stages:
		_bake_structures()
	if "buildings" in stages:
		_bake_buildings()
	if "props" in stages:
		_bake_props()
	if failed:
		push_error("bake: errors above, %s NOT saved" % SCENE_PATH)
		quit(1)
		return
	_own(world, world)
	# Instanced models build their MultiMesh on load; don't bake it into the scene.
	for n in world.find_children("*", "MultiMeshInstance3D", true, false):
		(n as MultiMeshInstance3D).multimesh = null
		(n as MultiMeshInstance3D).material_override = null
	var packed := PackedScene.new()
	var err := packed.pack(world)
	if err != OK:
		push_error("bake: pack failed (%d)" % err)
		quit(1)
		return
	err = ResourceSaver.save(packed, SCENE_PATH)
	if err != OK:
		push_error("bake: saving %s failed (%d)" % [SCENE_PATH, err])
		quit(1)
		return
	print("bake: saved %s in %.1f s" % [SCENE_PATH, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)


## Loads a resource or stops the bake: a missing asset is an error, never a silent null.
func _res(path: String) -> Resource:
	var r: Resource = load(path) if ResourceLoader.exists(path) else null
	if r == null:
		_fail("missing resource %s" % path)
	return r


func _fail(msg: String) -> void:
	push_error("bake: " + msg)
	failed = true


func _load_or_new() -> Node3D:
	if ResourceLoader.exists(SCENE_PATH):
		return (load(SCENE_PATH) as PackedScene).instantiate() as Node3D
	var n := Node3D.new()
	n.name = "VillageWorld"
	return n


func _replace(name: String, node: Node) -> Node:
	var old := world.get_node_or_null(name)
	if old != null:
		world.remove_child(old)
		old.free()
	node.name = name
	_mark(node)
	world.add_child(node)
	return node


## Only nodes the bake created (tagged with _mark) are saved; plugin-generated children are
## rebuilt by the plugins. Instanced model scenes are saved as instances.
func _own(node: Node, owner_: Node) -> void:
	for c in node.get_children():
		if not c.has_meta(BAKED):
			continue
		c.owner = owner_
		if c.scene_file_path == "":
			_own(c, owner_)


func _mark(node: Node) -> Node:
	node.set_meta(BAKED, true)
	return node


# ---------------------------------------------------------------- terrain

func _bake_terrain() -> void:
	var t0 := Time.get_ticks_msec()
	var terrain: Node3D = ClassDB.instantiate("Terrain3D")
	var mat: Resource = ClassDB.instantiate("Terrain3DMaterial")
	mat.set("world_background", 2)          # NOISE: endless hills outside the baked map
	mat.set("macro_variation_enabled", true)
	mat.set("dual_scaling_enabled", false)
	ResourceSaver.save(mat, TERRAIN_MATERIAL)
	var assets: Resource = ClassDB.instantiate("Terrain3DAssets")
	for i in VillageTerrain.LAYER_NAMES.size():
		var lname: String = VillageTerrain.LAYER_NAMES[i]
		var ta: Resource = ClassDB.instantiate("Terrain3DTextureAsset")
		ta.set("name", lname)
		var tname: String = LAYER_TEXTURE.get(lname, lname)
		ta.set("albedo_texture", _res(TEX_DIR + tname + "_albedo_height.webp"))
		ta.set("normal_texture", _res(TEX_DIR + tname + "_normal_rough.webp"))
		ta.set("uv_scale", LAYER_LOOK[lname][0])
		ta.set("albedo_color", LAYER_LOOK[lname][1])
		ta.set("detiling_rotation", 0.3)
		ta.set("detiling_shift", 0.3)
		assets.call("set_texture_asset", i, ta)
	ResourceSaver.save(assets, TERRAIN_ASSETS)
	terrain.set("material", _res(TERRAIN_MATERIAL))
	terrain.set("assets", _res(TERRAIN_ASSETS))
	var dir := ProjectSettings.globalize_path(TERRAIN_DIR)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.make_dir_recursive_absolute(dir)
	terrain.set("data_directory", TERRAIN_DIR)
	_replace("Terrain", terrain)
	await process_frame
	var data: Object = terrain.get("data")
	var img := Image.create(shape.w, shape.h, false, Image.FORMAT_RF)
	for j in shape.h:
		for i in shape.w:
			img.set_pixel(i, j, Color(shape.heights[j * shape.w + i], 0, 0))
	data.call("import_images", [img, null, null], Vector3(shape.rect.position.x, 0, shape.rect.position.y), 0.0, 1.0)
	for j in shape.h:
		for i in shape.w:
			var k := j * shape.w + i
			var p := Vector3(shape.rect.position.x + i * shape.spacing, 0, shape.rect.position.y + j * shape.spacing)
			data.call("set_control_base_id", p, shape.base_id[k])
			data.call("set_control_overlay_id", p, shape.overlay_id[k])
			data.call("set_control_blend", p, shape.blend[k])
	data.call("update_maps", 3, true, false)
	data.call("calc_height_range", true)
	data.call("save_directory", TERRAIN_DIR)
	print("bake: terrain imported + painted in %d ms" % (Time.get_ticks_msec() - t0))


# ---------------------------------------------------------------- roads

const ROAD_STEP := 6.0
const TAPER := 10.0
## Route pieces: [container name, segment id, s0 or -1 (start), s1 or -1 (end), material, deck thickness]
const ROAD_PIECES := [
	["start", "start", -1, -1, "road_ford", -1.0],
	["hills1", "hills1", -1, -1, "road_asphalt", -1.0],
	# The run-up stops where the kicker starts: no road edge left standing above the pit.
	["ramp_jump_run_up", "ramp_jump", "jin", "kick", "road_asphalt", -1.0],
	["ramp_jump_landing", "ramp_jump", "land", "jout", "road_asphalt", -1.0],
	["ramp_around", "ramp_around", "jin", "jout", "road_dirt_detour", -1.0],
	["hills2", "hills2", -1, -1, "road_asphalt", -1.0],
	# The fork's shared stretches reach past the water's edge, so the ford runs junction to junction.
	["pond_ford", "pond_water", "jin", "jout", "road_ford", -1.0],
	["pond_bridge_in", "pond_bridge", "jin", "deck_in", "road_asphalt", -1.0],
	["pond_bridge_deck", "pond_bridge", "deck_in", "deck_out", "road_planks", 0.45],
	["pond_bridge_out", "pond_bridge", "deck_out", "jout", "road_asphalt", -1.0],
	["mill", "mill", -1, -1, "road_asphalt", -1.0],
	["farm", "farm", -1, -1, "road_dirt_detour", -1.0],
	["cobbles", "cobbles", -1, -1, "road_ford", -1.0],
	["ridge", "ridge", -1, -1, "road_asphalt", -1.0],
	["alpbach_in", "alpbach", -1, "water_in", "road_asphalt", -1.0],
	["alpbach_ford", "alpbach", "water_in", "water_out", "road_ford", -1.0],
	["alpbach_out", "alpbach", "water_out", -1, "road_asphalt", -1.0],
	["cross_exposed_in", "cross_exposed", "jin", "causeway_in", "road_planks", -1.0],
	["cross_exposed", "cross_exposed", "causeway_in", "causeway_out", "road_planks", 0.35],
	["cross_exposed_out", "cross_exposed", "causeway_out", "jout", "road_planks", -1.0],
	["cross_sheltered", "cross_sheltered", "jin", "jout", "road_ford", -1.0],
	# One road straight through the roundabout: no join where the race enters or leaves the
	# ring. The ring (_roundabout) draws only the part of the circle the race doesn't drive.
	["bends", "bends", -1, -1, "road_asphalt", -1.0],
]


## Fork junctions: [direct branch, detour branch, material of the shared surface]. Near each
## split and merge the two branches overlap; that stretch is ONE road (_junction_pieces) whose
## edges follow the union of both branches, and each branch's own road starts only where it
## has left the other ("jin") and ends where it meets it again ("jout"). No coplanar overlap.
const FORKS := [
	["ramp_jump", "ramp_around", "road_asphalt"],
	["pond_water", "pond_bridge", "road_asphalt"],
	["cross_exposed", "cross_sheltered", "road_planks"],
]
const JUNCTION_STEP := 1.0
var _junction := {}   # fork direct id -> [split length, merge length] along both branches


## Metres from a fork's split (or merge) until the two branches no longer overlap.
func _junction_lengths() -> void:
	for f in FORKS:
		var a: Dictionary = course.segments[f[0]]
		var b: Dictionary = course.segments[f[1]]
		var ra: Route = a["route"]
		var rb: Route = b["route"]
		var need: float = float(a["half_width"]) + float(b["half_width"]) + 0.6
		var lens := []
		for from_end in [false, true]:
			var s := 0.0
			while s < minf(ra.length, rb.length) * 0.5:
				var pa := ra.pos_at(ra.length - s if from_end else s)
				var pb := rb.pos_at(rb.length - s if from_end else s)
				if Vector2(pa.x - pb.x, pa.z - pb.z).length() >= need:
					break
				s += 0.5
			lens.append(s)
		print("bake: fork %s junctions %.1f m / %.1f m" % [f[0], lens[0], lens[1]])
		_junction[f[0]] = lens
		_junction[f[1]] = lens


## The shared stretches at each fork's split and merge, as single roads covering both branches.
func _junction_pieces(mgr: Node) -> void:
	for f in FORKS:
		var a: Dictionary = course.segments[f[0]]
		var b: Dictionary = course.segments[f[1]]
		var ra: Route = a["route"]
		var rb: Route = b["route"]
		var lens: Array = _junction[f[0]]
		for end in [0, 1]:
			var length: float = lens[end]
			var pts: Array = []
			var n := maxi(2, int(ceil(length / JUNCTION_STEP)))
			for i in n + 1:
				var t := length * i / n
				var sa := t if end == 0 else ra.length - length + t
				var sb := t if end == 0 else rb.length - length + t
				var ca := ra.pos_at(sa)
				var nrm := ra.normal_at(sa)
				var off := (rb.pos_at(sb) - ca).dot(nrm)
				var lo := minf(-road_hw(a, sa), off - road_hw(b, sb))
				var hi := maxf(road_hw(a, sa), off + road_hw(b, sb))
				var dir := (ra.pos_at(minf(sa + 0.5, ra.length)) - ra.pos_at(maxf(sa - 0.5, 0.0))).normalized()
				pts.append([ca + nrm * (lo + hi) * 0.5, dir, hi - lo, 0.45])
			_container(mgr, "%s_%s" % [f[0], "split" if end == 0 else "merge"], f[2], -1.0, pts)


## One Road Generator container through points [position, direction, width, shoulder].
func _container(mgr: Node, name: String, material: String, thickness: float, pts: Array) -> void:
	var cont := RoadContainer.new()
	cont.name = name
	_mark(cont)
	cont.flatten_terrain = false
	cont.material_resource = _road_material(material)
	cont.underside_thickness = thickness
	mgr.add_child(cont)
	var prev: RoadPoint = null
	for i in pts.size():
		var rp := RoadPoint.new()
		rp.name = "RP_%03d" % i
		_mark(rp)
		cont.add_child(rp)
		rp.transform = Transform3D(Basis.looking_at(-(pts[i][1] as Vector3), Vector3.UP), pts[i][0])
		rp.auto_lanes = false
		rp.traffic_dir = [RoadPoint.LaneDir.FORWARD]
		rp.lanes = [RoadPoint.LaneType.ONE_WAY]
		rp.lane_width = pts[i][2]
		rp.shoulder_width_l = pts[i][3]
		rp.shoulder_width_r = pts[i][3]
		rp.gutter_profile = Vector2(0.45, -0.25)
		var gap: float = (pts[mini(i + 1, pts.size() - 1)][0] as Vector3).distance_to(pts[maxi(i - 1, 0)][0]) * 0.5
		rp.prior_mag = gap / 3.0
		rp.next_mag = gap / 3.0
		if prev != null:
			prev.connect_roadpoint(RoadPoint.PointInit.NEXT, rp, RoadPoint.PointInit.PRIOR)
		prev = rp


## A road material by name: the village's own copy where it has one, else the shared one.
func _road_material(name: String) -> Material:
	return _res(VILLAGE_ROAD[name] if VILLAGE_ROAD.has(name) else MAT_DIR + name + ".tres")


## Junction half width: the widest trunk segment touching the junction, else the widest of any.
func _junction_hw(p: Vector3) -> float:
	var trunk := 0.0
	var any := 0.0
	for id in course.ordered_ids:
		var seg: Dictionary = course.segments[id]
		var r: Route = seg["route"]
		if r.pos_at(0.0).distance_to(p) < 0.05 or r.pos_at(r.length).distance_to(p) < 0.05:
			any = maxf(any, seg["half_width"])
			if seg["fork"] == "":
				trunk = maxf(trunk, seg["half_width"])
	return trunk if trunk > 0.0 else any


## Visual half width at s: the sim half width, tapered from/to the junction width over TAPER m.
func road_hw(seg: Dictionary, s: float) -> float:
	var r: Route = seg["route"]
	var w: float = seg["half_width"]
	w = lerpf(_junction_hw(r.pos_at(0.0)), w, smoothstep(0.0, TAPER, s))
	return lerpf(w, _junction_hw(r.pos_at(r.length)), smoothstep(r.length - TAPER, r.length, s))


func _piece_s(seg: Dictionary, key: String) -> float:
	match key:
		"jin":
			return float(_junction[seg["id"]][0])
		"jout":
			return (seg["route"] as Route).length - float(_junction[seg["id"]][1])
		"kick":
			return float(seg["ramp"]["kick_a"]) + 0.5
		"lip":
			return float(seg["ramp"]["lip_s"])
		"land":
			return float(seg["ramp"]["land_s"])
		"water_in":
			return float(seg["water"][0][0])
		"water_out":
			return float(seg["water"][0][1])
		"deck_in":
			return plan.bridge_s - VillagePlan.BRIDGE_HALF_LENGTH
		"deck_out":
			return plan.bridge_s + VillagePlan.BRIDGE_HALF_LENGTH
		"causeway_in":
			return 18.0
		"causeway_out":
			return (seg["route"] as Route).length - 18.0
	_fail("unknown road piece split '%s'" % key)
	return 0.0


func _bake_roads() -> void:
	var mgr := RoadManager.new()
	_replace("Roads", mgr)
	_junction_lengths()
	_junction_pieces(mgr)
	for piece in ROAD_PIECES:
		var seg: Dictionary = course.segments[piece[1]]
		var r: Route = seg["route"]
		var s0 := 0.0 if typeof(piece[2]) == TYPE_INT else _piece_s(seg, piece[2])
		var s1 := r.length if typeof(piece[3]) == TYPE_INT else _piece_s(seg, piece[3])
		if s1 - s0 < 0.5:
			_fail("road piece %s is empty (s %.1f..%.1f)" % [piece[0], s0, s1])
			continue
		var n := maxi(1, int(ceil((s1 - s0) / ROAD_STEP)))
		var step := (s1 - s0) / n
		var pts: Array = []
		for i in n + 1:
			var s := s0 + i * step
			var dir := (r.pos_at(minf(s + 0.5, r.length)) - r.pos_at(maxf(s - 0.5, 0.0))).normalized()
			var sh := 0.45
			# A branch leaving or joining a fork's shared stretch: no shoulder lip on the join.
			if (str(piece[2]) == "jin" and s < s0 + 6.0) or (str(piece[3]) == "jout" and s > s1 - 6.0):
				sh = 0.0
			# On the roundabout the road lies in the ring: no shoulder or gutter dropping into it.
			if piece[1] == "bends" and s > float(course.roundabout["s0"]) - 12.0 and s < float(course.roundabout["s1"]) + 12.0:
				sh = 0.0
			pts.append([r.pos_at(s), dir, 2.0 * road_hw(seg, s), sh])
		_container(mgr, piece[0], piece[4], piece[5], pts)
	await process_frame
	for cont in mgr.get_children():
		(cont as RoadContainer).rebuild_segments(true)
	await process_frame
	print("bake: roads %d containers" % mgr.get_child_count())
	_roundabout()


## The full roundabout ring and its side streets as road meshes with the asphalt material
## (lane UVs so the edge lines are painted), a hair under the raced roads, plus the island's
## white kerb. The raced part of the ring is the "bends" road on top.
func _roundabout() -> void:
	var asphalt: Material = _road_material("road_asphalt")
	var stone := _std_material("kerb_stone", "", Color(0.86, 0.85, 0.82), 0.8)
	if asphalt == null:
		return
	var node := Node3D.new()
	_replace("Roundabout", node)
	var c: Vector2 = plan.fountain
	var radius: float = course.roundabout["radius"]
	var y := shape.roundabout_y() - 0.015
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Lane UV across the ring (u in the 1/8..2/8 lane column) so the edge lines are painted
	# at the inner and outer edges.
	var inner := radius - plan.ring_hw
	var outer := radius + plan.ring_hw
	var vert := func(d: Vector2, r: float) -> void:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2((1.0 + (r - inner) / (outer - inner)) / 8.0, 0.0))
		st.add_vertex(Vector3(c.x + d.x * r, y, c.y + d.y * r))
	# Ring cells the raced road already covers are left out, so the two never lie on top of
	# each other: a cell goes when its centre is within the road's width, measured square to
	# the road (not past its ends).
	var br: Route = course.segments["bends"]["route"]
	var road: Array = []
	var rs := 0.0
	while rs <= br.length:
		var q := br.pos_at(rs)
		var t := br.tangent_at(rs)
		road.append([Vector2(q.x, q.z), Vector2(t.x, t.z), road_hw(course.segments["bends"], rs)])
		rs += 0.25
	var under_road := func(q: Vector2) -> bool:
		var best := INF
		var hit := false
		for e in road:
			var dq: Vector2 = q - e[0]
			var dd := dq.length_squared()
			if dd < best:
				best = dd
				var along: float = absf(dq.dot(e[1]))
				var across: float = absf(dq.dot(Vector2(-e[1].y, e[1].x)))
				hit = along < 0.2 and across < float(e[2])
		return hit
	var n := 480
	var rings := 12
	for i in n:
		var d0 := Vector2(cos(TAU * i / n), sin(TAU * i / n))
		var d1 := Vector2(cos(TAU * (i + 1) / n), sin(TAU * (i + 1) / n))
		for k in rings:
			var r0 := lerpf(inner, outer, float(k) / rings)
			var r1 := lerpf(inner, outer, float(k + 1) / rings)
			# A cell belongs to the road when its centre is on it (cells are ~20 cm).
			var mid := c + (d0 + d1).normalized() * (r0 + r1) * 0.5
			if under_road.call(mid):
				continue
			for v: Array in [[d0, r1], [d1, r0], [d0, r0], [d0, r1], [d1, r1], [d1, r0]]:
				vert.call(v[0], v[1])
	# Side streets start at the ring's outer edge (no overlap with the ring).
	for arm in plan.arms:
		var a: Vector2 = arm[0]
		var b: Vector2 = arm[1]
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x) * VillagePlan.ARM_HALF_WIDTH
		var yb := shape.height_at(b.x, b.y) + 0.04
		var corners := [Vector3(a.x - side.x, y, a.y - side.y), Vector3(a.x + side.x, y, a.y + side.y),
			Vector3(b.x - side.x, yb, b.y - side.y), Vector3(b.x + side.x, yb, b.y + side.y)]
		for v: Array in [[0, 0.0], [3, 1.0], [1, 1.0], [0, 0.0], [2, 0.0], [3, 1.0]]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2((1.0 + float(v[1])) / 8.0, 0.0))
			st.add_vertex(corners[v[0]])
	st.set_material(asphalt)
	_mesh_node(node, "Ring", st.commit(), false)
	# Island kerb: short stone blocks round the island edge.
	var kerb := MeshBatch.new(1.0)
	var island: float = inner - 0.25
	var k := 48
	for i in k:
		var t := TAU * (i + 0.5) / k
		var q := c + Vector2(cos(t), sin(t)) * island
		kerb.box(Transform3D(Basis(Vector3.UP, -t), Vector3(q.x, y + 0.08, q.y)), Vector3(0.3, 0.2, TAU * island / k * 0.98))
	_mesh_node(node, "IslandKerb", kerb.commit(stone))


# ---------------------------------------------------------------- shared helpers

## A StandardMaterial3D in VMAT_DIR, created once (later edits in the editor are kept).
func _std_material(name: String, tex: String, tint: Color, rough := 0.85, uv := Vector3.ONE) -> Material:
	var path := VMAT_DIR + name + ".tres"
	if not ResourceLoader.exists(path):
		var m := StandardMaterial3D.new()
		m.albedo_color = tint
		m.roughness = rough
		if tex != "":
			var base := "res://assets/textures/%s/%s_1K-JPG_" % [tex, tex]
			m.albedo_texture = _res(base + "Color.jpg")
			m.normal_enabled = true
			m.normal_texture = _res(base + "NormalGL.jpg")
			m.roughness_texture = _res(base + "Roughness.jpg")
		m.uv1_scale = uv
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		ResourceSaver.save(m, path)
	return _res(path) as Material


func _save_mesh(mesh: Mesh, name: String) -> Mesh:
	var path := BAKED_DIR + name + ".res"
	var err := ResourceSaver.save(mesh, path)
	if err != OK:
		_fail("could not save %s (%d)" % [path, err])
		return mesh
	return load(path)


func _mesh_node(parent: Node, name: String, mesh: Mesh, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = _save_mesh(mesh, name.to_snake_case())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mark(mi)
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- water

func _bake_water() -> void:
	var water: Material = _res(MAT_DIR + "water.tres")
	if water == null:
		return
	var node := Node3D.new()
	_replace("Water", node)
	var poly := Geometry2D.offset_polygon(plan.pond, 1.5)[0]
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		_fail("pond polygon did not triangulate")
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in range(0, idx.size(), 3):
		for k in [0, 1, 2]:
			var q: Vector2 = poly[idx[i + k]]
			st.set_uv(q * 0.1)
			st.add_vertex(Vector3(q.x, VillageTerrain.POND_LEVEL, q.y))
	st.generate_tangents()
	st.set_material(water)
	_mesh_node(node, "Pond", st.commit(), false)
	# Brook: a ribbon just above its bed, never rising downstream, meeting the pond level.
	var pts: Array[Vector2] = []
	for i in plan.brook.size() - 1:
		var a := plan.brook[i]
		var b := plan.brook[i + 1]
		var n := maxi(1, int(a.distance_to(b)))
		for k in n:
			pts.append(a.lerp(b, float(k) / n))
	pts.append(plan.brook[plan.brook.size() - 1])
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var level := INF
	var hw := VillagePlan.BROOK_HALF_WIDTH + 0.8
	for i in pts.size():
		var p := pts[i]
		var dir := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		level = minf(level, maxf(shape.height_at(p.x, p.y) + VillageTerrain.BROOK_LEVEL_DROP, VillageTerrain.POND_LEVEL))
		left.append(Vector3(p.x + nrm.x * hw, level, p.y + nrm.y * hw))
		right.append(Vector3(p.x - nrm.x * hw, level, p.y - nrm.y * hw))
	var mb := MeshBatch.new(8.0)
	mb.ribbon(right, left)
	_mesh_node(node, "Brook", mb.commit(water), false)
	print("bake: water (pond %d tris, brook %d m)" % [idx.size() / 3, pts.size()])
	# Alpbach: a ribbon following its channel, at the ford's level where it crosses the road.
	var apts: Array[Vector2] = []
	for i in plan.alp_stream.size() - 1:
		var a := plan.alp_stream[i]
		var b := plan.alp_stream[i + 1]
		var n := maxi(1, int(a.distance_to(b)))
		for k in n:
			apts.append(a.lerp(b, float(k) / n))
	apts.append(plan.alp_stream[plan.alp_stream.size() - 1])
	var al := PackedVector3Array()
	var ar := PackedVector3Array()
	var alevel := INF
	var ahw := VillagePlan.ALP_HALF_WIDTH + 0.6
	for i in apts.size():
		var p := apts[i]
		var dir := (apts[mini(i + 1, apts.size() - 1)] - apts[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var on_road := shape.road_edge_at(p.x, p.y) < 0.5
		alevel = plan.alp_level if on_road else shape.height_at(p.x, p.y) + 0.45
		al.append(Vector3(p.x + nrm.x * ahw, alevel, p.y + nrm.y * ahw))
		ar.append(Vector3(p.x - nrm.x * ahw, alevel, p.y - nrm.y * ahw))
	var amb := MeshBatch.new(8.0)
	amb.ribbon(ar, al)
	_mesh_node(node, "Alpbach", amb.commit(water), false)


# ---------------------------------------------------------------- structures

func _bake_structures() -> void:
	var wood := _std_material("wood_dark", "Planks037A", Color(0.95, 0.9, 0.85))
	if wood is BaseMaterial3D and (wood as BaseMaterial3D).cull_mode != BaseMaterial3D.CULL_DISABLED:
		(wood as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		ResourceSaver.save(wood, wood.resource_path)
	var white := _std_material("paint_white", "Planks021", Color(1.6, 1.6, 1.6), 0.6)
	var red := _std_material("paint_red", "", Color(0.85, 0.08, 0.1), 0.5)
	var node := Node3D.new()
	_replace("Structures", node)
	_kicker(node, wood, red)
	_causeway(node, wood, white)
	_square(node)
	print("bake: structures")


## Wooden ski-jump kicker on the jump road from kick_a to the lip, following the sim's ramp
## profile, with a red-painted lip, and a plank landing wedge out of the hay meadow.
func _kicker(parent: Node, wood: Material, paint: Material) -> void:
	var seg: Dictionary = course.segments["ramp_jump"]
	var r: Route = seg["route"]
	var rp: Dictionary = seg["ramp"]
	var hw: float = road_hw(seg, float(rp["kick_a"])) + 0.15
	var a := float(rp["kick_a"])
	var lip := float(rp["lip_s"])
	var top_l := PackedVector3Array()
	var top_r := PackedVector3Array()
	var n := 16
	for i in n + 1:
		var s := lerpf(a, lip, float(i) / n)
		var y := course.surface_y(seg, s) + 0.03
		var c := r.pos_at(s)
		var nrm := r.normal_at(s)
		top_l.append(Vector3(c.x, y, c.z) - nrm * hw)
		top_r.append(Vector3(c.x, y, c.z) + nrm * hw)
	var mb := MeshBatch.new(2.2)
	mb.ribbon(top_r, top_l)
	for side: PackedVector3Array in [top_l, top_r]:
		var lo := PackedVector3Array()
		for v in side:
			lo.append(Vector3(v.x, shape.height_at(v.x, v.z) - 0.1, v.z))
		if side == top_l:
			mb.ribbon(lo, side)
		else:
			mb.ribbon(side, lo)
	var fl := top_l[n]
	var fr := top_r[n]
	mb.ribbon(PackedVector3Array([fr, Vector3(fr.x, shape.height_at(fr.x, fr.z) - 0.2, fr.z)]),
		PackedVector3Array([fl, Vector3(fl.x, shape.height_at(fl.x, fl.z) - 0.2, fl.z)]))
	_mesh_node(parent, "Kicker", mb.commit(wood))
	var lipb := MeshBatch.new()
	lipb.beam(fl + Vector3(0, 0.03, 0) + r.tangent_at(lip) * -0.2, fr + Vector3(0, 0.03, 0) + r.tangent_at(lip) * -0.2, 0.4, 0.06)
	_mesh_node(parent, "KickerLip", lipb.commit(paint))
	var land := float(rp["land_s"])
	var wl := PackedVector3Array()
	var wr := PackedVector3Array()
	var hw_l := road_hw(seg, land) + 0.15
	for k in 5:
		var s := land - 1.6 + 1.6 * k / 4.0
		var c := r.pos_at(s)
		var y := lerpf(c.y - float(rp["pit_depth"]) - 0.05, c.y + 0.02, smoothstep(0.0, 1.0, k / 4.0))
		var nrm := r.normal_at(s)
		wl.append(Vector3(c.x, y, c.z) - nrm * hw_l)
		wr.append(Vector3(c.x, y, c.z) + nrm * hw_l)
	var wedge := MeshBatch.new(2.2)
	wedge.ribbon(wr, wl)
	_mesh_node(parent, "LandingWedge", wedge.commit(wood))


## Posts and cross-beams under the causeway deck where it is clear of the ground, and low white
## rails along both edges over its raised length.
func _causeway(parent: Node, wood: Material, paint: Material) -> void:
	var seg: Dictionary = course.segments["cross_exposed"]
	var r: Route = seg["route"]
	var piers := MeshBatch.new(1.0)
	var rails := MeshBatch.new(1.0)
	var deck := 0.35
	var s := 3.0
	while s <= r.length - 3.0:
		var c := r.pos_at(s)
		var hw := road_hw(seg, s)
		var nrm := r.normal_at(s)
		var under := c.y - deck
		if under - shape.height_at(c.x, c.z) > 0.3:
			for side: float in [-1.0, 1.0]:
				var p := c + nrm * side * (hw - 0.3)
				var g := shape.height_at(p.x, p.z)
				piers.cylinder(Vector3(p.x, g - 0.3, p.z), 0.16, under - g + 0.3, 8)
			piers.beam(c - nrm * (hw + 0.2) + Vector3(0, -deck - 0.12, 0), c + nrm * (hw + 0.2) + Vector3(0, -deck - 0.12, 0), 0.25, 0.25)
		s += 5.0
	var y0 := r.pos_at(0.0).y
	var prev := {}
	s = 0.0
	while s <= r.length:
		var c := r.pos_at(s)
		if c.y - y0 > 0.3:
			var hw := road_hw(seg, s) + 0.15
			var nrm := r.normal_at(s)
			for side: float in [-1.0, 1.0]:
				var base := c + nrm * side * hw
				rails.box(Transform3D(Basis(Vector3.UP, r.heading_at(s)), base + Vector3(0, 0.38, 0)), Vector3(0.12, 0.76, 0.12))
				var top := base + Vector3(0, 0.72, 0)
				var mid := base + Vector3(0, 0.38, 0)
				if prev.has(side):
					rails.beam(prev[side][0], top, 0.09, 0.12)
					rails.beam(prev[side][1], mid, 0.06, 0.08)
				prev[side] = [top, mid]
		else:
			prev = {}
		s += 2.0
	_mesh_node(parent, "CausewayPiers", piers.commit(wood))
	_mesh_node(parent, "CausewayRails", rails.commit(paint))


## Cobbled Dorfplatz round the fountain: a disc just above the ground, inside the bends' arc.
func _square(parent: Node) -> void:
	var cobble: Material = _res(MAT_DIR + "road_ford.tres")
	if cobble == null:
		return
	var poly: PackedVector2Array = plan.square
	var c: Vector2 = plan.fountain
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		for q: Vector2 in [c, a, b]:
			st.set_normal(Vector3.UP)
			st.set_uv(q / 2.5)
			st.add_vertex(Vector3(q.x, shape.height_at(q.x, q.y) + 0.04, q.y))
	st.set_material(cobble)
	_mesh_node(parent, "Square", st.commit(), false)


# ---------------------------------------------------------------- buildings and props

## Module transforms collected across buildings/props: one InstancedModel node per module (the
## scene keeps the model path and transforms; the MultiMesh is built at load).
func _instanced(parent: Node, kit: VillageKit, placed: Dictionary) -> void:
	var swiss := VillageKit.swiss_material()
	if swiss == null:
		_fail("could not make the Swiss kit material")
		return
	for module in placed:
		if kit.mesh(module) == null:
			continue
		var n := InstancedModel.new()
		n.name = module.get_file().get_basename() if module.begins_with("res://") else module.replace("nature:", "").to_pascal_case()
		n.model = VillageKit.model_path(module)
		n.transforms = InstancedModel.pack(placed[module])
		if module in VillageKit.ANIMALS:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(module)
			var paths := PackedFloat32Array()
			for xf: Transform3D in placed[module]:
				paths.append_array(kit.wander_path(plan, shape, xf.origin, rng))
			n.wander = paths
			n.wander_points = VillageKit.WANDER_POINTS
		if not module.begins_with("nature:") and not module.begins_with("res://"):
			n.override = swiss
		_mark(n)
		parent.add_child(n)
	if not kit.errors.is_empty():
		_fail("village kit: %s" % "; ".join(kit.errors))


func _bake_buildings() -> void:
	var node := Node3D.new()
	_replace("Buildings", node)
	var houses := VillageHouses.new()
	houses.name = "Houses"
	var kinds := PackedStringArray()
	var data := PackedFloat32Array()
	for b in plan.buildings:
		var p: Vector2 = b["pos"]
		# Sit on the lowest ground under the footprint so no corner floats; the plinth reaches
		# down into the ground and up past the highest ground under it.
		var lo := INF
		var hi := -INF
		for q in VillagePlan.sample_points(VillagePlan.footprint(b)):
			var g := shape.height_at(q.x, q.y)
			lo = minf(lo, g)
			hi = maxf(hi, g)
		kinds.append(b["kind"])
		data.append_array([p.x, lo - 0.15, p.y, b["yaw"], b["size"].x, b["size"].y, absi(hash(p)) % 100000, hi - lo + 0.15])
	houses.kinds = kinds
	houses.houses = data
	var seg: Dictionary = course.segments["pond_bridge"]
	var r: Route = seg["route"]
	var half := VillagePlan.BRIDGE_HALF_LENGTH
	var n := int(round(half * 2.0 / 2.0))
	var joints := PackedFloat32Array()
	for k in n + 1:
		var s: float = plan.bridge_s - half + k * half * 2.0 / n
		var c := r.pos_at(s)
		var rise := r.pos_at(s + 0.5).y - r.pos_at(s - 0.5).y
		joints.append_array([c.x, c.y, c.z, r.heading_at(s), atan2(rise, 1.0)])
	houses.bridge = joints
	houses.bridge_half_width = road_hw(seg, plan.bridge_s) + 1.0
	_mark(houses)
	# Build once here too: for the props the buildings keep, and to fail the bake on errors.
	var built = VillageHouses.build(houses.kinds, houses.houses, houses.bridge, houses.bridge_half_width)
	if not built.errors.is_empty():
		_fail("buildings: %s" % "; ".join(built.errors))
		return
	node.add_child(houses)
	var kit := VillageKit.new()
	var placed := {}
	for m in built.props:
		if not placed.has(m[0]):
			placed[m[0]] = []
		placed[m[0]].append(m[1])
	_instanced(node, kit, placed)
	print("bake: %d buildings (%d vertices), %d prop types" % [plan.buildings.size(), built.vertex_count(), placed.size()])


func _bake_props() -> void:
	var kit := VillageKit.new()
	var node := Node3D.new()
	_replace("Props", node)
	var placed := {}
	var props: Array = kit.props(course, plan, shape)
	var swiss: Dictionary = kit.swiss_details(course, plan, shape)
	props.append_array(swiss["modules"])
	for m in props:
		if not placed.has(m[0]):
			placed[m[0]] = []
		placed[m[0]].append(m[1])
	_instanced(node, kit, placed)
	_fountain_water(node)
	_flags(node, swiss["flags"])
	_signs(node, swiss["signs"], swiss["boards"])
	_labels(node, swiss["labels"])
	print("bake: %d props, %d types, %d flags, %d signs" % [props.size(), placed.size(), swiss["flags"].size(), swiss["signs"].size()])


## Water in the fountain's basin: a disc at the water level, its edge just inside the basin
## wall (the centre piece stands up through it).
func _fountain_water(parent: Node) -> void:
	var water: Material = _res(MAT_DIR + "water.tres")
	if water == null:
		return
	var fw: Array = VillageKit.fountain_water(plan, shape)
	var c: Vector3 = fw[0]
	var r: float = fw[1]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 40
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		for q: Vector3 in [c, c + Vector3(cos(a0), 0, sin(a0)) * r, c + Vector3(cos(a1), 0, sin(a1)) * r]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(q.x, q.z) * 0.1)
			st.add_vertex(q)
	st.generate_tangents()
	st.set_material(water)
	_mesh_node(parent, "FountainWater", st.commit(), false)


## Swiss flags: a square cloth (the public-domain flag, assets/village/swiss_flag/) hanging
## from each pole top, gently bent so it reads as cloth.
func _flags(parent: Node, at: Array) -> void:
	var path := VMAT_DIR + "swiss_flag.tres"
	if not ResourceLoader.exists(path):
		var m := StandardMaterial3D.new()
		m.albedo_texture = _res("res://assets/village/swiss_flag/Flag_of_Switzerland.svg")
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.9
		ResourceSaver.save(m, path)
	var mat: Material = _res(path)
	if mat == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var size := 1.6
	var n := 6
	for xf: Transform3D in at:
		for i in n:
			var u0 := float(i) / n
			var u1 := float(i + 1) / n
			var quad: Array[Vector3] = []
			for uv: Vector2 in [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)]:
				var wave := sin(uv.x * PI * 1.5) * 0.18 * uv.x
				quad.append(xf * Vector3(0.12 + uv.x * size, -uv.y * size, wave))
			var uvs: Array[Vector2] = [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)]
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_uv(uvs[k])
				st.add_vertex(quad[k])
	st.generate_normals()
	st.set_material(mat)
	_mesh_node(parent, "SwissFlags", st.commit())


## Text on the ability signs, shops and factory (Label3D, readable from the camera).
func _labels(parent: Node, labels: Array) -> void:
	for l in labels:
		var lb := Label3D.new()
		lb.name = "Label_%s" % String(l[0]).validate_node_name().replace(" ", "")
		lb.text = l[0]
		lb.transform = l[1]
		lb.font_size = int(l[2])
		lb.pixel_size = 0.006
		lb.outline_size = 14
		lb.modulate = Color(0.12, 0.1, 0.08)
		lb.outline_modulate = Color(1.0, 0.95, 0.75)
		lb.double_sided = true
		_mark(lb)
		parent.add_child(lb)


## Yellow hiking signpost boards (Swiss Wanderweg style): a pointed yellow board per arrow.
func _signs(parent: Node, at: Array, boards: Array) -> void:
	var yellow := _std_material("wanderweg_yellow", "", Color(0.98, 0.78, 0.05), 0.6)
	var mb := MeshBatch.new(1.0)
	for xf: Transform3D in boards:
		mb.box(xf, Vector3(2.6, 0.7, 0.06))
	for xf: Transform3D in at:
		mb.box(Transform3D(xf.basis, xf.origin + xf.basis.x * 0.55), Vector3(1.0, 0.3, 0.05))
		mb.box(Transform3D(xf.basis * Basis(Vector3.BACK, PI * 0.25), xf.origin + xf.basis.x * 1.05), Vector3(0.21, 0.21, 0.05))
	_mesh_node(parent, "WanderwegSigns", mb.commit(yellow))
