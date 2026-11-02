extends CanvasLayer
## Big-screen HUD around the halves (ui/duel_hud.gd shows the racers, their lights, times and
## verdicts, the crown and the line). Every string comes from ui/i18n.gd.
##  - Leaderboard: the session's best times (on a loop, best laps), BOARD_ROWS rows: rank, the
##    racer's picture (the avatar the game rendered for the phones), name, racer title and time.
##    Top right on the full screen; on the split screen under the crown, between the halves.
##    No fallbacks: a picture that hasn't come AVATAR_WAIT_S after its row appeared turns the
##    row's picture red with "no picture" under the name, and is reported as a problem.
##  - Problems (top centre, red): errors for the facilitator. No fallbacks: shown, never hidden.
##  - Podium (centre): the session's top three when it ends, for PODIUM_S.
## main.gd feeds it (set_roster, set_leaderboard, set_session, run_result, problem, split,
## crown_bottom) and calls update() every frame.

const I18n = preload("res://ui/i18n.gd")

## Distinct racer colours, in join order (a colour comes free again when its racer leaves).
const PALETTE := [
	Color("#ff4b4b"), Color("#3b8cff"), Color("#ffd23a"), Color("#33d17a"),
	Color("#ff8a1f"), Color("#b061ff"), Color("#24d6e0"), Color("#ff5fb8"),
	Color("#a8e03a"), Color("#c08457"), Color("#e8e8f0"), Color("#7a8cff"),
]
const PROBLEM_S := 30.0
const PROBLEMS_TOP := 300.0     # the problems' top edge, under the crown
const PODIUM_S := 30.0
const FONT_NAMES := ["Arial Rounded MT Bold", "Avenir Next", "Helvetica Neue", "Arial"]
const BOARD_ROWS := 6           # rows on the big screen (the phones list the whole leaderboard)
const BOARD_W := 420.0
const BOARD_CHIP := 56          # a board row's picture, in pixels
const MARGIN := 18.0            # from the screen's edge (as ui/duel_hud.gd's plates)
const CROWN_GAP := 10.0         # between the crown and the board on the split screen
const AVATAR_WAIT_S := 10.0     # a picture may take this long to download or render
const NO_PICTURE := Color("#d62828")

## pid -> Texture2D (or null while it downloads). Server mode: RosterAssets.avatar_for.
var avatar_of := Callable()
## Mock mode has no server leaderboard: bests come from the runs finished here.
var local_bests := false
## The screen is split in two halves (main.gd): the board sits under the crown, between them.
var split := false
## The bottom edge of the crown at the top centre (main.gd, from ui/duel_hud.gd).
var crown_bottom := 0.0

var _font: SystemFont
var _t := 0.0
var _colors := {}               # pid -> Color
var _roster := {}               # pid -> RosterEntry-like {nickname, status, stage, connected}
var _ranks := {}                # pid -> {rank, bestTimeMs, nickname, racerTitle?}
var _problems: VBoxContainer
var _session := ""
var _podium: Control = null
var _board: PanelContainer
var _board_rows: VBoxContainer
var _board_dirty := false
var _rows := {}                 # pid -> {chip, sub, title} of its board row
var _no_pic_since := {}         # pid -> _t when its board row was first without a picture
var _no_pic_told := {}          # pid (or "" in mock mode) -> true once reported


func _ready() -> void:
	layer = 7  # over the halves' HUD: problems and the podium must be seen
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(FONT_NAMES)
	_font.font_weight = 700
	_build_board_panel()  # before the problems, so a problem is drawn over the board
	_problems = VBoxContainer.new()
	_problems.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_problems.offset_left = -380
	_problems.offset_right = 380
	_problems.offset_top = PROBLEMS_TOP
	_problems.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_problems)


# ---------------------------------------------------------------- data in

