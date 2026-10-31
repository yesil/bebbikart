extends Node
## Racer assets for players from the server roster (contracts §5, §7 RosterEntry):
## keeps each player's RacerSpec, downloads the ride drawing (sticker), and renders + uploads
## the phone images (hero, avatars) once per package via AvatarRenderer.
##
##   assets.update(roster)          # on every roster.updated
##   assets.spec_for(player_id)     # {} when the racer has no package yet
##   assets.drawing_for(player_id)  # Texture2D or null
## Signals: racer_ready(player_id) when a player's package is first seen (for a "new racer" moment).

signal racer_ready(player_id: String)

var http_base := "http://localhost:8080"
var game_key := ""

var entries := {}        # playerId -> RosterEntry
var _drawings := {}      # packageId -> Texture2D
var _requested := {}     # packageId -> true (download started)
var _rendered := {}      # packageId -> true (render queued or done)
var _queue: Array = []   # playerIds waiting for a render
var _rendering := false
var _renderer: AvatarRenderer


func _ready() -> void:
	_renderer = AvatarRenderer.new()
	_renderer.base_url = http_base
	_renderer.game_key = game_key
	add_child(_renderer)


func update(roster: Array) -> void:
	var seen := {}
	for e in roster:
		var pid := String(e.get("playerId", ""))
		seen[pid] = true
		var had: bool = entries.has(pid) and entries[pid].has("asset")
		var old_pkg := String(entries[pid].get("asset", {}).get("packageId", "")) if entries.has(pid) else ""
		entries[pid] = e
		if not e.has("asset"):
			continue
		var asset: Dictionary = e["asset"]
		var pkg := String(asset.get("packageId", ""))
		if not _requested.has(pkg):
			_requested[pkg] = true
			_download_drawing(pkg, String(asset.get("drawings", {}).get("vehicle", "")))
		var renders: Dictionary = asset.get("renders", {})
		if not renders.has("hero") and not _rendered.has(pkg):
			_rendered[pkg] = true
			_queue.append(pid)
			_pump()
		if not had or old_pkg != pkg:
			racer_ready.emit(pid)
	for pid in entries.keys():
		if not seen.has(pid):
			entries.erase(pid)


func nickname(player_id: String) -> String:
	return String(entries.get(player_id, {}).get("nickname", ""))


func spec_for(player_id: String) -> Dictionary:
	return entries.get(player_id, {}).get("asset", {}).get("spec", {})


func drawing_for(player_id: String) -> Texture2D:
	var pkg := String(entries.get(player_id, {}).get("asset", {}).get("packageId", ""))
	return _drawings.get(pkg)


func _url(path: String) -> String:
	return path if path.begins_with("http") else http_base.trim_suffix("/") + path


func _download_drawing(pkg: String, path: String) -> void:
	if path == "":
		return
	var req := HTTPRequest.new()
	add_child(req)
	if req.request(_url(path)) != OK:
		req.queue_free()
		return
	var res: Array = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		push_warning("RosterAssets: drawing download failed for %s (%s)" % [pkg, res[1]])
		return
	var img := Image.new()
	var body: PackedByteArray = res[3]
	var err := img.load_jpg_from_buffer(body)
	if err != OK:
		err = img.load_png_from_buffer(body)
	if err == OK:
		_drawings[pkg] = ImageTexture.create_from_image(img)


## One render at a time: each takes a few frames of the offscreen viewport.
func _pump() -> void:
	if _rendering or _queue.is_empty():
		return
	if not _renderer.can_render():
		_queue.clear()
		return
	_rendering = true
	while not _queue.is_empty():
		var pid: String = _queue.pop_front()
		var spec := spec_for(pid)
		if spec.is_empty():
			continue
		# Give the drawing a moment to arrive so the sticker is in the hero render.
		var pkg := String(entries[pid]["asset"].get("packageId", ""))
		for i in 60:
			if _drawings.has(pkg):
				break
			await get_tree().process_frame
		var paths: Dictionary = await _renderer.render_all(spec, pid, drawing_for(pid))
		var ok: int = await _renderer.upload_all(pid, paths)
		print("RosterAssets: rendered %s (%s), uploaded %d/%d" % [nickname(pid), spec.get("title", "?"), ok, paths.size()])
	_rendering = false
