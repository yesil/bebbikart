extends Node3D
## A racer on the track built from its RacerSpec with the racer kit (drop-in for the placeholder
## world/racer_view.gd: same setup/sync/nickname). Pose comes from the sim racer every frame.

const I18n = preload("res://ui/i18n.gd")
const CameraHud = preload("res://ui/camera_hud.gd")

var racer = null   # sim/racer.gd
var nickname := ""
var toy: ToyRacer
var _body: Node3D
var _was_air := false
var _was_bumped := false
var _box := AABB()   # the toy's bounds at rest, in its own space (frames the inset camera)


func setup(p_racer, spec: Dictionary, drawing: Texture2D, p_nickname: String) -> void:
	racer = p_racer
	nickname = p_nickname
	_body = Node3D.new()
	_body.rotation_order = EULER_ORDER_YXZ
	add_child(_body)
	toy = RacerBuilder.build(spec, drawing)
	if toy == null:
		# Invalid spec: no stand-in racer. Show the problems where the racer would be.
		var l := Label3D.new()
		l.text = I18n.f("racer.invalid_spec", [nickname]) + "\n" + "\n".join(RacerBuilder.last_errors.slice(0, 4))
		l.modulate = Color(1.0, 0.25, 0.2)
		l.outline_size = 12
		l.font_size = 40
		l.pixel_size = 0.01
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.position = Vector3(0, 1.5, 0)
		_body.add_child(l)
		return
	toy.rotation.y = PI  # the kit faces -Z, the sim's heading is measured from +Z
	_body.add_child(toy)
	toy.set_name_tag(nickname)
	toy.show_name_tag(true)
	toy.name_tag.layers = CameraHud.NAME_TAG_LAYER  # not drawn in the picture-in-picture inset
	_box = RacerBuilder._aabb(toy, Transform3D.IDENTITY)
	sync()


## Where the second camera (ui/camera_hud.gd) looks, in world space; {} without a built toy.
func shot_frame() -> Dictionary:
	if toy == null:
		return {}
	var head := toy.head_pivot.get_child(0) as Node3D
	return {
		"root": global_position,
		"head": head.global_position,
		"head_r": 0.42 * head.global_basis.get_scale().y,  # as the avatar renderer frames it
		"center": toy.global_transform * _box.get_center(),
		"radius": _box.size.length() * 0.5 * toy.global_basis.get_scale().x,
		"fwd": _body.global_basis.z.normalized(),
	}


func sync() -> void:
	if racer == null:
		return
	visible = racer.state == "racing"
	if not visible:
		return
	position = racer.world_pos()
	_body.rotation = Vector3(racer.pitch(), racer.yaw(), racer.roll())
	if toy == null:
		return
	toy.set_state({
		"speed": racer.v,
		"lean": clampf(racer.vd * 0.25, -1.0, 1.0),
		"airborne": racer.airborne,
		"boost": racer.boost_t > 0.0,
	})
	if _was_air and not racer.airborne:
		toy.land()
	_was_air = racer.airborne
	var bumped: bool = racer.bumped_t > 0.0
	if bumped and not _was_bumped:
		toy.bump()
	_was_bumped = bumped
