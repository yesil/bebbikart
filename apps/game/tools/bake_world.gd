extends SceneTree
## Bakes the course world from sim/course.gd + world/landscape.gd into editor scenes:
##   godot --headless --path apps/game --script res://tools/bake_world.gd [-- --only=terrain,roads,...]
##
## Writes res://world/course_world.tscn (never touches res://world/decor.tscn). Stages:
##   terrain  Terrain3D heights + painted texture layers (world/terrain_shape.gd), saved to
##            res://world/terrain_data/, with res://world/terrain_material.tres and
##            res://world/terrain_assets.tres as editable resources.
##   roads    Road Generator containers: one per route piece, RoadPoints every ROAD_STEP metres
##            following the sim centre line, widths tapered at junctions. Materials in
##            res://world/materials/ are created once and then left alone (edit them freely).
##   water    Pond surface (pond polygon + 1.5 m into the banks) and the inflow stream ribbon.
##   structures  Course-following set pieces: the wooden kicker ramp, the causeway's posts and
##            low white rails, and the fence along the lakeside lane. Meshes go to
##            res://world/baked/*.res.
## Re-run after editing the course; the checks in tools/world_check.gd verify the result.

const Course = preload("res://sim/course.gd")
const Route = preload("res://sim/route.gd")
const Landscape = preload("res://world/landscape.gd")
const TerrainShape = preload("res://world/terrain_shape.gd")
const MeshBatch = preload("res://world/mesh_batch.gd")

const SCENE_PATH := "res://world/course_world.tscn"
const BAKED := &"baked"
const TERRAIN_DIR := "res://world/terrain_data"
const TERRAIN_MATERIAL := "res://world/terrain_material.tres"
const TERRAIN_ASSETS := "res://world/terrain_assets.tres"
const TEX_DIR := "res://assets/textures/terrain/"
## Per layer: tiling (uv_scale) and a tint that pulls the photo textures towards one palette.
const LAYER_LOOK := {
	"grass": [0.12, Color(0.92, 1.0, 0.82)],
	"grass_dirt": [0.14, Color(0.95, 1.0, 0.85)],
	"dirt": [0.2, Color(1.0, 0.95, 0.88)],
	"gravel": [0.35, Color(0.95, 0.95, 0.95)],
	"mud": [0.25, Color(0.8, 0.72, 0.62)],
	"rock": [0.15, Color(1.25, 1.22, 1.15)],
}

var course: Course
var land: Landscape
var shape: TerrainShape
var world: Node3D
var stages: PackedStringArray = ["terrain", "roads", "water", "structures"]
var failed := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			stages = a.trim_prefix("--only=").split(",")
	_bake.call_deferred()


func _bake() -> void:
	var t0 := Time.get_ticks_msec()
	course = Course.new()
	land = Landscape.new(course)
	shape = TerrainShape.new(course, land)
	shape.build()
	print("bake: terrain shape %dx%d in %d ms" % [shape.w, shape.h, Time.get_ticks_msec() - t0])
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
	if failed:
		push_error("bake: errors above, %s NOT saved" % SCENE_PATH)
		quit(1)
		return
	_own(world, world)
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


## Re-bakes update the existing scene in place so stages not being re-run keep their nodes.
func _load_or_new() -> Node3D:
	if ResourceLoader.exists(SCENE_PATH):
		var ps: PackedScene = load(SCENE_PATH)
		return ps.instantiate() as Node3D
	var n := Node3D.new()
	n.name = "CourseWorld"
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


## Only nodes the bake created (tagged with _mark) are saved. Plugin-generated children (road
## segments under RoadPoints, Terrain3D internals, scatter output) are rebuilt by the plugins.
func _own(node: Node, owner_: Node) -> void:
	for c in node.get_children():
		if not c.has_meta(BAKED):
			continue
		c.owner = owner_
		_own(c, owner_)


