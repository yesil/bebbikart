extends Camera3D
## The big-screen camera: chase a racer, or a wide shot that frames the whole field, or fixed
## vantage points at the three forks. Each half of the screen has one (world/duel_screen.gd says
## which racer it chases).

enum Mode { FOLLOW, WIDE, FORKS }

## A cut to a racer whose chase spot is further than this from the camera jumps there; only a
## racer close by gets a quick swoop (a longer swoop flew over other karts or the pond, and for a
## second the frame showed the wrong racer).
const SNAP_DIST := 12.0
## The chase spot: this far behind the racer and this high, looking this far ahead of it.
const CHASE_BACK := 9.0
const CHASE_UP := 4.5
const CHASE_AHEAD := 6.0
## The chase direction follows the racer's heading at TURN_RATE (per second), so bumps and wobbles
## don't swing the camera. The camera holds its spot at FOLLOW_RATE: tight enough that it stays
## about CHASE_BACK behind at full speed (a slack follow trailed some 15 m behind, and in a pack
## the karts in between filled the frame). After a close cut it flies over at SWOOP_RATE and
## tightens to FOLLOW_RATE over SWOOP_S. Wide and fork shots ease at SLACK_RATE.
const TURN_RATE := 4.0
const FOLLOW_RATE := 14.0
const SWOOP_RATE := 3.0
const SWOOP_S := 0.8
const SLACK_RATE := 3.0

var mode := Mode.FOLLOW
var target: Node3D = null
var targets: Array = []      # all visible racer nodes, for WIDE framing
var fork_shots: Array = []   # [[pos, look_at], ...]
var fork_idx := 0
var _look := Vector3.ZERO
var _chased: Node3D = null   # the target the follow camera last framed
## world/camera_blockers.gd (village houses, the covered bridge's roof), or null: the follow camera
## pulls in towards the racer instead of sitting in a house or looking through its wall.
var blockers = null
var blocked_s := 0.0         # seconds the chase position was behind or in a blocker (pulled in)
var _yaw := 0.0              # eased chase direction
var _since_cut := SWOOP_S    # seconds since the follow camera took its current racer
var _chase_sum := 0.0        # distance to the chased racer, integrated over time once settled
var _chase_t := 0.0


func _ready() -> void:
	fov = 60.0
	far = 800.0
	position = Vector3(0, 8, -12)
	_look = Vector3(0, 0, 10)


func cycle_mode() -> void:
	mode = ((mode + 1) % 3) as Mode


func _process(delta: float) -> void:
	var want_pos := position
	var want_look := _look
	var focus := Vector3.ZERO    # the racer's middle, when the follow camera keeps out of blockers
	var keep_out := false
	var rate := SLACK_RATE
	match mode:
		Mode.FOLLOW:
			if target != null and target.visible:
				var body: Node3D = target.get_child(0)
				var yaw := body.rotation.y
				var tpos := target.global_position
				if target != _chased:
					# A far cut jumps (facing the new racer's way); a close one swoops over.
					var jump := _chased == null or position.distance_to(_chase_pos(tpos, yaw)) > SNAP_DIST
					_since_cut = SWOOP_S if jump else 0.0
					if jump:
						_yaw = yaw
				_since_cut += delta
				_yaw = lerp_angle(_yaw, yaw, 1.0 - exp(-delta * TURN_RATE))
				var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
				want_pos = _chase_pos(tpos, _yaw)
				want_look = tpos + fwd * CHASE_AHEAD + Vector3(0, 1.0, 0)
				rate = lerpf(SWOOP_RATE, FOLLOW_RATE, clampf(_since_cut / SWOOP_S, 0.0, 1.0))
				if blockers != null:
					focus = target.global_position + Vector3(0, 1.2, 0)
					keep_out = true
					var clear: Vector3 = blockers.clip(focus, want_pos)
					if clear != want_pos:
						blocked_s += delta
					want_pos = clear
				if target != _chased and _since_cut > SWOOP_S:
					position = want_pos
					_look = want_look
				_chased = target
		Mode.WIDE:
			var c := Vector3(0, 0, 180)
			var spread := 120.0
			var vis: Array = targets.filter(func(n): return is_instance_valid(n) and n.visible)
			if not vis.is_empty():
				var lo := INF
				var hi := -INF
				var sx := 0.0
				for n in vis:
					lo = minf(lo, n.global_position.z)
					hi = maxf(hi, n.global_position.z)
					sx += n.global_position.x
				c = Vector3(sx / vis.size(), 0, (lo + hi) * 0.5)
				spread = maxf(40.0, hi - lo + 30.0)
			want_pos = c + Vector3(spread * 0.75, spread * 0.6, -spread * 0.25)
			want_look = c
		Mode.FORKS:
			if not fork_shots.is_empty():
				var shot: Array = fork_shots[fork_idx % fork_shots.size()]
				want_pos = shot[0]
				want_look = shot[1]
	var k := 1.0 - exp(-delta * rate)
	position = position.lerp(want_pos, k)
	if keep_out:
		# The lagging camera can still cut a corner through a house: keep it on the racer's side.
		position = blockers.clip(focus, position)
	_look = _look.lerp(want_look, k)
	if position.distance_to(_look) > 0.01:
		look_at(_look, Vector3.UP)
	if mode == Mode.FOLLOW and target != null and target.visible and _since_cut > SWOOP_S * 2.0:
		_chase_sum += position.distance_to(target.global_position) * delta
		_chase_t += delta


func _chase_pos(tpos: Vector3, yaw: float) -> Vector3:
	return tpos - Vector3(sin(yaw), 0, cos(yaw)) * CHASE_BACK + Vector3(0, CHASE_UP, 0)


## One line for the mock summary: how far the chase camera kept from its racer, and how long it
## was pulled in front of a house.
func summary() -> String:
	var out := "chase camera %.1f m from its racer on average" % (_chase_sum / _chase_t) if _chase_t > 0.0 else "chase camera never settled on a racer"
	if blockers != null:
		out += "; pulled in front of a house or roof for %.1f s" % blocked_s
	return out
