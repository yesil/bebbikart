extends CanvasLayer
## Big-screen HUD for a group race (built for 4 to 8 racers, works up to 20): who is who, who is
## ahead, and how everyone did. Every string comes from ui/i18n.gd.
##  - Tags: a place badge and the name over every kart, in the racer's colour, pushed apart so
##    they never overlap (side by side on the grid, bunched up in a bend).
##  - Race board (right): place, avatar, name, lap or section, time. Finishers stay with their
##    time while the rest of the field comes home, so the group sees its own results.
##  - Paddock (left): everyone in the session, by rank: avatar, best time, or what the designer
##    is doing while their racer is made.
##  - Banners (top centre): each finish and each oops as it happens.
##  - Problems (top centre, red): errors for the facilitator. No fallbacks: shown, never hidden.
##  - Podium (centre): the session's top three when it ends, for PODIUM_S.
##  - Countdown (upper middle): the race start lights (contracts §2c) with everyone on the grid.
## The bottom of the screen belongs to the camera director (on-camera name tag bottom left,
## picture-in-picture bottom right, the name pop after a cut at 56 % down).
## main.gd feeds it (set_roster, set_leaderboard, run_result, run_gone, problem) and calls
## update() every frame with the sim and the racer views.

const I18n = preload("res://ui/i18n.gd")

## Distinct racer colours, in join order (a colour comes free again when its racer leaves).
const PALETTE := [
	Color("#ff4b4b"), Color("#3b8cff"), Color("#ffd23a"), Color("#33d17a"),
	Color("#ff8a1f"), Color("#b061ff"), Color("#24d6e0"), Color("#ff5fb8"),
	Color("#a8e03a"), Color("#c08457"), Color("#e8e8f0"), Color("#7a8cff"),
]
const BOARD_ROWS := 10
const BOARD_FULL_ROWS := 8      # more racers on the board: compact rows
const BOARD_W := 480
const PADDOCK_W := 330
const PADDOCK_FULL_ROWS := 10    # more racers than this: compact one-line rows
const PADDOCK_MAX_ROWS := 20
const RESULT_HOLD_S := 25.0     # a finisher stays on the board this long at most
const EMPTY_HOLD_S := 10.0      # ...or this long after the last racer left the track
const BANNER_S := 3.5
const PROBLEM_S := 30.0
const PODIUM_S := 30.0
const TAG_NEAR := 14.0          # metres: tags shrink beyond this distance
const FONT_NAMES := ["Arial Rounded MT Bold", "Avenir Next", "Helvetica Neue", "Arial"]

var camera: Camera3D
## pid -> Texture2D (or null while it downloads). Server mode: RosterAssets.avatar_for.
var avatar_of := Callable()
## Mock mode has no server leaderboard: bests come from the runs finished here.
var local_bests := false

var _font: SystemFont
var _t := 0.0
var _colors := {}               # pid -> Color
var _roster := {}               # pid -> RosterEntry-like {nickname, status, stage, connected}
var _join_order: Array = []     # pids, oldest first
var _ranks := {}                # pid -> {rank, bestTimeMs}
var _heat := {}                 # runId -> {pid, state, result_ms, reason, done_t}
var _empty_since := -1.0
var _tags := {}                 # runId -> PanelContainer
var _tag_layer: Control
var _board_panel: PanelContainer
var _board_title: Label
var _board_rows: Array = []     # [{root, place, chip, avatar, initial, name, info, time}]
var _board_more: Label
var _paddock: VBoxContainer
var _paddock_panel: PanelContainer
var _paddock_title: Label
var _paddock_dirty := true
var _paddock_t := 0.0
var _banners: VBoxContainer
var _problems: VBoxContainer
var _session := ""
var _laps_missing := {}         # runId -> true once reported (a loop run without a lap count)
var _podium: Control = null
var _countdown: PanelContainer
var _count_label: Label
var _count_names: HBoxContainer
var _count_key := ""            # who is on the grid now, to rebuild the name chips on change
var _green_tick := -1           # the countdown that last went green (GO! shows for GO_S)
var _go_until := -1.0
const GO_S := 1.2


