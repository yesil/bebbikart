# In-game options menu (Esc, or ⌘, on a Mac): fullscreen, graphics, sound, language, track and quit.
# The game manager sets the game options here, on the big screen; phones only join and quit.
# It does not pause the sim: in server mode phones keep racing while it is open.
# In server mode a track change during a running session ends that session (fresh
# leaderboard), so the first click asks for a second click to confirm.
# Every string comes from ui/i18n.gd; main.gd rebuilds the menu when the language changes.
extends CanvasLayer

const AudioSettings = preload("res://audio/audio_settings.gd")
const I18n = preload("res://ui/i18n.gd")

signal fullscreen_toggled
signal track_chosen(id: String)
signal quit_pressed
signal quality_chosen(id: String)
signal language_chosen(id: String)

const MAC := "macOS"

var _panel: PanelContainer
var _fullscreen: CheckButton
var _tracks := {}            # TrackId -> Button
var _qualities := {}         # preset id -> Button
var _volumes := {}           # audio bus -> HSlider
var _track_note: Label
var _resume: Button
var _current_track := ""
var _server := false
var _session := "?"          # server session status (server mode)
var _confirm := ""           # track waiting for its confirming second click


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

	box.add_child(_label(I18n.t("menu.graphics"), 20))
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 10)
	box.add_child(qrow)
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
	box.add_child(qnote)

	box.add_child(_label(I18n.t("menu.sound"), 20))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	box.add_child(grid)
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

	box.add_child(_label(I18n.t("menu.language"), 20))
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 10)
	box.add_child(lrow)
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
	box.add_child(lnote)

	box.add_child(_label(I18n.t("menu.track"), 20))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
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
	_track_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_track_note.modulate = Color(1, 1, 1, 0.75)
	box.add_child(_track_note)
	_set_track_note()

	box.add_child(HSeparator.new())
	_resume = _button(I18n.t("menu.resume") + "    Esc", func(): close())
	box.add_child(_resume)
	box.add_child(_button(I18n.t("menu.quit") + "    " + ("⌘Q" if _is_mac() else ""), func(): quit_pressed.emit()))
	visible = false


func set_session(status: String) -> void:
	_session = status
	if _confirm == "":
		_set_track_note()


func set_quality(id: String) -> void:
	_qualities[id].set_pressed_no_signal(true)


func is_open() -> bool:
	return visible


func open() -> void:
	_fullscreen.set_pressed_no_signal(_is_fullscreen())
	for bus in _volumes:
		_volumes[bus].set_value_no_signal(AudioSettings.get_volume(bus))
	_cancel_confirm()
	visible = true
	_resume.grab_focus()


func close() -> void:
	visible = false


## The window mode changed outside the menu (key shortcut or the green title-bar button).
func sync_fullscreen() -> void:
	_fullscreen.set_pressed_no_signal(_is_fullscreen())


## A track switch was refused or failed: show why, in red, until the menu is reopened.
func show_error(text: String) -> void:
	_track_note.text = text
	_track_note.modulate = Color(1.0, 0.45, 0.4)
	for k in _tracks:
		_tracks[k].disabled = k == _current_track


func _on_track(id: String) -> void:
	if _server and _session == "running" and _confirm != id:
		_cancel_confirm()
		_confirm = id
		_tracks[id].text = I18n.f("menu.end_session_to", [_track_name(id)])
		_tracks[id].set_pressed_no_signal(false)
		_track_note.modulate = Color(1.0, 0.85, 0.4)
		_track_note.text = I18n.f("menu.confirm_switch", [_track_name(id)])
		return
	_confirm = ""
	for k in _tracks:
		_tracks[k].disabled = true
	_track_note.modulate = Color(1, 1, 1, 0.75)
	_track_note.text = I18n.f("menu.asking_server" if _server else "menu.loading", [_track_name(id)])
	track_chosen.emit(id)


func _cancel_confirm() -> void:
	if _confirm != "":
		_tracks[_confirm].text = _track_name(_confirm)
		_confirm = ""
	_set_track_note()


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
