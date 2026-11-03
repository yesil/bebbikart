# In-game options menu (Esc, or ⌘, on a Mac): fullscreen, graphics, sound, language, track,
# the village surprises, the session, the phone address with its QR code, and quit.
# The game manager sets the game options here, on the big screen; phones only join and quit.
# It does not pause the sim: in server mode phones keep racing while it is open.
# In server mode picking a track starts a new session on it right away, and "New session" starts
# over on the same track: the karts on the track stop, the leaderboard starts empty, the racers
# stay. Neither asks a question.
# The phone address comes from the server (GET /api/join, asked when the menu opens and again
# every few seconds while it is open): the address it prints, http://<the Mac's Wi-Fi IP>:8080,
# which follows the Mac to another network. Without it (mock mode, server unreachable, no
# network, an old server) the menu says why in red instead of showing a code. Under the code it
# says what the server knows about phones getting through: the firewall stops them, or none has
# yet (on a guest Wi-Fi that keeps devices apart, none ever will).
# Every string comes from ui/i18n.gd; main.gd rebuilds the menu when the language changes.
extends CanvasLayer

const AudioSettings = preload("res://audio/audio_settings.gd")
const I18n = preload("res://ui/i18n.gd")

signal fullscreen_toggled
signal track_chosen(id: String)
signal new_session_pressed
signal quit_pressed
signal quality_chosen(id: String)
signal language_chosen(id: String)
signal surprises_toggled(on: bool)

const MAC := "macOS"
const COL_W := 440.0         # a column's width for the wrapping notes
const JOIN_W := 330.0        # the join column's notes
const QR_PX := 300.0         # the QR code's size on a 1080p screen, quiet zone included
const QUIET := 4             # light modules around the code
const RETRY_S := 3.0         # while open, ask the server again this often (new address, first phone)
const RED := Color(1.0, 0.45, 0.4)
# GET /api/join `network` (apps/server/src/network.js NETWORK).
const NETWORKS := ["no_network", "firewall", "no_phone_yet", "phone_seen"]

var _panel: PanelContainer
var _fullscreen: CheckButton
var _tracks := {}            # TrackId -> Button
var _qualities := {}         # preset id -> Button
var _volumes := {}           # audio bus -> HSlider
var _track_note: Label
var _surprises: CheckButton  # village surprises on the road (sim/obstacles.gd)
var _surprises_note: Label
var _session_btn: Button     # New session
var _session_note: Label
var _resume: Button
var _current_track := ""
var _server := false
var _session := "?"          # server session status (server mode)
var _join_base := ""         # server HTTP base (server mode), e.g. http://localhost:8080
var _join_http: HTTPRequest
var _join_busy := false
var _join_retry := 0.0       # > 0: ask the server again when it runs out
var _join_qr: TextureRect
var _join_url: Label
var _join_note: Label


