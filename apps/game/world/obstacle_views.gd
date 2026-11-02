extends Node3D
## Draws the village surprises (sim/obstacles.gd) on the road: toy cows (walking in, grazing,
## trotting off, galloping away when hit) and sheep crossing in a little flock (world/toy_animal.gd
## builds and moves them), cheese wheels rolling across, hay bales dropping off a cart and being
## picked up again. The animals turn smoothly, watch karts coming at them, hop when one shaves past
## and spin or tumble when one hits them (a hit sheep bursts a puff of wool). A bouncing "!" hangs
## over each group, and a hit pops a word over the kart that rides along with it ("MOO!").
## setup() returns "" or why it can't show them; main.gd reports that on screen.

const Course = preload("res://sim/course.gd")
const Obstacles = preload("res://sim/obstacles.gd")
const SteerMarks = preload("res://world/steer_marks.gd")
const I18n = preload("res://ui/i18n.gd")
const ToyAnimal = preload("res://world/toy_animal.gd")

const TURN_RATE := {"cow": 2.4, "sheep": 4.0}   # rad/s an animal turns at most
const LOOK_M := {"cow": 24.0, "sheep": 18.0}     # it watches a kart this close
const WOOL_PUFFS := 3                             # puff bursts that can fly at once
const CHEESE_R := 0.62
const CHEESE_W := 0.42
const HAY_R := 0.6
const HAY_W := 1.15
const HAY_DROP_H := 1.8          # metres a bale falls from the cart
const SIGN_UP := 2.7             # the "!" over a group
const SIGN_SEEN_M := 90.0
const POP_S := 1.1               # a hit's word floats up this long
const POP_UP := 1.9              # metres over the kart it starts at
const FONT_NAMES := ["Arial Rounded MT Bold", "Avenir Next", "Helvetica Neue", "Arial"]

var sim
var course
var _nodes := {}                 # item id -> {root, body, animal (toy_animal.gd or null), yaw, roll, ...}
var _signs := {}                 # group id -> Label3D
var _pops: Array = []            # [Label3D, age, runId]
var _cheese_mat: StandardMaterial3D
var _rind_mat: StandardMaterial3D
var _hay_mat: StandardMaterial3D
var _font: SystemFont
var _rng := RandomNumberGenerator.new()
var _karts := PackedVector3Array()   # where the racing karts are this frame
var _wool: Array[CPUParticles3D] = []
var _wool_next := 0


func setup(p_sim) -> String:
	sim = p_sim
	course = sim.course
	if sim.obstacles == null:
		return "the sim has no surprises to draw"
	_rng.randomize()
	for i in WOOL_PUFFS:
		_wool.append(_wool_burst())
	_cheese_mat = StandardMaterial3D.new()
	_cheese_mat.albedo_color = Color(0.98, 0.8, 0.32)
	_cheese_mat.roughness = 0.55
	_rind_mat = StandardMaterial3D.new()
	_rind_mat.albedo_color = Color(0.86, 0.55, 0.16)
	_rind_mat.roughness = 0.7
	_hay_mat = StandardMaterial3D.new()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.noise = noise
	tex.seamless = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.72, 0.56, 0.22))
	ramp.set_color(1, Color(0.98, 0.86, 0.45))
	tex.color_ramp = ramp
	_hay_mat.albedo_texture = tex
	_hay_mat.uv1_scale = Vector3(3.0, 1.0, 1.0)
	_hay_mat.roughness = 0.95
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(FONT_NAMES)
	_font.font_weight = 800
	return ""


## A burst of cream wool puffs for a sheep that is hit (one shot, reused).
func _wool_burst() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 22
	p.lifetime = 0.8
	p.local_coords = false
	var m := KitMesh.sphere(0.075)
	p.mesh = m
	p.material_override = KitMaterial.toon()
	p.set_instance_shader_parameter("albedo", ToyAnimal.WOOL[0])
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 3.4
	p.gravity = Vector3(0, -4.0, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.6, 0.8))
	c.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = c
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


