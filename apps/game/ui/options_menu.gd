# In-game options menu (Esc, or ⌘, on a Mac): fullscreen, track and quit.
# It does not pause the sim: in server mode phones keep racing while it is open.
# In server mode the session config owns the track, so the track buttons are locked
# and the menu says where to change it instead of switching locally.
extends CanvasLayer

signal fullscreen_toggled
signal track_chosen(id: String)
signal quit_pressed
signal quality_chosen(id: String)

const MAC := "macOS"

var _panel: PanelContainer
var _fullscreen: CheckButton
var _tracks := {}            # TrackId -> Button
var _qualities := {}         # preset id -> Button
var _track_note: Label
var _resume: Button
var _current_track := ""
var _server := false


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

	box.add_child(_label("Options", 30))

	_fullscreen = CheckButton.new()
	_fullscreen.text = "Fullscreen    " + ("⌃⌘F" if _is_mac() else "F11")
	_fullscreen.add_theme_font_size_override("font_size", 20)
	_fullscreen.toggled.connect(func(_on: bool): fullscreen_toggled.emit())
	box.add_child(_fullscreen)

	box.add_child(_label("Graphics", 20))
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 10)
	box.add_child(qrow)
	var group := ButtonGroup.new()
	for id in ["low", "medium", "high"]:
		var b := Button.new()
		b.text = id.capitalize()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(110, 40)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func(): quality_chosen.emit(id))
		qrow.add_child(b)
		_qualities[id] = b
	var qnote := _label("Low keeps the Mac coolest; High is full resolution with all effects.", 15)
	qnote.modulate = Color(1, 1, 1, 0.75)
	box.add_child(qnote)

	box.add_child(_label("Track", 20))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	for id in Protocol.TRACK_IDS:
		var b := Button.new()
		b.text = String(id).capitalize()
		b.toggle_mode = true
		b.button_pressed = id == current_track
		b.disabled = server_mode or id == current_track
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
	_resume = _button("Resume    Esc", func(): close())
	box.add_child(_resume)
	box.add_child(_button("Quit    " + ("⌘Q" if _is_mac() else ""), func(): quit_pressed.emit()))
	visible = false


func set_quality(id: String) -> void:
	_qualities[id].set_pressed_no_signal(true)


func is_open() -> bool:
	return visible


func open() -> void:
	_fullscreen.set_pressed_no_signal(_is_fullscreen())
	visible = true
	_resume.grab_focus()


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## The window mode changed outside the menu (key shortcut or the green title-bar button).
func sync_fullscreen() -> void:
	_fullscreen.set_pressed_no_signal(_is_fullscreen())


## A track switch was refused or failed: show why, in red, until the menu is reopened.
func show_error(text: String) -> void:
	_track_note.text = text
	_track_note.modulate = Color(1.0, 0.45, 0.4)


func _on_track(id: String) -> void:
	if _server:
		# The buttons are disabled in server mode; reaching here is a bug, say so.
		show_error("The server session owns the track; it was not changed.")
		return
	for k in _tracks:
		_tracks[k].disabled = true
	_track_note.text = "Loading %s…" % id.capitalize()
	track_chosen.emit(id)


func _set_track_note() -> void:
	if _server:
		_track_note.text = ("Locked: the server session picks the track (now %s). "
			+ "End the session and change the track on the admin page; the big screen follows.") % _current_track.capitalize()
	else:
		_track_note.text = "Switching reloads the course and restarts the mock race."


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
