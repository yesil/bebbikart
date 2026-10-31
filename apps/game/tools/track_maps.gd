extends RefCounted
## Track maps for the phone (contracts §2e): the sim courses (sim/course.gd, sim/village_course.gd)
## flattened to small 2D polylines per segment, each tagged with its stretch, written as JSON into
## packages/shared/src/track-maps/<track>.json. tools/export_track_maps.gd writes them
## (`bun run maps:export`) or checks they are current (`-- --check`; village_laps.gd runs the check).
## Map coordinates: x = world x, y = -world z (north up), metres, rounded to 0.1.

const Course = preload("res://sim/course.gd")
const VillageCourse = preload("res://sim/village_course.gd")
const Route = preload("res://sim/route.gd")

const STEP := 2.5  # metres between points
const WINDY := 0.7  # a segment this exposed (sim exposure) is where wind hits
const OUT_DIR := "res://../../packages/shared/src/track-maps"


## {track: course} for every track, or {} after printing why not (a broken course).
static func courses() -> Dictionary:
	var out := {"countryside": Course.new(), "village": VillageCourse.new()}
	for track in out:
		if not out[track].errors.is_empty():
			push_error("track_maps: %s course is broken: %s" % [track, "; ".join(out[track].errors)])
			return {}
	return out


## The map of one course as the JSON text written to the file.
static func map_json(track: String, course) -> String:
	var segs: Array = []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for id in course.ordered_ids:
		var sg: Dictionary = course.segments[id]
		var r: Route = sg["route"]
		var n := maxi(1, int(ceil(r.length / STEP)))
		var pts: Array = []
		for i in n + 1:
			var p := _xy(r.pos_at(r.length * i / n))
			lo = Vector2(minf(lo.x, p[0]), minf(lo.y, p[1]))
			hi = Vector2(maxf(hi.x, p[0]), maxf(hi.y, p[1]))
			pts.append(p)
		# Where the weather bites (sim/racer.gd): rain on fords, mud and slick decks, wind on open ground.
		var wet: bool = not (sg["water"] as Array).is_empty() or float(sg.get("grip", 1.0)) < 1.0 \
			or float(sg.get("rain_slick", 1.0)) > 1.0
		segs.append({"id": id, "stretch": sg["stretch"], "fork": sg["fork"], "choice": sg["choice"],
			"rain": wet, "wind": float(sg["exposure"]) >= WINDY, "pts": pts})
	# The start line: across the first segment at s = 0, as wide as the road.
	var first: Dictionary = course.segments[course.ordered_ids[0]]
	var fr: Route = first["route"]
	var hw: float = first["half_width"]
	var doc := {
		"generated": "apps/game/tools/export_track_maps.gd from the sim course; do not edit (bun run maps:export)",
		"track": track,
		"loop": course.get("loop") == true,
		"bounds": [snappedf(lo.x, 0.1), snappedf(lo.y, 0.1), snappedf(hi.x, 0.1), snappedf(hi.y, 0.1)],
		"start": [_xy(fr.world_at(0.0, -hw)), _xy(fr.world_at(0.0, hw))],
		"segments": segs,
	}
	return JSON.stringify(doc) + "\n"


static func path(track: String) -> String:
	return ProjectSettings.globalize_path(OUT_DIR).simplify_path() + "/%s.json" % track


## Tracks whose map file is missing or differs from the course now; [] when all are current.
static func stale() -> PackedStringArray:
	var out: PackedStringArray = []
	var cs := courses()
	if cs.is_empty():
		out.append("a course is broken")
		return out
	for track in cs:
		var f := path(track)
		if not FileAccess.file_exists(f):
			out.append("%s: %s is missing" % [track, f])
		elif FileAccess.get_file_as_string(f) != map_json(track, cs[track]):
			out.append("%s: %s is stale" % [track, f])
	return out


static func _xy(p: Vector3) -> Array:
	return [snappedf(p.x, 0.1), snappedf(-p.z, 0.1)]
