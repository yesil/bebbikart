@tool
extends Node3D
## The village's buildings and its covered bridge, built by world/village/chalet_builder.gd when
## the node enters the tree (also in the editor) from the few numbers tools/bake_village.gd
## stores, so the baked scene stays small: a MeshInstance3D per chunk of the village (a surface
## per material), and on a finer grid ones for the small pieces (no shadows, hidden from afar).

const ChaletBuilder = preload("res://world/village/chalet_builder.gd")
const FIELDS := 8
const BRIDGE_FIELDS := 5

## Building kinds (world/village/village_plan.gd), one per building.
@export var kinds := PackedStringArray()
## Per building: x, y (floor), z, yaw, width, depth, seed, rise of the ground under it.
@export var houses := PackedFloat32Array()
## Covered bridge: x, y, z, heading, pitch of each joint between its cells, along the road's
## centre line.
@export var bridge := PackedFloat32Array()
@export var bridge_half_width := 4.0

## Vertices built, for the bake's report and the benchmarks.
var vertex_count := 0


func _ready() -> void:
	for c in get_children():
		if c.has_meta(&"houses"):
			c.queue_free()
	var t0 := Time.get_ticks_usec()
	var b := build(kinds, houses, bridge, bridge_half_width)
	if not b.errors.is_empty():
		push_error("village_houses: %s" % "; ".join(b.errors))
		return
	var meshes := b.meshes()
	if not b.errors.is_empty():
		push_error("village_houses: %s" % "; ".join(b.errors))
		return
	var parts := 0
	for chunk: Dictionary in meshes:
		var mi := MeshInstance3D.new()
		mi.name = "%s%d" % ["Detail" if chunk["detail"] else "Main", parts]
		mi.mesh = chunk["mesh"]
		mi.position = chunk["centre"]
		if chunk["detail"]:
			# Small pieces: no shadows, and gone where they'd be a pixel or two.
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = ChaletBuilder.DETAIL_RANGE
		mi.set_meta(&"houses", true)
		add_child(mi)
		parts += 1
	vertex_count = b.vertex_count()
	print("village_houses: %d buildings, %d vertices in %d meshes, built in %d ms" % [kinds.size(), vertex_count, meshes.size(), (Time.get_ticks_usec() - t0) / 1000])


## Runs the builder over the stored numbers (the bake calls it too, for the props).
static func build(p_kinds: PackedStringArray, p_houses: PackedFloat32Array, p_bridge: PackedFloat32Array, half_width: float) -> ChaletBuilder:
	var b := ChaletBuilder.new()
	if p_houses.size() != p_kinds.size() * FIELDS:
		b.errors.append("%d numbers for %d buildings" % [p_houses.size(), p_kinds.size()])
		return b
	for i in p_kinds.size():
		var k := i * FIELDS
		var h := p_houses
		b.add_building(p_kinds[i], Vector3(h[k], h[k + 1], h[k + 2]), h[k + 3], Vector2(h[k + 4], h[k + 5]), int(h[k + 6]), h[k + 7])
	var joints: Array = []
	var f := p_bridge
	for i in range(0, f.size() - BRIDGE_FIELDS + 1, BRIDGE_FIELDS):
		# Level across the road, tilted up the hump along it.
		joints.append(Transform3D(Basis(Vector3.UP, f[i + 3]) * Basis(Vector3.RIGHT, -f[i + 4]), Vector3(f[i], f[i + 1], f[i + 2])))
	if joints.size() >= 2:
		b.add_bridge(joints, half_width)
	return b
