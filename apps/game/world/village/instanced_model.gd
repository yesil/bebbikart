@tool
extends MultiMeshInstance3D
## Many copies of one model (a Kenney kit module or a Quaternius plant), placed by
## tools/bake_village.gd. The scene stores only the model path and the transforms; the MultiMesh
## is built when the node enters the tree (also in the editor), so the baked scene stays small.

## glTF/GLB model whose first mesh is instanced, or a mesh resource (the prepared plants).
@export_file("*.glb", "*.gltf", "*.res") var model := ""
## 12 floats per copy: basis x, y, z columns then origin.
@export var transforms := PackedFloat32Array()
## Overrides the model's own materials when set (the Swiss Kenney palette).
@export var override: Material
## Animals: wander_points grazing spots per copy (x, y, z each). A copy walks slowly from spot to
## spot, turning to face the way it goes, and stops at each to graze with a gentle nod. Purely
## visual: the race never sees it. Empty for still models.
@export var wander := PackedFloat32Array()
@export var wander_points := 0

const WALK_SPEED := 0.45           # m/s
const TURN_SPEED := 1.2            # rad/s
const GRAZE_TIME := Vector2(3.0, 9.0)

var _base: Array[Transform3D] = []   # placed transforms (scale, yaw) without the inner node
var _inner := Transform3D()
var _state: Array = []               # per copy: [pos: Vector3, yaw, target index, pause left, phase]
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var res: Resource = load(model) if ResourceLoader.exists(model) else null
	if not (res is PackedScene or res is Mesh):
		push_error("instanced_model %s: cannot load %s as a model or mesh" % [name, model])
		return
	var inner := Transform3D()
	var mesh: Mesh = res as Mesh
	if res is PackedScene:
		var root := (res as PackedScene).instantiate()
		var mi := _first_mesh(root)
		if mi == null:
			root.free()
			push_error("instanced_model %s: no mesh in %s" % [name, model])
			return
		# Many models scale or turn their mesh on an inner node (e.g. Z-up exports at 100x):
		# carry that into every copy, or the mesh comes out tiny or lying down.
		inner = _model_transform(mi)
		mesh = _rest_pose(mi)
		root.free()
	if mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var n := transforms.size() / 12
	mm.instance_count = n
	for i in n:
		var k := i * 12
		var t := transforms
		mm.set_instance_transform(i, Transform3D(Vector3(t[k], t[k + 1], t[k + 2]), Vector3(t[k + 3], t[k + 4], t[k + 5]),
			Vector3(t[k + 6], t[k + 7], t[k + 8]), Vector3(t[k + 9], t[k + 10], t[k + 11])) * inner)
	multimesh = mm
	material_override = override
	_inner = inner
	if wander_points > 0:
		if wander.size() != n * wander_points * 3:
			push_error("instanced_model %s: %d wander floats for %d copies of %d points" % [name, wander.size(), n, wander_points])
			return
		_rng.seed = hash(name)
		for i in n:
			var k := i * 12
			var t := transforms
			var b := Transform3D(Vector3(t[k], t[k + 1], t[k + 2]), Vector3(t[k + 3], t[k + 4], t[k + 5]),
				Vector3(t[k + 6], t[k + 7], t[k + 8]), Vector3(t[k + 9], t[k + 10], t[k + 11]))
			_base.append(b)
			var yaw := atan2(b.basis.z.x, b.basis.z.z)
			_state.append([b.origin, yaw, 1, _rng.randf_range(0.0, GRAZE_TIME.y), _rng.randf() * TAU])
	set_process(wander_points > 0 and not Engine.is_editor_hint())


func _process(delta: float) -> void:
	if multimesh == null:
		return
	for i in _state.size():
		var st: Array = _state[i]
		var pos: Vector3 = st[0]
		var yaw: float = st[1]
		st[4] = float(st[4]) + delta
		var nod := 0.0
		if float(st[3]) > 0.0:
			# Grazing: head down, a slow nod.
			st[3] = float(st[3]) - delta
			nod = 0.08 + 0.06 * sin(float(st[4]) * 1.7)
		else:
			var j: int = st[2]
			var k := (i * wander_points + j) * 3
			var target := Vector3(wander[k], wander[k + 1], wander[k + 2])
			var to := target - pos
			var flat := Vector2(to.x, to.z)
			if flat.length() < 0.15:
				st[2] = (j + 1) % wander_points
				st[3] = _rng.randf_range(GRAZE_TIME.x, GRAZE_TIME.y)
			else:
				var want := atan2(to.x, to.z)
				var turn := wrapf(want - yaw, -PI, PI)
				yaw += clampf(turn, -TURN_SPEED * delta, TURN_SPEED * delta)
				# Walk only once roughly facing the next spot.
				if absf(turn) < 0.6:
					pos += to.normalized() * minf(WALK_SPEED * delta, to.length())
				st[0] = pos
				st[1] = yaw
		var scale := _base[i].basis.get_scale()
		# The Quaternius animals face -z: turn them so they walk head first.
		var basis := Basis(Vector3.UP, yaw + PI) * Basis(Vector3.RIGHT, nod)
		multimesh.set_instance_transform(i, Transform3D(basis.scaled_local(scale), pos) * _inner)


static func pack(xfs: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for x: Transform3D in xfs:
		out.append_array([x.basis.x.x, x.basis.x.y, x.basis.x.z, x.basis.y.x, x.basis.y.y, x.basis.y.z,
			x.basis.z.x, x.basis.z.y, x.basis.z.z, x.origin.x, x.origin.y, x.origin.z])
	return out


## The mesh of a skinned model (the animals) posed on its skeleton's rest pose. A MultiMesh
## draws the raw vertices without the bones, and some models keep parts there that only the
## bones put in place (the Swiss cow's hooves, the whole blacknose sheep). Unskinned models
## come back as they are.
func _rest_pose(mi: MeshInstance3D) -> Mesh:
	var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	if mi.skin == null or skel == null:
		return mi.mesh
	var binds: Array[Transform3D] = []
	for k in mi.skin.get_bind_count():
		var bone := mi.skin.get_bind_bone(k)
		if bone < 0:
			bone = skel.find_bone(mi.skin.get_bind_name(k))
		if bone < 0:
			push_error("instanced_model %s: %s binds unknown bone \"%s\"" % [name, model, mi.skin.get_bind_name(k)])
			return null
		binds.append(skel.get_bone_global_rest(bone) * mi.skin.get_bind_pose(k))
	var src := mi.mesh
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var a := src.surface_get_arrays(s)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		for i in verts.size():
			var p := Vector3.ZERO
			var n := Vector3.ZERO
			for j in per:
				var w := weights[i * per + j]
				if w > 0.0:
					var t := binds[bones[i * per + j]]
					p += (t * verts[i]) * w
					n += (t.basis * normals[i]) * w
			verts[i] = p
			normals[i] = n.normalized()
		a[Mesh.ARRAY_VERTEX] = verts
		a[Mesh.ARRAY_NORMAL] = normals
		a[Mesh.ARRAY_TANGENT] = null
		a[Mesh.ARRAY_BONES] = null
		a[Mesh.ARRAY_WEIGHTS] = null
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), a)
		out.surface_set_material(s, src.surface_get_material(s))
	return out


## Transform of a mesh node relative to its model's root.
static func _model_transform(n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != null and cur.get_parent() != null and cur is Node3D:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r != null:
			return r
	return null