func _mark(node: Node) -> Node:
	node.set_meta(BAKED, true)
	return node


# ---------------------------------------------------------------- terrain

func _bake_terrain() -> void:
	var t0 := Time.get_ticks_msec()
	var terrain: Node3D = ClassDB.instantiate("Terrain3D")
	var mat: Resource = ClassDB.instantiate("Terrain3DMaterial")
	mat.set("world_background", 2)          # NOISE: endless rolling hills outside the baked map
	mat.set("macro_variation_enabled", true)
	mat.set("dual_scaling_enabled", false)
	ResourceSaver.save(mat, TERRAIN_MATERIAL)
	var assets: Resource = ClassDB.instantiate("Terrain3DAssets")
	for i in TerrainShape.LAYER_NAMES.size():
		var lname: String = TerrainShape.LAYER_NAMES[i]
		var ta: Resource = ClassDB.instantiate("Terrain3DTextureAsset")
		ta.set("name", lname)
		ta.set("albedo_texture", _res(TEX_DIR + lname + "_albedo_height.webp"))
		ta.set("normal_texture", _res(TEX_DIR + lname + "_normal_rough.webp"))
		ta.set("uv_scale", LAYER_LOOK[lname][0])
		ta.set("albedo_color", LAYER_LOOK[lname][1])
		ta.set("detiling_rotation", 0.3)
		ta.set("detiling_shift", 0.3)
		assets.call("set_texture_asset", i, ta)
	ResourceSaver.save(assets, TERRAIN_ASSETS)
	terrain.set("material", _res(TERRAIN_MATERIAL))
	terrain.set("assets", _res(TERRAIN_ASSETS))
	# Wipe old data so regions outside the new map do not linger.
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
const MAT_DIR := "res://world/materials/"
const DETOURS := ["ramp_around", "pond_bridge", "cross_sheltered"]
## Route pieces: [container name, segment id, s0 or -1 (start), s1 or -1 (end), material, deck thickness]
const ROAD_PIECES := [
	["start", "start", -1, -1, "road_asphalt", -1.0],
	["hills1", "hills1", -1, -1, "road_asphalt", -1.0],
	["ramp_jump_run_up", "ramp_jump", -1, "lip", "road_asphalt", -1.0],
	["ramp_jump_landing", "ramp_jump", "land", -1, "road_asphalt", -1.0],
	["ramp_around", "ramp_around", -1, -1, "road_asphalt_detour", -1.0],
	["hills2", "hills2", -1, -1, "road_asphalt", -1.0],
	["pond_water_in", "pond_water", -1, "water_in", "road_asphalt", -1.0],
	["pond_ford", "pond_water", "water_in", "water_out", "road_ford", -1.0],
	["pond_water_out", "pond_water", "water_out", -1, "road_asphalt", -1.0],
	["pond_bridge", "pond_bridge", -1, -1, "road_asphalt_detour", 0.45],
	["cross_exposed", "cross_exposed", -1, -1, "road_planks", 0.35],
	["cross_sheltered", "cross_sheltered", -1, -1, "road_dirt_detour", -1.0],
	["bends", "bends", -1, -1, "road_asphalt", -1.0],
]