## A kart hit an item (sim.obstacle): its word pops up over the kart, the animal it hit spins or
## tumbles (a sheep in a puff of wool).
func on_hit(pl: Dictionary) -> void:
	var n: Dictionary = _nodes.get(int(pl.get("item", -1)), {})
	if not n.is_empty() and n["animal"] != null:
		n["animal"].knock()
		if n["kind"] == "sheep":
			var w := _wool[_wool_next]
			_wool_next = (_wool_next + 1) % _wool.size()
			w.global_position = (n["root"] as Node3D).position + Vector3.UP * 0.6
			w.restart()
	var l := Label3D.new()
	l.font = _font
	l.text = I18n.t("obstacle.pop." + String(pl["kind"]))
	l.font_size = 120
	l.pixel_size = 0.009
	l.outline_size = 24
	l.outline_modulate = Color(0.12, 0.08, 0.2)
	l.modulate = Color(1.0, 0.95, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.layers = SteerMarks.SIGN_LAYER
	l.position = (pl["pos"] as Vector3) + Vector3.UP * POP_UP
	add_child(l)
	_pops.append([l, 0.0, String(pl["runId"])])


func _process(delta: float) -> void:
	if sim == null or sim.obstacles == null:
		return
	var seen := {}
	var group_pos := {}             # group id -> [sum of positions, count]
	_karts.resize(sim.racers.size())
	for i in sim.racers.size():
		_karts[i] = sim.racers[i].world_pos()
	for it: Dictionary in sim.obstacles.items:
		var id := int(it["id"])
		seen[id] = true
		var n: Dictionary = _nodes.get(id, {})
		if n.is_empty():
			n = _make(it)
			_nodes[id] = n
		_place(it, n, delta)
		if sim.obstacles.hittable(it):
			var gid := int(it["group"])
			var acc: Array = group_pos.get(gid, [Vector3.ZERO, 0])
			acc[0] += (n["root"] as Node3D).position
			acc[1] += 1
			group_pos[gid] = acc
	for id in _nodes.keys():
		if not seen.has(id):
			(_nodes[id]["root"] as Node).queue_free()
			_nodes.erase(id)
	_update_signs(group_pos)
	_update_pops(delta)


func _make(it: Dictionary) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var body := Node3D.new()
	root.add_child(body)
	var kind: String = it["kind"]
	var animal: Node3D = null
	if kind == "cow" or kind == "sheep":
		animal = ToyAnimal.new()
		animal.setup(kind, _rng)
		animal.rotation.y = PI  # the toys face -z: turn them to walk head first
		body.add_child(animal)
	elif kind == "cheese":
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = CHEESE_R
		cyl.bottom_radius = CHEESE_R
		cyl.height = CHEESE_W
		cyl.radial_segments = 28
		mi.mesh = cyl
		mi.material_override = _cheese_mat
		mi.rotation.z = PI * 0.5  # axis across its way: it rolls head first along +z
		body.add_child(mi)
		# The rind round the rim.
		var rim := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = CHEESE_R - 0.05
		tor.outer_radius = CHEESE_R + 0.02
		rim.mesh = tor
		rim.material_override = _rind_mat
		rim.rotation.z = PI * 0.5
		rim.scale = Vector3(1.0, 3.2, 1.0)
		body.add_child(rim)
		body.position.y = CHEESE_R
	else:
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = HAY_R
		cyl.bottom_radius = HAY_R
		cyl.height = HAY_W
		cyl.radial_segments = 24
		mi.mesh = cyl
		mi.material_override = _hay_mat
		mi.rotation.z = PI * 0.5
		body.add_child(mi)
		body.position.y = HAY_R
	return {"root": root, "body": body, "animal": animal, "roll": 0.0, "hop": 0.0, "kind": kind,
		"yaw": INF, "was_hit": false, "armed": true}


func _place(it: Dictionary, n: Dictionary, delta: float) -> void:
	var seg: Dictionary = course.segments[it["seg"]]
	var r = seg["route"]
	var s := float(it["s"])
	var root: Node3D = n["root"]
	var body: Node3D = n["body"]
	var kind: String = it["kind"]
	root.visible = float(it["wait"]) <= 0.0
	var p: Vector3 = r.world_at(s, float(it["d"]))
	p.y = course.surface_y(seg, s)
	# Facing: along the road turned by rel (towards +d at rel = PI/2). The sim turns an animal at
	# once; here it turns round smoothly.
	var rel := float(it["rel"])
	var dir: Vector3 = r.tangent_at(s) * cos(rel) + r.normal_at(s) * sin(rel)
	var yaw := atan2(dir.x, dir.z)
	var yaw_rate := 0.0
	if n["animal"] != null and n["yaw"] != INF and root.visible:
		var diff := wrapf(yaw - float(n["yaw"]), -PI, PI)
		var max_turn: float = TURN_RATE[kind] * delta
		var turn := clampf(diff * (1.0 - exp(-delta * 7.0)), -max_turn, max_turn)
		yaw = float(n["yaw"]) + turn
		yaw_rate = turn / maxf(delta, 1e-4)
	n["yaw"] = yaw
	root.rotation = Vector3(0.0, yaw, 0.0)
	var state: String = it["state"]
	match kind:
		"cow", "sheep":
			_animal(it, n, p, delta, yaw_rate)
		"cheese":
			# Rolls on its rim; knocked away by a kart it tumbles off in a hop.
			n["roll"] = float(n["roll"]) + absf(float(it["vd"])) * delta / CHEESE_R
			body.rotation.x = float(n["roll"])
			if state == "scared":
				n["hop"] = float(n["hop"]) + delta
				var t := float(n["hop"])
				p.y += maxf(0.0, 3.2 * t - 6.0 * t * t)
				body.rotation.z = t * 6.0
		"hay":
			var t := float(it["t"])
			if state == "stay" and t < 0.0:
				var f := -t / Obstacles.HAY_DROP_S
				p.y += HAY_DROP_H * f * f
			elif state == "out":
				root.scale = Vector3.ONE * maxf(0.01, 1.0 - t / Obstacles.HAY_PICK_S)
			elif state == "scared":
				n["roll"] = float(n["roll"]) + absf(float(it["vd"])) * delta / HAY_R
				body.rotation.x = float(n["roll"])
	root.position = p


## Moves a cow or sheep: its gait from its pace, and an eye on the nearest kart. A kart that shaves
## past makes it hop; one that scares the whole flock (a sheep's flock-mate was hit) too.
func _animal(it: Dictionary, n: Dictionary, p: Vector3, delta: float, yaw_rate: float) -> void:
	var animal: Node3D = n["animal"]
	var kind: String = n["kind"]
	var look = null
	var near := INF
	for k in _karts:
		var dist := k.distance_to(p)
		if dist < near:
			near = dist
			look = k
	if near > float(LOOK_M[kind]):
		look = null
	var near_m: float = ToyAnimal.SPEC[kind]["near_m"]
	if it["hit"] and not n["was_hit"]:
		n["was_hit"] = true
		animal.startle()      # the one a kart hit is knocked over by on_hit instead
	elif not it["hit"]:
		if near < near_m and n["armed"]:
			n["armed"] = false
			animal.startle()
		elif near > near_m + 3.0:
			n["armed"] = true
	animal.animate(delta, absf(float(it["vd"])), String(it["state"]), yaw_rate, look, near)


## A bouncing "!" over each group still in the way.
func _update_signs(group_pos: Dictionary) -> void:
	for gid in group_pos:
		var l: Label3D = _signs.get(gid)
		if l == null:
			l = Label3D.new()
			l.font = _font
			l.text = "!"
			l.font_size = 160
			l.pixel_size = 0.014
			l.outline_size = 30
			l.outline_modulate = Color(0.12, 0.08, 0.2)
			l.modulate = Color(1.0, 0.82, 0.2)
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.layers = SteerMarks.SIGN_LAYER
			l.visibility_range_end = SIGN_SEEN_M
			l.visibility_range_end_margin = 10.0
			l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(l)
			_signs[gid] = l
		var acc: Array = group_pos[gid]
		var c: Vector3 = acc[0] / float(acc[1])
		l.position = c + Vector3.UP * (SIGN_UP + 0.2 * absf(sin(Time.get_ticks_msec() * 0.006)))
	for gid in _signs.keys():
		if not group_pos.has(gid):
			(_signs[gid] as Node).queue_free()
			_signs.erase(gid)


func _update_pops(delta: float) -> void:
	var keep: Array = []
	for pop in _pops:
		var l: Label3D = pop[0]
		pop[1] = float(pop[1]) + delta
		var f := float(pop[1]) / POP_S
		if f >= 1.0:
			l.queue_free()
			continue
		# Over its kart as it drives on (the chase camera keeps it the same size), rising a little.
		var r = sim.by_run.get(pop[2])
		if r != null:
			l.position = r.world_pos() + Vector3.UP * (POP_UP + f * 1.2)
		else:
			l.position.y += delta * 1.2
		l.modulate.a = 1.0 - f * f
		l.outline_modulate.a = l.modulate.a
		l.scale = Vector3.ONE * (0.6 + 0.6 * minf(1.0, f * 5.0))
		keep.append(pop)
	_pops = keep
