extends Node3D
## A racer on the track built from its RacerSpec with the racer kit (drop-in for the placeholder
## world/racer_view.gd: same setup/sync/nickname). Pose comes from the sim racer every frame.

var racer = null   # sim/racer.gd
var nickname := ""
var toy: ToyRacer
var _body: Node3D
var _was_air := false
var _was_bumped := false


func setup(p_racer, spec: Dictionary, drawing: Texture2D, p_nickname: String) -> void:
	racer = p_racer
	nickname = p_nickname
	_body = Node3D.new()
	_body.rotation_order = EULER_ORDER_YXZ
	add_child(_body)
	toy = RacerBuilder.build(spec, drawing)
	toy.rotation.y = PI  # the kit faces -Z, the sim's heading is measured from +Z
	_body.add_child(toy)
	toy.set_name_tag(nickname)
	toy.show_name_tag(true)
	sync()


func sync() -> void:
	if racer == null:
		return
	visible = racer.state == "racing"
	if not visible:
		return
	position = racer.world_pos()
	_body.rotation = Vector3(racer.pitch(), racer.yaw(), racer.roll())
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