## The racer's colour (the podium; main.gd's racer views and the mock karts).
func color_for(pid: String) -> Color:
	if not _colors.has(pid):
		var used := {}
		for c in _colors.values():
			used[c] = true
		var pick := Color.WHITE
		var found := false
		for c in PALETTE:
			if not used.has(c):
				pick = c
				found = true
				break
		if not found:  # more racers than colours: a lighter round of the palette
			pick = PALETTE[_colors.size() % PALETTE.size()].lightened(0.35)
		_colors[pid] = pick
	return _colors[pid]


## Roster entries (server RosterEntry, or mock players): names for the podium.
func set_roster(entries: Array) -> void:
	var still := {}
	for e in entries:
		var pid := String(e["playerId"])
		still[pid] = true
		_roster[pid] = e
		color_for(pid)
	for pid in _roster.keys():
		if not still.has(pid):
			_roster.erase(pid)
			_colors.erase(pid)
			_ranks.erase(pid)
	_board_dirty = true


## Server leaderboard.updated (LeaderboardEntry[], ranked): the board and the podium.
func set_leaderboard(entries: Array) -> void:
	_ranks.clear()
	for e in entries:
		var r := {"rank": int(e["rank"]), "bestTimeMs": int(e["bestTimeMs"]), "nickname": String(e["nickname"])}
		if e.has("racerTitle"):
			r["racerTitle"] = String(e["racerTitle"])
		_ranks[String(e["playerId"])] = r
	_board_dirty = true


## Server session status (idle | running | ended). Ending shows the podium; a new session
## clears the leaderboard right after, so the podium is taken now.
func set_session(status: String) -> void:
	if status == "ended" and _session != "ended":
		_show_podium()
	_session = status


## A run finished (ok) or failed: result_ms is the finish time, or the best lap on a loop. Mock
## mode keeps its own bests for the board and the podium; the halves show the verdict
## (ui/duel_hud.gd).
func run_result(pid: String, ok: bool, result_ms: int) -> void:
	if ok and local_bests and (not _ranks.has(pid) or result_ms < int(_ranks[pid]["bestTimeMs"])):
		_ranks[pid] = {"rank": 0, "bestTimeMs": result_ms, "nickname": _nick(pid)}
		_rerank_local()
		_board_dirty = true


## An error the facilitator must see (red, top centre, for PROBLEM_S).
func problem(text: String) -> void:
	var l := _label(text, 20, Color(1, 0.92, 0.9))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(740, 0)
	var p := _panel(Color(0.55, 0.05, 0.05, 0.88), 8)
	p.add_child(l)
	p.set_meta("until", _t + PROBLEM_S)
	_problems.add_child(p)
	while _problems.get_child_count() > 4:
		_problems.get_child(0).free()


# ---------------------------------------------------------------- per frame

func update(delta: float) -> void:
	_t += delta
	_expire(_problems)
	if _podium != null and _t > float(_podium.get_meta("until")):
		_podium.queue_free()
		_podium = null
	if _board_dirty:
		_build_board_rows()
	_update_board()


# ---------------------------------------------------------------- leaderboard

