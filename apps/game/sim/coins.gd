extends RefCounted
## Chocolate coins (Schoggitaler in gold foil): short lines of coins on the road for a steering kid
## to collect. Every racer gets its own coins, laid out afresh each lap at random places of the
## course's `coin_ranges` ({seg, a, b}): straight lines, lines slanting across the road and lines
## curving round. Each coin counts; a whole line collected gives a boost (sim/racer.gd
## _catch_coins). Hands off, the autopilot doesn't go for them. Pure data, like the rest of the sim:
## world/coin_views.gd draws each racer's coins in its own half. main.gd turns them on for the
## game; the balance tools build their sims without them.
##
## A coin is {seg, s, d, line, taken}; lines are numbered from 0 in driving order.

const Course = preload("res://sim/course.gd")

const LINES := 7                  # lines on a lap
const PER_LINE := 5
const EVERY := 3.0                # metres between coins along a line
const LINE_GAP := 10.0            # free road between two lines
const EDGE := 0.45                # coins stay this far inside the rails' limit
const SHAPES := ["straight", "slant", "curve"]

var course


func _init(p_course) -> void:
	course = p_course


## Problems with the course's ranges ("" when fine): main.gd refuses to start coins on a bad course.
func check() -> String:
	for r in course.coin_ranges:
		var seg: Dictionary = course.segments.get(r["seg"], {})
		if seg.is_empty():
			return "coin range on unknown segment %s" % r["seg"]
		if String(seg["fork"]) != "":
			return "coin range on fork way %s" % r["seg"]
		var len_: float = seg["route"].length
		if float(r["a"]) < 0.0 or float(r["b"]) > len_ or float(r["b"]) - float(r["a"]) < line_len():
			return "coin range on %s runs %.0f..%.0f m of %.0f m" % [r["seg"], r["a"], r["b"], len_]
	return ""


static func line_len() -> float:
	return EVERY * (PER_LINE - 1)


## A fresh lap of coins from `seed_`: LINES lines, none overlapping, in driving order of `path`
## (the racer's segment ids, so lines come in the order it meets them).
func lay(seed_: int, path: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	# Where lines may start: [seg, a, b] with room for a whole line.
	var room: Array = []
	var total := 0.0
	for r in course.coin_ranges:
		var span := float(r["b"]) - float(r["a"]) - line_len()
		if span >= 0.0:
			room.append([r["seg"], float(r["a"]), span])
			total += span + 0.01
	var starts: Array = []        # [seg, s]
	var tries := 0
	while starts.size() < LINES and tries < 200:
		tries += 1
		var x := rng.randf() * total
		for r in room:
			if x <= float(r[2]) + 0.01:
				var s: float = float(r[1]) + x
				var clear := true
				for o in starts:
					if o[0] == r[0] and absf(float(o[1]) - s) < line_len() + LINE_GAP:
						clear = false
				if clear:
					starts.append([r[0], s])
				break
			x -= float(r[2]) + 0.01
	starts.sort_custom(func(p, q):
		var ip := path.find(p[0])
		var iq := path.find(q[0])
		return ip < iq or (ip == iq and float(p[1]) < float(q[1])))
	var out: Array = []
	for li in starts.size():
		var seg: Dictionary = course.segments[starts[li][0]]
		var lim := Course.rail_lim(seg) - EDGE
		var shape: String = SHAPES[rng.randi() % SHAPES.size()]
		var a := rng.randf_range(-lim, lim)
		var b := a
		if shape == "slant":
			# Across at least a third of the road.
			while absf(b - a) < lim * 0.66:
				b = rng.randf_range(-lim, lim)
		var amp := rng.randf_range(0.35, 0.6) * lim
		var mid := clampf(a, -lim + amp, lim - amp)
		for k in PER_LINE:
			var f := float(k) / (PER_LINE - 1)
			var d := a
			match shape:
				"slant":
					d = lerpf(a, b, f)
				"curve":
					d = mid + amp * sin(f * PI * 1.5 + (0.0 if a > 0.0 else PI))
			out.append({"seg": starts[li][0], "s": float(starts[li][1]) + k * EVERY, "d": d, "line": li, "taken": false})
	return out
