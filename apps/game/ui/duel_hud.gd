extends CanvasLayer
## Duel mode's HUD (contracts §2i), over world/duel_screen.gd's halves (or the full screen):
##  - Each racing half, top: the racer's name on its side's colour (left red, right blue), the
##    lap time, the record to beat, boosts left, and PUSH! while Push is held (SLIDE! after a
##    slide with Push, contracts §2g).
##  - Each half's own start lights (a duel run never shares a countdown), then GO!.
##  - A finished lap's verdict in its half for duelResultMs: NEW CHAMPION!, or how far short of
##    whose record; a failed lap says oops and why.
##  - An idle half: who is next, or "Press Go on your phone".
##  - Top centre: the crown (champion, time, tries) and the line.
## Every string comes from ui/i18n.gd. main.gd feeds it: set_queue (queue.updated), result (a
## lap ended), update (per frame, with the sim and which run races in which half).

const I18n = preload("res://ui/i18n.gd")

const SIDE_COLOR := {"left": Color("#ff4b4b"), "right": Color("#3b8cff")}
const FONT_NAMES := ["Arial Rounded MT Bold", "Avenir Next", "Helvetica Neue", "Arial"]
const GO_S := 1.2
const LINE_NAMES := 4        # names shown in the line at the top

var result_s := 5.0          # how long a verdict stays (config.duelResultMs)
var _font: SystemFont
var _queue := {}
var _halves := {}            # side -> {root, plate, name, time, record, boosts, push, lights, verdict, verdict_big, verdict_small, idle}
var _crown: PanelContainer
var _crown_label: Label
var _line_label: Label
var _verdict_until := {}     # side -> seconds left showing the verdict
var _go_until := {}          # side -> seconds left showing GO!
var _was_grid := {}          # side -> the run on the grid last frame
var _sides_by_run := {}      # runId -> the side the server gave it (its colour on a full screen)


func _ready() -> void:
	layer = 6
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(FONT_NAMES)
	_font.font_weight = 700
	for side in ["left", "right"]:
		_halves[side] = _build_half(side)
	_crown = _panel(Color(0.08, 0.08, 0.12, 0.82), 14, Color("#ffd23a"), 3)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_crown.add_child(box)
	_crown_label = _label("", 30, Color("#ffd23a"))
	_crown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_crown_label)
	_line_label = _label("", 20, Color.WHITE)
	_line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_line_label)
	add_child(_crown)
	_set_crown()


func _build_half(side: String) -> Dictionary:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var col: Color = SIDE_COLOR[side]
	var plate := _panel(col.darkened(0.3), 12, col.lightened(0.3), 3)
	plate.position = Vector2(18, 18)
	root.add_child(plate)
	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", 0)
	plate.add_child(pbox)
	var name_l := _label("", 30, Color.WHITE)
	pbox.add_child(name_l)
	var time_l := _label("", 54, Color.WHITE)
	pbox.add_child(time_l)
	var record_l := _label("", 20, Color(1, 1, 1, 0.85))
	pbox.add_child(record_l)
	var boosts_l := _label("", 20, Color("#ffd23a"))
	pbox.add_child(boosts_l)
	var push := _panel(Color("#ff6b35"), 12, Color.WHITE, 3)
	var push_l := _label("", 34, Color.WHITE)
	push.add_child(push_l)
	root.add_child(push)
	var lights := _label("", 150, Color("#ff4b4b"))
	lights.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(lights)
	var verdict := _panel(Color(0.08, 0.08, 0.12, 0.88), 18, col, 4)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	verdict.add_child(vbox)
	var big := _label("", 64, Color.WHITE)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(big)
	var small := _label("", 30, Color.WHITE)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(small)
	root.add_child(verdict)
	var idle := _label("", 44, Color.WHITE)
	idle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	idle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(idle)
	return {"root": root, "plate": plate, "name": name_l, "time": time_l, "record": record_l,
		"boosts": boosts_l, "push": push, "push_label": push_l, "lights": lights, "verdict": verdict,
		"verdict_big": big, "verdict_small": small, "idle": idle}


## queue.updated: the line, who races in which half, the champion.
func set_queue(q: Dictionary) -> void:
	_queue = q
	if _crown_label != null:  # before _ready, the crown is set up from _queue there
		_set_crown()


func _set_crown() -> void:
	var c: Dictionary = _queue.get("champion", {})
	if c.is_empty():
		_crown_label.text = I18n.t("duel.no_crown")
	else:
		var tries := int(c.get("tries", 0))
		_crown_label.text = "%s   ·   %s" % [I18n.f("duel.crown", [c["nickname"], int(c["timeMs"]) / 1000.0]),
			I18n.t("duel.tries_1") if tries == 1 else I18n.f("duel.tries", [tries])]
	var names: Array = (_queue.get("line", []) as Array).map(func(e): return String(e["nickname"]))
	if names.size() > LINE_NAMES:
		names = names.slice(0, LINE_NAMES) + ["+%d" % (names.size() - LINE_NAMES)]
	_line_label.text = I18n.f("duel.next", [", ".join(names)]) if not names.is_empty() else I18n.t("duel.press_go")


