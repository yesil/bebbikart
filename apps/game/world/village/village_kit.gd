extends RefCounted
## The village's props from the Kenney Fantasy Town Kit (CC0, see
## res://assets/village/kenney_fantasy_town/License_Kenney.txt) and the Quaternius nature kit:
## fountain, benches, lanterns, fences, flower clumps, orchard and alpine trees, hay bales, flag
## poles, signposts, the animals, and the stalls, banners and water wheel the buildings keep.
## tools/bake_village.gd merges every module type into one MultiMesh, so they cost a few dozen
## draw calls. The Kenney modules share one material: the kit's colour map recoloured to a Swiss
## palette, rebuilt at every bake by swiss_material(). The buildings themselves are real
## geometry from world/village/chalet_builder.gd.

const KIT := "res://assets/village/kenney_fantasy_town/"
const PLANT_MESHES := "res://world/vegetation/meshes/"
const VMAT_DIR := "res://world/village/materials/"
const SWISS_MAT := VMAT_DIR + "kenney_swiss.tres"
const SWISS_TEX := VMAT_DIR + "kenney_swiss_colormap.res"

const FLOOR_H := 2.6        # metres per storey (the shop and factory names hang above it)
const CELL := 2.25          # the old Kenney cell width: the shop stalls stand one half cell in

## Colour map recolouring: [x0, y0, x1, y1] pixel block of colormap.png -> target HSV.
static func _recolour() -> Array:
	return [
	[64, 384, 128, 512, Color.from_hsv(0.07, 0.3, 0.3)],      # teal roofs -> dark shingles
	# Sand and green: only the roof slabs' end boards sample them (a strip from the shingles
	# to the timber), which showed as sand and teal stripes on every gable.
	[128, 384, 256, 512, Color.from_hsv(0.06, 0.55, 0.36)],   # -> dark timber boards
	[192, 256, 256, 384, Color.from_hsv(0.08, 0.62, 0.66)],   # light wood -> honey timber
	[256, 256, 320, 384, Color.from_hsv(0.06, 0.6, 0.42)],    # brown wood -> dark timber
	[256, 384, 384, 512, Color.from_hsv(0.06, 0.55, 0.4)],    # dark wood trims
	[64, 256, 128, 384, Color.from_hsv(0.11, 0.06, 0.96)],    # lavender stone -> white plaster
	[448, 384, 512, 512, Color.from_hsv(0.1, 0.05, 0.74)],    # grey stone -> warm grey stone
	[0, 384, 64, 512, Color.from_hsv(0.995, 0.75, 0.58)],     # candy red -> deep Swiss red (church roof, banners)
	]

var errors: PackedStringArray = []
var _meshes := {}           # module name -> Mesh


## Model file of a module: a Kenney kit name, "nature:<name>" for a Quaternius plant, or a
## res:// path. Plants are the countryside's prepared meshes (tools/bake_world.gd, from the
## Quaternius kit): leaves that sway with the weather's wind and toned-down bark.
static func model_path(module: String) -> String:
	if module.begins_with("res://"):
		return module
	if module.begins_with("nature:"):
		return PLANT_MESHES + module.trim_prefix("nature:").to_snake_case() + ".res"
	return KIT + module + ".glb"


## Mesh of a kit module (first MeshInstance3D in the model), cached.
func mesh(module: String) -> Mesh:
	if _meshes.has(module):
		return _meshes[module]
	var path := model_path(module)
	if not ResourceLoader.exists(path):
		errors.append("missing model %s" % path)
		_meshes[module] = null
		return null
	var res := load(path)
	var m: Mesh = res as Mesh
	if res is PackedScene:
		var root: Node = (res as PackedScene).instantiate()
		var mi := _first_mesh(root)
		m = mi.mesh if mi != null else null
		root.free()
	if m == null:
		errors.append("no mesh in %s" % path)
	_meshes[module] = m
	return m


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r != null:
			return r
	return null