func setup(current_track: String, server_mode: bool) -> void:
	_current_track = current_track
	_server = server_mode
	layer = 10
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.92)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(28)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)

	box.add_child(_label(I18n.t("menu.title"), 30))

	_fullscreen = CheckButton.new()
	_fullscreen.text = I18n.t("menu.fullscreen") + "    " + ("⌃⌘F" if _is_mac() else "F11")
	_fullscreen.add_theme_font_size_override("font_size", 20)
	_fullscreen.toggled.connect(func(_on: bool): fullscreen_toggled.emit())
	box.add_child(_fullscreen)

	# Two columns (display on the left, the game on the right), so the menu fits a 1080p screen.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 44)
	box.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 14)
	cols.add_child(right)
	var join := VBoxContainer.new()
	join.add_theme_constant_override("separation", 14)
	cols.add_child(join)

	left.add_child(_label(I18n.t("menu.graphics"), 20))
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 10)
	left.add_child(qrow)
	var group := ButtonGroup.new()
	for id in ["low", "medium", "high"]:
		var b := Button.new()
		b.text = I18n.t("quality." + id)
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(110, 40)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func(): quality_chosen.emit(id))
		qrow.add_child(b)
		_qualities[id] = b
	var qnote := _label(I18n.t("menu.quality_note"), 15)
	qnote.modulate = Color(1, 1, 1, 0.75)
	_wrap(qnote)
	left.add_child(qnote)

	left.add_child(_label(I18n.t("menu.sound"), 20))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	left.add_child(grid)
	for bus in AudioSettings.BUSES:
		grid.add_child(_label(I18n.t("bus." + bus), 17))
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.custom_minimum_size = Vector2(0, 28)
		sl.value_changed.connect(func(v: float): AudioSettings.set_volume(bus, v))
		grid.add_child(sl)
		_volumes[bus] = sl

	right.add_child(_label(I18n.t("menu.language"), 20))
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 10)
	right.add_child(lrow)
	var lgroup := ButtonGroup.new()
	for id in Protocol.LANGUAGES:
		var b := Button.new()
		b.text = I18n.t("lang." + id)
		b.toggle_mode = true
		b.button_group = lgroup
		b.button_pressed = id == I18n.language
		b.custom_minimum_size = Vector2(150, 40)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func(): if id != I18n.language: language_chosen.emit(id))
		lrow.add_child(b)
	var lnote := _label(I18n.t("menu.language_note"), 15)
	lnote.modulate = Color(1, 1, 1, 0.75)
	_wrap(lnote)
	right.add_child(lnote)

	right.add_child(_label(I18n.t("menu.track"), 20))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	right.add_child(row)
	for id in Protocol.TRACK_IDS:
		var b := Button.new()
		b.text = _track_name(id) + ("  ✓" if id == current_track else "")
		b.toggle_mode = true
		b.button_pressed = id == current_track
		b.disabled = id == current_track
		b.custom_minimum_size = Vector2(150, 44)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_on_track.bind(id))
		row.add_child(b)
		_tracks[id] = b
	_track_note = _label("", 15)
	_wrap(_track_note)
	_track_note.modulate = Color(1, 1, 1, 0.75)
	right.add_child(_track_note)
	_set_track_note()

	_surprises = CheckButton.new()
	_surprises.text = I18n.t("menu.surprises")
	_surprises.add_theme_font_size_override("font_size", 18)
	_surprises.toggled.connect(func(on: bool): surprises_toggled.emit(on))
	right.add_child(_surprises)
	_surprises_note = _label(I18n.t("menu.surprises_note"), 15)
	_surprises_note.modulate = Color(1, 1, 1, 0.75)
	_wrap(_surprises_note)
	right.add_child(_surprises_note)

	right.add_child(_label(I18n.t("menu.session"), 20))
	_session_btn = Button.new()
	_session_btn.custom_minimum_size = Vector2(310, 44)
	_session_btn.add_theme_font_size_override("font_size", 18)
	_session_btn.pressed.connect(_on_session)
	_session_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_child(_session_btn)
	_session_note = _label("", 15)
	_wrap(_session_note)
	right.add_child(_session_note)
	_set_session_row()

	join.add_child(_label(I18n.t("menu.join"), 20))
	_join_qr = TextureRect.new()
	_join_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_join_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_join_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_join_qr.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_join_qr.visible = false
	join.add_child(_join_qr)
	_join_url = _label("", 26)
	_join_url.visible = false
	join.add_child(_join_url)
	_join_note = _label("", 15)
	_wrap(_join_note, JOIN_W)
	join.add_child(_join_note)
	_join_http = HTTPRequest.new()
	_join_http.timeout = 4.0
	_join_http.request_completed.connect(_on_join)
	add_child(_join_http)
	if not _server:
		_join_problem(I18n.t("menu.join_mock"))

	box.add_child(HSeparator.new())
	_resume = _button(I18n.t("menu.resume") + "    Esc", func(): close())
	box.add_child(_resume)
	box.add_child(_button(I18n.t("menu.quit") + "    " + ("⌘Q" if _is_mac() else ""), func(): quit_pressed.emit()))
	visible = false


func set_session(status: String) -> void:
	_session = status
	_set_session_row()
	# A track button waits for its reload; otherwise the note follows the session.
	if not _tracks.values().all(func(b): return b.disabled):
		_set_track_note()


## Server mode: the server's HTTP base, where the menu asks for the phone address on opening.
func set_join_server(http_base: String) -> void:
	_join_base = http_base.trim_suffix("/")


