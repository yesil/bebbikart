extends SceneTree
## Headless check of world/camera_blockers.gd, the boxes the chase cameras keep out of (village
## houses, the covered bridge's roof):
##   godot --headless --path apps/game --script res://tools/camera_check.gd
## Prints every broken expectation and exits 1 if there is one.

const CameraBlockers = preload("res://world/camera_blockers.gd")
const VillageCourse = preload("res://sim/village_course.gd")

var fails: PackedStringArray = []


func _initialize() -> void:
	_blocker_box_maths()
	_village_houses_clear_the_road()
	if fails.is_empty():
		print("camera_check: all good")
		quit(0)
		return
	for f in fails:
		printerr("camera_check: " + f)
	quit(1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)


# ---------------------------------------------------------------- blockers (houses, bridge roof)

func _inside(b: Dictionary, p: Vector3) -> bool:
	var q: Vector3 = (b["inv"] as Transform3D) * p
	var h: Vector3 = b["half"]
	return absf(q.x) <= h.x and absf(q.y) <= h.y and absf(q.z) <= h.z


func _blocker_box_maths() -> void:
	var bl := CameraBlockers.new()
	bl.add_box(Transform3D.IDENTITY, Vector3.ONE)
	var t := bl.clear_t(Vector3(-5, 0, 0), Vector3(5, 0, 0))
	_expect(is_equal_approx(t, 0.4), "blockers: a segment through a 2 m box enters at 0.4, got %.3f" % t)
	var c := bl.clip(Vector3(-5, 0, 0), Vector3(5, 0, 0))
	_expect(c.is_equal_approx(Vector3(-1.0 - CameraBlockers.MARGIN, 0, 0)), "blockers: the camera stops MARGIN short of the wall, got %s" % c)
	_expect(bl.clip(Vector3(-5, 3, 0), Vector3(5, 3, 0)) == Vector3(5, 3, 0), "blockers: a segment above the box is not clipped")
	_expect(bl.clip(Vector3(0, 0, 0), Vector3(5, 0, 0)) == Vector3(5, 0, 0), "blockers: a box holding the racer is left out")
	_expect(bl.clip(Vector3(-5, 0, 0), Vector3(-3, 0, 0)) == Vector3(-3, 0, 0), "blockers: a segment that stops short is not clipped")
	# Turned a quarter: local z (depth) lies along world x.
	var turned := CameraBlockers.new()
	turned.add_box(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), Vector3(2, 1, 0.5))
	t = turned.clear_t(Vector3(-5, 0, 0), Vector3(5, 0, 0))
	_expect(is_equal_approx(t, 0.45), "blockers: a turned box enters at 0.45, got %.3f" % t)


## Every village house becomes a box that keeps clear of every road (so the racer is never inside
## one), and chase-camera spots behind racers in the village get pulled in where a house is in
## the way.
func _village_houses_clear_the_road() -> void:
	var course := VillageCourse.new()
	var bl := CameraBlockers.new()
	var t0 := Time.get_ticks_msec()
	var ok := bl.add_village(course, func(_x: float, _z: float) -> float: return 0.0)
	var ms := Time.get_ticks_msec() - t0
	_expect(ok, "blockers: village built (%s)" % "; ".join(bl.errors))
	_expect(bl.houses >= 40, "blockers: expected the village's houses, got %d" % bl.houses)
	_expect(bl.boxes.size() > bl.houses, "blockers: the covered bridge roof is missing")
	var on_road := 0
	var spots := 0
	var pulled := 0
	for id in course.ordered_ids:
		var seg: Dictionary = course.segments[id]
		var r = seg["route"]
		var hw := float(seg["half_width"])
		var s := 0.0
		while s <= r.length:
			for d in [-hw, 0.0, hw]:
				var p: Vector3 = r.world_at(s, d)
				p.y = 1.2
				for i in bl.houses:
					if _inside(bl.boxes[i], p):
						on_road += 1
			# The chase spot behind a racer on the line (houses stand on y 0 here).
			var yaw: float = r.heading_at(s)
			var fwd := Vector3(sin(yaw), 0, cos(yaw))
			var kart: Vector3 = r.pos_at(s)
			kart.y = 0.0
			var focus := kart + Vector3(0, 1.2, 0)
			var want := kart - fwd * 9.0 + Vector3(0, 4.5, 0)
			spots += 1
			if bl.clear_t(focus, want) < 1.0:
				pulled += 1
			for i in bl.houses:
				if _inside(bl.boxes[i], bl.clip(focus, want)):
					fails.append("blockers: pulled-in camera still inside a house on %s at s %.0f" % [id, s])
			s += 2.0
	_expect(on_road == 0, "blockers: %d road points lie inside a house box" % on_road)
	print("camera_check: %d village houses + %d bridge roof boxes in %d ms; %d of %d chase spots pulled in" % [
		bl.houses, bl.boxes.size() - bl.houses, ms, pulled, spots])
