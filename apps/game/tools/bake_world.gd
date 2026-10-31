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
## Re-run after editing the course; the checks in tools/world_check.gd verify the result.

const Course = preload("res://sim/course.gd")
const Route = preload("res://sim/route.gd")
const Landscape = preload("res://world/landscape.gd")
const TerrainShape = preload("res://world/terrain_shape.gd")

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
var stages: PackedStringArray = ["terrain", "roads"]
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
