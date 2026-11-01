extends Node3D
## What thumb steering (contracts §2g) needs on the big screen, built at load from the course on
## top of the baked world (no re-bake):
##   - the boost arrows: glowing chevrons on the road where a strip is (sim/course.gd boosts);
##     a kart driving over them gets the boost;
##   - a sign over each fork: which way each side of the road takes (sim/forks.gd);
##   - a ring on the road ahead of a kart a thumb is steering, at the lane the thumb asks for.
## setup() returns "" or why it can't show them; main.gd reports that on screen.

const Course = preload("res://sim/course.gd")
const Forks = preload("res://sim/forks.gd")
const Route = preload("res://sim/route.gd")
const Tuning = preload("res://sim/tuning.gd")
const I18n = preload("res://ui/i18n.gd")
const ARROW_SHADER := "res://world/materials/boost_arrows.gdshader"

const CHEVRON_EVERY := 2.0    # metres between chevrons along a strip
const CHEVRON_LEN := 0.9      # metres from a chevron's tips to its point
const CHEVRON_THICK := 0.4    # metres, along the road
const LIFT := 0.04            # metres above the road surface (no z-fighting)
const SIGN_AT := 4.0          # metres past the junction, where the two ways start to part
const SIGN_UP := 3.4          # metres above the road
const SIGN_GAP := 1.6         # metres between the two signs, as the camera sees them
const SIGN_SEEN_M := 75.0     # signs show from this close (they draw over hills otherwise)
const RING_AHEAD := 6.0       # metres ahead of the kart
const FONT_NAMES := ["Arial Rounded MT Bold", "Avenir Next", "Helvetica Neue", "Arial"]
## The signs and the rings draw through everything (no_depth_test), so they sit on their own
## render layer: the face cams (ui/face_cam.gd) and the front shot (world/camera_rig.gd) leave it
## out, the chase view keeps it. Bits 10 and 11 are the duel halves' racers (DuelScreen.SIDE_LAYER).
const SIGN_LAYER := 1 << 12

var course
var sim
var _signs: Array = []        # [Label3D, fork, choice, "left" | "right"]
var _language := ""
var _rings := {}              # runId -> MeshInstance3D
var _ring_mesh: TorusMesh
var _ring_mat: StandardMaterial3D


func setup(p_course, p_sim) -> String:
	course = p_course
	sim = p_sim
	if not ResourceLoader.exists(ARROW_SHADER):
		return "%s is missing" % ARROW_SHADER
	if course.forks.is_empty():
		return "the course has no forks to sign"
	var err := _build_arrows()
	if err != "":
		return err
	err = _build_signs()
	if err != "":
		return err
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.45
	_ring_mesh.outer_radius = 0.7
	_ring_mesh.rings = 24
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(1.0, 0.95, 0.5)
	_ring_mat.no_depth_test = true
	_ring_mat.render_priority = 1
	return ""


## Every strip of every segment, as one mesh: chevrons pointing forward, centred on the strip's
## lane (Course.arrow_d), as wide as the catch (BOOST_ARROW_HALF either side).
func _build_arrows() -> String:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for id in course.ordered_ids:
		var seg: Dictionary = course.segments[id]
		var r: Route = seg["route"]
		for b in seg["boosts"]:
			var a := float(b[0])
			var e := float(b[1])
			var side := int(b[2])
			if e <= a or e > r.length + 0.01 or absi(side) != 1:
				return "segment %s has a bad boost strip %s" % [id, b]
			var c := Course.arrow_d(seg, side)
			var count := maxi(1, int((e - a) / CHEVRON_EVERY))
			for k in count:
				var s := a + CHEVRON_EVERY * (k + 0.5) + CHEVRON_LEN * 0.5
				_chevron(st, seg, r, s, c, float(k) / maxf(1.0, count - 1.0))
				n += 1
	if n == 0:
		return "the course has no boost arrows"
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "BoostArrows"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = load(ARROW_SHADER)
	mi.material_override = m
	add_child(mi)
	return ""