## The village surprises switch: on or off, and whether this track (and run) has them at all.
func set_surprises(on: bool, available: bool) -> void:
	_surprises.set_pressed_no_signal(on and available)
	_surprises.disabled = not available
	_surprises_note.text = I18n.t("menu.surprises_note" if available else "menu.surprises_none")


func set_quality(id: String) -> void:
	_qualities[id].set_pressed_no_signal(true)


func is_open() -> bool:
	return visible


func open() -> void:
	_fullscreen.set_pressed_no_signal(_is_fullscreen())
	for bus in _volumes:
		_volumes[bus].set_value_no_signal(AudioSettings.get_volume(bus))
	visible = true
	_fetch_join()
	_resume.grab_focus()


func close() -> void:
	visible = false
	_join_retry = 0.0


func _process(dt: float) -> void:
	if not visible or _join_retry <= 0.0:
		return
	_join_retry -= dt
	if _join_retry <= 0.0:
		_fetch_join()


## The window mode changed outside the menu (key shortcut or the green title-bar button).
func sync_fullscreen() -> void:
	_fullscreen.set_pressed_no_signal(_is_fullscreen())


## A track switch was refused or failed: show why, in red, until the menu is reopened.
func show_error(text: String) -> void:
	_track_note.text = text
	_track_note.modulate = RED
	for k in _tracks:
		_tracks[k].disabled = k == _current_track


## One click: a new session on that track (server mode) or the course reloaded (mock mode).
func _on_track(id: String) -> void:
	for k in _tracks:
		_tracks[k].disabled = true
	_track_note.modulate = Color(1, 1, 1, 0.75)
	_track_note.text = I18n.f("menu.asking_server" if _server else "menu.loading", [_track_name(id)])
	track_chosen.emit(id)


## One click: start over on the same track (the button waits for the new session).
func _on_session() -> void:
	_session_btn.disabled = true
	_session_btn.text = I18n.t("menu.session_starting")
	new_session_pressed.emit()


## The session button and its note for the session's status.
func _set_session_row() -> void:
	if _session_btn == null:
		return
	_session_btn.disabled = not _server
	_session_btn.text = I18n.t("menu.new_session")
	_session_note.modulate = Color(1, 1, 1, 0.75)
	if not _server:
		_session_note.text = I18n.t("menu.session_mock")
	elif _session == "running":
		_session_note.text = I18n.f("menu.new_session_note", [_track_name(_current_track)])
	else:
		_session_note.text = I18n.f("menu.session_idle_note", [I18n.t("session." + (_session if _session != "?" else "unknown"))])


## Ending or starting the session failed: show why, in red, until the menu is reopened.
func show_session_error(text: String) -> void:
	_set_session_row()
	_session_note.text = text
	_session_note.modulate = RED


## Asks the server for the phone address (GET /api/join). The last code stays up meanwhile.
func _fetch_join() -> void:
	_join_retry = 0.0
	if not _server:
		return
	if _join_base == "":
		push_error("options menu: server mode without a server address for the phone address")
		_join_problem(I18n.f("error.join_bad", ["?", "no server address"]))
		return
	if _join_busy:
		return
	if _join_note.text == "":
		_join_url.visible = false
		_join_note.text = I18n.t("menu.join_loading")
		_join_note.modulate = Color(1, 1, 1, 0.75)
	var err := _join_http.request(_join_base + "/api/join")
	if err != OK:
		_join_unreachable(error_string(err))
		return
	_join_busy = true


