extends CanvasLayer
## Big-screen HUD around the halves (ui/duel_hud.gd shows the racers, their lights, times and
## verdicts, the crown and the line). Every string comes from ui/i18n.gd.
##  - Problems (top centre, red): errors for the facilitator. No fallbacks: shown, never hidden.
##  - Podium (centre): the session's top three when it ends, for PODIUM_S.
## main.gd feeds it (set_roster, set_leaderboard, set_session, run_result, problem) and calls
## update() every frame.

const I18n = preload("res://ui/i18n.gd")

## Distinct racer colours, in join order (a colour comes free again when its racer leaves).
const PALETTE := [
	Color("#ff4b4b"), Color("#3b8cff"), Color("#ffd23a"), Color("#33d17a"),
	Color("#ff8a1f"), Color("#b061ff"), Color("#24d6e0"), Color("#ff5fb8"),
	Color("#a8e03a"), Color("#c08457"), Color("#e8e8f0"), Color("#7a8cff"),
]
const PROBLEM_S := 30.0
const PODIUM_S := 30.0
const FONT_NAMES := ["Arial Rounded MT Bold", "Avenir Next", "Helvetica Neue", "Arial"]

## pid -> Texture2D (or null while it downloads). Server mode: RosterAssets.avatar_for.
var avatar_of := Callable()
## Mock mode has no server leaderboard: bests come from the runs finished here.
var local_bests := false

var _font: SystemFont
var _t := 0.0
var _colors := {}               # pid -> Color
var _roster := {}               # pid -> RosterEntry-like {nickname, status, stage, connected}
var _ranks := {}                # pid -> {rank, bestTimeMs}
var _problems: VBoxContainer
var _session := ""
var _podium: Control = null


func _ready() -> void:
	layer = 7  # over the halves' HUD: problems and the podium must be seen
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(FONT_NAMES)
	_font.font_weight = 700
	_problems = VBoxContainer.new()
	_problems.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_problems.offset_left = -380
	_problems.offset_right = 380
	_problems.offset_top = 300
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


## Server leaderboard.updated: rank and best time per racer.
func set_leaderboard(entries: Array) -> void:
	_ranks.clear()
	for e in entries:
		_ranks[String(e["playerId"])] = {"rank": int(e["rank"]), "bestTimeMs": int(e["bestTimeMs"])}


## Server session status (idle | running | ended). Ending shows the podium; a new session
## clears the leaderboard right after, so the podium is taken now.
func set_session(status: String) -> void:
	if status == "ended" and _session != "ended":
		_show_podium()
	_session = status


## A run finished (ok) or failed: result_ms is the finish time, or the best lap on a loop. Mock
## mode keeps its own bests for the podium; the halves show the verdict (ui/duel_hud.gd).
func run_result(pid: String, ok: bool, result_ms: int) -> void:
	if ok and local_bests and (not _ranks.has(pid) or result_ms < int(_ranks[pid]["bestTimeMs"])):
		_ranks[pid] = {"rank": 0, "bestTimeMs": result_ms}
		_rerank_local()


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
		_fill_chip(chip, pid, col)
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
	var tex := TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.custom_minimum_size = Vector2(size - 6, size - 6)
	root.add_child(tex)
	var initial := _label("", int(size * 0.55), Color.WHITE)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(initial)
	return {"root": root, "tex": tex, "initial": initial}


func _fill_chip(chip: Dictionary, pid: String, col: Color) -> void:
	var tex: Texture2D = avatar_of.call(pid) if avatar_of.is_valid() else null
	chip["tex"].texture = tex
	chip["initial"].text = "" if tex != null else _nick(pid).left(1).to_upper()
	var sb: StyleBoxFlat = chip["root"].get_theme_stylebox("panel")
	sb.bg_color = col.darkened(0.2) if tex == null else Color(0.95, 0.95, 0.98)
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
