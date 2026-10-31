extends CanvasLayer
## Big-screen camera HUD (game.md "Camera director"):
##  - bottom left: the racer on camera, in their colour, over a bar that runs down to the next
##    automatic switch (LOCKED when A turned automatic switching off);
##  - lower middle: their name, big, for a moment after every cut ("wants to be on the big screen!"
##    when their phone asked for it);
##  - bottom right: picture in picture, a second camera on the same racer that looks back at its
##    face, or at its side. V or the options menu cycles face → side → off.
## Racer views provide shot_frame() (world space: root, head, head_r, center, radius, fwd).
## Their name tags sit on NAME_TAG_LAYER, which the inset camera does not draw.

const I18n = preload("res://ui/i18n.gd")

const INSET_IDS := ["face", "side", "off"]
const NAME_TAG_LAYER := 1 << 19    # render layer 20: racer name tags, main camera only
const INSET_SIZE := Vector2(576, 340)
const MARGIN := 24.0
const POP_S := 2.2
const POP_BOTTOM := 36.0  # px from the bottom edge to the name pop
const FACE_FOV := 36.0
const SIDE_FOV := 42.0

var inset := "face"
var _view = null                   # racer view on camera (RacerView or KitRacerView), or null
var _vp: SubViewport
var _cam: Camera3D
var _inset_box: Control
var _inset_label: Label
var _tag: PanelContainer
var _tag_title: Label
var _tag_name: Label
var _tag_bar: ProgressBar
var blockers = null  # world/camera_blockers.gd, or null: the inset pulls in front of houses too
var _pop: VBoxContainer
var _pop_name: Label
var _pop_note: Label
var _pop_t := 0.0
var _fwd := Vector3.ZERO           # smoothed heading of the racer, for the inset camera
var _off := Vector3.ZERO           # smoothed head/centre offset from the racer's root


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_inset(root)
	_build_tag(root)
	_build_pop(root)
	set_inset(inset)


## "face", "side" or "off". Returns false (and says why) for anything else.
func set_inset(id: String) -> bool:
	if not INSET_IDS.has(id):
		push_error("camera HUD: unknown inset \"%s\" (known: %s)" % [id, ", ".join(INSET_IDS)])
		return false
	inset = id
	_fwd = Vector3.ZERO
	if _inset_label != null:
		match id:
			"face":
				_inset_label.text = I18n.t("cam.inset_face")
			"side":
				_inset_label.text = I18n.t("cam.inset_side")
	return true


## V: face → side → off → face. Returns the new inset id.
func cycle_inset() -> String:
	set_inset(INSET_IDS[(INSET_IDS.find(inset) + 1) % INSET_IDS.size()])
	return inset


## Every frame: the racer view on camera (null if nobody), its name and colour, whether the main
## camera is chasing it (follow mode), how much of the interval to the next automatic cut is
## left (0..1, or < 0 for none coming) and whether automatic switching is off.
func show_racer(view, nickname: String, color: Color, chasing: bool, left_frac: float, locked: bool) -> void:
	if view != _view:
		_fwd = Vector3.ZERO
	_view = view
	_tag.visible = view != null and chasing
	if not _tag.visible:
		return
	_tag_name.text = nickname
	_tag_name.add_theme_color_override("font_color", color.lightened(0.35))
	_tag_title.text = I18n.t("cam.locked") if locked else I18n.t("cam.on_camera")
	_tag_bar.visible = left_frac >= 0.0
	_tag_bar.value = clampf(left_frac, 0.0, 1.0)


## The camera just cut to this racer: their name, big, for POP_S.
func pop(nickname: String, color: Color, by_phone: bool) -> void:
	_pop_name.text = nickname
	_pop_name.add_theme_color_override("font_color", color.lightened(0.35))
	_pop_note.text = I18n.t("cam.asked") if by_phone else ""
	_pop_note.visible = by_phone
	_pop_t = POP_S


func _process(delta: float) -> void:
	_pop_t = maxf(0.0, _pop_t - delta)
	_pop.visible = _pop_t > 0.0
	# Fade in over 0.15 s, out over the last 0.5 s.
	_pop.modulate.a = clampf(_pop_t / 0.5, 0.0, 1.0) * clampf((POP_S - _pop_t) / 0.15, 0.0, 1.0)
	var frame: Dictionary = {}
	if inset != "off" and _view != null and is_instance_valid(_view) and _view.visible:
		frame = _view.shot_frame()
	var on := not frame.is_empty()
	_inset_box.visible = on
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if on:
		_aim(frame, delta)


