extends CanvasLayer
## The halves' HUD (contracts §2i), over world/duel_screen.gd's halves (or the full screen):
##  - Each racing half, in its outer top corner (left half top left, right half top right, so the
##    crown fits between them): a live face cam of the racer (face and hands, ui/face_cam.gd, on
##    the outer edge) beside its name on its side's colour (left red, right blue), the lap time,
##    their own best lap, the record to beat (once there is one), under it the chocolate coins
##    taken on this lap (sim/coins.gd, a gold coin and "12/35"; it bounces as one is taken),
##    BOOST! while a boost arrow or a whole line of coins the kid steered onto surges the kart
##    (contracts §2g), and a warning while a village surprise is on the road ahead ("Cow on the
##    road!", sim/obstacles.gd).
##  - Each half's own start lights (a duel run never shares a countdown), then GO!.
##  - A finished lap's verdict in its half for duelResultMs: NEW CHAMPION!, or how far short of
##    whose record; a failed lap says oops and why.
##  - An idle half: who is next (nothing when nobody waits: the crown says to press Go).
##  - Top centre: the crown (champion, time, tries) and the line.
## Every string comes from ui/i18n.gd. main.gd feeds it: set_queue (queue.updated), result (a
## lap ended), update (per frame, with the sim and which run races in which half).

const I18n = preload("res://ui/i18n.gd")
const FaceCam = preload("res://ui/face_cam.gd")
const DuelScreen = preload("res://world/duel_screen.gd")

const SIDE_COLOR := {"left": Color("#ff4b4b"), "right": Color("#3b8cff")}
const FONT_NAMES := ["Arial Rounded MT Bold", "Avenir Next", "Helvetica Neue", "Arial"]
const GO_S := 1.2
const LINE_NAMES := 4        # names shown in the line at the top
const MARGIN := 18.0
const PLATE_W := 300.0       # the plate's least width, so a right-aligned plate doesn't jiggle
const FACE_PX := 200.0       # the racer's face cam on its plate
const FACE_MAX_PX := 360     # the face cam's render size cap in pixels (big screens upscale it)
const WARN_M := 80.0         # a surprise this far ahead on the racer's road shows its warning