## The shared Swiss-palette material for every Kenney module. The colour map is rebuilt from
## the recolour table at every bake; the material is created once (its other settings stay
## editable) and pointed at the new map.
static func swiss_material() -> Material:
	var mat_path := SWISS_MAT
	var tex_path := SWISS_TEX
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VMAT_DIR))
	var src := Image.load_from_file(ProjectSettings.globalize_path(KIT + "Textures/colormap.png"))
	if src == null or src.is_empty():
		push_error("village_kit: cannot read the Kenney colour map")
		return null
	src.convert(Image.FORMAT_RGBA8)
	for r in _recolour():
		var target: Color = r[4]
		var mean := 0.0
		var n := 0
		for y in range(r[1], r[3]):
			for x in range(r[0], r[2]):
				mean += src.get_pixel(x, y).v
				n += 1
		mean /= n
		for y in range(r[1], r[3]):
			for x in range(r[0], r[2]):
				var c := src.get_pixel(x, y)
				src.set_pixel(x, y, Color.from_hsv(target.h, target.s, clampf(target.v * c.v / mean, 0.0, 1.0), c.a))
	if ResourceSaver.save(ImageTexture.create_from_image(src), tex_path) != OK:
		push_error("village_kit: cannot save %s" % tex_path)
		return null
	if not ResourceLoader.exists(mat_path):
		var made := StandardMaterial3D.new()
		made.roughness = 0.85
		made.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		ResourceSaver.save(made, mat_path)
	var m := ResourceLoader.load(mat_path, "", ResourceLoader.CACHE_MODE_REPLACE) as StandardMaterial3D
	if m == null:
		push_error("village_kit: %s is not a StandardMaterial3D" % mat_path)
		return null
	m.albedo_texture = ResourceLoader.load(tex_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if ResourceSaver.save(m, mat_path) != OK:
		push_error("village_kit: cannot save %s" % mat_path)
		return null
	return m


static func _cells(size: float, target := CELL, even := false) -> int:
	var n := maxi(1, int(round(size / target)))
	if even and n % 2 == 1:
		n += 1 if size / target > n else -1
		n = maxi(2, n)
	return n


# ---------------------------------------------------------------- props

const FOUNTAIN_SCALE := 2.4
## The basin of "fountain-round-detail" in model units: inner wall radius and a water level a
## little under its 0.28 rim.
const FOUNTAIN_BASIN_R := 0.70
const FOUNTAIN_WATER_Y := 0.2


## The fountain's water: [centre at the water level, radius reaching just into the basin wall].
static func fountain_water(plan, shape) -> Array:
	var f: Vector2 = plan.fountain
	return [Vector3(f.x, shape.height_at(f.x, f.y) + FOUNTAIN_WATER_Y * FOUNTAIN_SCALE, f.y), (FOUNTAIN_BASIN_R + 0.01) * FOUNTAIN_SCALE]


## Street furniture and planting. Returns [[module, Transform3D world]] (modules may be
## "nature:<name>" for the Quaternius kit).
func props(course, plan, shape) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ground := func(p: Vector2) -> float: return shape.height_at(p.x, p.y)
	# Fountain on the square: round basin (its water is baked as a disc, fountain_water()), lime
	# tree beside it.
	var f: Vector2 = plan.fountain
	out.append(["fountain-round-detail", Transform3D(Basis().scaled(Vector3(FOUNTAIN_SCALE, FOUNTAIN_SCALE, FOUNTAIN_SCALE)), Vector3(f.x, ground.call(f), f.y))])
	var lt: Vector2 = plan.lime_tree
	out.append(["nature:CommonTree_3", Transform3D(Basis().scaled(Vector3(1.6, 1.6, 1.6)), Vector3(lt.x, ground.call(lt), lt.y))])
	# Benches round the square.
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var p: Vector2 = f + Vector2(cos(a), sin(a)) * 5.0
		out.append(["stall-bench", Transform3D(Basis(Vector3.UP, -a).scaled(Vector3(2.2, 2.2, 2.2)), Vector3(p.x, ground.call(p), p.y))])
	# Lanterns along the main street and the square, on alternate sides.
	for id in ["start", "hills1", "bends"]:
		var r = course.segments[id]["route"]
		var hw: float = course.segments[id]["half_width"]
		var s := 4.0
		var side := 1.0
		while s < r.length - 2.0:
			var q: Vector3 = r.world_at(s, side * (hw + 1.0))
			var p := Vector2(q.x, q.z)
			if _free(plan, p, 0.6):
				out.append(["lantern", Transform3D(Basis().scaled(Vector3(2.0, 2.0, 2.0)), Vector3(p.x, ground.call(p), p.y))])
			s += 14.0
			side = -side
	# Wooden fences along the bridge lane and round the hay meadow side of the around lane.
	for id in ["pond_bridge", "ramp_around"]:
		var r = course.segments[id]["route"]
		var hw: float = course.segments[id]["half_width"]
		var s := 22.0
		while s < r.length - 22.0:
			if id == "pond_bridge" and absf(s - plan.bridge_s) < 9.0:
				s += 2.0
				continue
			for side: float in [-1.0, 1.0]:
				# The fence's rails stand on its model's +x edge (0.92 m out at this scale): turn
				# it so that edge faces away from the road on both sides, rails at hw + 1.2 m.
				var q: Vector3 = r.world_at(s, side * (hw + 0.35))
				var p := Vector2(q.x, q.z)
				if _free(plan, p, 0.3):
					var yaw: float = r.heading_at(s) + (PI if side > 0.0 else 0.0)
					out.append(["fence", Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(2.0, 2.4, 2.0)), Vector3(p.x, ground.call(p), p.y))])
			s += 2.0
	# Flower boxes: flower clumps under the front windows of every chalet and the inn.
	for b in plan.buildings:
		if not b["kind"] in ["chalet", "inn", "bakery", "arcade"]:
			continue
		var fwd := Vector2(sin(b["yaw"]), cos(b["yaw"]))
		var rgt := Vector2(fwd.y, -fwd.x)
		var sz: Vector2 = b["size"]
		var n := int(sz.x / 2.5)
		for k in n:
			var p: Vector2 = b["pos"] + fwd * (sz.y * 0.5 + 0.5) + rgt * ((k + 0.5) / n - 0.5) * sz.x * 0.85
			out.append(["nature:Flower_3_Group" if k % 2 == 0 else "nature:Flower_4_Group",
				Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.5, 0.5, 0.5)), Vector3(p.x, ground.call(p), p.y))])
	# Orchard trees.
	for p in plan.orchard:
		var s := rng.randf_range(0.8, 1.1)
		out.append(["nature:CommonTree_%d" % rng.randi_range(1, 5), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, ground.call(p), p.y))])
	# Hay bales in the hay meadow (clear of the jump road).
	var hm: Vector4 = plan.hay_meadow
	for k in 6:
		var p := Vector2(hm.x, hm.y) + Vector2(rng.randf_range(-hm.z, hm.z), rng.randf_range(-hm.w, hm.w)).rotated(-plan.hay_yaw)
		if _free(plan, p, 2.5):
			out.append(["cart" if k == 0 else "nature:Bush_Common", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(2.0, 2.0, 2.0)), Vector3(p.x, ground.call(p), p.y))])
	# Alpine trees: pines on the slopes round the village.
	var pines := 0
	var tries := 0
	while pines < 450 and tries < 12000:
		tries += 1
		var p := Vector2(rng.randf_range(shape.rect.position.x + 40.0, shape.rect.end.x - 40.0), rng.randf_range(shape.rect.position.y + 40.0, shape.rect.end.y - 40.0))
		var d: float = shape.course_dist_at(p)
		if d < 35.0 or d > 330.0:
			continue
		var y: float = ground.call(p)
		if y > 45.0:
			continue
		if not _free(plan, p, 4.0):
			continue
		# Clumps: more trees further out.
		if rng.randf() > smoothstep(35.0, 140.0, d) * 0.9 + 0.1:
			continue
		var s := rng.randf_range(1.0, 1.8)
		out.append(["nature:Pine_%d" % rng.randi_range(1, 5), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, y - 0.1, p.y))])
		pines += 1
	return out


