extends Node3D
## Draws the village surprises (sim/obstacles.gd) on the road: cows (walking in, grazing, trotting
## off, galloping away when hit), sheep crossing in a little flock, cheese wheels rolling across,
## hay bales dropping off a cart and being picked up again. A bouncing "!" hangs over each group,
## and a hit pops a word over the kart ("MOO!"). setup() returns "" or why it can't show them;
## main.gd reports that on screen.

const Course = preload("res://sim/course.gd")
const Obstacles = preload("res://sim/obstacles.gd")
const SteerMarks = preload("res://world/steer_marks.gd")
const I18n = preload("res://ui/i18n.gd")

const MODELS := {
	"cow": "res://assets/village/poly_pizza/Cow_2.glb",
	"sheep": "res://assets/village/poly_pizza/Sheep_2.glb",
}
const SCALE := {"cow": 0.34, "sheep": 0.58}
## Animations by state (matched on the end of the clip name, the glTF names carry armature prefixes).
const ANIM := {
	"cow": {"walk": "Walk", "stay": "Eating", "flee": "Gallop", "hit": "Idle_HitReact_Left"},
	"sheep": {"walk": "Walk", "stay": "Idle_Eating", "flee": "Run", "hit": "Jump"},
}
const WALK_ANIM_SPEED := {"cow": 1.0, "sheep": 1.1}  # clip speed at the kind's walking pace
const CHEESE_R := 0.62
const CHEESE_W := 0.42
const HAY_R := 0.6
const HAY_W := 1.15
const HAY_DROP_H := 1.8          # metres a bale falls from the cart
const SIGN_UP := 2.7             # the "!" over a group
const SIGN_SEEN_M := 90.0
const POP_S := 1.1               # a hit's word floats up this long
const FONT_NAMES := ["Arial Rounded MT Bold", "Avenir Next", "Helvetica Neue", "Arial"]

var sim
var course
var _scenes := {}                # kind -> PackedScene
var _nodes := {}                 # item id -> {root, body, anim (AnimationPlayer or null), clip, roll}
var _signs := {}                 # group id -> Label3D
var _pops: Array = []            # [Label3D, age]
var _cheese_mat: StandardMaterial3D
var _rind_mat: StandardMaterial3D
var _hay_mat: StandardMaterial3D
var _font: SystemFont


func setup(p_sim) -> String:
	sim = p_sim
	course = sim.course
	if sim.obstacles == null:
		return "the sim has no surprises to draw"
	for kind in MODELS:
		var ps := load(MODELS[kind]) as PackedScene
		if ps == null:
			return "%s is missing" % MODELS[kind]
		_scenes[kind] = ps
		# Every clip the views play loops (walking, grazing, galloping).
		var probe := ps.instantiate()
		var ap := probe.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap == null:
			probe.free()
			return "%s has no AnimationPlayer" % MODELS[kind]
		for state in ANIM[kind]:
			var clip := _clip(ap, ANIM[kind][state])
			if clip == "":
				probe.free()
				return "%s has no \"%s\" animation" % [MODELS[kind], ANIM[kind][state]]
			if state != "hit":
				ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		probe.free()
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


static func _clip(ap: AnimationPlayer, want: String) -> String:
	for n in ap.get_animation_list():
		if n == want or String(n).ends_with("|" + want):
			return n
	return ""


## A kart hit an item (sim.obstacle): its word pops up over the kart.
func on_hit(pl: Dictionary) -> void:
	var l := Label3D.new()
	l.font = _font
	l.text = I18n.t("obstacle.pop." + String(pl["kind"]))
	l.font_size = 120
	l.pixel_size = 0.012
	l.outline_size = 24
	l.outline_modulate = Color(0.12, 0.08, 0.2)
	l.modulate = Color(1.0, 0.95, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.layers = SteerMarks.SIGN_LAYER
	l.position = (pl["pos"] as Vector3) + Vector3.UP * 1.8
	add_child(l)
	_pops.append([l, 0.0])


func _process(delta: float) -> void:
	if sim == null or sim.obstacles == null:
		return
	var seen := {}
	var group_pos := {}             # group id -> [sum of positions, count]
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
	var anim: AnimationPlayer = null
	if _scenes.has(kind):
		var inst: Node3D = (_scenes[kind] as PackedScene).instantiate()
		inst.scale = Vector3.ONE * float(SCALE[kind])
		inst.rotation.y = PI  # the Quaternius animals face -z: turn them to walk head first
		body.add_child(inst)
		anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim != null:
			anim.seek(randf() * 1.5)
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
	return {"root": root, "body": body, "anim": anim, "clip": "", "roll": 0.0, "hop": 0.0, "kind": kind}


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
	# Facing: along the road turned by rel (towards +d at rel = PI/2).
	var rel := float(it["rel"])
	var dir: Vector3 = r.tangent_at(s) * cos(rel) + r.normal_at(s) * sin(rel)
	root.rotation = Vector3(0.0, atan2(dir.x, dir.z), 0.0)
	var state: String = it["state"]
	var moving := absf(float(it["vd"])) > 0.05
	match kind:
		"cow", "sheep":
			var want := "stay"
			if state == "scared":
				want = "flee"
			elif moving:
				want = "walk"
			_play(n, kind, want)
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


func _play(n: Dictionary, kind: String, state: String) -> void:
	var ap: AnimationPlayer = n["anim"]
	if ap == null:
		return
	var clip := _clip(ap, ANIM[kind][state])
	if n["clip"] == clip:
		return
	n["clip"] = clip
	ap.play(clip, 0.25)
	ap.speed_scale = float(WALK_ANIM_SPEED[kind]) if state == "walk" else 1.0


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
		l.position.y += delta * 1.2
		l.modulate.a = 1.0 - f * f
		l.outline_modulate.a = l.modulate.a
		l.scale = Vector3.ONE * (0.6 + 0.6 * minf(1.0, f * 5.0))
		keep.append(pop)
	_pops = keep
