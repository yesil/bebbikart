extends Node
## The big screen (contracts §2i): one world, one world clock, a camera per half.
##  - Split (queue.updated split: two people play, racing or waiting in the line; it stays split
##    while anyone plays, see the server): the screen is cut down the middle,
##    the left racer (red) on the left half, the right racer (blue) on the right. Each half is a
##    SubViewport on the main viewport's World3D with its own CameraRig chasing its racer; an idle
##    half cycles through the fork shots. The main viewport stops drawing 3D (no third render),
##    and its camera moves to the middle of the two halves' cameras: the terrain's level of
##    detail and the audio's distances centre there.
##  - Full screen (one person playing, or nobody): the main camera chases whoever is racing, or
##    shows the fork shots while nobody is.
## The halves render at the window's pixel size (TextureRect with the SubViewport's texture, so the
## canvas_items stretch doesn't upscale a 960x1080 picture), capped by the quality's render height
## and upscaled with MetalFX on Metal (FSR elsewhere), like the main viewport.
## main.gd builds it, feeds it per frame (update) and passes on the quality (apply_quality).

const CameraRig = preload("res://world/camera_rig.gd")

const SIDES := ["left", "right"]
const IDLE_SHOT_S := 7.0     # an idle half moves to the next fork shot this often
const DIVIDER_W := 6.0       # the line between the halves, in 2D units
## Each half's racer is drawn on its own render layer (main.gd tags its meshes), so the other
## half's front shot and face cam can leave it out: the two duel racers wait in separate grid
## slots, but their karts drive through each other on their own lines.
const SIDE_LAYER := {"left": 1 << 10, "right": 1 << 11}

var split := false
var main_camera: CameraRig
var panes := {}              # side -> {sv: SubViewport, rig: CameraRig, tex: TextureRect}
var _layer: CanvasLayer
var _divider: ColorRect
var _idle_t := 0.0
var _render_cap := 0         # QUALITY render_height (0 = native)
var _fork_shots: Array = []


func setup(p_main_camera: CameraRig, fork_shots: Array) -> void:
	main_camera = p_main_camera
	_fork_shots = fork_shots
	_layer = CanvasLayer.new()
	_layer.layer = -1  # under every HUD
	add_child(_layer)
	for side in SIDES:
		var sv := SubViewport.new()
		sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
		sv.handle_input_locally = false
		sv.audio_listener_enable_3d = false
		var main_vp := get_viewport()
		sv.msaa_3d = main_vp.msaa_3d
		sv.screen_space_aa = main_vp.screen_space_aa
		sv.use_taa = main_vp.use_taa
		sv.use_debanding = main_vp.use_debanding
		sv.mesh_lod_threshold = main_vp.mesh_lod_threshold
		sv.use_occlusion_culling = main_vp.use_occlusion_culling
		sv.positional_shadow_atlas_size = main_vp.positional_shadow_atlas_size
		add_child(sv)
		var rig := CameraRig.new()
		rig.fork_shots = fork_shots
		rig.mode = CameraRig.Mode.FORKS
		rig.fork_idx = 0 if side == "left" else 1
		rig.front_hide = SIDE_LAYER["right" if side == "left" else "left"]
		sv.add_child(rig)
		rig.make_current()
		var tex := TextureRect.new()
		tex.texture = sv.get_texture()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.visible = false
		_layer.add_child(tex)
		panes[side] = {"sv": sv, "rig": rig, "tex": tex}
	_divider = ColorRect.new()
	_divider.color = Color(0.06, 0.06, 0.09)
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_divider.visible = false
	_layer.add_child(_divider)
	get_viewport().size_changed.connect(_layout)


## The village's camera blockers, once built (houses the chase cameras keep out of).
func set_blockers(b) -> void:
	for side in panes:
		panes[side]["rig"].blockers = b


## Split the screen (true) or give it to one racer (false).
func set_split(on: bool) -> void:
	if on == split and (not on or panes["left"]["tex"].visible):
		return
	split = on
	_layout()
	print("duel screen: %s" % ("split, a half per racer" if on else "full screen"))


## Turns the halves off for good (back to free races): the main viewport draws 3D again.
func teardown() -> void:
	split = false
	_layout()