const COW := "res://assets/village/quaternius_cow/Cow.glb"
const COW_2 := "res://assets/village/poly_pizza/Cow_2.glb"
## Blacknose sheep, the Valais breed (white fleece, black face and legs).
const SHEEP := "res://assets/village/poly_pizza/Sheep_1.glb"
const CHEESE := "res://assets/village/poly_pizza/CheeseBlock.glb"
## Models that wander about their spot (world/village/instanced_model.gd "wander").
const ANIMALS := [COW, COW_2, SHEEP]
const WANDER_POINTS := 5
const WANDER_RADIUS := 4.0
const WANDER_CLEAR := 2.5          # metres every wander point keeps from roads, houses and water
const CHOCOLATE := "res://assets/village/poly_pizza/ChocolateBar.glb"


## Swiss details: flag poles (Kenney wooden pillars) and their flags, yellow hiking signposts
## before each fork, and cows on the pastures. Returns {modules: [[module, Transform3D]],
## flags: [Transform3D of the cloth's hoist corner, x along the cloth], signs: [Transform3D of
## a sign board centre, x along the board]}.
func swiss_details(course, plan, shape) -> Dictionary:
	var out: Array = []
	var flags: Array = []
	var signs: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 1291    # the Federal Charter
	var ground := func(p: Vector2) -> float: return shape.height_at(p.x, p.y)
	var pole := func(p: Vector2, height: float, yaw: float) -> void:
		var y: float = ground.call(p)
		out.append(["pillar-wood", Transform3D(Basis().scaled(Vector3(0.9, height, 0.9)), Vector3(p.x, y, p.y))])
		flags.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y + height - 0.15, p.y)))
	# Two tall flags either side of the start/finish line, one at the inn, one by the church,
	# one at each end of the covered bridge, and one on the square.
	var sr = course.segments["start"]["route"]
	var hw: float = course.segments["start"]["half_width"]
	for side: float in [-1.0, 1.0]:
		var q: Vector3 = sr.world_at(0.0, side * (hw + 1.6))
		pole.call(Vector2(q.x, q.z), 8.0, sr.heading_at(0.0) + PI * 0.5)
	for b in plan.buildings:
		if b["kind"] in ["inn", "church", "school"]:
			var fwd := Vector2(sin(b["yaw"]), cos(b["yaw"]))
			var rgt := Vector2(fwd.y, -fwd.x)
			var p: Vector2 = b["pos"] + fwd * (b["size"].y * 0.5 + 1.2) + rgt * (b["size"].x * 0.5 + 1.0)
			if _free(plan, p, 0.6):
				pole.call(p, 7.0, b["yaw"])
	var br = course.segments["pond_bridge"]["route"]
	var bhw: float = course.segments["pond_bridge"]["half_width"]
	for ds: float in [-9.5, 9.5]:
		var q: Vector3 = br.world_at(plan.bridge_s + ds, bhw + 1.4)
		if _free(plan, Vector2(q.x, q.z), 0.6):
			pole.call(Vector2(q.x, q.z), 6.0, br.heading_at(plan.bridge_s))
	var sq: Vector2 = plan.fountain + (plan.lime_tree - plan.fountain).rotated(PI * 0.6)
	pole.call(sq, 7.0, 0.0)
	# Yellow hiking signposts on the outside of each fork's run-in, arrows down both branches.
	for fk in [["hills1", "ramp_around"], ["hills2", "pond_bridge"], ["alpbach", "cross_sheltered"]]:
		var r = course.segments[fk[0]]["route"]
		var fhw: float = course.segments[fk[0]]["half_width"]
		var detour = course.segments[fk[1]]["route"]
		# The detour peels off to the side its curvature first turns away from.
		var side := -signf(detour.curv_at(8.0)) if absf(detour.curv_at(8.0)) > 0.001 else 1.0
		# The first clear spot in the last 20 m before the fork.
		var s: float = r.length - 6.0
		var p := Vector2.ZERO
		while s > r.length - 20.0:
			var q: Vector3 = r.world_at(s, side * (fhw + 1.5))
			p = Vector2(q.x, q.z)
			if _free(plan, p, 0.4):
				break
			s -= 1.0
		if not _free(plan, p, 0.4):
			errors.append("no room for the signpost before the %s fork" % fk[1])
			continue
		var y: float = ground.call(p)
		out.append(["pillar-wood", Transform3D(Basis().scaled(Vector3(0.8, 2.6, 0.8)), Vector3(p.x, y, p.y))])
		var h: float = r.heading_at(s)
		signs.append(Transform3D(Basis(Vector3.UP, h - PI * 0.5 + 0.35), Vector3(p.x, y + 2.25, p.y)))
		signs.append(Transform3D(Basis(Vector3.UP, h - PI * 0.5 - 0.35), Vector3(p.x, y + 1.85, p.y)))
	# Cows on the pastures outside the loop.
	var cows := 0
	var tries := 0
	while cows < 16 and tries < 4000:
		tries += 1
		var p := Vector2(rng.randf_range(shape.rect.position.x, shape.rect.end.x), rng.randf_range(shape.rect.position.y, shape.rect.end.y))
		var d: float = shape.course_dist_at(p)
		if d < 10.0 or d > 90.0 or plan._inside_loop(p) or not _free(plan, p, 3.0):
			continue
		var y: float = ground.call(p)
		if absf(shape.height_at(p.x + 2.0, p.y) - y) > 0.5 or absf(shape.height_at(p.x, p.y + 2.0) - y) > 0.5:
			continue
		out.append([COW, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.26, 0.26, 0.26)), Vector3(p.x, y, p.y))])
		cows += 1
	# The farm's herd inside the alp detour: cows and sheep grazing between the farm track and
	# the ridge, kept clear of the roads and the farm buildings.
	var labels: Array = []
	var boards: Array = []
	var herd := 0
	tries = 0
	var box := Rect2(plan.detour_poly[0], Vector2.ZERO)
	for q in plan.detour_poly:
		box = box.expand(q)
	while herd < 26 and tries < 4000:
		tries += 1
		var p := Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
		if not Geometry2D.is_point_in_polygon(p, plan.detour_poly) or not _free(plan, p, 3.0):
			continue
		var y: float = ground.call(p)
		var model := COW_2 if herd % 3 == 0 else (SHEEP if herd % 3 == 1 else COW)
		var sc := 0.34 if model == COW_2 else (0.25 if model == SHEEP else 0.32)
		out.append([model, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(p.x, y, p.y))])
		herd += 1
	# Sheep on the slopes round the alp.
	var flock := 0
	tries = 0
	while flock < 18 and tries < 4000:
		tries += 1
		var c: Vector2 = plan.detour_poly[plan.detour_poly.size() / 2]
		var p := c + Vector2(rng.randf_range(-70.0, 70.0), rng.randf_range(-60.0, 30.0))
		if Geometry2D.is_point_in_polygon(p, plan.detour_poly) or not _free(plan, p, 3.0):
			continue
		var y: float = ground.call(p)
		out.append([SHEEP, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.23, 0.23, 0.23)), Vector3(p.x, y, p.y))])
		flock += 1
	# Ability signs: a yellow board on a post at the start of each detour stretch, with its name.
	for st in plan.STAT_SIGNS:
		var r = course.segments[st[0]]["route"]
		var shw: float = course.segments[st[0]]["half_width"]
		var q: Vector3 = r.world_at(2.0, int(st[1]) * (shw + 1.6))
		var p := Vector2(q.x, q.z)
		if not _free(plan, p, 0.4):
			errors.append("no room for the %s sign" % st[2])
			continue
		var y: float = ground.call(p)
		out.append(["pillar-wood", Transform3D(Basis().scaled(Vector3(0.8, 2.6, 0.8)), Vector3(p.x, y, p.y))])
		# Board faces the oncoming racers.
		var face := Basis(Vector3.UP, r.heading_at(2.0) + PI)
		boards.append(Transform3D(face, Vector3(p.x, y + 2.95, p.y)))
		labels.append([st[3], Transform3D(face, Vector3(p.x, y + 2.95, p.y) + face.z * 0.05), 64])
	# Shop goods on the stalls, and the shop and factory names.
	for b in plan.buildings:
		if not b["kind"] in ["shop", "factory", "farmhouse"]:
			continue
		var fwd := Vector2(sin(b["yaw"]), cos(b["yaw"]))
		var face := Basis(Vector3.UP, b["yaw"])
		var front: Vector2 = b["pos"] + fwd * (b["size"].y * 0.5 + 0.05)
		var gy: float = ground.call(front)
		labels.append([b["label"], Transform3D(face, Vector3(front.x, gy + FLOOR_H + 0.4, front.y)), 96])
		if b["kind"] == "shop":
			var rgt := Vector2(fwd.y, -fwd.x)
			var stall: Vector2 = b["pos"] + fwd * (b["size"].y * 0.5 + 0.4) + rgt * (b["size"].x / _cells(b["size"].x, CELL, true) * 0.5)
			var cheese: bool = String(b["label"]).begins_with("K")
			for k in 3:
				var at3 := Vector3(stall.x, ground.call(stall) + 0.78, stall.y) + face * Vector3((k - 1) * 0.45, 0, 0)
				if cheese:
					out.append([CHEESE, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.18, 0.18, 0.18)), at3)])
				else:
					out.append([CHOCOLATE, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.5, 0.5, 0.5)), at3)])
	return {"modules": out, "flags": flags, "signs": signs, "labels": labels, "boards": boards}


