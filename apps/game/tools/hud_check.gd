extends SceneTree
## Renders the race HUD from test data (20 racers, the top 14 with a time) and saves screenshots,
## so a look at it doesn't need a whole session: the leaderboard on the full screen (top right)
## and on the split screen (under the crown), a racer whose picture never comes (red, reported),
## and the podium at the end of the session. The halves' HUD has its own frames in
## tools/duel_check.gd. Must run windowed (the dummy renderer saves blank images):
##   godot --path apps/game --resolution 1920x1080 --script res://tools/hud_check.gd -- --out=DIR [--language=de]
## Exits 1 if the board or the podium is missing, doesn't fit the screen, covers the crown or is
## covered by a problem, shows a picture that isn't the racer's, or a missing picture isn't shown
## and reported.

const RaceHud = preload("res://ui/race_hud.gd")
const DuelHud = preload("res://ui/duel_hud.gd")
const I18n = preload("res://ui/i18n.gd")
const NAMES := ["Mia", "Noah", "Lina", "Ben", "Ella", "Finn", "Zoe", "Leo", "Ava", "Max",
	"Nora", "Tim", "Ida", "Kai", "Yara", "Oli", "Rosa", "Sam", "Lou", "Jan"]
const TITLES := ["Sofa Racer", "Rocket Cow", "Cheese Wheel Express", "", "Thunder Duck"]
const NO_PICTURE_PID := "p4"   # Ella, 5th: her picture never comes

var _fails: PackedStringArray = []


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
	var duel := DuelHud.new()
	root.add_child(duel)
	var hud := RaceHud.new()
	var pictures := {}
	for i in NAMES.size():
		var pid := "p%d" % i
		if pid != NO_PICTURE_PID:
			pictures[pid] = _picture(i)
	hud.avatar_of = func(pid: String) -> Texture2D: return pictures.get(pid)
	root.add_child(hud)
	await process_frame  # _ready builds the panels
	duel.set_queue({"champion": {"playerId": "p0", "nickname": NAMES[0], "timeMs": 29800, "tries": 3},
		"line": [{"nickname": NAMES[1]}, {"nickname": NAMES[2]}]})
	var roster: Array = []
	var board: Array = []
	for i in NAMES.size():
		roster.append({"playerId": "p%d" % i, "nickname": NAMES[i], "status": "ready", "connected": true})
		if i < 14:
			var e := {"playerId": "p%d" % i, "nickname": NAMES[i], "rank": i + 1, "bestTimeMs": 29800 + i * 730}
			if i < TITLES.size() and TITLES[i] != "":
				e["racerTitle"] = TITLES[i]
			board.append(e)
	hud.set_roster(roster)
	hud.set_leaderboard(board)
	hud.set_session("running")
	var screen := root.get_viewport().get_visible_rect()

	# The full screen: the board top right, Ella's picture still on its way.
	await _frames(hud, duel, false, 0.1)
	await _shot(out.path_join("board_full.png"))
	_check_board(hud, duel, false, screen, pictures, false)
	var b: Control = hud.get("_board")
	if b.get_global_rect().end.x < screen.end.x - 40.0:
		_fail("the full screen's board isn't at the right edge: %s" % b.get_global_rect())

	# Ella's picture never comes: red, "no picture", reported.
	hud.update(RaceHud.AVATAR_WAIT_S)
	await _frames(hud, duel, false, 0.1)
	_check_board(hud, duel, false, screen, pictures, true)
	var problems: VBoxContainer = hud.get("_problems")
	if problems.get_child_count() != 1:
		_fail("a missing picture is reported once as a problem, got %d problems" % problems.get_child_count())

	# The split screen: the board under the crown, between the halves.
	await _frames(hud, duel, true, 0.1)
	await _shot(out.path_join("board_split.png"))
	_check_board(hud, duel, true, screen, pictures, true)
	if absf(b.get_global_rect().get_center().x - screen.get_center().x) > 1.0:
		_fail("the split screen's board isn't centred: %s" % b.get_global_rect())
	if problems.get_global_rect().intersects(b.get_global_rect()):
		_fail("the problem covers the split screen's board: %s" % problems.get_global_rect())

	# The podium, the board out of its way.
	hud.set_session("ended")
	await _frames(hud, duel, true, 0.1)
	await _shot(out.path_join("podium.png"))
	var podium: Control = hud.get("_podium")
	if podium == null:
		_fail("no podium at the end of the session")
	else:
		var r := podium.get_global_rect()
		print("podium at %s on a %s screen" % [r, screen.size])
		if not screen.encloses(r):
			_fail("the podium doesn't fit the screen")
	if b.visible:
		_fail("the board shows over the podium")
	if not _fails.is_empty():
		for f in _fails:
			print("HUD CHECK FAILED: ", f)
		quit(1)
		return
	print("HUD CHECK PASSED")
	quit(0)