func _layout() -> void:
	var vp := get_viewport()
	vp.disable_3d = split
	var rect := vp.get_visible_rect().size     # 2D units (canvas_items stretch)
	var px := Vector2(get_window().size)        # pixels
	for i in SIDES.size():
		var p: Dictionary = panes[SIDES[i]]
		var tex: TextureRect = p["tex"]
		var sv: SubViewport = p["sv"]
		tex.visible = split
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS if split else SubViewport.UPDATE_DISABLED
		if not split:
			continue
		var w := (rect.x - DIVIDER_W) * 0.5
		tex.position = Vector2(0.0 if i == 0 else w + DIVIDER_W, 0.0)
		tex.size = Vector2(w, rect.y)
		sv.size = Vector2i(maxi(16, int(px.x * w / rect.x)), maxi(16, int(px.y)))
	_divider.visible = split
	_divider.position = Vector2((rect.x - DIVIDER_W) * 0.5, 0.0)
	_divider.size = Vector2(DIVIDER_W, rect.y)
	_apply_render_scale()


## The quality's render height cap (0 = native), for the halves' 3D resolution.
func apply_quality(render_height: int) -> void:
	_render_cap = render_height
	_apply_render_scale()


func _apply_render_scale() -> void:
	var metal := RenderingServer.get_current_rendering_driver_name() == "metal"
	for side in panes:
		var sv: SubViewport = panes[side]["sv"]
		var h := float(sv.size.y)
		var k := 1.0 if _render_cap <= 0 or h <= _render_cap else float(_render_cap) / h
		sv.scaling_3d_scale = k
		if k >= 1.0:
			sv.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		else:
			sv.scaling_3d_mode = Viewport.SCALING_3D_MODE_METALFX_SPATIAL if metal else Viewport.SCALING_3D_MODE_FSR


## Per frame. on_side: side -> the racer view racing (or parked on the grid, or still cheering
## after its lap) in that half, or null when the half is idle. fronts: side -> true while that
## half's camera should show its racer from the front (on the grid, after the lap; see
## CameraRig.SWING_S). Returns the cameras now showing the race (for the weather volumes).
func update(delta: float, on_side: Dictionary, targets: Array, fronts := {}) -> Array:
	_idle_t += delta
	var next_shot := _idle_t >= IDLE_SHOT_S
	if next_shot:
		_idle_t = 0.0
	if not split:
		var v = on_side.get("left", null) if on_side.get("left", null) != null else on_side.get("right", null)
		_aim(main_camera, v, next_shot, bool(fronts.get("left", false)))
		main_camera.targets = targets
		return [main_camera]
	var mid := Vector3.ZERO
	for side in SIDES:
		var rig: CameraRig = panes[side]["rig"]
		_aim(rig, on_side.get(side, null), next_shot, bool(fronts.get(side, false)))
		rig.targets = targets
		mid += rig.global_position * 0.5
	# The main camera draws nothing now; it marks the middle for the terrain's detail and the audio.
	main_camera.mode = CameraRig.Mode.FOLLOW
	main_camera.target = null
	main_camera.front = false
	main_camera.global_position = mid
	return [panes["left"]["rig"], panes["right"]["rig"]]


## Chase a racer (from the front while `front`), or show the fork shots (the next one every
## IDLE_SHOT_S) while the half is idle.
func _aim(rig: CameraRig, view, next_shot: bool, front: bool) -> void:
	if view != null and is_instance_valid(view):
		rig.mode = CameraRig.Mode.FOLLOW
		rig.target = view
		rig.front = front
		return
	rig.target = null
	rig.front = false
	if rig.mode != CameraRig.Mode.FORKS:
		rig.mode = CameraRig.Mode.FORKS
	elif next_shot and not _fork_shots.is_empty():
		rig.fork_idx += 1


## The camera of a half (split), or the main camera (full screen).
func camera_of(side: String) -> Camera3D:
	return panes[side]["rig"] if split else main_camera


## The 2D rect of a half (split) or the whole screen, in canvas units: where the duel HUD draws.
func rect_of(side: String) -> Rect2:
	var rect := get_viewport().get_visible_rect().size
	if not split:
		return Rect2(Vector2.ZERO, rect)
	var w := (rect.x - DIVIDER_W) * 0.5
	return Rect2(Vector2(0.0 if side == "left" else w + DIVIDER_W, 0.0), Vector2(w, rect.y))


## One line for the mock summary, over the main camera and both halves' cameras.
func summary() -> String:
	var sum := Vector3.ZERO
	for rig in [main_camera, panes["left"]["rig"], panes["right"]["rig"]]:
		sum += rig.chase_stats()
	var out := "chase cameras %.1f m from their racers on average" % (sum.x / sum.y) if sum.y > 0.0 else "no chase camera settled on a racer"
	if main_camera.blockers != null or panes["left"]["rig"].blockers != null:
		out += "; pulled in front of a house or roof for %.1f s" % sum.z
	return out
