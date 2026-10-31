extends SceneTree
## Seeds res://world/environment.tscn: the countryside sky, sun and post-processing.
##   godot --headless --path apps/game --script res://tools/seed_environment.gd [-- --force]
## Like decor.tscn it is hand-editable: it is only written if missing or with --force.
## weather_fx.gd scales the sun, ambient light, fog and the sky's `gloom` from these values.

const PATH := "res://world/environment.tscn"
const HDRI := "res://assets/sky/kloofendal_48d_partly_cloudy_puresky_2k.hdr"
const SKY_SHADER := "res://world/materials/sky.gdshader"


func _initialize() -> void:
	if ResourceLoader.exists(PATH) and not ("--force" in OS.get_cmdline_user_args()):
		push_error("seed_environment: %s exists and may be hand-edited; pass --force to replace it" % PATH)
		quit(1)
		return
	for p in [HDRI, SKY_SHADER]:
		if not ResourceLoader.exists(p):
			push_error("seed_environment: missing %s" % p)
			quit(1)
			return
	var root := Node3D.new()
	root.name = "Lighting"

	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load(SKY_SHADER)
	sky_mat.set_shader_parameter("panorama", load(HDRI))
	sky_mat.set_shader_parameter("exposure", 1.0)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.5
	env.ssil_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.70, 0.78, 0.88)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.15
	env.fog_density = 0.0018
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)

	# Warm late-morning sun from behind the start, over the camera's left shoulder.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42.0, 160.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.35
	sun.light_angular_distance = 0.8
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 170.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	root.add_child(sun)

	we.owner = root
	sun.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	var err := ResourceSaver.save(ps, PATH)
	if err != OK:
		push_error("seed_environment: saving failed (%d)" % err)
		quit(1)
		return
	print("seed_environment: saved %s" % PATH)
	quit(0)
