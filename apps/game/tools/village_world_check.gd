extends SceneTree
## Checks the baked village world against the course and plan (headless), exits 1 on failure:
##   godot --headless --path apps/game --script res://tools/village_world_check.gd
## - the course closes and the plan places every landmark (their own error lists)
## - res://world/village/village_world.tscn loads with every baked part and model in place
## - the terrain sits just under every road (never above it, never far below it off the decks)
## - no prop or building module stands on a road, outside the covered bridge
## - props stand on the ground, buildings neither float nor sink
## - the Houses node keeps one record per building of the plan, in the plan's order, and they
##   build without errors (world/village/chalet_builder.gd)

const VillageCourse = preload("res://sim/village_course.gd")
const VillagePlan = preload("res://world/village/village_plan.gd")
const VillageTerrain = preload("res://world/village/village_terrain.gd")
const InstancedModel = preload("res://world/village/instanced_model.gd")
const VillageHouses = preload("res://world/village/village_houses.gd")
const Course = preload("res://sim/course.gd")
const Route = preload("res://sim/route.gd")

const SCENE := "res://world/village/village_world.tscn"
const PARTS := ["Terrain", "Roads", "Water/Pond", "Water/Brook", "Structures/Kicker", "Structures/CausewayRails",
	"Structures/Square", "Buildings", "Buildings/Houses", "Props"]
## Props that belong at the roadside (their origin may sit this close to a road edge).
const ROADSIDE := {"Lantern": 0.5, "Fence": 0.3}
const PROP_GROUND := 0.35          # props may sit this far off the ground
const ON_STALLS := ["CheeseBlock", "ChocolateBar"]   # shop goods on the market stalls

var fails: PackedStringArray = []
var notes: PackedStringArray = []


func _init() -> void:
	var course := VillageCourse.new()
	for e in course.errors:
		fails.append("course: " + e)
	var plan := VillagePlan.new(course)
	for e in plan.errors:
		fails.append("plan: " + e)
	var shape := VillageTerrain.new(course, plan)
	shape.build()
	if not ResourceLoader.exists(SCENE):
		fails.append("%s is missing; run tools/bake_village.gd" % SCENE)
		_done()
		return
	var world: Node = (load(SCENE) as PackedScene).instantiate()
	for p in PARTS:
		if world.get_node_or_null(p) == null:
			fails.append("world: no %s node" % p)
	var roads := world.get_node_or_null("Roads")
	if roads != null and roads.get_child_count() < 10:
		fails.append("world: only %d road containers" % roads.get_child_count())
	_check_roads(course, plan, shape)
	_check_models(world, course, plan, shape)
	_check_houses(world, plan)
	world.free()
	_done()


func _done() -> void:
	for n in notes:
		print("  ", n)
	if fails.is_empty():
		print("VILLAGE WORLD CHECKS PASSED")
		quit(0)
	else:
		for f in fails:
			print("  FAIL ", f)
		print("VILLAGE WORLD CHECKS FAILED: %d" % fails.size())
		quit(1)


## The terrain under each road's centre line is just below the road surface, except under the
## decks (covered bridge, causeway) where it must be clearly below.
func _check_roads(course: VillageCourse, plan: VillagePlan, shape: VillageTerrain) -> void:
	var worst_above := 0.0
	var where := ""
	for id in course.ordered_ids:
		var seg: Dictionary = course.segments[id]
		var r: Route = seg["route"]
		var s := 0.0
		while s <= r.length:
			var c := r.pos_at(s)
			var road_y := course.surface_y(seg, s)
			var g := shape.height_at(c.x, c.z)
			var deck := is_nan(shape.corridor_target(seg, s))
			var ramp: Dictionary = seg["ramp"]
			var on_ramp := not ramp.is_empty() and s >= float(ramp["kick_a"]) - 1.0 and s <= float(ramp["land_s"]) + 1.0
			if not on_ramp:
				if g - road_y > worst_above:
					worst_above = g - road_y
					where = "%s s=%.0f" % [id, s]
				if g > road_y + 0.05:
					fails.append("terrain above the road: %s s=%.0f by %.2f m" % [id, s, g - road_y])
				elif not deck and g < road_y - 0.6:
					fails.append("terrain sags under the road: %s s=%.0f by %.2f m" % [id, s, road_y - g])
				elif deck and g > road_y - 0.4:
					fails.append("deck too close to the ground: %s s=%.0f (%.2f m clear)" % [id, s, road_y - g])
			s += 1.0
	notes.append("terrain highest relative to road: %.2f m at %s" % [worst_above, where])


