extends SceneTree
## Renders the race HUD's podium at the end of a session from test data (20 racers, the top 14
## with a time) and saves a screenshot, so a look at it doesn't need a whole session. The halves'
## HUD has its own frames in tools/duel_check.gd. Must run windowed (the dummy renderer saves
## blank images):
##   godot --path apps/game --resolution 1920x1080 --script res://tools/hud_check.gd -- --out=DIR [--language=de]
## Exits 1 if the podium is missing or doesn't fit the screen.

const RaceHud = preload("res://ui/race_hud.gd")
const I18n = preload("res://ui/i18n.gd")
const NAMES := ["Mia", "Noah", "Lina", "Ben", "Ella", "Finn", "Zoe", "Leo", "Ava", "Max",
	"Nora", "Tim", "Ida", "Kai", "Yara", "Oli", "Rosa", "Sam", "Lou", "Jan"]


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := String(args.get("out", "user://hud_check"))
	DirAccess.make_dir_recursive_absolute(out)
	var err := I18n.set_language(String(args.get("language", "en")))
	if err != "":
		push_error(err)
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		push_error("hud_check: run it windowed, the headless renderer saves blank images")
		quit(1)
		return
	var bg := ColorRect.new()
	bg.color = Color(0.32, 0.5, 0.36)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var hud := RaceHud.new()
	root.add_child(hud)
	await process_frame  # _ready builds the panels
	var roster: Array = []
	var board: Array = []
	for i in NAMES.size():
		roster.append({"playerId": "p%d" % i, "nickname": NAMES[i], "status": "ready", "connected": true})
		if i < 14:
			board.append({"playerId": "p%d" % i, "rank": i + 1, "bestTimeMs": 29800 + i * 730})
	hud.set_roster(roster)
	hud.set_leaderboard(board)
	hud.set_session("running")
	hud.set_session("ended")
	for f in 3:
		hud.update(0.1)
		await process_frame
	await _shot(out.path_join("podium.png"))
	var podium: Control = hud.get("_podium")
	if podium == null:
		print("HUD CHECK FAILED: no podium at the end of the session")
		quit(1)
		return
	var r := podium.get_global_rect()
	var screen := root.get_viewport().get_visible_rect()
	print("podium at %s on a %s screen" % [r, screen.size])
	if not screen.encloses(r):
		print("HUD CHECK FAILED: the podium doesn't fit the screen")
		quit(1)
		return
	print("HUD CHECK PASSED")
	quit(0)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path)
