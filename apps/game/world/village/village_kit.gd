extends RefCounted
## Builds the village's buildings and props from the Kenney Fantasy Town Kit (CC0, see
## res://assets/village/kenney_fantasy_town/License_Kenney.txt) and the Quaternius nature kit.
## Each building is a list of kit modules with transforms; tools/bake_village.gd merges every
## module type into one MultiMesh, so the whole village costs a few dozen draw calls.
##
## Kenney modules are 1 m cells: walls stand on the cell's +x edge, roofs cover the cell. A
## building is laid out on a grid of cells (stretched to its footprint), front facing +z
## (towards its road), origin at the footprint centre on the ground. All modules share one
## material: the kit's colour map recoloured to a Swiss palette (dark shingle roofs, honey and
## dark timber, white plaster, grey stone), made once by swiss_material().
##
## Building kinds follow the village plan: chalet, inn, arcade, bakery, church, mill, barn, school.

const KIT := "res://assets/village/kenney_fantasy_town/"
const NATURE := "res://assets/nature/quaternius/"
const VMAT_DIR := "res://world/village/materials/"
const SWISS_MAT := VMAT_DIR + "kenney_swiss.tres"
const SWISS_TEX := VMAT_DIR + "kenney_swiss_colormap.res"

const FLOOR_H := 2.6        # metres per storey
const CELL := 2.25          # target cell width in metres
const ROOF_RISE := 0.63     # Kenney "roof" rises this much per cell

## Colour map recolouring: [x0, y0, x1, y1] pixel block of colormap.png -> target HSV.
static func _recolour() -> Array:
	return [
	[64, 384, 128, 512, Color.from_hsv(0.07, 0.35, 0.36)],    # teal roofs -> dark shingles
	[192, 256, 256, 384, Color.from_hsv(0.08, 0.62, 0.66)],   # light wood -> honey timber
	[256, 256, 320, 384, Color.from_hsv(0.06, 0.6, 0.42)],    # brown wood -> dark timber
	[256, 384, 384, 512, Color.from_hsv(0.06, 0.55, 0.4)],    # dark wood trims
	[64, 256, 128, 384, Color.from_hsv(0.11, 0.06, 0.96)],    # lavender stone -> white plaster
	[448, 384, 512, 512, Color.from_hsv(0.1, 0.05, 0.74)],    # grey stone -> warm grey stone
	]

var errors: PackedStringArray = []
var _meshes := {}           # module name -> Mesh


## Model file of a module: a Kenney kit name, "nature:<name>" for the Quaternius kit, or a
## res:// path.
static func model_path(module: String) -> String:
	if module.begins_with("res://"):
		return module
	if module.begins_with("nature:"):
		return NATURE + module.trim_prefix("nature:") + ".gltf"
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
	var root: Node = (load(path) as PackedScene).instantiate()
	var mi := _first_mesh(root)
	var m: Mesh = mi.mesh if mi != null else null
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


## The shared Swiss-palette material for every Kenney module (created once, then editable).
static func swiss_material() -> Material:
	if ResourceLoader.exists(SWISS_MAT):
		return load(SWISS_MAT)
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
	var tex := ImageTexture.create_from_image(src)
	ResourceSaver.save(tex, SWISS_TEX)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(SWISS_TEX)
	m.roughness = 0.85
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ResourceSaver.save(m, SWISS_MAT)
	return load(SWISS_MAT)


# ---------------------------------------------------------------- building grid helpers