func _ready() -> void:
	layer = 4  # under the camera HUD (5): its picture-in-picture covers kart tags behind it
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(FONT_NAMES)
	_font.font_weight = 700
	_tag_layer = Control.new()
	_tag_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tag_layer)
	_build_board()
	_build_paddock()
	_banners = VBoxContainer.new()
	_banners.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banners.offset_left = -380
	_banners.offset_right = 380
	_banners.offset_top = 18
	_banners.alignment = BoxContainer.ALIGNMENT_BEGIN
	_banners.add_theme_constant_override("separation", 8)
	_banners.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banners)
	_build_countdown()
	_problems = VBoxContainer.new()
	_problems.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_problems.offset_left = -380
	_problems.offset_right = 380
	_problems.offset_top = 300
	_problems.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_problems)


# ---------------------------------------------------------------- data in

## The racer's colour for tags, board, paddock and its name tag.
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


## Roster entries (server RosterEntry, or mock players): names, status, design step, presence.
func set_roster(entries: Array) -> void:
	var still := {}
	for e in entries:
		var pid := String(e["playerId"])
		still[pid] = true
		if not _roster.has(pid):
			_join_order.append(pid)
		_roster[pid] = e
		color_for(pid)
	for pid in _roster.keys():
		if not still.has(pid):
			_roster.erase(pid)
			_colors.erase(pid)
			_ranks.erase(pid)
			_join_order.erase(pid)
	_paddock_dirty = true


## Server leaderboard.updated: rank and best time per racer.
func set_leaderboard(entries: Array) -> void:
	_ranks.clear()
	for e in entries:
		_ranks[String(e["playerId"])] = {"rank": int(e["rank"]), "bestTimeMs": int(e["bestTimeMs"])}
	_paddock_dirty = true


## Server session status (idle | running | ended). Ending shows the podium; the server's next
## session (autostart) clears the leaderboard right after, so the podium is taken now.
func set_session(status: String) -> void:
	if status == "ended" and _session != "ended":
		_show_podium()
	_session = status


## A run finished (ok) or failed: result_ms is the finish time, or the best lap on a loop.
func run_result(run_id: String, pid: String, ok: bool, result_ms: int, reason: String) -> void:
	var h: Dictionary = _heat.get(run_id, {"pid": pid})
	h["state"] = "finished" if ok else "failed"
	h["result_ms"] = result_ms
	h["reason"] = reason
	h["done_t"] = _t
	_heat[run_id] = h
	var name := _nick(pid)
	if ok:
		# No place in the banner: a racer who started later may still beat this time (the board
		# keeps the places sorted as the times come in).
		var best: Dictionary = _ranks.get(pid, {})
		var pb := best.is_empty() or result_ms < int(best["bestTimeMs"])
		_banner(I18n.f("hud.banner_finish", [name, result_ms / 1000.0]) + ("   " + I18n.t("hud.new_best") if pb and not best.is_empty() else ""), color_for(pid))
		if local_bests and pb:
			_ranks[pid] = {"rank": 0, "bestTimeMs": result_ms}
			_rerank_local()
	else:
		_banner(I18n.f("hud.banner_oops", [name, I18n.t("fail." + reason)]), color_for(pid).darkened(0.35))
	_paddock_dirty = true


## A run left the track without a result (aborted, the racer quit): off the board.
func run_gone(run_id: String) -> void:
	_heat.erase(run_id)
	var tag: Control = _tags.get(run_id)
	if tag != null:
		tag.queue_free()
		_tags.erase(run_id)


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

