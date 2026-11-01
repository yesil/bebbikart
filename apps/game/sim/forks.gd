extends RefCounted
## Which side of the road each way of a fork leaves on, as the big screen shows it from behind
## the kart: +1 right, -1 left, 0 straight on. Measured from the course itself in the sim's
## lateral frame (positive d is along Route.normal_at, which is the chase camera's right). The
## steering kid picks a way by the side the kart is on at the junction (sim/racer.gd).

const Route = preload("res://sim/route.gd")

## Metres a way must swing out from the junction's line to count as leaving to a side.
const SIDE_MIN := 1.5


## {fork id: {choice: {seg: segment id, side: -1 | 0 | 1}}} for sim/course.gd or
## sim/village_course.gd. Every way of a fork starts at the same junction with the same heading.
static func ways(course) -> Dictionary:
	var out := {}
	for id in course.ordered_ids:
		var seg: Dictionary = course.segments[id]
		var fork: String = seg["fork"]
		if fork == "":
			continue
		var r: Route = seg["route"]
		var p0 := r.pos_at(0.0)
		var n0 := r.normal_at(0.0)
		var far := 0.0
		var s := 0.0
		while s <= r.length:
			var off := (r.pos_at(s) - p0).dot(n0)
			if absf(off) > absf(far):
				far = off
			s += 1.0
		var side := 0
		if absf(far) >= SIDE_MIN:
			side = 1 if far > 0.0 else -1
		if not out.has(fork):
			out[fork] = {}
		out[fork][seg["choice"]] = {"seg": id, "side": side}
	return out


## Problems with a course's forks: each needs two ways that leave to different sides (one may go
## straight on). Empty when all is well.
static func errors(w: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for fork in w:
		var f: Dictionary = w[fork]
		if f.size() != 2:
			out.append("fork %s has %d ways (need 2)" % [fork, f.size()])
			continue
		var s: Array = []
		for c in f:
			s.append(int(f[c]["side"]))
		if s[0] == s[1]:
			out.append("fork %s: both ways leave %s" % [fork, side_name(s[0])])
	return out


## The way (choice) a kart on `side` of the road takes at fork `f` (an entry of ways()): the way
## leaving to that side, else the one going straight on.
static func pick(f: Dictionary, side: int) -> String:
	for c in f:
		if int(f[c]["side"]) == side:
			return c
	for c in f:
		if int(f[c]["side"]) == 0:
			return c
	push_error("forks: no way to the %s or straight on in %s" % [side_name(side), f])
	return ""


## The side a kart leans to for way `choice` of fork `f`: the way's own side, or for the way straight
## on, away from the other.
static func lean(f: Dictionary, choice: String) -> int:
	var s := int(f[choice]["side"])
	if s != 0:
		return s
	for c in f:
		if c != choice:
			return -int(f[c]["side"])
	return 0


static func side_name(side: int) -> String:
	return "right" if side > 0 else ("left" if side < 0 else "straight on")
