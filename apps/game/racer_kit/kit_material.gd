class_name KitMaterial
extends RefCounted
## One shared toon material for all racer parts. Colours are per-instance uniforms.

const TOON_SHADER := preload("res://racer_kit/toon.gdshader")
const STICKER_SHADER := preload("res://racer_kit/sticker.gdshader")

static var _toon: ShaderMaterial


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


static func sticker(tex: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = STICKER_SHADER
	m.set_shader_parameter("drawing", tex)
	return m