## sim: sim/sim.gd (racers on track and in the start queue); views: runId -> racer view node.
func update(delta: float, sim, views: Dictionary) -> void:
	_t += delta
	for r in sim.racers:
		_heat_entry(r, "racing")
	for r in sim.queue:
		_heat_entry(r, "queued")
	var on_track: bool = not sim.racers.is_empty() or not sim.queue.is_empty()
	if on_track:
		_empty_since = -1.0
	elif _empty_since < 0.0:
		_empty_since = _t
	for run_id in _heat.keys():
		var h: Dictionary = _heat[run_id]
		if h["state"] == "racing" or h["state"] == "queued":
			if not sim.by_run.has(run_id):
				_heat.erase(run_id)  # gone without a result we saw (aborted)
			continue
		if _t - float(h["done_t"]) > RESULT_HOLD_S or (_empty_since >= 0.0 and _t - _empty_since > EMPTY_HOLD_S):
			_heat.erase(run_id)
	var order := _order(sim)
	_update_countdown(sim)
	_update_board(order, sim)
	_update_tags(order, sim, views, delta)
	_paddock_t -= delta
	if _paddock_dirty or _paddock_t <= 0.0:
		_rebuild_paddock(sim)
	_expire(_banners)
	_expire(_problems)
	if _podium != null and _t > float(_podium.get_meta("until")):
		_podium.queue_free()
		_podium = null


func _heat_entry(r, state: String) -> void:
	var h: Dictionary = _heat.get(r.run_id, {})
	if h.is_empty():
		_heat[r.run_id] = {"pid": r.player_id, "state": state, "racer": r}
	else:
		h["state"] = state
		h["racer"] = r


## Run ids by place: finishers by time, then racers by distance, then the start queue, then oopses.
func _order(sim) -> Array:
	var fin: Array = []
	var racing: Array = []
	var queued: Array = []
	var failed: Array = []
	for run_id in _heat:
		match String(_heat[run_id]["state"]):
			"finished": fin.append(run_id)
			"racing": racing.append(run_id)
			"queued": queued.append(run_id)
			_: failed.append(run_id)
	fin.sort_custom(func(a, b): return int(_heat[a]["result_ms"]) < int(_heat[b]["result_ms"]))
	racing.sort_custom(func(a, b):
		var ra = _heat[a]["racer"]
		var rb = _heat[b]["racer"]
		return ra.lap + ra.progress() > rb.lap + rb.progress())
	var qorder: Array = sim.queue.map(func(r): return r.run_id)
	queued.sort_custom(func(a, b): return qorder.find(a) < qorder.find(b))
	return fin + racing + queued + failed


func _ordinal(n: int) -> String:
	return I18n.t("hud.place_%d" % n) if n <= 3 else I18n.f("hud.place_n", [n])


# ---------------------------------------------------------------- race board

func _build_board() -> void:
	_board_panel = _panel(Color(0.06, 0.07, 0.1, 0.72), 14)
	_board_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_board_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_board_panel.offset_left = -16 - BOARD_W
	_board_panel.offset_right = -16
	_board_panel.offset_top = 16
	_board_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_board_panel.add_child(box)
	_board_title = _label("", 26, Color(1, 0.86, 0.3))
	box.add_child(_board_title)
	for i in BOARD_ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var place := _label("", 30, Color.WHITE)
		place.custom_minimum_size = Vector2(44, 0)
		place.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(place)
		var chip := _avatar_chip(44)
		row.add_child(chip["root"])
		var name := _label("", 28, Color.WHITE)
		name.custom_minimum_size = Vector2(124, 0)
		name.clip_text = true
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var info := _label("", 20, Color(0.8, 0.84, 0.92))
		info.custom_minimum_size = Vector2(90, 0)
		row.add_child(info)
		var time := _label("", 28, Color.WHITE)
		time.custom_minimum_size = Vector2(108, 0)
		time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(time)
		box.add_child(row)
		_board_rows.append({"root": row, "place": place, "chip": chip, "name": name, "info": info, "time": time})
	_board_more = _label("", 20, Color(0.8, 0.84, 0.92))
	box.add_child(_board_more)