var result_s := 5.0          # how long a verdict stays (config.duelResultMs)
var bests := {}              # playerId -> best lap in ms this session (main.gd keeps it)
var _font: SystemFont
var _queue := {}
var _halves := {}            # side -> {root, plate, face, cam, name, time, record, coins, coins_label, boost, warn, warn_label, lights, verdict, verdict_big, verdict_small, verdict_coins, idle}
var _coins_was := {}         # side -> coins taken last frame (the counter bounces on a new one)
var _coin_pop := {}          # side -> seconds left of its bounce
var _coins_said := {}        # side -> coins_result came for the verdict about to show
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
	plate.position = Vector2(MARGIN, MARGIN)
	plate.custom_minimum_size = Vector2(PLATE_W, 0)
	root.add_child(plate)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	plate.add_child(row)
	var cam := FaceCam.new()
	cam.phase = 0 if side == "left" else 1  # the two cams draw on alternate frames
	add_child(cam)
	var face := Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color.BLACK  # opaque: the clip multiplies the picture by this alpha
	fsb.set_corner_radius_all(14)
	face.add_theme_stylebox_override("panel", fsb)
	face.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	face.custom_minimum_size = Vector2(FACE_PX, FACE_PX)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.visible = false
	var pic := TextureRect.new()
	pic.texture = cam.get_texture()
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(pic)
	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", 0)
	pbox.alignment = BoxContainer.ALIGNMENT_CENTER
	pbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The face on the plate's outer edge: left of the text in the left half, right of it in the right.
	if side == "right":
		row.add_child(pbox)
		row.add_child(face)
	else:
		row.add_child(face)
		row.add_child(pbox)
	var name_l := _label("", 30, Color.WHITE)
	pbox.add_child(name_l)
	var time_l := _label("", 54, Color.WHITE)
	pbox.add_child(time_l)
	var best_l := _label("", 22, Color.WHITE)
	pbox.add_child(best_l)
	var record_l := _label("", 20, Color(1, 1, 1, 0.85))
	pbox.add_child(record_l)
	if side == "right":  # its plate sits in the right corner: the text hugs the outer edge
		for l in pbox.get_children():
			(l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var coins := _panel(Color(0.08, 0.08, 0.12, 0.82), 12, Color("#ffd23a"), 3)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 10)
	coins.add_child(crow)
	var coin := Panel.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color("#ffc61a")
	csb.border_color = Color("#b8860b")
	csb.set_border_width_all(3)
	csb.set_corner_radius_all(16)
	coin.add_theme_stylebox_override("panel", csb)
	coin.custom_minimum_size = Vector2(32, 32)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crow.add_child(coin)
	var coins_l := _label("", 30, Color("#ffd23a"))
	crow.add_child(coins_l)
	root.add_child(coins)
	var boost := _panel(Color("#ff6b35"), 12, Color.WHITE, 3)
	boost.add_child(_label(I18n.t("duel.boost"), 34, Color.WHITE))
	root.add_child(boost)
	var warn := _panel(Color("#ffc61a"), 12, Color(0.12, 0.08, 0.2), 3)
	var warn_l := _label("", 30, Color(0.12, 0.08, 0.2))
	warn_l.add_theme_constant_override("outline_size", 0)
	warn.add_child(warn_l)
	root.add_child(warn)
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
	var coins_won := _label("", 28, Color("#ffd23a"))
	coins_won.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins_won.visible = false
	vbox.add_child(coins_won)
	root.add_child(verdict)
	var idle := _label("", 44, Color.WHITE)
	idle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	idle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(idle)
	return {"root": root, "plate": plate, "face": face, "cam": cam, "name": name_l, "time": time_l, "best": best_l, "record": record_l,
		"coins": coins, "coins_label": coins_l, "boost": boost, "warn": warn, "warn_label": warn_l, "lights": lights,
		"verdict": verdict, "verdict_big": big, "verdict_small": small, "verdict_coins": coins_won, "idle": idle}


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
	if _coins_said.get(side, false):
		_coins_said[side] = false  # said for this verdict: the next one starts without
	else:
		h["verdict_coins"].visible = false
	h["verdict_big"].text = big
	h["verdict_big"].add_theme_color_override("font_color", Color("#ffd23a") if good else Color.WHITE)
	h["verdict_small"].text = small
	h["verdict_small"].visible = small != ""
	_verdict_until[side] = result_s


## The chocolate coins a lap took, under its verdict (call before result()).
func coins_result(side: String, text: String) -> void:
	var h: Dictionary = _halves[side]
	h["verdict_coins"].text = text
	h["verdict_coins"].visible = true
	_coins_said[side] = true


## The village's camera blockers, once built (houses the face cams keep out of).
func set_blockers(b) -> void:
	for side in _halves:
		_halves[side]["cam"].blockers = b


