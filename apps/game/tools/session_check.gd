extends SceneTree
## Drives the options menu's session controls against a running server, the way the game
## manager clicks them, and checks what the server answers:
##   bun apps/server/src/index.js   (another terminal)
##   godot --headless --path apps/game --script res://tools/session_check.gd -- --server[=URL]
## New session (one click: the session ends and a new one runs), then a track change (one click,
## no question) and back: each must reach its state within TIMEOUT_S. Exits 1 if one doesn't.
## The server's side (the karts on the track stop) is in apps/server/test/flow.test.js.

const TIMEOUT_S := 20.0

var problems: PackedStringArray = []
var _log_status := ""


func _initialize() -> void:
	_run.call_deferred()


func _main() -> Node:
	return current_scene


func _status() -> String:
	var m := _main()
	if m == null or m.get("net") == null:
		return "?"
	return String(m.net.session_status)


func _wait(what: String, ok: Callable) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < TIMEOUT_S * 1000.0:
		await process_frame
		var s := _status()
		if s != _log_status:
			print("session_check: session %s" % s)
			_log_status = s
		if _main() != null and ok.call():
			print("session_check: %s after %.1f s" % [what, (Time.get_ticks_msec() - t0) / 1000.0])
			return true
	problems.append("%s: not within %.0f s (session %s)" % [what, TIMEOUT_S, _status()])
	return false


## The server's session id, from GET /api/state next to the game's WebSocket URL.
func _session_id() -> String:
	var ws := "ws://localhost:8080/ws"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			ws = arg.get_slice("=", 1)
	var url := ws.replace("ws://", "http://").replace("wss://", "https://").trim_suffix("/ws") + "/api/state"
	var req := HTTPRequest.new()
	root.add_child(req)
	if req.request(url) != OK:
		problems.append("GET %s failed" % url)
		return ""
	var res: Array = await req.request_completed
	req.queue_free()
	var body = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return String(body.get("session", {}).get("id", "")) if body is Dictionary else ""


func _run() -> void:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	if not await _wait("online", func(): return _main().net.status == "online" and _status() != "?"):
		return _finish()
	_main().open_menu()  # like Esc: the menu learns the session's status
	if _status() != "running":
		_main().menu._on_session()  # Start a new session
		if not await _wait("first session running", func(): return _status() == "running"):
			return _finish()
	# New session: one click ends this session and starts the next (a new session id).
	var before := await _session_id()
	_main().menu._on_session()
	if not await _wait("New session sent", func(): return _main().menu._session_btn.disabled == false and _status() == "running"):
		return _finish()
	await create_timer(0.5).timeout
	var after := await _session_id()
	print("session_check: session %s -> %s" % [before, after])
	if after == "" or after == before:
		problems.append("New session: still session %s" % before)
	# A track change ends the session and starts a new one on the other track, in one click.
	for i in 2:
		var from: String = _main().track
		var to := "countryside" if from == "village" else "village"
		_main().open_menu()
		_main().menu._on_track(to)  # one click
		if not await _wait("%s -> %s loaded" % [from, to], func(): return _main().track == to and _main().net.status == "online"):
			return _finish()
		if not await _wait("running on %s" % to, func(): return _status() == "running"):
			return _finish()
	_finish()


func _finish() -> void:
	if problems.is_empty():
		print("SESSION CHECK PASSED")
		quit(0)
	else:
		for p in problems:
			print("FAIL ", p)
		print("SESSION CHECK FAILED (%d problems)" % problems.size())
		quit(1)