## More than BOARD_FULL_ROWS racers: smaller rows, so the board stays clear of the camera's
## picture-in-picture at the bottom right.
func _set_board_compact(on: bool) -> void:
	if _board_panel.get_meta("compact", false) == on:
		return
	_board_panel.set_meta("compact", on)
	for row in _board_rows:
		var chip: Control = row["chip"]["root"]
		chip.custom_minimum_size = Vector2.ONE * (32 if on else 44)
		row["chip"]["tex"].custom_minimum_size = Vector2.ONE * (26 if on else 38)
		row["chip"]["initial"].add_theme_font_size_override("font_size", 17 if on else 24)
		for k in ["place", "name", "time"]:
			row[k].add_theme_font_size_override("font_size", 22 if on else (30 if k == "place" else 28))
		row["info"].add_theme_font_size_override("font_size", 16 if on else 20)
	_board_panel.reset_size()


func _update_board(order: Array, sim) -> void:
	_board_panel.visible = not order.is_empty()
	if order.is_empty():
		return
	_set_board_compact(order.size() > BOARD_FULL_ROWS)
	var racing := false
	for run_id in order:
		if _heat[run_id]["state"] == "racing" or _heat[run_id]["state"] == "queued":
			racing = true
	_board_title.text = I18n.t("hud.race") if racing else I18n.t("hud.results")
	for i in BOARD_ROWS:
		var row: Dictionary = _board_rows[i]
		row["root"].visible = i < order.size()
		if i >= order.size():
			continue
		var h: Dictionary = _heat[order[i]]
		var pid := String(h["pid"])
		var col := color_for(pid)
		var state := String(h["state"])
		_fill_chip(row["chip"], pid, col)
		row["name"].text = _nick(pid)
		row["name"].add_theme_color_override("font_color", col.lightened(0.25))
		row["place"].text = str(i + 1) if state == "racing" or state == "finished" else ""
		row["place"].add_theme_color_override("font_color", _place_color(i + 1) if state == "finished" else Color.WHITE)
		var info := ""
		var time := ""
		match state:
			"queued":
				info = I18n.t("hud.at_start")
			"racing":
				var r = h["racer"]
				if r.looping:
					# The laps this run races (it brought them from the server), not a setting here.
					info = I18n.f("hud.lap", [mini(r.lap + 1, r.laps_max), r.laps_max])
					if r.laps_max <= 0:
						info = I18n.t("hud.laps_missing")
						if not _laps_missing.has(r.run_id):
							_laps_missing[r.run_id] = true
							push_error("race HUD: loop run %s has no lap count" % r.run_id)
							problem(I18n.f("log.no_laps", [r.run_id, _nick(String(h["pid"]))]))
					if r.pit_requested:
						info = I18n.f("hud.lap_pit", [r.lap + 1])  # finishes at the next line
					time = I18n.f("hud.secs_live", [r.lap_ms() / 1000.0])
				else:
					info = I18n.t("section." + String(r.section))
					time = I18n.f("hud.secs_live", [r.elapsed_ms() / 1000.0])
			"finished":
				info = I18n.t("hud.best_lap") if h.has("racer") and h["racer"].looping else I18n.t("hud.finished")
				time = I18n.f("hud.best_time", [int(h["result_ms"]) / 1000.0])
			_:
				info = I18n.t("hud.oops")
				time = ""
		row["info"].text = info
		row["time"].text = time
		row["time"].add_theme_color_override("font_color", _place_color(i + 1) if state == "finished" else Color.WHITE)
		row["root"].modulate.a = 0.55 if state == "failed" or state == "queued" else 1.0
	_board_more.visible = order.size() > BOARD_ROWS
	_board_more.text = I18n.f("hud.more", [order.size() - BOARD_ROWS])


func _place_color(place: int) -> Color:
	match place:
		1: return Color("#ffd23a")
		2: return Color("#d9e2ec")
		3: return Color("#e0a060")
	return Color.WHITE


# ---------------------------------------------------------------- kart tags

