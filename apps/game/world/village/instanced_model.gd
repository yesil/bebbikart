@tool
extends MultiMeshInstance3D
## Many copies of one model (a Kenney kit module or a Quaternius plant), placed by
## tools/bake_village.gd. The scene stores only the model path and the transforms; the MultiMesh
## is built when the node enters the tree (also in the editor), so the baked scene stays small.

## glTF/GLB model whose first mesh is instanced.
@export_file("*.glb", "*.gltf") var model := ""
## 12 floats per copy: basis x, y, z columns then origin.
@export var transforms := PackedFloat32Array()
## Overrides the model's own materials when set (the Swiss Kenney palette).
@export var override: Material


func _ready() -> void:
	var ps: PackedScene = load(model) if ResourceLoader.exists(model) else null
	if ps == null:
		push_error("instanced_model %s: cannot load %s" % [name, model])
		return
	var root := ps.instantiate()
	var mi := _first_mesh(root)
	if mi == null:
		root.free()
		push_error("instanced_model %s: no mesh in %s" % [name, model])
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mi.mesh
	root.free()
	var n := transforms.size() / 12
	mm.instance_count = n
	for i in n:
		var k := i * 12
		var t := transforms
		mm.set_instance_transform(i, Transform3D(Vector3(t[k], t[k + 1], t[k + 2]), Vector3(t[k + 3], t[k + 4], t[k + 5]),
			Vector3(t[k + 6], t[k + 7], t[k + 8]), Vector3(t[k + 9], t[k + 10], t[k + 11])))
	multimesh = mm
	material_override = override


static func pack(xfs: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for x: Transform3D in xfs:
		out.append_array([x.basis.x.x, x.basis.x.y, x.basis.x.z, x.basis.y.x, x.basis.y.y, x.basis.y.z,
			x.basis.z.x, x.basis.z.y, x.basis.z.z, x.origin.x, x.origin.y, x.origin.z])
	return out


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r != null:
			return r
	return null