## A small loop of grazing spots round an animal's home, each clear of roads, buildings and
## water, as WANDER_POINTS x (x, y, z). The home itself is always the first spot.
func wander_path(plan, shape, home: Vector3, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array([home.x, home.y, home.z])
	var tries := 0
	while out.size() < WANDER_POINTS * 3 and tries < 200:
		tries += 1
		var a := rng.randf() * TAU
		var p := Vector2(home.x, home.z) + Vector2(cos(a), sin(a)) * rng.randf_range(1.5, WANDER_RADIUS)
		if not _free(plan, p, WANDER_CLEAR):
			continue
		out.append_array([p.x, shape.height_at(p.x, p.y), p.y])
	if out.size() < WANDER_POINTS * 3:
		errors.append("no room for an animal to wander at (%.0f, %.0f)" % [home.x, home.z])
	return out


## p keeps `clear` metres from every road edge, building, the pond and the brook.
static func _free(plan, p: Vector2, clear: float) -> bool:
	if float(plan.road_edge(p)[0]) < clear:
		return false
	for b in plan.buildings:
		if (b["pos"] as Vector2).distance_to(p) < (b["size"] as Vector2).length() * 0.5 + clear:
			if Geometry2D.is_point_in_polygon(p, Geometry2D.offset_polygon(plan.footprint(b), clear)[0]):
				return false
	if Geometry2D.is_point_in_polygon(p, plan.pond):
		return false
	if plan.polyline_dist(p, plan.alp_stream) < plan.ALP_HALF_WIDTH + clear:
		return false
	return plan.polyline_dist(p, plan.brook) > plan.BROOK_HALF_WIDTH + clear