func _build_board_panel() -> void:
	_board = _panel(Color(0.06, 0.07, 0.1, 0.82), 16, Color("#ffd23a"), 3)
	_board.custom_minimum_size = Vector2(BOARD_W, 0)
	_board.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(box)
	var title := _label(I18n.t("hud.board_title"), 26, Color("#ffd23a"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_board_rows = VBoxContainer.new()
	_board_rows.add_theme_constant_override("separation", 6)
	_board_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_board_rows)
	add_child(_board)


## The board's racers: the best BOARD_ROWS, by rank.
func _board_pids() -> Array:
	var pids: Array = _ranks.keys()
	pids.sort_custom(func(a, b): return int(_ranks[a]["rank"]) < int(_ranks[b]["rank"]))
	return pids.slice(0, BOARD_ROWS)


func _build_board_rows() -> void:
	_board_dirty = false
	for c in _board_rows.get_children():
		_board_rows.remove_child(c)
		c.queue_free()
	_rows.clear()
	for pid in _board_pids():
		_rows[pid] = _board_row(pid)


func _board_row(pid: String) -> Dictionary:
	var r: Dictionary = _ranks[pid]
	var place := int(r["rank"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_rows.add_child(row)
	var num := _label(str(place), 30, _place_color(place))
	num.custom_minimum_size = Vector2(34, 0)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(num)
	var chip := _avatar_chip(BOARD_CHIP)
	row.add_child(chip["root"])
	var who := VBoxContainer.new()
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", -2)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(who)
	var name := _label(String(r["nickname"]), 26, color_for(pid).lightened(0.35))
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.add_child(name)
	var title := String(r.get("racerTitle", ""))
	var sub := _label(title, 16, Color(1, 1, 1, 0.75))
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.visible = title != ""
	who.add_child(sub)
	var time := _label("%.2f s" % (int(r["bestTimeMs"]) / 1000.0), 28, Color.WHITE)
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(time)
	return {"chip": chip, "sub": sub, "title": title}


## Each row's picture (it may arrive after the row), the missing ones in red and reported, and
## where the board sits.
func _update_board() -> void:
	_board.visible = not _rows.is_empty() and _podium == null
	if not _board.visible:
		_problems.offset_top = PROBLEMS_TOP
		return
	for pid in _rows:
		var row: Dictionary = _rows[pid]
		var tex: Texture2D = avatar_of.call(pid) if avatar_of.is_valid() else null
		if tex != null:
			_no_pic_since.erase(pid)
		elif not _no_pic_since.has(pid):
			_no_pic_since[pid] = _t
		# Mock mode has no pictures at all: missing right away.
		var missing: bool = tex == null and (not avatar_of.is_valid() or _t - float(_no_pic_since[pid]) >= AVATAR_WAIT_S)
		_show_picture(row["chip"], tex, missing, color_for(pid))
		var sub: Label = row["sub"]
		sub.text = I18n.t("hud.no_picture") if missing else String(row["title"])
		sub.add_theme_color_override("font_color", NO_PICTURE.lightened(0.35) if missing else Color(1, 1, 1, 0.75))
		sub.visible = sub.text != ""
		if missing:
			_report_no_picture(pid)
	_board.reset_size()
	var vp := get_viewport().get_visible_rect().size
	if split:
		_board.position = Vector2((vp.x - _board.size.x) * 0.5, crown_bottom + CROWN_GAP)
	else:
		_board.position = Vector2(vp.x - _board.size.x - MARGIN, MARGIN)
	# The problems sit top centre: under the board when it is there too, never over it.
	_problems.offset_top = maxf(PROBLEMS_TOP, _board.position.y + _board.size.y + CROWN_GAP) if split else PROBLEMS_TOP


func _report_no_picture(pid: String) -> void:
	var key := pid if avatar_of.is_valid() else ""
	if _no_pic_told.has(key):
		return
	_no_pic_told[key] = true
	var text := I18n.f("hud.no_picture_problem", [String(_ranks[pid]["nickname"]), int(AVATAR_WAIT_S)]) \
		if avatar_of.is_valid() else I18n.t("hud.no_pictures_mock")
	push_error("RaceHud: " + text)
	problem(text)


# ---------------------------------------------------------------- podium

func _show_podium() -> void:
	if _podium != null:
		_podium.queue_free()
		_podium = null
	var top: Array = _ranks.keys().filter(func(pid): return _roster.has(pid))
	top.sort_custom(func(a, b): return int(_ranks[a]["rank"]) < int(_ranks[b]["rank"]))
	top = top.slice(0, 3)
	if top.is_empty():
		return  # nobody finished this session: nothing to celebrate
	var panel := _panel(Color(0.06, 0.07, 0.1, 0.86), 22, Color("#ffd23a"), 4)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title := _label(I18n.t("hud.podium_title"), 52, Color("#ffd23a"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var steps := HBoxContainer.new()
	steps.alignment = BoxContainer.ALIGNMENT_CENTER
	steps.add_theme_constant_override("separation", 28)
	box.add_child(steps)
	# Second, first, third: the winner in the middle on the highest step.
	for place in [2, 1, 3]:
		if place > top.size():
			continue
		var pid: String = top[place - 1]
		var col := color_for(pid)
		var step := VBoxContainer.new()
		step.alignment = BoxContainer.ALIGNMENT_END
		step.add_theme_constant_override("separation", 6)
		step.custom_minimum_size = Vector2(250, 0)
		var chip := _avatar_chip(150 if place == 1 else 110)
		# The session is over: a picture that isn't here now is missing (the board reported it).
		var tex: Texture2D = avatar_of.call(pid) if avatar_of.is_valid() else null
		_show_picture(chip, tex, tex == null, col)
		var holder := CenterContainer.new()
		holder.add_child(chip["root"])
		step.add_child(holder)
		var name := _label(_nick(pid), 36 if place == 1 else 30, col.lightened(0.3))
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		step.add_child(name)
		var block := _panel(_place_color(place).darkened(0.15), 10)
		block.custom_minimum_size = Vector2(230, [0, 140, 100, 70][place])
		var num := _label("%s   %.2f s" % [_ordinal(place), int(_ranks[pid]["bestTimeMs"]) / 1000.0], 30, Color(0.1, 0.08, 0.05))
		num.remove_theme_constant_override("outline_size")
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		block.add_child(num)
		step.add_child(block)
		steps.add_child(step)
	panel.set_meta("until", _t + PODIUM_S)
	add_child(panel)
	_podium = panel


# ---------------------------------------------------------------- helpers

func _nick(pid: String) -> String:
	return String(_roster.get(pid, {}).get("nickname", "?"))


func _rerank_local() -> void:
	var pids: Array = _ranks.keys()
	pids.sort_custom(func(a, b): return int(_ranks[a]["bestTimeMs"]) < int(_ranks[b]["bestTimeMs"]))
	for i in pids.size():
		_ranks[pids[i]]["rank"] = i + 1


func _avatar_chip(size: int) -> Dictionary:
	var root := _panel(Color.WHITE, size / 2, Color.WHITE, 3)
	root.custom_minimum_size = Vector2(size, size)
	(root.get_theme_stylebox("panel") as StyleBoxFlat).set_content_margin_all(3)  # the chip is the size
	root.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW  # the picture is round, like the chip
	var tex := TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.custom_minimum_size = Vector2(size - 6, size - 6)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tex)
	var mark := _label("", int(size * 0.55), Color.WHITE)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(mark)
	return {"root": root, "tex": tex, "mark": mark}


## The racer's picture in its chip. No picture yet: "…" while it may still come; missing: a red
## chip with "!" (never a stand-in picture or the racer's initial).
func _show_picture(chip: Dictionary, tex: Texture2D, missing: bool, col: Color) -> void:
	chip["tex"].texture = tex
	chip["mark"].text = "" if tex != null else ("!" if missing else "…")
	var sb: StyleBoxFlat = chip["root"].get_theme_stylebox("panel")
	if tex != null:
		sb.bg_color = Color(0.95, 0.95, 0.98)
		sb.border_color = col
	elif missing:
		sb.bg_color = NO_PICTURE
		sb.border_color = NO_PICTURE.lightened(0.5)
	else:
		sb.bg_color = Color(0.25, 0.27, 0.32)
		sb.border_color = col


func _panel(bg: Color, radius: int, border := Color.TRANSPARENT, border_w := 0) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(6 if radius < 10 else 10)
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08))
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _ordinal(n: int) -> String:
	return I18n.t("hud.place_%d" % n) if n <= 3 else I18n.f("hud.place_n", [n])


func _place_color(place: int) -> Color:
	match place:
		1: return Color("#ffd23a")
		2: return Color("#d9e2ec")
		3: return Color("#e0a060")
	return Color.WHITE


func _expire(box: Container) -> void:
	for c in box.get_children():
		if _t > float(c.get_meta("until", INF)):
			c.queue_free()