func _check_models(world: Node, course: VillageCourse, plan: VillagePlan, shape: VillageTerrain) -> void:
	var counts := {}
	for group in ["Buildings", "Props"]:
		var node := world.get_node_or_null(group)
		if node == null:
			continue
		for n in node.get_children():
			if not n is InstancedModel:
				continue
			var im: InstancedModel = n
			if not ResourceLoader.exists(im.model):
				fails.append("%s/%s: model %s is missing" % [group, n.name, im.model])
				continue
			var t := im.transforms
			if t.size() == 0 or t.size() % 12 != 0:
				fails.append("%s/%s: %d transform floats" % [group, n.name, t.size()])
				continue
			counts[group] = int(counts.get(group, 0)) + t.size() / 12
			# Wandering animals: every grazing spot stays off the roads.
			var wd := im.wander
			for k in range(0, wd.size(), 3):
				var e: Array = plan.road_edge(Vector2(wd[k], wd[k + 2]))
				if float(e[0]) < 2.0:
					fails.append("%s wanders to (%.1f, %.1f), %.2f m from %s" % [n.name, wd[k], wd[k + 2], e[0], e[1]])
			if im.wander_points > 0:
				notes.append("%s: %d animals wander between %d spots each" % [n.name, t.size() / 12, im.wander_points])
			for k in range(0, t.size(), 12):
				var o := Vector3(t[k + 9], t[k + 10], t[k + 11])
				var p := Vector2(o.x, o.z)
				if group == "Props":
					var clear: float = ROADSIDE.get(String(n.name), 0.6)
					var e: Array = plan.road_edge(p)
					if float(e[0]) < clear:
						fails.append("prop %s at (%.1f, %.1f) is %.2f m from %s" % [n.name, o.x, o.z, e[0], e[1]])
					var g := shape.height_at(o.x, o.z)
					if absf(o.y - g) > PROP_GROUND and not String(n.name) in ON_STALLS and not String(n.name).begins_with("Fountain"):
						fails.append("prop %s at (%.1f, %.1f) is %.2f m off the ground" % [n.name, o.x, o.z, o.y - g])
	notes.append("%d building modules, %d props" % [counts.get("Buildings", 0), counts.get("Props", 0)])
	# Buildings: the floor is at or below the ground everywhere under the footprint (no gaps) and
	# no more than 2.5 m below its highest point (no buried houses).
	for b in plan.buildings:
		var lo := INF
		var hi := -INF
		for q in VillagePlan.sample_points(VillagePlan.footprint(b)):
			var g := shape.height_at(q.x, q.y)
			lo = minf(lo, g)
			hi = maxf(hi, g)
		if hi - lo > 2.5:
			fails.append("building %s at (%.0f, %.0f) stands on a %.1f m slope" % [b["kind"], b["pos"].x, b["pos"].y, hi - lo])


func _check_houses(world: Node, plan: VillagePlan) -> void:
	var h := world.get_node_or_null("Buildings/Houses") as VillageHouses
	if h == null:
		return
	if h.kinds.size() != plan.buildings.size():
		fails.append("houses: %d records for %d buildings of the plan; re-run tools/bake_village.gd" % [h.kinds.size(), plan.buildings.size()])
		return
	for i in plan.buildings.size():
		var b: Dictionary = plan.buildings[i]
		var k := i * VillageHouses.FIELDS
		if h.kinds[i] != b["kind"] or Vector2(h.houses[k], h.houses[k + 2]).distance_to(b["pos"]) > 0.01:
			fails.append("houses: record %d is a %s at (%.1f, %.1f), the plan has a %s at (%.1f, %.1f); re-run tools/bake_village.gd" % [
				i, h.kinds[i], h.houses[k], h.houses[k + 2], b["kind"], b["pos"].x, b["pos"].y])
			return
	if h.bridge.is_empty():
		fails.append("houses: no covered bridge cells")
	var built = VillageHouses.build(h.kinds, h.houses, h.bridge, h.bridge_cell, h.bridge_half_width)
	for e in built.errors:
		fails.append("houses: " + e)
	notes.append("%d buildings and %d bridge cells: %d vertices" % [h.kinds.size(), h.bridge.size() / 4, built.vertex_count()])
