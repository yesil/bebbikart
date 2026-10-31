extends RefCounted
## Course V1 (game.md "Course (V1)"): start -> hills (ramp fork) -> pond (water/bridge fork)
## -> crossing (exposed/sheltered fork) -> bends -> finish. All junctions sit at x = 0 so every
## fork variant joins the same next segment. Pure data, no nodes.

const Route = preload("res://sim/route.gd")
const Tuning = preload("res://sim/tuning.gd")

## Segment: {
##   id, section, fork ("" or fork id), choice, route (Route), half_width,
##   edge (extra metres before off_track), rails (bool: d is clamped, no off_track),
##   exposure (0..1 wind), water: [[a,b]], boosts: [[a,b]], bumps: [s...],
##   ramp: {} or {kick_a, lip_s, lip_h, land_s, pit_depth}, offset (route s at segment start; per path)
## }
var segments := {}
var ordered_ids: Array[String] = []


func _init() -> void:
	_add("start", "hills", "", "", [Vector3(0, 0, 0), Vector3(0, 0, 7), Vector3(0, 0, 15)], 5.0, {})
	_add("hills1", "hills", "", "", [
		Vector3(0, 0, 15), Vector3(0, 0, 19), Vector3(3, 1.2, 30), Vector3(-2, 0.3, 42), Vector3(0, 0, 51), Vector3(0, 0, 55)
	], 4.0, {"bumps": [12.0, 26.0]})
	_add("ramp_jump", "hills", "ramp", "jump", [Vector3(0, 0, 55), Vector3(0, 0, 75), Vector3(0, 0, 95)], 3.0, {
		"ramp": {"kick_a": 8.0, "lip_s": 14.0, "lip_h": 2.0, "land_s": 32.0, "pit_depth": 0.4},
	})
	_add("ramp_around", "hills", "ramp", "around", [
		Vector3(0, 0, 55), Vector3(0, 0, 59), Vector3(5, 0, 66), Vector3(8, 0, 75), Vector3(7, 0, 85), Vector3(3, 0, 91), Vector3(0, 0, 95)
	], 3.5, {})
	_add("hills2", "hills", "", "", [Vector3(0, 0, 95), Vector3(0, 0, 99), Vector3(0, 1.5, 106), Vector3(0, 0, 113), Vector3(0, 0, 120)], 4.0, {
		"boosts": [[10.0, 20.0]],
	})
	_add("pond_water", "pond", "pond", "water", [
		Vector3(0, 0, 120), Vector3(0, 0, 124), Vector3(2, -0.2, 150), Vector3(-2, -0.2, 190), Vector3(0, 0, 216), Vector3(0, 0, 220)
	], 4.0, {"water": [[10.0, 90.0]]})
	_add("pond_bridge", "pond", "pond", "bridge", [
		Vector3(0, 0, 120), Vector3(0, 0, 124), Vector3(-17, 0, 135), Vector3(-38, 1.6, 170), Vector3(-17, 0, 206), Vector3(0, 0, 216), Vector3(0, 0, 220)
	], 2.8, {"rails": true})
	_add("cross_exposed", "crossing", "crossing", "exposed", [
		Vector3(0, 0, 220), Vector3(0, 0, 224), Vector3(0, 2.5, 234), Vector3(1, 2.5, 266), Vector3(0, 0, 276), Vector3(0, 0, 280)
	], 2.6, {"exposure": 1.0, "edge": Tuning.OFF_TRACK_MARGIN_RAILS})
	_add("cross_sheltered", "crossing", "crossing", "sheltered", [
		Vector3(0, 0, 220), Vector3(0, 0, 224), Vector3(11, 0, 234), Vector3(18, 0, 250), Vector3(11, 0, 266), Vector3(0, 0, 276), Vector3(0, 0, 280)
	], 3.5, {"exposure": 0.0})
	_add("bends", "bends", "", "", [
		Vector3(0, 0, 280), Vector3(0, 0, 286), Vector3(-12, 0, 298), Vector3(-12, 0, 312), Vector3(4, 0, 322), Vector3(14, 0, 336),
		Vector3(4, 0, 350), Vector3(0, 0, 358), Vector3(0, 0, 378)
	], 3.5, {})
	var b: Dictionary = segments["bends"]
	var bl: float = (b["route"] as Route).length
	b["boosts"] = [[bl - 18.0, bl - 8.0]]


func _add(id: String, section: String, fork: String, choice: String, ctrl: Array, half_width: float, extra: Dictionary) -> void:
	var r := Route.new()
	r.build(ctrl)
	var seg := {
		"id": id, "section": section, "fork": fork, "choice": choice, "route": r,
		"half_width": half_width, "edge": Tuning.OFF_TRACK_MARGIN, "rails": false,
		"exposure": 0.4, "water": [], "boosts": [], "bumps": [], "ramp": {},
	}
	for k in extra:
		seg[k] = extra[k]
	segments[id] = seg
	ordered_ids.append(id)


## Segment ids in driving order for a build's route choices.
func path_for(routes: Dictionary) -> Array[String]:
	var ramp := "ramp_jump" if routes.get("ramp", "around") == "jump" else "ramp_around"
	var pond := "pond_water" if routes.get("pond", "bridge") == "water" else "pond_bridge"
	var cross := "cross_exposed" if routes.get("crossing", "sheltered") == "exposed" else "cross_sheltered"
	var p: Array[String] = ["start", "hills1", ramp, "hills2", pond, cross, "bends"]
	return p


func path_length(path: Array[String]) -> float:
	var total := 0.0
	for id in path:
		total += (segments[id]["route"] as Route).length
	return total


static func in_ranges(ranges: Array, s: float) -> bool:
	for r in ranges:
		if s >= float(r[0]) and s <= float(r[1]):
			return true
	return false


## Ground height offset added to the centre line (ramp kicker and landing pit).
static func surface_offset(seg: Dictionary, s: float) -> float:
	var ramp: Dictionary = seg["ramp"]
	if ramp.is_empty():
		return 0.0
	var a: float = ramp["kick_a"]
	var lip: float = ramp["lip_s"]
	if s >= a and s <= lip:
		var f := (s - a) / (lip - a)
		return float(ramp["lip_h"]) * f * f
	if s > lip and s < float(ramp["land_s"]):
		return -float(ramp["pit_depth"])
	return 0.0


func surface_y(seg: Dictionary, s: float) -> float:
	return (seg["route"] as Route).pos_at(s).y + surface_offset(seg, s)


func all_route_lengths() -> Dictionary:
	var out := {}
	for ramp in ["jump", "around"]:
		for pond in ["water", "bridge"]:
			for cross in ["exposed", "sheltered"]:
				var p := path_for({"ramp": ramp, "pond": pond, "crossing": cross})
				out["%s/%s/%s" % [ramp, pond, cross]] = path_length(p)
	return out
