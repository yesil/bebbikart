extends Node
## Racer assets for players from the server roster (contracts §5, §7 RosterEntry):
## keeps each player's RacerSpec, downloads the ride drawing (sticker), and renders + uploads
## the phone images (hero, avatars) once per package via AvatarRenderer.
##
##   assets.update(roster)          # on every roster.updated
##   assets.spec_for(player_id)     # {} when the racer has no package yet
##   assets.drawing_for(player_id)  # Texture2D or null
##   assets.avatar_for(player_id)   # Texture2D (happy face, for the big-screen HUD) or null
## Signals: racer_ready(player_id) when a player's package is first seen (for a "new racer" moment),
## problem(text) when something fails (no fallbacks: main shows it on screen, and it is logged).

signal racer_ready(player_id: String)
signal problem(text: String)

var http_base := "http://localhost:8080"
var game_key := ""

var entries := {}        # playerId -> RosterEntry
var _drawings := {}      # packageId -> Texture2D
var _avatars := {}       # playerId -> Texture2D (avatar_happy)
var _avatar_urls := {}   # playerId -> avatar_happy URL downloaded or being downloaded
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
		# Rendered by an earlier run of the game (or before a reroll): fetch the avatar.
		var av_url := String(renders.get("avatar_happy", ""))
		if av_url != "" and _avatar_urls.get(pid, "") != av_url and not _rendered.has(pkg):
			_avatar_urls[pid] = av_url
			_download_avatar(pid, av_url)
		if not renders.has("hero") and not _rendered.has(pkg):
			_rendered[pkg] = true
			_queue.append(pid)
			_pump()
		if not had or old_pkg != pkg:
			racer_ready.emit(pid)
	for pid in entries.keys():
		if not seen.has(pid):
			entries.erase(pid)
			_avatars.erase(pid)
			_avatar_urls.erase(pid)


func nickname(player_id: String) -> String:
	return String(entries.get(player_id, {}).get("nickname", ""))


func spec_for(player_id: String) -> Dictionary:
	return entries.get(player_id, {}).get("asset", {}).get("spec", {})


func drawing_for(player_id: String) -> Texture2D:
	var pkg := String(entries.get(player_id, {}).get("asset", {}).get("packageId", ""))
	return _drawings.get(pkg)


func avatar_for(player_id: String) -> Texture2D:
	return _avatars.get(player_id)


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
		_fail("drawing download failed for %s: result %d, HTTP %d (%s)" % [pkg, res[0], res[1], _url(path)])
		return
	var img := Image.new()
	var body: PackedByteArray = res[3]
	var err := img.load_jpg_from_buffer(body)
	if err != OK:
		err = img.load_png_from_buffer(body)
	if err != OK:
		_fail("drawing for %s is not a JPEG/PNG (%s)" % [pkg, _url(path)])
		return
	_drawings[pkg] = ImageTexture.create_from_image(img)


func _download_avatar(pid: String, path: String) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	if req.request(_url(path)) != OK:
		req.queue_free()
		_fail("avatar download for %s could not start (%s)" % [nickname(pid), _url(path)])
		return
	var res: Array = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_fail("avatar download failed for %s: result %d, HTTP %d (%s)" % [nickname(pid), res[0], res[1], _url(path)])
		return
	var img := Image.new()
	if img.load_png_from_buffer(res[3]) != OK:
		_fail("avatar for %s is not a PNG (%s)" % [nickname(pid), _url(path)])
		return
	if _avatar_urls.get(pid, "") == path:
		_avatars[pid] = ImageTexture.create_from_image(img)


## One render at a time: each takes a few frames of the offscreen viewport.
func _pump() -> void:
	if _rendering or _queue.is_empty():
		return
	if not _renderer.can_render():
		_fail("can't render racer images for the phones in headless mode (%d waiting)" % _queue.size())
		_queue.clear()
		return
	_rendering = true
	while not _queue.is_empty():
		var pid: String = _queue.pop_front()
		var spec := spec_for(pid)
		if spec.is_empty():
			_fail("no RacerSpec for %s, can't render" % nickname(pid))
			continue
		# Give the drawing a moment to arrive so the sticker is in the hero render.
		var pkg := String(entries[pid]["asset"].get("packageId", ""))
		for i in 300:
			if _drawings.has(pkg):
				break
			await get_tree().process_frame
		if not _drawings.has(pkg):
			_fail("rendering %s without the ride drawing sticker: it did not download" % nickname(pid))
		var paths: Dictionary = await _renderer.render_all(spec, pid, drawing_for(pid))
		if paths.size() != 4:
			_fail("rendering %s produced %d of 4 images" % [nickname(pid), paths.size()])
		if paths.has("avatar_happy"):
			var img := Image.load_from_file(String(paths["avatar_happy"]))
			if img == null or img.is_empty():
				_fail("can't read the avatar just rendered for %s (%s)" % [nickname(pid), paths["avatar_happy"]])
			else:
				_avatars[pid] = ImageTexture.create_from_image(img)
		var ok: int = await _renderer.upload_all(pid, paths)
		if ok != paths.size():
			_fail("uploaded %d of %d images for %s to %s" % [ok, paths.size(), nickname(pid), http_base])
		else:
			print("RosterAssets: rendered %s (%s), uploaded %d images" % [nickname(pid), spec.get("title", "?"), ok])
	_rendering = false


func _fail(text: String) -> void:
	push_error("RosterAssets: " + text)
	problem.emit(text)