func _update_tags(order: Array, sim, views: Dictionary, delta: float) -> void:
	var places := {}
	for i in order.size():
		places[order[i]] = i + 1
	# Tags for racers on the track; nearest first, so the kart in front of the camera keeps its
	# tag on its head and the ones behind move up out of its way.
	var shown: Array = []
	var vp := get_viewport().get_visible_rect()
	var parked: Array = sim.queue.filter(func(q): return sim.on_grid(q.run_id))
	for r in sim.racers + parked:
		var v: Node3D = views.get(r.run_id)
		var tag: PanelContainer = _tags.get(r.run_id)
		if tag == null:
			tag = _make_tag(r.player_id)
			_tags[r.run_id] = tag
		if camera == null or v == null or not v.visible:
			tag.visible = false
			continue
		var anchor: Vector3 = v.tag_anchor()
		if camera.is_position_behind(anchor):
			tag.visible = false
			continue
		var p := camera.unproject_position(anchor)
		var dist := camera.global_position.distance_to(anchor)
		if not vp.grow(200).has_point(p):
			tag.visible = false
			continue
		tag.visible = true
		var badge: Label = tag.get_meta("badge")
		badge.text = str(places.get(r.run_id, 0))
		if badge.get_parent().visible != (r.state == "racing"):
			badge.get_parent().visible = r.state == "racing"  # no place while waiting on the grid
			tag.reset_size()
		var k := clampf(TAG_NEAR / maxf(dist, 0.1), 0.55, 1.0)
		tag.scale = Vector2(k, k)
		shown.append({"tag": tag, "p": p, "dist": dist, "size": tag.get_combined_minimum_size() * k})
	shown.sort_custom(func(a, b): return a["dist"] < b["dist"])
	# A tag that would sit under a HUD panel is left out (half hidden behind a panel is noise).
	var blockers: Array = []
	for c in [_paddock_panel, _board_panel, _countdown, _podium]:
		if c != null and c.visible:
			blockers.append(c.get_global_rect())
	var placed: Array = []
	for s in shown:
		var size: Vector2 = s["size"]
		var rect := Rect2(s["p"] - Vector2(size.x * 0.5, size.y), size)
		for _pass in 12:
			var moved := false
			for other in placed:
				var o: Rect2 = other
				if rect.grow(-1).intersects(o):
					rect.position.y = o.position.y - size.y - 3.0
					moved = true
			if not moved:
				break
		placed.append(rect)
		var tag: Control = s["tag"]
		if blockers.any(func(b): return b.intersects(rect)):
			tag.visible = false
			continue
		# Glide to the new spot (no jitter when two karts swap), jump on a camera cut.
		if tag.position.distance_to(rect.position) > 220.0 or not tag.has_meta("placed"):
			tag.position = rect.position
			tag.set_meta("placed", true)
		else:
			tag.position = tag.position.lerp(rect.position, 1.0 - exp(-delta * 14.0))
	for run_id in _tags.keys():
		if not sim.by_run.has(run_id) or (sim.by_run[run_id].state != "racing" and not sim.on_grid(run_id)):
			_tags[run_id].queue_free()
			_tags.erase(run_id)


func _make_tag(pid: String) -> PanelContainer:
	var col := color_for(pid)
	var tag := _panel(col.darkened(0.45), 10, col, 3)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	tag.add_child(row)
	var badge_bg := _panel(col, 6)
	badge_bg.custom_minimum_size = Vector2(34, 0)
	var badge := _label("", 26, Color(0.08, 0.08, 0.1))
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.remove_theme_constant_override("outline_size")
	badge_bg.add_child(badge)
	row.add_child(badge_bg)
	row.add_child(_label(_nick(pid), 28, Color.WHITE))
	tag.set_meta("badge", badge)
	tag.visible = false
	_tag_layer.add_child(tag)
	tag.reset_size()
	tag.pivot_offset = Vector2.ZERO
	return tag


# ---------------------------------------------------------------- paddock (standings tower)

