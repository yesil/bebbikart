extends RefCounted
## A built racer's ground footprint for the sim (sim.gd add_run size): half its width and half its
## length, in metres about the racer's origin. Counts the ride (body, wheels, legs, hull, wings)
## and not what is mounted on its sockets (extras like flags or exhausts) or the rider on top;
## the sim clamps the result (Tuning.SIZE_HALF_WIDTH, SIZE_HALF_LENGTH_MAX).


## Builds `spec` (racer_kit RacerBuilder), measures it and frees it. Returns
## {"size": Vector2(half width, half length)} or {"error": String}.
static func of_spec(spec: Dictionary) -> Dictionary:
	var toy: ToyRacer = RacerBuilder.build(spec, null)
	if toy == null:
		return {"error": "the racer kit could not build it: %s" % "; ".join(RacerBuilder.last_errors.slice(0, 3))}
	var out := of_toy(toy)
	toy.free()
	return out


## Same for a toy that is already built.
static func of_toy(toy: ToyRacer) -> Dictionary:
	var ride: Node3D = toy.model.get_node_or_null("Ride") if toy.model != null else null
	if ride == null:
		return {"error": "the built toy has no Ride node to measure"}
	var box := _bounds(ride, toy.model.transform * ride.transform)
	if box.size.x <= 0.0 or box.size.z <= 0.0:
		return {"error": "the built toy's ride has no meshes to measure"}
	var hw := maxf(absf(box.position.x), absf(box.end.x))
	var hl := maxf(absf(box.position.z), absf(box.end.z))
	return {"size": Vector2(hw, hl)}


## Bounds of the meshes under n in the space xf maps n's children into, skipping socket markers
## (their extras) and labels.
static func _bounds(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.get_children():
		if not c is Node3D or c is Label3D or String(c.name).begins_with("Socket_"):
			continue
		var cx: Transform3D = xf * c.transform
		var box := AABB()
		var has := false
		if c is MeshInstance3D and c.mesh:
			box = cx * c.mesh.get_aabb()
			has = true
		var sub := _bounds(c, cx)
		if sub.size != Vector3.ZERO:
			box = sub if not has else box.merge(sub)
			has = true
		if has:
			out = box if first else out.merge(box)
			first = false
	return out
