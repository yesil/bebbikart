extends Node3D
## Placeholder toy racer (the real racer kit is WS3d): coloured body, head, wheels and a name tag.
## Pose comes straight from the sim racer every frame.

const CameraHud = preload("res://ui/camera_hud.gd")

var racer = null   # sim/racer.gd
var color := Color.WHITE
var nickname := ""
var _body: Node3D
var _label: Label3D
var _boost: MeshInstance3D


func setup(p_racer, p_color: Color, p_nickname: String) -> void:
	racer = p_racer
	color = p_color
	nickname = p_nickname
	_body = Node3D.new()
	add_child(_body)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.5
	var chassis := BoxMesh.new()
	chassis.size = Vector3(1.0, 0.45, 1.5)
	_part(chassis, m, Vector3(0, 0.45, 0))
	var head := SphereMesh.new()
	head.radius = 0.32
	head.height = 0.64
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(1.0, 0.85, 0.7)
	_part(head, hm, Vector3(0, 0.95, -0.15))
	var hat := CylinderMesh.new()
	hat.top_radius = 0.22
	hat.bottom_radius = 0.34
	hat.height = 0.2
	_part(hat, m, Vector3(0, 1.22, -0.15))
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.12, 0.12, 0.14)
	for x in [-0.55, 0.55]:
		for z in [-0.5, 0.5]:
			var w := CylinderMesh.new()
			w.top_radius = 0.22
			w.bottom_radius = 0.22
			w.height = 0.18
			_part(w, wm, Vector3(x, 0.22, z)).rotation = Vector3(0, 0, PI / 2)
	var flame := PrismMesh.new()
	flame.size = Vector3(0.5, 0.9, 0.3)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1.0, 0.6, 0.1)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.5, 0.1)
	fm.emission_energy_multiplier = 3.0
	_boost = _part(flame, fm, Vector3(0, 0.45, -1.15))
	_boost.rotation = Vector3(-PI / 2, 0, 0)
	_boost.visible = false
	_label = Label3D.new()
	_label.text = nickname
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 48
	_label.pixel_size = 0.01
	_label.outline_size = 12
	_label.modulate = color.lightened(0.3)
	_label.no_depth_test = true
	_label.position = Vector3(0, 1.9, 0)
	_label.layers = CameraHud.NAME_TAG_LAYER  # not drawn in the picture-in-picture inset
	add_child(_label)
	sync()


## Where the second camera (ui/camera_hud.gd) looks, in world space.
func shot_frame() -> Dictionary:
	return {
		"root": global_position,
		"head": _body.global_transform * Vector3(0, 0.95, -0.15),
		"head_r": 0.32,
		"center": _body.global_transform * Vector3(0, 0.6, 0),
		"radius": 1.1,
		"fwd": _body.global_basis.z.normalized(),
	}


func _part(mesh: Mesh, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	_body.add_child(mi)
	return mi


func sync() -> void:
	if racer == null:
		return
	visible = racer.state == "racing"
	if not visible:
		return
	position = racer.world_pos() - Vector3(0, 0.0, 0)
	# Model faces +z; route heading is measured from +z towards +x.
	_body.rotation_order = EULER_ORDER_YXZ
	_body.rotation = Vector3(racer.pitch(), racer.yaw(), racer.roll())
	_boost.visible = racer.boost_t > 0.0
	if _boost.visible:
		_boost.scale = Vector3.ONE * (0.8 + 0.4 * randf())
	var tag := nickname
	if racer.slipping:
		tag += " ~"
	if racer.in_water:
		tag += " ≈"
	_label.text = tag
