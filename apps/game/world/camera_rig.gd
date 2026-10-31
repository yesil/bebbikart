extends Camera3D
## Simple placeholder camera (the camera director is WS3c): chase a racer, or a wide shot
## that frames the whole field, or fixed vantage points at the three forks.

enum Mode { FOLLOW, WIDE, FORKS }

var mode := Mode.FOLLOW
var target: Node3D = null
var targets: Array = []      # all visible racer nodes, for WIDE framing
var fork_shots: Array = []   # [[pos, look_at], ...]
var fork_idx := 0
var _look := Vector3.ZERO


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
	match mode:
		Mode.FOLLOW:
			if target != null and target.visible:
				var body: Node3D = target.get_child(0)
				var yaw := body.rotation.y
				var fwd := Vector3(sin(yaw), 0, cos(yaw))
				want_pos = target.global_position - fwd * 9.0 + Vector3(0, 4.5, 0)
				want_look = target.global_position + fwd * 6.0 + Vector3(0, 1.0, 0)
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
	var k := 1.0 - exp(-delta * 3.0)
	position = position.lerp(want_pos, k)
	_look = _look.lerp(want_look, k)
	if position.distance_to(_look) > 0.01:
		look_at(_look, Vector3.UP)
