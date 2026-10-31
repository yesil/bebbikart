extends Node3D
## A racer on the track built from its RacerSpec with the racer kit (drop-in for the placeholder
## world/racer_view.gd: same setup/sync/nickname). Pose and the driver's state (turns, jumps,
## water, slips, boost) come from the sim racer every frame; when the run ends, leave() keeps the
## racer a moment for its finish cheer or crash slump. Weather and overtakes: race_reactions.gd.

const I18n = preload("res://ui/i18n.gd")
const CameraHud = preload("res://ui/camera_hud.gd")

var racer = null   # sim/racer.gd
var nickname := ""
var parked := false  # waiting on the start grid for the countdown (main sets it from the sim)
var toy: ToyRacer
# Set by race_reactions.gd.
var react_id := -1
var react_cool := 0.0
var brace_cool := 0.0
var react_prev := Vector3.ZERO
var grid_t := -1.0       # seconds waiting on the start grid; -1 = not on it
var grid_next := 0.0     # grid_t of the next fidget
var grid_beat := 0       # whole seconds to green at the last nod
var grid_ready := false  # leaning in for the start
var grid_bumped := false # fist-bumped a neighbour this countdown
var race_t := 0.0        # seconds since it left the grid (race_reactions.gd)
var cheered := false     # already cheered together with another finisher
var hf_with = null       # the finisher this one is high-fiving (race_reactions.gd), or null
var hf_t := 0.0
var hf_go := -1.0        # hf_t the slap started at (once side by side within reach), -1 before
## "" while racing, else the outcome being shown ("finished" / "failed") before the view frees.
var leaving := ""
var _leave_t := 0.0
var _leave_v := 0.0
var _leave_seg := {}      # where on the course the racer coasts after its run: segment, metres
var _leave_ls := 0.0      # along it, sideways offset, height above the road
var _leave_d := 0.0
var _leave_dy := 0.0
var _nudged := 0.0        # seconds left of being kept apart from another racer (race_reactions.gd)
var _yaw_prev := 0.0
var _turn := 0.0
var _braced := false
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
	set_process(false)
	sync()
	_yaw_prev = racer.yaw()


## Where the big-screen HUD puts this racer's tag: just above the toy's head (its 3D name tag
## spot), or above the error text for an invalid spec.
func tag_anchor() -> Vector3:
	if toy != null and toy.name_tag != null:
		return toy.name_tag.global_position
	return global_position + Vector3(0, 1.8, 0)


## The HUD draws its own tags (place + name, never overlapping); the 3D one is off then.
func show_name_tag(on: bool) -> void:
	if toy != null:
		toy.show_name_tag(on)


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
	visible = racer.state == "racing" or parked
	if not visible:
		return
	position = racer.world_pos()
	var yaw: float = racer.yaw()
	_body.rotation = Vector3(racer.pitch(), yaw, racer.roll())
	if toy == null:
		return
	var dt := get_process_delta_time()
	if dt > 0.0:
		_turn = lerpf(_turn, clampf(wrapf(yaw - _yaw_prev, -PI, PI) / dt, -3.0, 3.0), minf(1.0, dt * 8.0))
	_yaw_prev = yaw
	toy.speed = racer.v
	toy.lean = clampf(racer.vd * 0.25, -1.0, 1.0)
	toy.airborne = racer.airborne
	toy.boost = racer.boost_t > 0.0
	toy.turn = _turn
	toy.vy = racer.vy
	toy.big_air = racer.jump_air
	toy.in_water = racer.in_water
	toy.slipping = racer.slipping
	var r = racer.route()
	toy.ahead_turn = wrapf(r.heading_at(minf(racer.ls + 9.0, r.length)) - r.heading_at(racer.ls), -PI, PI)
	if racer.airborne and racer.vy < -0.5 and not _braced:
		# Brace just before touching down.
		if (racer.y - racer.course_ref.surface_y(racer.seg, racer.ls)) / -racer.vy < 0.22:
			_braced = true
			toy.gesture("brace")
	if _was_air and not racer.airborne:
		toy.land()
		_braced = false
	_was_air = racer.airborne
	var bumped: bool = racer.bumped_t > 0.0
	if bumped and not _was_bumped:
		toy.bump()
	_was_bumped = bumped