func _road_materials() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAT_DIR))
	var sh: Shader = _res(MAT_DIR + "road.gdshader")
	# [name, texture set, tile metres, tint, edge lines, depth pull, roughness bias]
	var defs := [
		["road_asphalt", "Asphalt012", 4.0, Color(0.9, 0.9, 0.92), true, 0.0, 0.0],
		["road_asphalt_detour", "Asphalt012", 4.0, Color(0.9, 0.9, 0.92), true, 0.0015, 0.0],
		["road_ford", "Bricks076C", 2.5, Color(0.85, 0.85, 0.8), false, 0.0, -0.1],
		["road_planks", "Planks037A", 2.2, Color(1.0, 0.95, 0.88), false, 0.0, 0.0],
		["road_dirt_detour", "dirt", 3.0, Color(1.0, 0.97, 0.9), false, 0.0015, 0.0],
	]
	for d in defs:
		var path: String = MAT_DIR + String(d[0]) + ".tres"
		if ResourceLoader.exists(path):
			continue
		var m := ShaderMaterial.new()
		m.shader = sh
		var tex: String = d[1]
		if tex == "dirt":
			m.set_shader_parameter("albedo_tex", _res(TEX_DIR + "dirt_albedo_height.webp"))
			m.set_shader_parameter("normal_tex", _res("res://assets/textures/Asphalt012/Asphalt012_1K-JPG_NormalGL.jpg"))
			m.set_shader_parameter("rough_tex", _res("res://assets/textures/Asphalt012/Asphalt012_1K-JPG_Roughness.jpg"))
			m.set_shader_parameter("roughness_bias", 0.15)
		else:
			var base := "res://assets/textures/%s/%s_1K-JPG_" % [tex, tex]
			m.set_shader_parameter("albedo_tex", _res(base + "Color.jpg"))
			m.set_shader_parameter("normal_tex", _res(base + "NormalGL.jpg"))
			m.set_shader_parameter("rough_tex", _res(base + "Roughness.jpg"))
			m.set_shader_parameter("roughness_bias", d[6])
		m.set_shader_parameter("tile_m", d[2])
		m.set_shader_parameter("tint", d[3])
		m.set_shader_parameter("edge_lines", d[4])
		m.set_shader_parameter("depth_pull", d[5])
		ResourceSaver.save(m, path)


## Junction half width: the widest trunk (non-fork) segment touching the junction, else the
## widest of any segment touching it.
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
	var hw: float = seg["half_width"]
	var w := hw
	if seg["id"] != "start":
		var j0 := _junction_hw(r.pos_at(0.0))
		w = lerpf(j0, w, smoothstep(0.0, TAPER, s))
	var j1 := _junction_hw(r.pos_at(r.length))
	if seg["id"] != "bends":
		w = lerpf(w, j1, smoothstep(r.length - TAPER, r.length, s))
	return w


## Named split points along a segment: ramp lip/landing and the ford's water range.
func _piece_s(seg: Dictionary, key: String) -> float:
	match key:
		"lip":
			return float(seg["ramp"]["lip_s"])
		"land":
			return float(seg["ramp"]["land_s"])
		"water_in":
			return float(seg["water"][0][0])
		"water_out":
			return float(seg["water"][0][1])
	_fail("unknown road piece split '%s'" % key)
	return 0.0


func _bake_roads() -> void:
	_road_materials()
	var mgr := RoadManager.new()
	_replace("Roads", mgr)
	for piece in ROAD_PIECES:
		var seg: Dictionary = course.segments[piece[1]]
		var r: Route = seg["route"]
		var s0 := 0.0 if typeof(piece[2]) == TYPE_INT else _piece_s(seg, piece[2])
		var s1 := r.length if typeof(piece[3]) == TYPE_INT else _piece_s(seg, piece[3])
		var cont := RoadContainer.new()
		cont.name = piece[0]
		_mark(cont)
		cont.flatten_terrain = false
		cont.material_resource = _res(MAT_DIR + String(piece[4]) + ".tres")
		cont.underside_thickness = piece[5]
		mgr.add_child(cont)
		var n := maxi(1, int(ceil((s1 - s0) / ROAD_STEP)))
		var step := (s1 - s0) / n
		var detour: bool = piece[1] in DETOURS
		var prev: RoadPoint = null
		for i in n + 1:
			var s := s0 + i * step
			var rp := RoadPoint.new()
			rp.name = "RP_%03d" % i
			_mark(rp)
			cont.add_child(rp)
			var pos := r.pos_at(s)
			var dir := (r.pos_at(minf(s + 0.5, r.length)) - r.pos_at(maxf(s - 0.5, 0.0))).normalized()
			rp.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), pos)
			rp.auto_lanes = false
			rp.traffic_dir = [RoadPoint.LaneDir.FORWARD]
			rp.lanes = [RoadPoint.LaneType.ONE_WAY]
			rp.lane_width = 2.0 * road_hw(seg, s)
			# Detours start on top of the direct road: no shoulders until they have split off.
			var sh := 0.45
			if detour and (s < 16.0 or s > r.length - 16.0):
				sh = 0.0
			rp.shoulder_width_l = sh
			rp.shoulder_width_r = sh
			rp.gutter_profile = Vector2(0.45, -0.25)
			rp.prior_mag = step / 3.0
			rp.next_mag = step / 3.0
			if prev != null:
				prev.connect_roadpoint(RoadPoint.PointInit.NEXT, rp, RoadPoint.PointInit.PRIOR)
			prev = rp
	await process_frame
	for cont in mgr.get_children():
		(cont as RoadContainer).rebuild_segments(true)
	await process_frame
	print("bake: roads %d containers" % mgr.get_child_count())