func _on_join(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_join_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_join_unreachable(_result_name(result))
		return
	if code != 200:
		push_error("options menu: GET %s/api/join answered %d" % [_join_base, code])
		_join_problem(I18n.f("error.join_bad", [_join_base, "HTTP %d" % code]))
		return
	var j = JSON.parse_string(body.get_string_from_utf8())
	var why := ""
	if not (j is Dictionary):
		why = "not JSON"
	elif not (String(j.get("network", "")) in NETWORKS):
		why = "no network state"
	elif j.network == "no_network":
		_join_problem(I18n.t("menu.join_no_network"))
	elif not (j.get("url") is String) or String(j.url) == "":
		why = "no url"
	elif not (j.get("qr") is Array) or (j.qr as Array).is_empty():
		why = "no QR code"
	else:
		why = show_join(String(j.url), j.qr, bool(j.get("phoneSite", true)), String(j.network))
	if why != "":
		push_error("options menu: GET %s/api/join: %s" % [_join_base, why])
		_join_problem(I18n.f("error.join_bad", [_join_base, why]))
	_join_retry = RETRY_S


## The phone address, its QR code (rows of "0"/"1", 1 dark), whether the phone site is built
## and what the server knows about phones reaching it (one of NETWORKS, not "no_network").
## Returns why it can't be shown ("" when shown).
func show_join(url: String, rows: Array, phone_site: bool, network: String) -> String:
	var tex := qr_texture(rows)
	if tex == null:
		return "broken QR code"
	_join_qr.texture = tex
	# Whole screen pixels per module on a 1080p screen keep the modules even.
	var side := tex.get_width() * floorf(QR_PX / tex.get_width())
	_join_qr.custom_minimum_size = Vector2(side, side)
	_join_url.text = url
	_join_url.visible = true
	var host := url.get_slice("//", 1).get_slice("/", 0).rsplit(":", true, 1)[0]
	if host in ["localhost", "[::1]"] or host.begins_with("127."):
		# Phones would open their own localhost: no code to scan.
		_join_qr.visible = false
		_join_note.text = I18n.t("menu.join_local")
		_join_note.modulate = RED
	else:
		_join_qr.visible = true
		if not phone_site:
			_join_note.text = I18n.t("menu.join_no_site")
		elif network == "firewall":
			_join_note.text = I18n.t("menu.join_firewall")
		elif network == "no_phone_yet":
			_join_note.text = I18n.t("menu.join_waiting")
		else:
			_join_note.text = I18n.t("menu.join_note")
		_join_note.modulate = Color(1, 1, 1, 0.75) if phone_site and network != "firewall" else RED
	return ""


## A QR code as a texture, a white quiet zone around it; null if the rows aren't a square of 0/1.
static func qr_texture(rows: Array) -> ImageTexture:
	var n := rows.size()
	if n < 21:
		return null
	var img := Image.create(n + 2 * QUIET, n + 2 * QUIET, false, Image.FORMAT_L8)
	img.fill(Color.WHITE)
	for y in n:
		var r := String(rows[y])
		if r.length() != n:
			return null
		for x in n:
			if r[x] == "1":
				img.set_pixel(x + QUIET, y + QUIET, Color.BLACK)
			elif r[x] != "0":
				return null
	return ImageTexture.create_from_image(img)


## The server can't be reached: say so in red and ask again while the menu is open.
func _join_unreachable(why: String) -> void:
	push_warning("options menu: can't reach %s for the phone address (%s)" % [_join_base, why])
	_join_problem(I18n.f("error.join_unreachable", [_join_base, why]))
	_join_retry = RETRY_S


## No phone address: no code and no address (an old one could be wrong), the reason in red.
func _join_problem(text: String) -> void:
	_join_qr.visible = false
	_join_url.visible = false
	_join_note.text = text
	_join_note.modulate = RED


static func _result_name(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "can't connect"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "unknown host"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "connection error"
		HTTPRequest.RESULT_TIMEOUT:
			return "no answer"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "no response"
	return "error %d" % result


func _set_track_note() -> void:
	_track_note.modulate = Color(1, 1, 1, 0.75)
	if not _server:
		_track_note.text = I18n.t("menu.note_mock")
	elif _session == "running":
		_track_note.text = I18n.f("menu.note_running", [_track_name(_current_track)])
	else:
		_track_note.text = I18n.f("menu.note_session", [I18n.t("session." + (_session if _session != "?" else "unknown"))])


func _track_name(id: String) -> String:
	return I18n.t("track." + id)


func _is_fullscreen() -> bool:
	var m := get_viewport().get_window().mode
	return m == Window.MODE_FULLSCREEN or m == Window.MODE_EXCLUSIVE_FULLSCREEN


func _is_mac() -> bool:
	return OS.get_name() == MAC


## A note under a section: wraps at a column's width.
func _wrap(l: Label, width := COL_W) -> void:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text.strip_edges()
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b
