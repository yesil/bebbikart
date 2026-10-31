class_name KitMaterial
extends RefCounted
## One shared toon material for all racer parts. Colours are per-instance uniforms.

const TOON_SHADER := preload("res://racer_kit/toon.gdshader")
const STICKER_SHADER := preload("res://racer_kit/sticker.gdshader")

const PATTERNS := ["", "stripes", "spots", "stars", "hearts", "zigzag", "checks", "crayon", "swirl"]
const FINISHES := ["glossy", "matte", "metallic", "sparkle", "glow"]

static var _toon: ShaderMaterial
static var _glass: StandardMaterial3D


static func toon() -> ShaderMaterial:
	if _toon == null:
		_toon = ShaderMaterial.new()
		_toon.shader = TOON_SHADER
	return _toon


static func paint(gi: GeometryInstance3D, color: Color, glow: float = 0.0) -> void:
	gi.material_override = toon()
	gi.set_instance_shader_parameter("albedo", color)
	if glow > 0.0:
		gi.set_instance_shader_parameter("glow", glow)


## Paints a pattern (RacerSpec pattern: {type, scale} + its colour) and/or a finish over every
## toon-painted mesh under n. Pass pattern = {} or finish = "" to leave that unchanged.
## only: when a Color, only meshes painted exactly that colour are changed (a ride's main paint).
static func look(n: Node, pattern: Dictionary, pattern_color: Color, finish: String, only: Variant = null) -> void:
	if n is GeometryInstance3D and n.material_override == toon() \
			and (only == null or n.get_instance_shader_parameter("albedo") == only):
		var gi := n as GeometryInstance3D
		if not pattern.is_empty():
			gi.set_instance_shader_parameter("pattern", PATTERNS.find(str(pattern.type)))
			gi.set_instance_shader_parameter("pattern_color", pattern_color)
			gi.set_instance_shader_parameter("pattern_scale", float(pattern.scale))
		if finish != "":
			gi.set_instance_shader_parameter("finish", FINISHES.find(finish))
	for c in n.get_children():
		look(c, pattern, pattern_color, finish, only)


## See-through glass (car cabins), shared.
static func glass() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.albedo_color = Color(0.75, 0.92, 1.0, 0.22)
		_glass.roughness = 0.05
		_glass.metallic_specular = 1.0
		_glass.rim_enabled = true
		_glass.rim = 0.4
		_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glass


static func sticker(tex: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = STICKER_SHADER
	m.set_shader_parameter("drawing", tex)
	return m