## A few frames of both HUDs, as main.gd drives them: the crown first, then the board under it.
func _frames(hud: RaceHud, duel: DuelHud, split: bool, dt: float) -> void:
	var vp := root.get_viewport().get_visible_rect().size
	var rects := {"left": Rect2(Vector2.ZERO, vp)}
	if split:
		rects = {"left": Rect2(0, 0, vp.x * 0.5, vp.y), "right": Rect2(vp.x * 0.5, 0, vp.x * 0.5, vp.y)}
	for f in 3:
		duel.update(dt, null, rects, {}, func(pid: String) -> String: return pid)
		hud.split = split
		hud.crown_bottom = duel.crown_bottom()
		hud.update(dt)
		await process_frame


func _check_board(hud: RaceHud, duel: DuelHud, split: bool, screen: Rect2, pictures: Dictionary, late: bool) -> void:
	var tag := "split" if split else "full"
	var b: Control = hud.get("_board")
	if not b.visible:
		_fail("%s: the board is hidden" % tag)
		return
	var r := b.get_global_rect()
	print("%s: board at %s on a %s screen" % [tag, r, screen.size])
	if not screen.encloses(r):
		_fail("%s: the board doesn't fit the screen" % tag)
	var crown: Control = duel.get("_crown")
	if crown.get_global_rect().intersects(r):
		_fail("%s: the board covers the crown (%s)" % [tag, crown.get_global_rect()])
	var rows: Dictionary = hud.get("_rows")
	if rows.size() != RaceHud.BOARD_ROWS:
		_fail("%s: %d rows on the board, expected %d" % [tag, rows.size(), RaceHud.BOARD_ROWS])
	for pid in rows:
		var chip: Dictionary = rows[pid]["chip"]
		var tex: Texture2D = chip["tex"].texture
		var mark := String(chip["mark"].text)
		var sub := String(rows[pid]["sub"].text)
		if pictures.has(pid):
			if tex != pictures[pid]:
				_fail("%s: %s's row doesn't show their picture" % [tag, pid])
			if mark != "":
				_fail("%s: %s's picture has a mark over it: %s" % [tag, pid, mark])
		elif late:
			if tex != null or mark != "!" or sub != I18n.t("hud.no_picture"):
				_fail("%s: %s's missing picture isn't shown as missing (mark %s, line %s)" % [tag, pid, mark, sub])
		elif tex != null or mark != "…":
			_fail("%s: %s's picture on its way isn't shown as on its way (mark %s)" % [tag, pid, mark])


## A test picture in place of a racer's rendered avatar: two colours and a face-ish square.
func _picture(i: int) -> Texture2D:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var c := Color.from_hsv(float(i) / NAMES.size(), 0.6, 0.95)
	img.fill(c)
	img.fill_rect(Rect2i(0, 80, 128, 48), c.darkened(0.4))
	img.fill_rect(Rect2i(44, 28, 40, 40), Color(1, 0.88, 0.75))
	return ImageTexture.create_from_image(img)


func _fail(text: String) -> void:
	_fails.append(text)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path)
