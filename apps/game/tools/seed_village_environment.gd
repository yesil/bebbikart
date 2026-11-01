extends SceneTree
## Seeds res://world/village/village_environment.tscn: the village's sky, sun and post-processing.
##   godot --headless --path apps/game --script res://tools/seed_village_environment.gd [-- --force]
## Like world/environment.tscn (countryside) it is hand-editable: it is only written if missing
## or with --force. main.gd swaps it in for its default sky and sun on the village track;
## weather_fx.gd scales the sun, ambient light, fog and the sky's `gloom` from these values.
##
## The look: a clear alpine summer day. The sun stands in the north-east so it lights the tall
## mountain faces south of the village (the panorama is turned to put its sun there too), and
## exponential fog with aerial perspective hazes the mountains blue so they read as far away.

const PATH := "res://world/village/village_environment.tscn"
const HDRI := "res://assets/sky/kloofendal_48d_partly_cloudy_puresky_2k.hdr"
const SKY_SHADER := "res://world/materials/sky.gdshader"
## Where the HDRI's own sun is (measured from the panorama's brightest pixel): azimuth as the
## sky shader counts it, atan(x, -z), and elevation, in degrees.
const HDRI_SUN_AZIMUTH := 34.0
const HDRI_SUN_ELEVATION := 47.8
## Where the village's sun stands, same convention.
const SUN_AZIMUTH := 140.0


func _initialize() -> void:
	if ResourceLoader.exists(PATH) and not ("--force" in OS.get_cmdline_user_args()):
		push_error("seed_village_environment: %s exists and may be hand-edited; pass --force to replace it" % PATH)
		quit(1)
		return
	for p in [HDRI, SKY_SHADER]:
		if not ResourceLoader.exists(p):
			push_error("seed_village_environment: missing %s" % p)
			quit(1)
			return
	var root := Node3D.new()
	root.name = "Lighting"

	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load(SKY_SHADER)
	sky_mat.set_shader_parameter("panorama", load(HDRI))
	sky_mat.set_shader_parameter("exposure", 1.0)
	sky_mat.set_shader_parameter("rotation", deg_to_rad(SUN_AZIMUTH - HDRI_SUN_AZIMUTH))
	sky_mat.set_shader_parameter("ground_color", Color(0.36, 0.35, 0.32))
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
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.5
	env.ssao_power = 1.4
	env.ssao_detail = 0.5
	env.ssil_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.72, 0.80, 0.92)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.12
	env.fog_density = 0.0011
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.04
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	var az := deg_to_rad(SUN_AZIMUTH)
	var el := deg_to_rad(HDRI_SUN_ELEVATION)
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	sun.transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), Vector3.ZERO)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.3
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
		push_error("seed_village_environment: saving failed (%d)" % err)
		quit(1)
		return
	print("seed_village_environment: saved %s" % PATH)
	quit(0)
