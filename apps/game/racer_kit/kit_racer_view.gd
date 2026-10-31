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
	if toy == null:
		# Invalid spec: no stand-in racer. Show the problems where the racer would be.
		var l := Label3D.new()
		l.text = "INVALID RACER SPEC (%s)\n%s" % [nickname, "\n".join(RacerBuilder.last_errors.slice(0, 4))]
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
	sync()


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
