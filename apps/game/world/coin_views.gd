extends Node3D
## Each racer's chocolate coins (sim/coins.gd) on the road: gold-foil coins standing on edge,
## spinning and bobbing over the road; a collected one jumps up, spins fast and is gone. In a
## split screen each half shows only its own racer's coins: they are drawn on that side's coin
## layer (DuelScreen.COIN_LAYER), which the other half's camera leaves out. setup() returns "" or
## why it can't show them; main.gd reports that on screen.

const Course = preload("res://sim/course.gd")
const DuelScreen = preload("res://world/duel_screen.gd")

const R := 0.45                  # coin radius (metres)
const THICK := 0.1
const UP := 0.75                 # centre height over the road
const BOB := 0.08
const SPIN := 1.8                # rad/s
const POP_S := 0.35              # a collected coin's last moment
const SEEN_M := 70.0             # coins further than this ahead are not drawn

var sim
## runId -> "left" | "right": the half its racer races in (main.gd's duel sides); "" while unknown.
var side_of: Callable
var _sets := {}                  # runId -> {mm: MultiMeshInstance3D, lap, popped: {index: age}}
var _mesh: CylinderMesh
var _mat: StandardMaterial3D


func setup(p_sim, p_side_of: Callable) -> String:
	sim = p_sim
	side_of = p_side_of
	if sim.coins == null:
		return "the sim has no chocolate coins to draw"
	_mesh = CylinderMesh.new()
	_mesh.top_radius = R
	_mesh.bottom_radius = R
	_mesh.height = THICK
	_mesh.radial_segments = 20
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(1.0, 0.78, 0.22)
	_mat.metallic = 0.85
	_mat.roughness = 0.28
	# A little glow, so they read in the shade of the houses and from the far end of a street.
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.7, 0.15)
	_mat.emission_energy_multiplier = 0.35
	_mesh.material = _mat
	return ""


func _process(delta: float) -> void:
	if sim == null:
		return
	var seen := {}
	var t := Time.get_ticks_msec() / 1000.0
	for r in sim.racers:
		if r.coins.is_empty() or r.state != "racing":
			continue
		seen[r.run_id] = true
		var set_: Dictionary = _sets.get(r.run_id, {})
		if set_.is_empty() or int(set_["lap"]) != r.coins_lap:
			if not set_.is_empty():
				(set_["mm"] as Node).queue_free()
			set_ = _make(r)
			_sets[r.run_id] = set_
		var side: String = side_of.call(r.run_id)
		var mmi: MultiMeshInstance3D = set_["mm"]
		mmi.layers = DuelScreen.COIN_LAYER[side] if side != "" else 1
		var mm := mmi.multimesh
		var popped: Dictionary = set_["popped"]
		var here: float = r.gs()
		for i in r.coins.size():
			var c: Dictionary = r.coins[i]
			var seg: Dictionary = sim.course.segments[c["seg"]]
			var ahead := float(r.offsets[r.path.find(c["seg"])]) + float(c["s"]) - here
			var show := ahead > -3.0 and ahead < SEEN_M
			var scale := 1.0
			var lift := 0.0
			var spin := t * SPIN + float(i) * 0.7
			if c["taken"]:
				var age := float(popped.get(i, 0.0)) + delta
				popped[i] = age
				var f := age / POP_S
				show = show and f < 1.0
				scale = 1.0 + 0.4 * f
				lift = 1.2 * f
				spin = t * SPIN * 6.0
			var rt = seg["route"]
			var p: Vector3 = rt.world_at(float(c["s"]), float(c["d"]))
			if not show:
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), p))
				continue
			p.y = sim.course.surface_y(seg, float(c["s"])) + UP + lift + BOB * sin(t * 3.0 + float(i))
			# On edge (the cylinder's axis lying flat), turning about the vertical.
			var b := Basis(Vector3.UP, spin) * Basis(Vector3.RIGHT, PI * 0.5)
			mm.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * scale), p))
	for id in _sets.keys():
		if not seen.has(id):
			(_sets[id]["mm"] as Node).queue_free()
			_sets.erase(id)


func _make(r) -> Dictionary:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh
	mm.instance_count = r.coins.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return {"mm": mmi, "lap": r.coins_lap, "popped": {}}
