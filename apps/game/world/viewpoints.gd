extends RefCounted
## Camera viewpoints placed from the course data, so they follow route edits: the fork shots
## for the game's fork camera (main.gd) and the fixed screenshot set (tools/shots.gd).
## Each entry: [name, camera position, look-at point, fov (optional)].

const Course = preload("res://sim/course.gd")
const Route = preload("res://sim/route.gd")


## One wide shot per fork, seeing the split and both alternatives.
static func fork_shots(c: Course) -> Array:
	var out := []
	for v in all(c):
		if v[0] in ["ramp_split", "pond_split", "cross_split"]:
			out.append([v[1], v[2]])
	return out


static func all(c: Course) -> Array:
	var s0: Route = c.segments["start"]["route"]
	var jr: Route = c.segments["ramp_jump"]["route"]
	var pw: Route = c.segments["pond_water"]["route"]
	var pb: Route = c.segments["pond_bridge"]["route"]
	var ce: Route = c.segments["cross_exposed"]["route"]
	var bn: Route = c.segments["bends"]["route"]
	var j1 := jr.pos_at(0.0)
	var j2 := jr.pos_at(jr.length)
	var j3 := pw.pos_at(0.0)
	var j4 := ce.pos_at(0.0)
	var hump := pb.pos_at(pb.length * 0.5)
	var fin := bn.pos_at(bn.length)
	var mid := ce.pos_at(ce.length * 0.5)
	return [
		["start", s0.pos_at(0.0) + Vector3(9, 4.5, -12), s0.pos_at(15.0) + Vector3(0, 1, 0)],
		["ramp_split", j1 + Vector3(-9, 7, -14), j1 + Vector3(6, 0, 22)],
		["ramp_side", j1 + Vector3(-24, 9, 30), j1 + Vector3(6, 0, 30)],
		["ramp_merge", j2 + Vector3(16, 8, 14), j2 + Vector3(2, 0, -14)],
		["pond_split", j3 + Vector3(10, 9, -12), j3 + Vector3(-12, 0, 30)],
		["pond_bridge", hump + Vector3(-14, 5, -20), hump + Vector3(0, 1, 0)],
		["ford", pw.pos_at(30.0) + Vector3(9, 4, -10), pw.pos_at(55.0)],
		["cross_split", j4 + Vector3(-12, 8, -10), j4 + Vector3(8, 0, 28)],
		["causeway", mid + Vector3(-34, 5, -8), mid + Vector3(0, 0, 0)],
		["bends", bn.pos_at(30.0) + Vector3(22, 16, -14), bn.pos_at(62.0)],
		["finish", fin + Vector3(8, 4.5, -28), fin + Vector3(-2, 2.5, 0)],
		["overview", Vector3(70, 110, 120), Vector3(0, 0, 230), 55.0],
	]