## One storey of walls round a box of nx x nz cells (sx, sz metres each) at height y.
## `pick` chooses the module for each wall: pick.call(side, i, n) with side "front", "back",
## "left", "right" and i the cell index along that side (n cells).
static func _walls(out: Array, nx: int, nz: int, sx: float, sz: float, y: float, h: float, pick: Callable) -> void:
	var w := nx * sx
	var d := nz * sz
	for i in nx:
		var x := -w * 0.5 + (i + 0.5) * sx
		# Front (+z): local +x -> +z.
		out.append([pick.call("front", i, nx), Transform3D(Basis(Vector3.UP, -PI * 0.5).scaled_local(Vector3(sz, h, sx)), Vector3(x, y, d * 0.5 - sz * 0.5))])
		out.append([pick.call("back", nx - 1 - i, nx), Transform3D(Basis(Vector3.UP, PI * 0.5).scaled_local(Vector3(sz, h, sx)), Vector3(x, y, -d * 0.5 + sz * 0.5))])
	for k in nz:
		var z := -d * 0.5 + (k + 0.5) * sz
		out.append([pick.call("right", k, nz), Transform3D(Basis().scaled_local(Vector3(sx, h, sz)), Vector3(w * 0.5 - sx * 0.5, y, z))])
		out.append([pick.call("left", nz - 1 - k, nz), Transform3D(Basis(Vector3.UP, PI).scaled_local(Vector3(sx, h, sz)), Vector3(-w * 0.5 + sx * 0.5, y, z))])


## Gable roof over nx (even) x nz cells, ridge along z, from height y, with `eave_front` and
## `eave_back` extra cells of overhang. `module` is "roof" (low) or "roof-high" (steep).
## Returns the ridge height.
static func _roof(out: Array, nx: int, nz: int, sx: float, sz: float, y: float, pitch: float,
		eave_front: float, eave_back: float, module := "roof") -> float:
	var w := nx * sx
	var d := nz * sz
	var half := nx / 2
	var rise := (ROOF_RISE if module == "roof" else 1.14) * pitch
	var depth := d + (eave_front + eave_back) * sz
	var zc := (eave_front - eave_back) * sz * 0.5
	for i in nx:
		var left := i < half
		var step := i if left else nx - 1 - i
		var x := -w * 0.5 + (i + 0.5) * sx
		var b := Basis() if left else Basis(Vector3.UP, PI)
		b = b.scaled_local(Vector3(sx * 1.04, sx * pitch, depth))
		out.append([module, Transform3D(b, Vector3(x, y + step * rise * sx, zc))])
	return y + half * rise * sx


## Triangle gable fills (front and back) under a `_roof`, as one wood-panel mesh.
static func gable_mesh(nx: int, nz: int, sx: float, sz: float, y: float, ridge: float, inset := 0.15) -> PackedVector3Array:
	var w := nx * sx
	var d := nz * sz
	var tris := PackedVector3Array()
	for side: float in [1.0, -1.0]:
		var z := side * (d * 0.5 - inset)
		var a := Vector3(-w * 0.5, y, z)
		var b := Vector3(w * 0.5, y, z)
		var c := Vector3(0, ridge, z)
		if side > 0.0:
			tris.append_array([a, c, b])
		else:
			tris.append_array([a, b, c])
	return tris


static func _cells(size: float, target := CELL, even := false) -> int:
	var n := maxi(1, int(round(size / target)))
	if even and n % 2 == 1:
		n += 1 if size / target > n else -1
		n = maxi(2, n)
	return n


# ---------------------------------------------------------------- buildings

## Modules and extra geometry for one building: {modules: [[name, Transform3D]], gables:
## PackedVector3Array (wood triangles)}, or null for an unknown kind.
func building(kind: String, size: Vector2, seed_: int) -> Variant:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	match kind:
		"chalet", "bakery":
			return _chalet(size, rng, kind == "bakery")
		"inn":
			return _inn(size, rng)
		"arcade":
			return _arcade(size, rng)
		"church":
			return _church(size, rng)
		"mill":
			return _mill(size, rng)
		"barn":
			return _barn(size, rng)
		"school":
			return _school(size, rng)
		"factory":
			return _factory(size, rng)
		"shop":
			return _shop(size, rng)
		"farmhouse":
			return _farmhouse(size, rng)
	errors.append("unknown building kind '%s'" % kind)
	return null