## Per frame. rects: side -> Rect2 of its half (only "left" when the screen isn't split: the
## whole screen). runs: side -> the Racer in that half (racing or on the grid), or null.
## nick_of: Callable(player_id) -> nickname. views: side -> the racer view in that half (main.gd's
## on_side), for its face cam.
func update(delta: float, sim, rects: Dictionary, runs: Dictionary, nick_of: Callable, views := {}) -> void:
	var full := not rects.has("right")
	for side in _halves:
		var h: Dictionary = _halves[side]
		var root: Control = h["root"]
		# Full screen: the one racer is drawn in the left slot whatever its side.
		var shown: bool = rects.has(side)
		root.visible = shown
		if not shown:
			h["face"].visible = false
			h["cam"].follow(null)
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
		# The plate: name in the side's colour, lap time, record.
		h["plate"].visible = r != null
		h["idle"].visible = r == null and not verdict
		h["boost"].visible = false
		h["warn"].visible = false
		h["coins"].visible = false
		h["lights"].visible = false
		if r == null:
			# Who is next; with nobody waiting the crown at the top already says to press Go.
			var next: Array = _queue.get("line", [])
			h["idle"].visible = h["idle"].visible and not next.is_empty()
			if not next.is_empty():
				h["idle"].text = I18n.f("duel.next", [next[0]["nickname"]])
				# A wrapping label shrinks to one letter wide on reset_size(): give it its width.
				h["idle"].custom_minimum_size = Vector2(rect.size.x * 0.8, 0)
				_place_center(h["idle"], rect.size, 0.5)
			h["face"].visible = false
			h["cam"].follow(null)
			continue
		var col: Color = SIDE_COLOR[side if not full else String(_side_of(r.run_id, side))]
		var plate: PanelContainer = h["plate"]
		(plate.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = col.darkened(0.3)
		h["name"].text = nick_of.call(r.player_id)
		h["cam"].set_hide_layers(0 if full else DuelScreen.SIDE_LAYER["right" if side == "left" else "left"])
		var px := int(minf(FACE_PX * float(get_viewport().get_window().size.y) / get_viewport().get_visible_rect().size.y, FACE_MAX_PX))
		if h["cam"].size != Vector2i(px, px):
			h["cam"].size = Vector2i(px, px)
		h["face"].visible = h["cam"].follow(views.get(side, null))
		var ms: int = r.lap_ms() if r.looping else r.elapsed_ms()
		h["time"].text = "%.2f" % (ms / 1000.0) if r.state == "racing" else "0.00"
		var best := int(bests.get(r.player_id, 0))
		h["best"].text = I18n.f("duel.best", [best / 1000.0]) if best > 0 else I18n.t("duel.first_lap")
		var c: Dictionary = _queue.get("champion", {})
		h["record"].visible = not c.is_empty()  # no record yet: the crown at the top says so
		if not c.is_empty():
			h["record"].text = I18n.f("duel.record", [int(c["timeMs"]) / 1000.0]) + "  ·  " + String(c["nickname"])
		plate.reset_size()
		plate.position = Vector2(MARGIN if side == "left" else rect.size.x - plate.size.x - MARGIN, MARGIN)
		var below := plate.position.y + plate.size.y + 10.0
		# The chocolate coins taken on this lap; a new one bounces the counter.
		if r.state == "racing" and not r.coins.is_empty():
			var coins: PanelContainer = h["coins"]
			h["coins_label"].text = "%d/%d" % [r.coins_taken, r.coins.size()]
			if r.coins_taken > int(_coins_was.get(side, 0)):
				_coin_pop[side] = 0.25
			_coins_was[side] = r.coins_taken
			_coin_pop[side] = maxf(0.0, float(_coin_pop.get(side, 0.0)) - delta)
			coins.visible = true
			coins.reset_size()
			coins.pivot_offset = coins.size * 0.5
			coins.scale = Vector2.ONE * (1.0 + 0.6 * float(_coin_pop[side]))
			coins.position = Vector2(MARGIN if side == "left" else rect.size.x - coins.size.x - MARGIN, below)
			below += coins.size.y + 10.0
		# BOOST! while a boost arrow or a whole line of coins surges the kart.
		if r.boost_t > 0.0:
			var boost: PanelContainer = h["boost"]
			boost.visible = true
			boost.reset_size()
			boost.position = Vector2(MARGIN if side == "left" else rect.size.x - boost.size.x - MARGIN, below)
			below += boost.size.y + 10.0
		# A cow, sheep, cheese wheel or hay bale on the road ahead (sim/obstacles.gd).
		var ahead: String = sim.obstacles.kind_ahead(r, WARN_M) if sim.obstacles != null and r.state == "racing" else ""
		if ahead != "":
			var warn: PanelContainer = h["warn"]
			h["warn_label"].text = I18n.t("duel.ahead." + ahead)
			warn.visible = true
			warn.reset_size()
			# A gentle pulse so it catches the eye.
			warn.pivot_offset = warn.size * 0.5
			warn.scale = Vector2.ONE * (1.0 + 0.05 * sin(Time.get_ticks_msec() * 0.012))
			warn.position = Vector2(MARGIN if side == "left" else rect.size.x - warn.size.x - MARGIN, below)
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
			h["verdict"].visible = false  # the next racer's lights win over the last lap's verdict
	# The crown and the line, top centre over the divider (or the middle of the full screen).
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	_crown.reset_size()
	_crown.position = Vector2((vp_size.x - _crown.size.x) * 0.5, 14)


## The crown's bottom edge, as update() placed it (ui/race_hud.gd puts the board under it).
func crown_bottom() -> float:
	return _crown.position.y + _crown.size.y


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