# ---------------------------------------------------------------- shared materials

const BAKED_DIR := "res://world/baked/"


## Creates a StandardMaterial3D in MAT_DIR once (later edits in the editor are kept).
func _std_material(name: String, tex: String, tint: Color, rough := 0.85, uv := Vector3.ONE) -> Material:
	var path := MAT_DIR + name + ".tres"
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


func _water_material() -> Material:
	var path := MAT_DIR + "water.tres"
	if not ResourceLoader.exists(path):
		var m := ShaderMaterial.new()
		m.shader = _res(MAT_DIR + "water.gdshader")
		for k in ["normal_a", "normal_b"]:
			var nt := NoiseTexture2D.new()
			nt.width = 512
			nt.height = 512
			nt.seamless = true
			nt.as_normal_map = true
			nt.bump_strength = 6.0
			var fn := FastNoiseLite.new()
			fn.seed = 3 if k == "normal_a" else 9
			fn.frequency = 0.012 if k == "normal_a" else 0.02
			fn.fractal_octaves = 3
			nt.noise = fn
			m.set_shader_parameter(k, nt)
		ResourceSaver.save(m, path)
	return _res(path) as Material


func _save_mesh(mesh: Mesh, name: String) -> Mesh:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BAKED_DIR))
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
	var water := _water_material()
	var node := Node3D.new()
	_replace("Water", node)
	# Pond: the shore polygon grown 1.5 m so the surface meets the banks without a gap.
	var poly := Geometry2D.offset_polygon(land.pond, 1.5)[0]
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
			st.add_vertex(Vector3(q.x, Landscape.POND_LEVEL, q.y))
	st.generate_tangents()
	st.set_material(water)
	_mesh_node(node, "Pond", st.commit(), false)
	# Stream: a ribbon 0.55 m above its bed, never rising downstream.
	var pts: Array[Vector2] = []
	for i in land.stream.size() - 1:
		var a := land.stream[i]
		var b := land.stream[i + 1]
		var n := maxi(1, int(a.distance_to(b)))
		for k in n:
			pts.append(a.lerp(b, float(k) / n))
	pts.append(land.stream[land.stream.size() - 1])
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var level := INF
	var hw := Landscape.STREAM_HALF_WIDTH + 0.9
	for i in pts.size():
		var p := pts[i]
		var dir := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var bed := shape.stream_bed_at(p, shape.natural_at(p.x, p.y))
		level = minf(level, maxf(bed + 0.55, Landscape.POND_LEVEL))
		left.append(Vector3(p.x + nrm.x * hw, level, p.y + nrm.y * hw))
		right.append(Vector3(p.x - nrm.x * hw, level, p.y - nrm.y * hw))
	var mb := MeshBatch.new(8.0)
	mb.ribbon(left, right)
	_mesh_node(node, "Stream", mb.commit(water), false)
	print("bake: water (pond %d tris, stream %d m)" % [idx.size() / 3, pts.size()])


