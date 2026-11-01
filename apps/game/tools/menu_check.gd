extends SceneTree
## Renders the options menu (server mode, a running session) and saves a screenshot, so a look
## at it doesn't need a whole game. Must run windowed (the dummy renderer saves blank images):
##   godot --path apps/game --resolution 1920x1080 --script res://tools/menu_check.gd -- --out=DIR [--language=de]
## Exits 1 if the menu doesn't fit the screen (with a margin) in English or German, mock or
## server mode, idle or running, confirming an end.

const I18n = preload("res://ui/i18n.gd")
const OptionsMenu = preload("res://ui/options_menu.gd")
const MARGIN := 24.0

var problems: PackedStringArray = []


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("menu_check: run it windowed, the headless renderer saves blank images")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	var screen := get_root().get_visible_rect().size
	for lang in ["en", "de"]:
		var err := I18n.set_language(lang)
		if err != "":
			problems.append("i18n: " + err)
			continue
		for server in [false, true]:
			for state in (["idle", "running", "confirm"] if server else ["mock"]):
				var menu := OptionsMenu.new()
				get_root().add_child(menu)
				menu.setup("village", server)
				if server:
					menu.set_session("idle" if state == "idle" else "running")
				menu.open()
				if state == "confirm":
					menu._on_session()
				for i in 4:
					await process_frame
				var r: Rect2 = menu._panel.get_global_rect()
				var name := "%s_%s" % [lang, state]
				print("menu %-10s panel %s on a %s screen" % [name, r, screen])
				if r.position.x < MARGIN or r.position.y < MARGIN or r.end.x > screen.x - MARGIN or r.end.y > screen.y - MARGIN:
					problems.append("%s: the menu %s doesn't fit the %s screen" % [name, r, screen])
				if out != "" and (state == "running" or state == "confirm"):
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
