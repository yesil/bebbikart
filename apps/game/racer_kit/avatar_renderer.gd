class_name AvatarRenderer
extends Node
## Offscreen renders of a racer for the phone (contracts §5): hero (full racer, 3/4 view,
## 1024 px, transparent) and avatar_happy / avatar_excited / avatar_sad (head and shoulders,
## 512 px). Add this node to the tree, then:
##
##   var paths := await renderer.render_all(spec, player_id, drawing)   # {key: png path}
##   await renderer.upload_all(player_id, paths)                         # PUT to the server
##
## Files go to user://renders/<playerId>/<key>.png. In headless mode there is no renderer,
## so render_all() returns {} (and prints why) instead of writing blank files.

const HERO_SIZE := 1024
const AVATAR_SIZE := 512
const AVATARS := {"avatar_happy": "happy", "avatar_excited": "excited", "avatar_sad": "sad"}

## Server for uploads, e.g. "http://localhost:8787". Empty = uploads are skipped (stub).
var base_url := ""
var game_key := ""

var _vp: SubViewport
var _cam: Camera3D


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.name = "AvatarViewport"
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.82, 0.9)
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -35, 0)
	key.light_energy = 1.1
	key.shadow_enabled = true
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_energy = 0.35
	_vp.add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 30
	_vp.add_child(_cam)


func can_render() -> bool:
	return DisplayServer.get_name() != "headless"


## Renders all four images. Returns {key: absolute png path}.
func render_all(spec: Dictionary, player_id: String, drawing: Texture2D = null) -> Dictionary:
	if not can_render():
		push_warning("AvatarRenderer: headless display, renders skipped")
		return {}
	if _vp == null:
		await ready
	var dir := "user://renders/%s" % player_id.validate_filename()
	DirAccess.make_dir_recursive_absolute(dir)
	var racer := RacerBuilder.build(spec, drawing)
	racer.show_name_tag(false)
	racer.set_process(false)
	_vp.add_child(racer)
	var out := {}

	racer.snap_pose("happy")
	var box := RacerBuilder._aabb(racer, Transform3D.IDENTITY)
	var c := box.get_center()
	var radius := box.size.length() * 0.5
	var dir3 := Vector3(-0.62, 0.38, -0.69).normalized()  # 3/4 view from front-right-ish
	_cam.look_at_from_position(c + dir3 * radius / tan(deg_to_rad(_cam.fov * 0.5)) * 1.05, c)
	var img := await _shot(HERO_SIZE)
	if img:
		out.hero = _save(img, dir, "hero")

	var head := racer.head_pivot.get_child(0) as Node3D
	var head_c := head.global_position + Vector3(0, -0.06, 0)
	var head_r: float = 0.42 * head.scale.y
	var fdir := Vector3(-0.3, 0.12, -1.0).normalized()
	for k in AVATARS:
		racer.snap_pose(AVATARS[k])
		_cam.look_at_from_position(head_c + fdir * head_r / tan(deg_to_rad(_cam.fov * 0.5)) * 1.25, head_c)
		img = await _shot(AVATAR_SIZE)
		if img:
			out[k] = _save(img, dir, k)
	racer.queue_free()
	return out


func _shot(size: int) -> Image:
	_vp.size = Vector2i(size, size)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var tex := _vp.get_texture()
	return tex.get_image() if tex else null


func _save(img: Image, dir: String, key: String) -> String:
	var path := ProjectSettings.globalize_path(dir.path_join(key + ".png"))
	img.save_png(path)
	return path


## PUT /api/game/renders/:playerId/:key with the PNG body (header x-game-key) → 204.
## Stub until the server exists: with no base_url it only logs and returns false.
func upload(player_id: String, key: String, png_path: String) -> bool:
	if base_url == "":
		print("AvatarRenderer: upload stub, would PUT %s to /api/game/renders/%s/%s" % [png_path.get_file(), player_id, key])
		return false
	var body := FileAccess.get_file_as_bytes(png_path)
	var req := HTTPRequest.new()
	add_child(req)
	var url := "%s/api/game/renders/%s/%s" % [base_url.trim_suffix("/"), player_id.uri_encode(), key]
	var err := req.request_raw(url, PackedStringArray(["Content-Type: image/png", "x-game-key: " + game_key]), HTTPClient.METHOD_PUT, body)
	if err != OK:
		req.queue_free()
		return false
	var res: Array = await req.request_completed
	req.queue_free()
	return res[0] == HTTPRequest.RESULT_SUCCESS and res[1] in [200, 204]


func upload_all(player_id: String, paths: Dictionary) -> int:
	var ok := 0
	for k in paths:
		if await upload(player_id, k, paths[k]):
			ok += 1
	return ok