## One chevron (a V pointing forward) whose point is at (s, c) in the segment's road frame;
## u is its place along the strip (the shader's running light).
func _chevron(st: SurfaceTool, seg: Dictionary, r: Route, s: float, c: float, u: float) -> void:
	var w := Tuning.BOOST_ARROW_HALF
	for arm in [-1.0, 1.0]:
		# Outer edge from the tip (s - LEN, c + arm*w) to the point (s, c); inner edge THICK behind.
		var quad := [
			_at(seg, r, s - CHEVRON_LEN, c + arm * w),
			_at(seg, r, s, c),
			_at(seg, r, s - CHEVRON_THICK, c),
			_at(seg, r, s - CHEVRON_LEN - CHEVRON_THICK, c + arm * w),
		]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(Vector2(u, 0.0))
			st.add_vertex(quad[i])


func _at(seg: Dictionary, r: Route, s: float, d: float) -> Vector3:
	var p := r.world_at(s, d)
	p.y = r.pos_at(s).y + Course.surface_offset(seg, s) + LIFT
	return p


## Two signs over each fork, SIGN_AT past the junction: "← Water" to the left, "Bridge →" to the
## right (the side the kart is on there picks the way, sim/racer.gd). They face the camera and
## are pushed apart on screen, so seen from behind a kart left is the road's left and they never
## overlap, whatever the angle.
func _build_signs() -> String:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_NAMES)
	for fork in course.forks:
		var ways: Dictionary = course.forks[fork]
		var any: Dictionary = ways.values()[0]
		var r: Route = course.segments[any["seg"]]["route"]
		if r.length < SIGN_AT:
			return "fork %s: its way is shorter than %.0f m" % [fork, SIGN_AT]
		var p := r.pos_at(SIGN_AT) + Vector3.UP * SIGN_UP
		for dir in ["left", "right"]:
			var choice := Forks.pick(ways, -1 if dir == "left" else 1)
			if choice == "":
				return "fork %s has no way to the %s" % [fork, dir]
			var l := Label3D.new()
			l.font = font
			l.font_size = 128
			l.pixel_size = 0.016
			l.outline_size = 22
			l.outline_modulate = Color(0.12, 0.08, 0.2)
			l.modulate = Color(1.0, 0.86, 0.3)
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.layers = SIGN_LAYER
			l.fixed_size = false
			l.visibility_range_end = SIGN_SEEN_M
			l.visibility_range_end_margin = 10.0
			l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			l.position = p
			add_child(l)
			_signs.append([l, fork, choice, dir])
	_relabel()
	return ""


func _relabel() -> void:
	_language = I18n.language
	for s in _signs:
		var name_ := I18n.t("way." + String(s[1]) + "." + String(s[2]))
		var l: Label3D = s[0]
		l.text = I18n.f("way.left" if s[3] == "left" else "way.right", [name_])
		var w := l.font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x
		var push := w * 0.5 + SIGN_GAP * 0.5 / l.pixel_size
		l.offset = Vector2(-push if s[3] == "left" else push, 0.0)


func _process(_delta: float) -> void:
	if I18n.language != _language:
		_relabel()  # the options menu switched the language
	if sim == null:
		return
	var seen := {}
	for r in sim.racers:
		if r.steer_x == null or r.state != "racing":
			continue
		seen[r.run_id] = true
		var ring: MeshInstance3D = _rings.get(r.run_id)
		if ring == null:
			ring = MeshInstance3D.new()
			ring.mesh = _ring_mesh
			ring.material_override = _ring_mat
			ring.layers = SIGN_LAYER
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(ring)
			_rings[r.run_id] = ring
		var route: Route = r.route()
		var s := minf(r.ls + RING_AHEAD, route.length - 0.05)
		var p := route.world_at(s, float(r.steer_last) * r.steer_lim())
		p.y = route.pos_at(s).y + Course.surface_offset(r.seg, s) + 0.15
		ring.position = p
		ring.scale = Vector3.ONE * (1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.012))
	for id in _rings.keys():
		if not seen.has(id):
			(_rings[id] as Node).queue_free()
			_rings.erase(id)