## Puts the inset camera in front of the racer's face, or beside it. The racer's position is
## followed exactly (no lag at speed); its heading and its bobbing head are smoothed.
func _aim(f: Dictionary, delta: float) -> void:
	var root: Vector3 = f["root"]
	var fwd: Vector3 = f["fwd"]
	var target: Vector3 = (f["head"] if inset == "face" else f["center"]) - root
	if _fwd == Vector3.ZERO:
		_fwd = fwd
		_off = target
	else:
		_fwd = _fwd.lerp(fwd, 1.0 - exp(-delta * 5.0)).normalized()
		_off = _off.lerp(target, 1.0 - exp(-delta * 8.0))
	var up := Vector3.UP
	var side := up.cross(_fwd).normalized()
	var look := root + _off
	var dir: Vector3
	var dist: float
	if inset == "face":
		_cam.fov = FACE_FOV
		dir = (_fwd + side * 0.35 + up * 0.12).normalized()
		dist = float(f["head_r"]) / tan(deg_to_rad(FACE_FOV * 0.5)) * 2.4
	else:
		_cam.fov = SIDE_FOV
		dir = (side + _fwd * 0.3 + up * 0.2).normalized()
		dist = float(f["radius"]) / tan(deg_to_rad(SIDE_FOV * 0.5)) * 1.3
	var eye := look + dir * dist
	if blockers != null:
		eye = blockers.clip(look, eye)  # in a narrow lane the side shot would be inside a house
	_cam.look_at_from_position(eye, look, up)


func _build_inset(root: Control) -> void:
	# Rounded box: the viewport and the border are clipped to the box's rounded fill.
	_inset_box = Panel.new()
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.05, 0.06, 0.08)
	fill.set_corner_radius_all(18)
	_inset_box.add_theme_stylebox_override("panel", fill)
	_inset_box.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_inset_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_inset_box, 1.0, 1.0, INSET_SIZE)
	root.add_child(_inset_box)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inset_box.add_child(svc)
	_vp = SubViewport.new()  # shares the main World3D: same scene, second camera
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	svc.add_child(_vp)
	_cam = Camera3D.new()
	_cam.near = 0.05
	_cam.far = 500.0
	_cam.cull_mask = 0xFFFFF & ~NAME_TAG_LAYER
	_vp.add_child(_cam)
	_cam.current = true
	var border := Panel.new()
	var bs := StyleBoxFlat.new()
	bs.draw_center = false
	bs.border_color = Color(1, 1, 1, 0.92)
	bs.set_border_width_all(5)
	bs.set_corner_radius_all(18)
	border.add_theme_stylebox_override("panel", bs)
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inset_box.add_child(border)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _chip_style())
	chip.position = Vector2(14, 12)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inset_box.add_child(chip)
	_inset_label = _label("", 18)
	chip.add_child(_inset_label)


func _build_tag(root: Control) -> void:
	_tag = PanelContainer.new()
	var sb := _chip_style()
	sb.set_content_margin_all(14)
	sb.content_margin_left = 18
	sb.content_margin_right = 22
	_tag.add_theme_stylebox_override("panel", sb)
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_tag, 0.0, 1.0, Vector2.ZERO)
	_tag.grow_horizontal = Control.GROW_DIRECTION_END
	_tag.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_tag)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_tag.add_child(box)
	_tag_title = _label("", 16)
	_tag_title.modulate = Color(1, 1, 1, 0.8)
	box.add_child(_tag_title)
	_tag_name = _label("", 44)
	_tag_name.add_theme_constant_override("outline_size", 10)
	_tag_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	box.add_child(_tag_name)
	_tag_bar = ProgressBar.new()
	_tag_bar.show_percentage = false
	_tag_bar.min_value = 0.0
	_tag_bar.max_value = 1.0
	_tag_bar.custom_minimum_size = Vector2(240, 6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.18)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(1, 1, 1, 0.85)
	fg.set_corner_radius_all(3)
	_tag_bar.add_theme_stylebox_override("background", bg)
	_tag_bar.add_theme_stylebox_override("fill", fg)
	box.add_child(_tag_bar)
	_tag.visible = false


func _build_pop(root: Control) -> void:
	_pop = VBoxContainer.new()
	_pop.alignment = BoxContainer.ALIGNMENT_CENTER
	_pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pop.anchor_left = 0.0
	_pop.anchor_right = 1.0
	# Bottom middle, growing up: clear of the kart in the chase shot, its race-HUD tag and the
	# countdown lights, between the on-camera panel (left) and the inset (right).
	_pop.anchor_top = 1.0
	_pop.anchor_bottom = 1.0
	_pop.offset_top = -POP_BOTTOM
	_pop.offset_bottom = -POP_BOTTOM
	_pop.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_pop)
	_pop_name = _label("", 88)
	_pop_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pop_name.add_theme_constant_override("outline_size", 22)
	_pop_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_pop.add_child(_pop_name)
	_pop_note = _label("", 30)
	_pop_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pop_note.add_theme_constant_override("outline_size", 12)
	_pop_note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_pop.add_child(_pop_note)
	_pop.visible = false


## Anchors `c` to a screen corner (ax, ay: 0 = left/top, 1 = right/bottom), MARGIN in from it.
static func _place(c: Control, ax: float, ay: float, size: Vector2) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = MARGIN if ax == 0.0 else -MARGIN - size.x
	c.offset_right = c.offset_left + size.x
	c.offset_top = MARGIN if ay == 0.0 else -MARGIN - size.y
	c.offset_bottom = c.offset_top + size.y


static func _chip_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	return sb


static func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