# ---------------------------------------------------------------- structures

func _bake_structures() -> void:
	var wood := _std_material("wood_dark", "Planks037A", Color(0.95, 0.9, 0.85))
	var wood_light := _std_material("wood_light", "Planks021", Color(1, 1, 1))
	var white := _std_material("paint_white", "Planks021", Color(1.6, 1.6, 1.6), 0.6)
	var yellow := _std_material("paint_yellow", "", Color(1.0, 0.78, 0.1), 0.5)
	var node := Node3D.new()
	_replace("Structures", node)
	_kicker(node, wood, yellow)
	_causeway(node, wood, white)
	_lane_fence(node, wood_light)
	print("bake: structures")


## Wooden kicker on the jump road from kick_a to the lip, following the sim's ramp profile.
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
	# Side skirts and the front face down to the ground.
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
	# Painted lip edge so the take-off reads from the back of the room.
	var lipb := MeshBatch.new()
	lipb.beam(fl + Vector3(0, 0.03, 0) + r.tangent_at(lip) * -0.2, fr + Vector3(0, 0.03, 0) + r.tangent_at(lip) * -0.2, 0.4, 0.06)
	_mesh_node(parent, "KickerLip", lipb.commit(paint))
	# Landing wedge: a short plank slope from the mud of the dip up onto the landing road.
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
## rails along both edges for its whole raised length.
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
		var ground := shape.height_at(c.x, c.z)
		if under - ground > 0.4:
			for side: float in [-1.0, 1.0]:
				var p := c + nrm * side * (hw - 0.3)
				piers.cylinder(Vector3(p.x, shape.height_at(p.x, p.z) - 0.3, p.z), 0.16, under - shape.height_at(p.x, p.z) + 0.3, 8)
			piers.beam(c - nrm * (hw + 0.2) + Vector3(0, -deck - 0.12, 0), c + nrm * (hw + 0.2) + Vector3(0, -deck - 0.12, 0), 0.25, 0.25)
		s += 5.0
	# Rails over the raised part (deck at least 0.3 m above the junction level).
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


## Rustic fence along both sides of the railed lakeside lane, broken where the stone bridge
## (decor) carries the lane over the stream.
func _lane_fence(parent: Node, wood: Material) -> void:
	var seg: Dictionary = course.segments["pond_bridge"]
	var r: Route = seg["route"]
	var hump_s := _closest_s(r, Vector2(land.bridge_hump.x, land.bridge_hump.z))
	var fence := MeshBatch.new(1.5)
	var prev := {}
	var s := 14.0
	while s <= r.length - 14.0:
		if absf(s - hump_s) < 8.0:
			prev = {}
			s += 2.5
			continue
		var c := r.pos_at(s)
		var hw := road_hw(seg, s) + 0.55
		var nrm := r.normal_at(s)
		for side: float in [-1.0, 1.0]:
			var p := c + nrm * side * hw
			var g := shape.height_at(p.x, p.z)
			fence.cylinder(Vector3(p.x, g - 0.2, p.z), 0.07, 1.15, 6)
			var top := Vector3(p.x, g + 0.85, p.z)
			var mid := Vector3(p.x, g + 0.45, p.z)
			if prev.has(side):
				fence.beam(prev[side][0], top, 0.06, 0.1)
				fence.beam(prev[side][1], mid, 0.05, 0.08)
			prev[side] = [top, mid]
		s += 2.5
	_mesh_node(parent, "LaneFence", fence.commit(wood))


func _closest_s(r: Route, p: Vector2) -> float:
	var best := INF
	var best_s := 0.0
	var s := 0.0
	while s <= r.length:
		var q := r.pos_at(s)
		var d := Vector2(q.x, q.z).distance_to(p)
		if d < best:
			best = d
			best_s = s
		s += 0.25
	return best_s