## Half the racer's footprint (x across, y along the road), metres: the sim's own (its built
## toy's ride, world/toy_footprint.gd), so finishers keep the spacing the race kept.
func half_size() -> Vector2:
	return Vector2(racer.radius, racer.half_len)


## Slides a finisher sideways on its road (keeping on it) and back along it; race_reactions.gd
## uses it so finishers standing after their run never sit inside each other.
func nudge(side: float, back: float) -> void:
	var hw := float(_leave_seg.get("half_width", 3.0)) - 0.3
	_leave_d = clampf(_leave_d + side, -hw, hw)
	_leave_ls -= back
	_nudged = 0.15  # crowded: no pulling over for a moment


## How strongly the driver is mid-reaction (ToyRacer.reaction_weight); 0 without a built toy.
func reaction_weight() -> float:
	return toy.reaction_weight() if toy != null else 0.0


## Forward on the road (world, unit).
func forward() -> Vector3:
	return _body.global_basis.z


## The run ended (main.gd on sim.removed): the racer stays FINISH_STAY s (cheer, then a wave at
## the camera) or FAIL_STAY s (spin and slump), coasts to a stop along the road's curve (onto the
## next lap's first stretch on a loop), pops away and frees itself. An aborted run, or a view
## without a toy, goes at once.
func leave(outcome: String) -> void:
	if toy == null or outcome not in ["finished", "failed"]:
		queue_free()
		return
	leaving = outcome
	visible = true
	_leave_v = racer.v
	_leave_seg = racer.seg
	_leave_ls = racer.ls
	_leave_d = racer.d
	_leave_dy = racer.y - racer.course_ref.surface_y(racer.seg, racer.ls)
	toy.slipping = false
	toy.airborne = false
	if outcome == "finished":
		_leave_t = FINISH_STAY
		toy.finish()
	else:
		_leave_t = FAIL_STAY
		toy.fail()
	set_process(true)


const FINISH_STAY := 2.2
const FAIL_STAY := 1.6
const POP := 0.25


func _process(delta: float) -> void:
	if leaving == "":
		return
	_leave_t -= delta
	# Past the end of a point-to-point road it brakes hard, so it stops by the line, not in the meadow.
	var brake := 3.0 if _leave_ls > float(_leave_seg["route"].length) and not racer.looping else 1.0
	_leave_v = maxf(0.0, _leave_v - delta * maxf(8.0, _leave_v * 2.5) * brake)
	_leave_ls += _leave_v * delta
	_nudged = maxf(0.0, _nudged - delta)
	if leaving == "finished" and _nudged <= 0.0:
		# Pull over to the nearer road edge, out of the way of the racers finishing behind.
		var edge := float(_leave_seg.get("half_width", 3.0)) - half_size().x - 0.3
		_leave_d = move_toward(_leave_d, edge if _leave_d >= 0.0 else -edge, delta * 2.5)
	var rt = _leave_seg["route"]
	if _leave_ls > rt.length and racer.looping and not racer.segs.is_empty() and _leave_seg != racer.segs[0]:
		_leave_ls -= rt.length
		_leave_seg = racer.segs[0]
		rt = _leave_seg["route"]
	var s := minf(_leave_ls, rt.length)
	var p: Vector3 = rt.world_at(s, _leave_d) + rt.tangent_at(s) * (_leave_ls - s)  # past a road's end: straight on
	_leave_dy = maxf(0.0, _leave_dy - delta * 4.0)
	p.y = racer.course_ref.surface_y(_leave_seg, s) + _leave_dy
	position = p
	var yaw: float = rt.heading_at(s)
	var k := minf(1.0, delta * 6.0)
	toy.turn = lerpf(toy.turn, clampf(wrapf(yaw - _body.rotation.y, -PI, PI) / delta, -3.0, 3.0), k)
	_body.rotation = Vector3(lerpf(_body.rotation.x, 0.0, k), yaw, lerpf(_body.rotation.z, 0.0, k))
	toy.speed = _leave_v
	if _leave_t < POP:
		scale = Vector3.ONE * maxf(0.001, _leave_t / POP)
	if _leave_t <= 0.0:
		queue_free()