func _build_paddock() -> void:
	_paddock_panel = _panel(Color(0.06, 0.07, 0.1, 0.62), 14)
	_paddock_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_paddock_panel.offset_left = 16
	_paddock_panel.offset_top = 16
	_paddock_panel.offset_right = 16 + PADDOCK_W
	_paddock_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_paddock_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_paddock_panel.add_child(box)
	_paddock_title = _label(I18n.t("hud.paddock"), 24, Color(1, 0.86, 0.3))
	box.add_child(_paddock_title)
	_paddock = VBoxContainer.new()
	_paddock.add_theme_constant_override("separation", 4)
	box.add_child(_paddock)


func _rebuild_paddock(sim) -> void:
	_paddock_dirty = false
	_paddock_t = 0.5  # avatars arrive and racers start and stop: refresh twice a second
	_paddock_panel.visible = not _roster.is_empty()
	for c in _paddock.get_children():
		c.queue_free()
	var on_track := {}   # racing
	var at_start := {}   # on the grid or waiting to leave, like the race board says
	for r in sim.racers:
		on_track[r.player_id] = true
	for r in sim.queue:
		at_start[r.player_id] = true
	# Ranked racers first (by rank), then everyone else in join order.
	var pids: Array = _join_order.duplicate()
	pids.sort_custom(func(a, b):
		var ra: int = _ranks.get(a, {}).get("rank", 9999)
		var rb: int = _ranks.get(b, {}).get("rank", 9999)
		if ra != rb:
			return ra < rb
		return _join_order.find(a) < _join_order.find(b))
	var compact := pids.size() > PADDOCK_FULL_ROWS
	var av := 30 if compact else 48
	_paddock.add_theme_constant_override("separation", 1 if compact else 4)
	for pid in pids.slice(0, PADDOCK_MAX_ROWS):
		var e: Dictionary = _roster[pid]
		var col := color_for(pid)
		var rank: Dictionary = _ranks.get(pid, {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var place := _label(str(int(rank["rank"])) if not rank.is_empty() and int(rank["rank"]) > 0 else "", 20 if compact else 24, Color.WHITE)
		place.custom_minimum_size = Vector2(30, 0)
		place.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if not rank.is_empty():
			place.add_theme_color_override("font_color", _place_color(int(rank["rank"])))
		row.add_child(place)
		var chip := _avatar_chip(av)
		_fill_chip(chip, pid, col)
		row.add_child(chip["root"])
		var mid := VBoxContainer.new()
		mid.add_theme_constant_override("separation", -4)
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(mid)
		var name := _label(_nick(pid), 18 if compact else 23, col.lightened(0.3))
		name.clip_text = true
		name.custom_minimum_size = Vector2(120, 0)
		mid.add_child(name)
		var status := String(e.get("status", "ready"))
		var line := ""
		var line_col := Color(0.85, 0.88, 0.95)
		if status == "processing":
			var stage := String(e.get("stage", ""))
			line = I18n.t("making." + stage) if stage != "" else I18n.t("hud.queued_design")
			line_col = Color(1, 0.86, 0.3)
		elif status == "ready":
			if on_track.has(pid):
				line = I18n.t("hud.racing")
				line_col = Color(0.5, 1, 0.6)
			elif at_start.has(pid):
				line = I18n.t("hud.at_start")
				line_col = Color(1, 0.86, 0.3)
			elif rank.is_empty():
				line = I18n.t("hud.ready")
		else:
			line = _status_text(status)
			line_col = Color(1, 0.6, 0.5)
		if line != "" and not compact:
			var sl := _label(line, 15, line_col)
			sl.clip_text = true
			sl.custom_minimum_size = Vector2(120, 0)
			mid.add_child(sl)
		elif line != "":
			name.text += "  ·  " + line
		var best := _label(I18n.f("hud.best_time", [int(rank["bestTimeMs"]) / 1000.0]) if not rank.is_empty() else "", 18 if compact else 22, Color.WHITE)
		best.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(best)
		if not bool(e.get("connected", true)):
			row.modulate.a = 0.45
		_paddock.add_child(row)
	if pids.size() > PADDOCK_MAX_ROWS:
		_paddock.add_child(_label(I18n.f("hud.more", [pids.size() - PADDOCK_MAX_ROWS]), 18, Color(0.8, 0.84, 0.92)))


# ---------------------------------------------------------------- countdown

func _build_countdown() -> void:
	_countdown = _panel(Color(0.06, 0.07, 0.1, 0.78), 22, Color("#ffd23a"), 4)
	_countdown.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_countdown.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_countdown.offset_top = 210
	_countdown.visible = false
	add_child(_countdown)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_countdown.add_child(box)
	var title := _label(I18n.t("hud.get_ready"), 34, Color("#ffd23a"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_count_label = _label("", 130, Color.WHITE)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_count_label)
	_count_names = HBoxContainer.new()
	_count_names.alignment = BoxContainer.ALIGNMENT_CENTER
	_count_names.add_theme_constant_override("separation", 10)
	box.add_child(_count_names)
	set_meta("count_title", title)


## Lights while a countdown runs: seconds to green, and who is lined up; then GO! for a moment.
func _update_countdown(sim) -> void:
	var waiting: Array = []
	var go := -1
	for q in sim.queue:
		var t := int(sim.go_tick.get(q.run_id, -1))
		if t > sim.tick:
			waiting.append(q)
			go = t if go < 0 else mini(go, t)
	if waiting.is_empty() and sim.grid_go > 0 and sim.grid_go <= sim.tick and sim.grid_go != _green_tick:
		_green_tick = sim.grid_go
		_go_until = _t + GO_S
	var title: Label = get_meta("count_title")
	# While others are racing, the lights stay small and high, out of the race's way.
	var small: bool = not sim.racers.is_empty()
	if small != bool(_countdown.get_meta("small", false)):
		_countdown.set_meta("small", small)
		_countdown.offset_top = 96 if small else 210
		title.add_theme_font_size_override("font_size", 22 if small else 34)
		_count_label.add_theme_font_size_override("font_size", 64 if small else 130)
		_count_key = ""  # rebuild the name chips at the new size
	if not waiting.is_empty():
		_countdown.visible = true
		title.visible = true
		var left := float(go - sim.tick) / 60.0
		_count_label.text = str(ceili(left))
		_count_label.add_theme_color_override("font_color", Color("#ff4b4b") if left > 1.0 else Color("#ffd23a"))
		var key := ",".join(waiting.map(func(q): return q.run_id))
		if key != _count_key:
			_count_key = key
			for c in _count_names.get_children():
				c.queue_free()
			for q in waiting:
				var chip := _panel(color_for(q.player_id).darkened(0.35), 10, color_for(q.player_id), 3)
				chip.add_child(_label(_nick(q.player_id), 18 if small else 26, Color.WHITE))
				_count_names.add_child(chip)
	elif _t < _go_until:
		_countdown.visible = true
		title.visible = false
		_count_label.text = I18n.t("hud.go")
		_count_label.add_theme_color_override("font_color", Color("#33d17a"))
	else:
		_countdown.visible = false
		_count_key = ""
	if _countdown.visible:
		_countdown.reset_size()
		_countdown.offset_left = -_countdown.size.x * 0.5
		_countdown.offset_right = _countdown.size.x * 0.5


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

## A racer that can't race yet: what it needs (PlayerStatus draft, rejected, needs_review).
func _status_text(status: String) -> String:
	match status:
		"draft": return I18n.t("hud.status_draft")
		"rejected": return I18n.t("hud.status_rejected")
		"needs_review": return I18n.t("hud.status_needs_review")
	push_error("race HUD: unknown player status \"%s\"" % status)
	return status


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


func _banner(text: String, col: Color) -> void:
	var p := _panel(col.darkened(0.25), 14, Color.WHITE, 3)
	var l := _label(text, 38, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.set_meta("until", _t + BANNER_S)
	_banners.add_child(p)
	while _banners.get_child_count() > 3:
		_banners.get_child(0).free()


func _expire(box: Container) -> void:
	for c in box.get_children():
		if _t > float(c.get_meta("until", INF)):
			c.queue_free()
