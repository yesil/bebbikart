extends SceneTree
## Renders the options menu (server mode, a running session) and saves a screenshot, so a look
## at it doesn't need a whole game. Must run windowed (the dummy renderer saves blank images):
##   godot --path apps/game --resolution 1920x1080 --script res://tools/menu_check.gd -- --out=DIR [--server=http://localhost:8080]
## Exits 1 if the menu doesn't fit the screen (with a margin) in English or German, mock or
## server mode, idle, running or starting a new session, or with the phone address and QR code;
## or if the join column doesn't say why there is no code (mock mode, server unreachable).
## --server: also ask that server for the phone address (GET /api/join) and show its QR code.
## Decode the saved menu_*_join*.png with any QR reader to check the code scans.

const I18n = preload("res://ui/i18n.gd")
const OptionsMenu = preload("res://ui/options_menu.gd")
const MARGIN := 24.0
const NOBODY := "http://127.0.0.1:9"  # nothing listens there: the server is unreachable
const SAMPLE_URL := "http://192.168.1.23:8080"
# GET /api/join's qr for SAMPLE_URL (apps/server/test/qr.test.js has the same code).
const SAMPLE_QR := [
	"1111111001001100101111111", "1000001010110100001000001", "1011101010001000101011101",
	"1011101010110111101011101", "1011101000101010001011101", "1000001000101100101000001",
	"1111111010101010101111111", "0000000011001010000000000", "1000001011011101111001110",
	"0101110010011101110011110", "0111101111100101001101011", "0111000010010001100011001",
	"0000011001110010111000001", "1001010100101111000000010", "1011101101100001010101011",
	"1001000010001010100010101", "1000001111001100111110100", "0000000010000011100010100",
	"1111111000101110101011001", "1000001001010000100010001", "1011101001011101111111100",
	"1011101001101100001101011", "1011101000101000010000101", "1000001001101001101110001",
	"1111111011110011101001001",
]

var problems: PackedStringArray = []


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("menu_check: run it windowed, the headless renderer saves blank images")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	var out := ""
	var server := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--server="):
			server = a.get_slice("=", 1)
	var screen := get_root().get_visible_rect().size
	for lang in ["en", "de"]:
		var err := I18n.set_language(lang)
		if err != "":
			problems.append("i18n: " + err)
			continue
		var states := ["mock", "idle", "running", "starting", "join"] + (["join_live"] if server != "" else [])
		for state in states:
			var menu := OptionsMenu.new()
			get_root().add_child(menu)
			menu.setup("village", state != "mock")
			if state != "mock":
				menu.set_session("idle" if state == "idle" else "running")
				menu.set_join_server(server if state == "join_live" else NOBODY)
			menu.open()
			if state == "starting":  # New session clicked, waiting for the server
				menu._on_session()
			for i in 4:
				await process_frame
			var name := "%s_%s" % [lang, state]
			await _check_join(menu, name, state, server)
			var r: Rect2 = menu._panel.get_global_rect()
			print("menu %-10s panel %s on a %s screen" % [name, r, screen])
			if r.position.x < MARGIN or r.position.y < MARGIN or r.end.x > screen.x - MARGIN or r.end.y > screen.y - MARGIN:
				problems.append("%s: the menu %s doesn't fit the %s screen" % [name, r, screen])
			if out != "" and state != "idle" and state != "mock":
				await RenderingServer.frame_post_draw
				var path := out.path_join("menu_%s.png" % name)
				get_root().get_texture().get_image().save_png(path)
				print("saved ", path)
			menu.queue_free()
			await process_frame
	if problems.is_empty():
		print("MENU CHECK PASSED")
		quit(0)
	else:
		for p in problems:
			print("FAIL ", p)
		print("MENU CHECK FAILED (%d problems)" % problems.size())
		quit(1)


## The join column: the reason in red when there is no code, the code and address when there is.
func _check_join(menu, name: String, state: String, server: String) -> void:
	var note: Label = menu._join_note
	match state:
		"mock":
			if note.text != I18n.t("menu.join_mock") or menu._join_qr.visible:
				problems.append("%s: the join column doesn't say mock mode has no phones: %s" % [name, note.text])
		"join":
			# A server with no network (phones would open their own localhost) or no phone site.
			menu.show_join("http://localhost:8080", SAMPLE_QR, true)
			if menu._join_qr.visible or note.text != I18n.t("menu.join_local") or note.modulate != OptionsMenu.RED:
				problems.append("%s: a localhost address isn't shown as an error: %s" % [name, note.text])
			menu.show_join(SAMPLE_URL, SAMPLE_QR, false)
			if not menu._join_qr.visible or note.text != I18n.t("menu.join_no_site") or note.modulate != OptionsMenu.RED:
				problems.append("%s: a missing phone site isn't shown as an error: %s" % [name, note.text])
			if menu.show_join(SAMPLE_URL, ["1"], true) == "":
				problems.append("%s: a broken QR code was shown" % name)
			var why: String = menu.show_join(SAMPLE_URL, SAMPLE_QR, true)
			if why != "":
				problems.append("%s: the sample QR code wasn't shown: %s" % [name, why])
			await process_frame
		"join_live":
			for i in 600:  # up to ~10 s
				if menu._join_qr.visible or (note.modulate == OptionsMenu.RED):
					break
				await process_frame
			print("menu %-10s %s / %s" % [name, menu._join_url.text, note.text])
			if not menu._join_qr.visible:
				problems.append("%s: no QR code from %s: %s" % [name, server, note.text])
		_:
			var want := I18n.f("error.join_unreachable", [NOBODY, "can't connect"])
			for i in 600:
				if note.text == want:
					break
				await process_frame
			if note.text != want or note.modulate != OptionsMenu.RED or menu._join_qr.visible or menu._join_url.visible:
				problems.append("%s: an unreachable server isn't shown as an error: %s" % [name, note.text])
	if state == "join" or state == "join_live":
		if not menu._join_url.visible or menu._join_url.text == "":
			problems.append("%s: no phone address under the code" % name)
		var qr: Rect2 = menu._join_qr.get_global_rect()
		if qr.size.x < 250:
			problems.append("%s: the QR code is too small to scan from afar: %s" % [name, qr])