## Bernese chalet: white plaster ground floor, timber upper floor with shutters and a balcony
## across the gable front, low roof with deep eaves.
func _chalet(size: Vector2, rng: RandomNumberGenerator, bakery: bool) -> Dictionary:
	var nx := _cells(size.x, CELL, true)
	var nz := _cells(size.y)
	var sx := size.x / nx
	var sz := size.y / nz
	var out: Array = []
	var door := rng.randi_range(0, nx - 1)
	_walls(out, nx, nz, sx, sz, 0.0, FLOOR_H, func(side, i, n):
		if side == "front":
			return "wall-door" if i == door else ("wall-window-glass" if bakery else "wall-window-shutters")
		return "wall-window-small" if i % 2 == 1 else "wall")
	var upper := FLOOR_H
	_walls(out, nx, nz, sx, sz, upper, FLOOR_H, func(side, i, n):
		if side == "front" or side == "back":
			return "wall-wood-window-shutters"
		return "wall-wood-window-small" if i % 2 == 0 else "wall-wood")
	var floors := 2
	if rng.randf() < 0.35:
		_walls(out, nx, nz, sx, sz, upper + FLOOR_H, FLOOR_H, func(side, i, n):
			return "wall-wood-window-shutters" if side == "front" else "wall-wood")
		floors = 3
	var top := floors * FLOOR_H
	# Balcony on the gable front at the first upper floor.
	var bz := nz * sz * 0.5 + 0.55
	for i in nx:
		var x := -nx * sx * 0.5 + (i + 0.5) * sx
		out.append(["balcony-wall-fence", Transform3D(Basis(Vector3.UP, -PI * 0.5).scaled_local(Vector3(1.1, 1.0, sx)), Vector3(x, upper, bz - 0.55))])
		out.append(["planks", Transform3D(Basis().scaled_local(Vector3(sx, 1.0, 1.1)), Vector3(x, upper - 0.05, bz - 0.05))])
	var ridge := _roof(out, nx, nz, sx, sz, top, 0.55, 0.6, 0.35)
	if rng.randf() < 0.7:
		out.append(["chimney", Transform3D(Basis().scaled_local(Vector3(1.6, 2.0, 1.6)), Vector3(sx * 0.6, top + (ridge - top) * 0.5, -sz * 0.4))])
	if bakery:
		out.append(["stall-red", Transform3D(Basis(Vector3.UP, PI * 0.5).scaled_local(Vector3(2.2, 2.2, 2.2)), Vector3(sx, 0, nz * sz * 0.5 + 0.45))])
	return {"modules": out, "gables": gable_mesh(nx, nz, sx, sz, top, ridge)}