## A lap ended in `side`: its verdict shows there for result_s. big: the headline; small: the
## line under it; good: a new crown (gold) rather than short of it.
func result(side: String, big: String, small: String, good: bool) -> void:
	var h: Dictionary = _halves[side]
	h["verdict_big"].text = big
	h["verdict_big"].add_theme_color_override("font_color", Color("#ffd23a") if good else Color.WHITE)
	h["verdict_small"].text = small
	h["verdict_small"].visible = small != ""
	_verdict_until[side] = result_s


## Per frame. rects: side -> Rect2 of its half (only "left" when the screen isn't split: the
## whole screen). runs: side -> the Racer in that half (racing or on the grid), or null.
## nick_of: Callable(player_id) -> nickname.
func update(delta: float, sim, rects: Dictionary, runs: Dictionary, nick_of: Callable) -> void:
	var full := not rects.has("right")
	for side in _halves:
		var h: Dictionary = _halves[side]
		var root: Control = h["root"]
		# Full screen: the one racer is drawn in the left slot whatever its side.
		var shown: bool = rects.has(side)
		root.visible = shown
		if not shown:
			continue
		var rect: Rect2 = rects[side]
		root.position = rect.position
		root.size = rect.size
		var r = runs.get(side, null)
		_verdict_until[side] = maxf(0.0, float(_verdict_until.get(side, 0.0)) - delta)
		_go_until[side] = maxf(0.0, float(_go_until.get(side, 0.0)) - delta)
		var verdict: bool = _verdict_until[side] > 0.0
		_place_center(h["verdict"], rect.size, 0.42)
		h["verdict"].visible = verdict
		var on_grid: bool = r != null and sim.on_grid(r.run_id) or (r != null and r.state == "queued")
		if not on_grid and _was_grid.get(side, "") != "" and r != null and r.state == "racing":
			_go_until[side] = GO_S
		_was_grid[side] = r.run_id if r != null and on_grid else ""
		# The plate: name in the side's colour, lap time, record, boosts.
		h["plate"].visible = r != null
		h["idle"].visible = r == null and not verdict
		h["push"].visible = false
		h["lights"].visible = false
		if r == null:
			var next: Array = _queue.get("line", [])
			h["idle"].text = I18n.f("duel.next", [next[0]["nickname"]]) if not next.is_empty() else I18n.t("duel.press_go")
			h["idle"].size = Vector2(rect.size.x * 0.8, 0)
			_place_center(h["idle"], rect.size, 0.5)
			continue
		var col: Color = SIDE_COLOR[side if not full else String(_side_of(r.run_id, side))]
		var plate: PanelContainer = h["plate"]
		(plate.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = col.darkened(0.3)
		h["name"].text = nick_of.call(r.player_id)
		var ms: int = r.lap_ms() if r.looping else r.elapsed_ms()
		h["time"].text = "%.2f" % (ms / 1000.0) if r.state == "racing" else "0.00"
		var c: Dictionary = _queue.get("champion", {})
		h["record"].text = I18n.f("duel.record", [int(c["timeMs"]) / 1000.0]) + "  ·  " + String(c["nickname"]) if not c.is_empty() else I18n.t("duel.no_crown")
		h["boosts"].text = I18n.f("duel.boosts", [r.boosts_left])
		# PUSH! while held; SLIDE! while fishtailing after a slide with Push.
		var sliding: bool = r.push_recover_t > 0.0
		if r.pushing or sliding:
			h["push"].visible = true
			h["push_label"].text = I18n.t("duel.slide") if sliding else I18n.t("duel.push")
			(h["push"].get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color("#d64545") if sliding else Color("#ff6b35")
			h["push"].position = Vector2(rect.size.x - h["push"].size.x - 24, 24)
		# The half's own start lights, then GO!.
		var lights: Label = h["lights"]
		if on_grid:
			var go := int(sim.go_tick.get(r.run_id, -1))
			if go > sim.tick:
				var left := float(go - sim.tick) / 60.0
				lights.visible = true
				lights.text = str(ceili(left))
				lights.add_theme_color_override("font_color", Color("#ff4b4b") if left > 1.0 else Color("#ffd23a"))
		elif _go_until[side] > 0.0:
			lights.visible = true
			lights.text = I18n.t("hud.go")
			lights.add_theme_color_override("font_color", Color("#33d17a"))
		if lights.visible:
			_place_center(lights, rect.size, 0.3)
	# The crown and the line, top centre over the divider (or the middle of the full screen).
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	_crown.reset_size()
	_crown.position = Vector2((vp_size.x - _crown.size.x) * 0.5, 14)


## Full screen: the side the server gave the run decides its colour.
func set_side(run_id: String, side: String) -> void:
	_sides_by_run[run_id] = side


func _side_of(run_id: String, fallback: String) -> String:
	return _sides_by_run.get(run_id, fallback)


func _place_center(c: Control, area: Vector2, y_frac: float) -> void:
	c.reset_size()
	c.position = Vector2((area.x - c.size.x) * 0.5, area.y * y_frac - c.size.y * 0.5)


func _panel(bg: Color, radius: int, border := Color.TRANSPARENT, border_w := 0) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
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
