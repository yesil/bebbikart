extends RefCounted
## Boxes the big-screen cameras must not sit in or look through: the village houses (from
## world/village/village_plan.gd, standing on the terrain) and the covered bridge's roof. When a
## box is between the racer and where a camera wants to be, the camera pulls in towards the racer
## and stops just short of it (world/camera_rig.gd, the chase camera of each half). Plain maths, no physics bodies: a box test is a few multiplications, and boxes far
## from the camera are skipped before that.

const VillagePlan = preload("res://world/village/village_plan.gd")

const PAD := 0.6           # eaves and flower boxes stick out this far past a footprint
const ROOF_PAD := 1.0      # above the ridge height (chimneys, the spire's tip)
const MARGIN := 0.5        # a pulled-in camera stops this far short of the wall it met
const BRIDGE_ROOF := Vector2(2.5, 4.6)  # covered bridge roof, metres above the deck (eaves to ridge)
const BRIDGE_CELL := 2.0

## {inv: Transform3D (world -> box space), half: Vector3, c: Vector3 (centre), r: float (bounding radius)}
var boxes: Array = []
var errors: PackedStringArray = []
var houses := 0             # the first `houses` boxes are houses, the rest the bridge roof


func add_box(xf: Transform3D, half: Vector3) -> void:
	boxes.append({"inv": xf.affine_inverse(), "half": half, "c": xf.origin, "r": half.length()})


## Every house of the village plan, standing on the lowest ground height_at(x, z) gives under its
## footprint (as tools/bake_village.gd places it), and the covered bridge's roof. Pass the plan if
## it is already built (it takes about 2 s; main.gd builds it on a worker thread). Returns false
## with `errors` filled if the ground is missing under a house.
func add_village(course, height_at: Callable, plan: VillagePlan = null) -> bool:
	if plan == null:
		plan = VillagePlan.new(course)
	for b in plan.buildings:
		var floor_y := INF
		for q in VillagePlan.sample_points(VillagePlan.footprint(b)):
			var g: float = height_at.call(q.x, q.y)
			if is_nan(g):
				errors.append("no ground under the %s at (%.1f, %.1f)" % [b["kind"], q.x, q.y])
				return false
			floor_y = minf(floor_y, g)
		var size: Vector2 = b["size"]
		var top := float(b["height"]) + ROOF_PAD
		var p: Vector2 = b["pos"]
		# Footprint width runs along local x, depth along local z (the front faces +z, turned by yaw).
		add_box(Transform3D(Basis(Vector3.UP, b["yaw"]), Vector3(p.x, floor_y + top * 0.5, p.y)),
			Vector3(size.x * 0.5 + PAD, top * 0.5, size.y * 0.5 + PAD))
	houses = boxes.size()
	var seg: Dictionary = course.segments["pond_bridge"]
	var r = seg["route"]
	var w := float(seg["half_width"]) + 1.0 + PAD
	var n := int(round(VillagePlan.BRIDGE_HALF_LENGTH * 2.0 / BRIDGE_CELL))
	for k in n:
		var s: float = plan.bridge_s - VillagePlan.BRIDGE_HALF_LENGTH + (k + 0.5) * VillagePlan.BRIDGE_HALF_LENGTH * 2.0 / n
		var c: Vector3 = r.pos_at(s)
		c.y += (BRIDGE_ROOF.x + BRIDGE_ROOF.y) * 0.5
		add_box(Transform3D(Basis(Vector3.UP, r.heading_at(s)), c),
			Vector3(w, (BRIDGE_ROOF.y - BRIDGE_ROOF.x) * 0.5, BRIDGE_CELL * 0.5 + 0.05))
	return true


## How far along from -> to (0..1) the camera can go before it enters a box; 1 when nothing is in
## the way. Boxes that already hold `from` are left out (a racer under the bridge roof still gets
## a camera beside it).
func clear_t(from: Vector3, to: Vector3) -> float:
	var best := 1.0
	var mid := (from + to) * 0.5
	var reach := from.distance_to(to) * 0.5
	for b in boxes:
		if mid.distance_to(b["c"]) > float(b["r"]) + reach:
			continue
		var inv: Transform3D = b["inv"]
		best = minf(best, _enter(inv * from, inv * to, b["half"]))
	return best


## `to`, or MARGIN short of where from -> to first meets a box.
func clip(from: Vector3, to: Vector3) -> Vector3:
	var t := clear_t(from, to)
	if t >= 1.0:
		return to
	var len := from.distance_to(to)
	return from.lerp(to, maxf(0.0, t - MARGIN / len) if len > 0.0 else 0.0)


## Parameter where segment p -> q enters the box |x| <= h (slab test); 2 when it never does or
## when p is already inside.
static func _enter(p: Vector3, q: Vector3, h: Vector3) -> float:
	if absf(p.x) <= h.x and absf(p.y) <= h.y and absf(p.z) <= h.z:
		return 2.0
	var d := q - p
	var t0 := 0.0
	var t1 := 1.0
	for i in 3:
		if absf(d[i]) < 1e-6:
			if absf(p[i]) > h[i]:
				return 2.0
			continue
		var a := (-h[i] - p[i]) / d[i]
		var b := (h[i] - p[i]) / d[i]
		t0 = maxf(t0, minf(a, b))
		t1 = minf(t1, maxf(a, b))
		if t0 > t1:
			return 2.0
	return t0