## Gasthaus: three storeys, the ground floor plaster with a wide door, timber above, red banners.
func _inn(size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var nx := _cells(size.x, CELL, true)
	var nz := _cells(size.y)
	var sx := size.x / nx
	var sz := size.y / nz
	var out: Array = []
	_walls(out, nx, nz, sx, sz, 0.0, FLOOR_H, func(side, i, n):
		if side == "front":
			return "wall-doorway-square-wide" if i == n / 2 else "wall-window-glass"
		return "wall-window-shutters")
	for f in [1, 2]:
		_walls(out, nx, nz, sx, sz, f * FLOOR_H, FLOOR_H, func(side, i, n):
			return "wall-wood-window-shutters" if side != "back" or i % 2 == 0 else "wall-wood")
	var top := 3 * FLOOR_H
	var ridge := _roof(out, nx, nz, sx, sz, top, 0.6, 0.6, 0.4)
	for i: int in [0, nx - 1]:
		var x := -nx * sx * 0.5 + (i + 0.5) * sx
		out.append(["banner-red", Transform3D(Basis(Vector3.UP, -PI * 0.5).scaled_local(Vector3(2.0, 2.4, 2.0)), Vector3(x, FLOOR_H + 0.3, nz * sz * 0.5 - 0.6))])
	out.append(["chimney", Transform3D(Basis().scaled_local(Vector3(1.8, 2.4, 1.8)), Vector3(-sx, top + (ridge - top) * 0.45, 0.0))])
	return {"modules": out, "gables": gable_mesh(nx, nz, sx, sz, top, ridge)}


## Laubengasse house: an arcade of round arches on the ground floor, plaster storeys above.
func _arcade(size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var nx := _cells(size.x, CELL, true)
	var nz := _cells(size.y)
	var sx := size.x / nx
	var sz := size.y / nz
	var out: Array = []
	_walls(out, nx, nz, sx, sz, 0.0, FLOOR_H, func(side, i, n):
		return "wall-arch" if side == "front" else "wall")
	var upper := "wall-window-shutters" if rng.randf() < 0.5 else "wall-window-glass"
	for f in [1, 2]:
		_walls(out, nx, nz, sx, sz, f * FLOOR_H, FLOOR_H, func(side, i, n):
			return upper if side == "front" or side == "back" else "wall")
	var top := 3 * FLOOR_H
	var ridge := _roof(out, nx, nz, sx, sz, top, 0.6, 0.5, 0.3)
	return {"modules": out, "gables": gable_mesh(nx, nz, sx, sz, top, ridge)}


## Village church: a white nave with a steep roof and a tower with a tall pointed spire on the
## front, facing the road.
func _church(size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var nx := 2
	var nz := _cells(size.y, 3.0)
	var sx := size.x / nx
	var sz := size.y / nz
	var out: Array = []
	var nave_h := FLOOR_H * 1.9
	_walls(out, nx, nz, sx, sz, 0.0, nave_h, func(side, i, n):
		if side == "front":
			return "wall-doorway-round"
		return "wall-window-stone" if side != "back" else "wall")
	var ridge := _roof(out, nx, nz, sx, sz, nave_h, 0.75, 0.15, 0.15, "roof-high")
	# Tower: one cell wide, standing proud of the front.
	var tw := 3.6
	# Tower inside the footprint, flush with the front.
	var tz := nz * sz * 0.5 - tw * 0.5
	var storeys := 5
	for f in storeys:
		var y := f * FLOOR_H * 1.1
		for side in 4:
			var rot := -PI * 0.5 + side * PI * 0.5
			var m := "wall-window-round" if f == storeys - 1 else ("wall-doorway-round" if f == 0 and side == 0 else "wall")
			var b := Basis(Vector3.UP, rot).scaled_local(Vector3(tw, FLOOR_H * 1.1, tw))
			out.append([m, Transform3D(b, Vector3(0, y, tz))])
	var spire_y := storeys * FLOOR_H * 1.1
	out.append(["roof-high-point", Transform3D(Basis().scaled_local(Vector3(tw * 1.05, 8.5, tw * 1.05)), Vector3(0, spire_y, tz))])
	return {"modules": out, "gables": gable_mesh(nx, nz, sx, sz, nave_h, ridge, 0.1)}


## Mill on the pond: timber over a stone plinth, a water wheel on the pond side.
func _mill(size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var nx := _cells(size.x, CELL, true)
	var nz := _cells(size.y)
	var sx := size.x / nx
	var sz := size.y / nz
	var out: Array = []
	_walls(out, nx, nz, sx, sz, 0.0, FLOOR_H, func(side, i, n):
		return "wall-door" if side == "front" and i == 0 else "wall-window-small")
	_walls(out, nx, nz, sx, sz, FLOOR_H, FLOOR_H, func(side, i, n):
		return "wall-wood-window-shutters" if side == "front" else "wall-wood-detail-cross")
	var top := 2 * FLOOR_H
	var ridge := _roof(out, nx, nz, sx, sz, top, 0.55, 0.4, 0.4)
	# Water wheel on the back wall (the pond side), turning in the water.
	out.append(["watermill", Transform3D(Basis(Vector3.UP, PI * 0.5).scaled_local(Vector3(3.0, 3.0, 3.0)), Vector3(0, 1.4, -nz * sz * 0.5 - 0.9))])
	return {"modules": out, "gables": gable_mesh(nx, nz, sx, sz, top, ridge)}


## Hay barn: dark timber with cross-braced boards, wide low roof.
## Cheese and chocolate factory: a long plaster hall with big windows, timber upper floor and
## two tall chimneys.
func _factory(size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var nx := _cells(size.x, 2.5, true)
	var nz := _cells(size.y)
	var sx := size.x / nx
	var sz := size.y / nz
	var out: Array = []
	_walls(out, nx, nz, sx, sz, 0.0, FLOOR_H * 1.2, func(side, i, n):
		if side == "front" and i == n / 2:
			return "wall-doorway-square-wide"
		return "wall-window-glass")
	_walls(out, nx, nz, sx, sz, FLOOR_H * 1.2, FLOOR_H, func(side, i, n):
		return "wall-wood-window-shutters" if side == "front" or side == "back" else "wall-wood")
	var top := FLOOR_H * 2.2
	var ridge := _roof(out, nx, nz, sx, sz, top, 0.5, 0.3, 0.3)
	for x: float in [-size.x * 0.3, size.x * 0.3]:
		out.append(["chimney", Transform3D(Basis().scaled_local(Vector3(2.6, 6.0, 2.6)), Vector3(x, top, -sz * 0.6))])
	return {"modules": out, "gables": gable_mesh(nx, nz, sx, sz, top, ridge)}


## Village shop (cheese or chocolate): a small chalet with a big shop window and a striped
## awning stall in front.
func _shop(size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var nx := _cells(size.x, CELL, true)
	var nz := _cells(size.y)
	var sx := size.x / nx
	var sz := size.y / nz
	var out: Array = []
	_walls(out, nx, nz, sx, sz, 0.0, FLOOR_H, func(side, i, n):
		if side == "front":
			return "wall-door" if i == 0 else "wall-window-glass"
		return "wall")
	_walls(out, nx, nz, sx, sz, FLOOR_H, FLOOR_H, func(side, i, n):
		return "wall-wood-window-shutters" if side == "front" else "wall-wood")
	var top := 2 * FLOOR_H
	var ridge := _roof(out, nx, nz, sx, sz, top, 0.55, 0.6, 0.3)
	out.append(["stall-red", Transform3D(Basis(Vector3.UP, PI * 0.5).scaled_local(Vector3(2.0, 2.0, 2.0)), Vector3(sx * 0.5, 0, nz * sz * 0.5 + 0.4))])
	return {"modules": out, "gables": gable_mesh(nx, nz, sx, sz, top, ridge)}


## Farmhouse: a big Emmental farmhouse, timber on a stone base, a huge low roof.
func _farmhouse(size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var nx := _cells(size.x, CELL, true)
	var nz := _cells(size.y)
	var sx := size.x / nx
	var sz := size.y / nz
	var out: Array = []
	_walls(out, nx, nz, sx, sz, 0.0, FLOOR_H, func(side, i, n):
		if side == "front" and i == 1:
			return "wall-door"
		return "wall-window-shutters" if side == "front" else "wall")
	_walls(out, nx, nz, sx, sz, FLOOR_H, FLOOR_H, func(side, i, n):
		return "wall-wood-window-shutters" if side == "front" else "wall-wood-detail-cross")
	var top := 2 * FLOOR_H
	var ridge := _roof(out, nx, nz, sx, sz, top, 0.5, 0.9, 0.6)
	return {"modules": out, "gables": gable_mesh(nx, nz, sx, sz, top, ridge)}


func _barn(size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var nx := _cells(size.x, CELL, true)
	var nz := _cells(size.y)
	var sx := size.x / nx
	var sz := size.y / nz
	var out: Array = []
	_walls(out, nx, nz, sx, sz, 0.0, FLOOR_H * 1.3, func(side, i, n):
		if side == "front" and (i == n / 2 or i == n / 2 - 1):
			return "wall-wood-doorway-square-wide"
		return "wall-wood-detail-cross" if i % 2 == 0 else "wall-wood")
	var top := FLOOR_H * 1.3
	var ridge := _roof(out, nx, nz, sx, sz, top, 0.65, 0.4, 0.4)
	return {"modules": out, "gables": gable_mesh(nx, nz, sx, sz, top, ridge)}


## Schoolhouse: two plaster storeys with many windows and a small bell turret.
func _school(size: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var nx := _cells(size.x, CELL, true)
	var nz := _cells(size.y)
	var sx := size.x / nx
	var sz := size.y / nz
	var out: Array = []
	_walls(out, nx, nz, sx, sz, 0.0, FLOOR_H, func(side, i, n):
		if side == "front" and i == n / 2:
			return "wall-doorway-round"
		return "wall-window-glass")
	_walls(out, nx, nz, sx, sz, FLOOR_H, FLOOR_H, func(side, i, n):
		return "wall-window-glass")
	var top := 2 * FLOOR_H
	var ridge := _roof(out, nx, nz, sx, sz, top, 0.6, 0.3, 0.3)
	out.append(["roof-point", Transform3D(Basis().scaled_local(Vector3(2.2, 3.0, 2.2)), Vector3(0, ridge - 0.2, 0))])
	return {"modules": out, "gables": gable_mesh(nx, nz, sx, sz, top, ridge)}


# ---------------------------------------------------------------- covered bridge

## Emmental-style covered wooden bridge over pond_bridge around s = mid: timber side walls with
## open windows, a roof, gable ends. Modules in world space.
func covered_bridge(r, mid: float, half_len: float, road_hw: float) -> Dictionary:
	var out: Array = []
	var cell := 2.0
	var n := int(round(half_len * 2.0 / cell))
	var w := road_hw * 2.0 + 2.0
	var h := 2.8
	for k in n:
		var s: float = mid - half_len + (k + 0.5) * half_len * 2.0 / n
		var c: Vector3 = r.pos_at(s)
		var yaw: float = r.heading_at(s)
		var basis := Basis(Vector3.UP, yaw)
		for side: float in [1.0, -1.0]:
			# Walls stand on the +x edge of their cell: turn them to face out on each side.
			var b := basis * Basis(Vector3.UP, 0.0 if side < 0.0 else PI)
			var m := "wall-wood-window-small" if k % 2 == 1 else "wall-wood"
			out.append([m, Transform3D(b.scaled_local(Vector3(w, h, cell * 1.02)), c)])
		# Shingle roof: two low "roof" slopes meeting over the deck centre, with eaves.
		for side: float in [-1.0, 1.0]:
			var rb := basis * Basis(Vector3.UP, 0.0 if side < 0.0 else PI)
			out.append(["roof", Transform3D(rb.scaled_local(Vector3(w * 0.5 + 0.6, 1.4, cell * 1.02)), c + basis * Vector3(side * (w * 0.25 + 0.3), h, 0))])
	return {"modules": out}


# ---------------------------------------------------------------- props

## Street furniture and planting. Returns [[module, Transform3D world]] (modules may be
## "nature:<name>" for the Quaternius kit).
func props(course, plan, shape) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ground := func(p: Vector2) -> float: return shape.height_at(p.x, p.y)
	# Fountain on the square: round basin with its centre piece, lime tree beside it.
	var f: Vector2 = plan.fountain
	out.append(["fountain-round-detail", Transform3D(Basis().scaled(Vector3(2.4, 2.4, 2.4)), Vector3(f.x, ground.call(f), f.y))])
	out.append(["fountain-center", Transform3D(Basis().scaled(Vector3(2.4, 2.4, 2.4)), Vector3(f.x, ground.call(f) + 0.3, f.y))])
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
				var q: Vector3 = r.world_at(s, side * (hw + 0.9))
				var p := Vector2(q.x, q.z)
				if _free(plan, p, 0.3):
					var yaw: float = r.heading_at(s)
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
const SHEEP := "res://assets/village/poly_pizza/Sheep_2.glb"
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
		var sc := 0.34 if model == COW_2 else (0.65 if model == SHEEP else 0.32)
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
		out.append([SHEEP, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.55, 0.55, 0.55)), Vector3(p.x, y, p.y))])
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
