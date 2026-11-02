@tool
extends Node3D
## The village's buildings and its covered bridge, built by world/village/chalet_builder.gd when
## the node enters the tree (also in the editor) from the few numbers tools/bake_village.gd
## stores, so the baked scene stays small: per chunk of the village a main MeshInstance3D (a
## surface per material) and one for the small pieces (no shadows, hidden from afar).

const ChaletBuilder = preload("res://world/village/chalet_builder.gd")
const FIELDS := 8

## Building kinds (world/village/village_plan.gd), one per building.
@export var kinds := PackedStringArray()
## Per building: x, y (floor), z, yaw, width, depth, seed, rise of the ground under it.
@export var houses := PackedFloat32Array()
## Covered bridge cells: x, y, z, heading per cell.
@export var bridge := PackedFloat32Array()
@export var bridge_cell := 2.0
@export var bridge_half_width := 4.0

## Vertices built, for the bake's report and the benchmarks.
var vertex_count := 0


func _ready() -> void:
	for c in get_children():
		if c.has_meta(&"houses"):
			c.queue_free()
	var t0 := Time.get_ticks_usec()
	var b := build(kinds, houses, bridge, bridge_cell, bridge_half_width)
	if not b.errors.is_empty():
		push_error("village_houses: %s" % "; ".join(b.errors))
		return
	var meshes := b.meshes()
	if not b.errors.is_empty():
		push_error("village_houses: %s" % "; ".join(b.errors))
		return
	for key: Vector2i in meshes:
		var parts: Dictionary = meshes[key]
		for part in ["main", "detail"]:
			if parts[part] == null:
				continue
			var mi := MeshInstance3D.new()
			mi.name = "%s_%d_%d" % [part.capitalize(), key.x, key.y]
			mi.mesh = parts[part]
			mi.position = parts["centre"]
			if part == "detail":
				# Small pieces: no shadows, and gone where they'd be a pixel or two.
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visibility_range_end = ChaletBuilder.DETAIL_RANGE
			mi.set_meta(&"houses", true)
			add_child(mi)
	vertex_count = b.vertex_count()
	print("village_houses: %d buildings, %d vertices in %d chunks, built in %d ms" % [kinds.size(), vertex_count, meshes.size(), (Time.get_ticks_usec() - t0) / 1000])


## Runs the builder over the stored numbers (the bake calls it too, for the props).
static func build(p_kinds: PackedStringArray, p_houses: PackedFloat32Array, p_bridge: PackedFloat32Array, cell: float, half_width: float) -> ChaletBuilder:
	var b := ChaletBuilder.new()
	if p_houses.size() != p_kinds.size() * FIELDS:
		b.errors.append("%d numbers for %d buildings" % [p_houses.size(), p_kinds.size()])
		return b
	for i in p_kinds.size():
		var k := i * FIELDS
		var h := p_houses
		b.add_building(p_kinds[i], Vector3(h[k], h[k + 1], h[k + 2]), h[k + 3], Vector2(h[k + 4], h[k + 5]), int(h[k + 6]), h[k + 7])
	var cells: Array = []
	for i in range(0, p_bridge.size(), 4):
		cells.append(Transform3D(Basis(Vector3.UP, p_bridge[i + 3]), Vector3(p_bridge[i], p_bridge[i + 1], p_bridge[i + 2])))
	if not cells.is_empty():
		b.add_bridge(cells, cell, half_width)
	return b
