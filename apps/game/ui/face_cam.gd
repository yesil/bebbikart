extends SubViewport
## A live face cam of one racer for its plate (ui/duel_hud.gd): a small camera in front of the
## character, a little to one side, framing its face and hands, so the big screen shows the
## driver's gestures (racer_kit/racer_gestures.gd) while the race camera chases from behind.
## A SubViewport on the main World3D, drawn only while it has a racer, and then on every other
## frame (`phase`): the two halves' cams take turns, so at most one draws a frame; the plate shows
## get_texture(). The other half's racer is left out (set_hide_layers): in a duel both racers
## can sit in the same spot, and only this racer's face belongs here.

const FOV := 34.0
const HEAD_R := 0.21        # head radius per unit of the head's scale (racer_kit/kit_parts.gd HEAD_PARAMS)
const SPAN := 2.9           # the picture spans this many head radii up and down from its middle
const DROP := 0.95          # its middle sits this many head radii below the head: face and hands
## The camera stands on the side of the grid's front shot (world/camera_rig.gd FRONT_ANGLE): a
## racer looking into that camera on the grid looks into this one too.
const SIDE := -0.35         # the camera stands this far off to the racer's side (per unit forward)
const RISE := 0.08          # and a little above
const TURN_RATE := 5.0      # how fast it follows the racer's heading (per second)
const BOB_RATE := 9.0       # how fast it follows the head bobbing

var blockers = null         # world/camera_blockers.gd (village houses), or null
var phase := 0              # draws on the frames where Engine.get_process_frames() % 2 is this
var _cam: Camera3D
var _view = null            # the racer view framed, or null
var _fresh := false         # _view is new: jump to it rather than ease
var _yaw := 0.0             # eased heading of the racer
var _off := Vector3.ZERO    # the shot's middle relative to the racer's origin, eased


func _init() -> void:
	own_world_3d = false
	transparent_bg = false
	handle_input_locally = false
	audio_listener_enable_3d = false
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.near = 0.05
	_cam.far = 120.0
	add_child(_cam)


func _ready() -> void:
	var main_vp := get_parent().get_viewport()
	msaa_3d = main_vp.msaa_3d
	screen_space_aa = main_vp.screen_space_aa
	use_debanding = main_vp.use_debanding
	_cam.current = true


## Layers this camera leaves out (the other half's racer).
func set_hide_layers(mask: int) -> void:
	_cam.cull_mask = 0xFFFFF & ~mask


## Per frame: frame `view`'s face and hands. Returns false (and stops drawing) when there is
## nothing to show: no racer, or a mock placeholder box without a character. The camera moves in
## _process, after main.gd has moved the racers this frame (it calls this before): placed here,
## it framed where the racer was a frame ago, and a new racer's first picture missed it. A new
## racer's first picture is drawn at once, whatever the phase: the texture still holds the last
## racer.
func follow(view) -> bool:
	var toy = view.get("toy") if view != null and is_instance_valid(view) else null
	if toy == null or toy.head_pivot == null or toy.head_pivot.get_child_count() == 0:
		render_target_update_mode = SubViewport.UPDATE_DISABLED
		_view = null
		return false
	if view != _view:
		_view = view
		_fresh = true
	return true


func _process(delta: float) -> void:
	if _view == null or not is_instance_valid(_view):
		return
	var head := (_view.toy.head_pivot as Node3D).get_child(0) as Node3D
	var r := HEAD_R * head.global_basis.get_scale().y
	var root: Vector3 = _view.global_position
	var yaw: float = (_view.get_child(0) as Node3D).rotation.y  # the view's body, as camera_rig.gd reads it
	var off := head.global_position - Vector3.UP * r * DROP - root
	var draw_now := _fresh
	if _fresh:
		_fresh = false
		_yaw = yaw
		_off = off
	else:
		_yaw = lerp_angle(_yaw, yaw, 1.0 - exp(-delta * TURN_RATE))
		_off = _off.lerp(off, 1.0 - exp(-delta * BOB_RATE))
	var mid := root + _off
	var fwd := Vector3(sin(_yaw), 0.0, cos(_yaw))
	var side := Vector3.UP.cross(fwd)
	var dir := (fwd + side * SIDE + Vector3.UP * RISE).normalized()
	var eye := mid + dir * r * SPAN / tan(deg_to_rad(FOV * 0.5))
	if blockers != null:
		eye = blockers.clip(mid, eye)
	_cam.look_at_from_position(eye, mid, Vector3.UP)
	# Eased and moved every frame, drawn on every other one.
	if draw_now or Engine.get_process_frames() % 2 == phase:
		render_target_update_mode = SubViewport.UPDATE_ONCE
