extends Node3D
## Weather visuals driven by the sim weather state: rain particles + darker sky + wet look,
## wind streaks blowing along the wind direction, warning tint before a phase starts.
## Also publishes the global shader parameters the world materials read: road_wetness (wet
## roads, rain ripples on water), wind_strength and wind_dir (trees, grass and flags sway).
## Everything eases towards its target over seconds: no sudden flashes.

var weather = null   # sim/weather.gd
var env: Environment
var sun: DirectionalLight3D
var sky_mat: Material              # ProceduralSkyMaterial, or the world's sky shader (gloom)
var _base_sun := 1.0
var _base_ambient := 1.0
var _base_fog := 0.0
var _gloom := 0.0
var _wet := 0.0
var _wind_vis := 0.0
var follow: Node3D   # rain volume follows this (usually the camera)
## Split screen (duel mode): one rain and wind volume per camera, instead of `follow`'s one.
var followers: Array = []

var _rain: CPUParticles3D
var _wind: CPUParticles3D
var _extra: Array = []    # [rain, wind] volumes for the second and later followers
var _rain_vis := 0.0

const SKY_TOP := Color(0.32, 0.6, 0.98)
const SKY_HORIZON := Color(0.75, 0.88, 1.0)
const STORM_TOP := Color(0.25, 0.28, 0.36)
const STORM_HORIZON := Color(0.5, 0.53, 0.6)


func setup(p_weather, p_env: Environment, p_sun: DirectionalLight3D) -> void:
	weather = p_weather
	env = p_env
	sun = p_sun
	sky_mat = env.sky.sky_material
	_base_sun = sun.light_energy
	_base_ambient = env.ambient_light_energy
	_base_fog = env.fog_density if env.fog_enabled else 0.0
	_rain = CPUParticles3D.new()
	_rain.amount = 2500
	_rain.lifetime = 1.2
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(30, 1, 30)
	_rain.direction = Vector3(0, -1, 0)
	_rain.spread = 3.0
	_rain.initial_velocity_min = 18.0
	_rain.initial_velocity_max = 22.0
	_rain.gravity = Vector3(0, -10, 0)
	var drop := BoxMesh.new()
	drop.size = Vector3(0.03, 0.5, 0.03)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.7, 0.8, 1.0, 0.55)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = dm
	_rain.mesh = drop
	_rain.emitting = false
	_rain.local_coords = false
	add_child(_rain)

	_wind = CPUParticles3D.new()
	_wind.amount = 300
	_wind.lifetime = 1.4
	_wind.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_wind.emission_box_extents = Vector3(35, 4, 35)
	_wind.spread = 4.0
	_wind.gravity = Vector3.ZERO
	_wind.initial_velocity_min = 14.0
	_wind.initial_velocity_max = 20.0
	var streak := BoxMesh.new()
	streak.size = Vector3(0.04, 2.2, 0.04)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(1, 1, 1, 0.45)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.material = sm
	_wind.mesh = streak
	_wind.particle_flag_align_y = true
	_wind.emitting = false
	_wind.local_coords = false
	add_child(_wind)


## The rain and wind volumes for follower i (0: the main pair; more are made on first use and
## share the main pair's meshes, so their looks ease together). Split screen halves the drops per
## volume: the same rain on the screen, the same CPU.
func _volumes(i: int) -> Array:
	if i == 0:
		return [_rain, _wind]
	while _extra.size() < i:
		var r := _rain.duplicate() as CPUParticles3D
		var w := _wind.duplicate() as CPUParticles3D
		r.mesh = _rain.mesh
		w.mesh = _wind.mesh
		add_child(r)
		add_child(w)
		_extra.append([r, w])
	return _extra[i - 1]


func _process(delta: float) -> void:
	if weather == null:
		return
	var rain_i: float = weather.rain_intensity()
	var wind_s: float = weather.wind_strength()
	_rain_vis = move_toward(_rain_vis, rain_i, delta * 0.5)
	(_rain.mesh.material as StandardMaterial3D).albedo_color.a = 0.15 + 0.45 * _rain_vis
	var wdir: Vector3 = weather.wind_dir()
	(_wind.mesh.material as StandardMaterial3D).albedo_color.a = 0.1 + 0.4 * wind_s
	var follows: Array = followers if not followers.is_empty() else ([follow] if follow != null else [])
	var split := follows.size() > 1
	for i in maxi(follows.size(), 1 + _extra.size()):
		var v: Array = _volumes(i)
		var rain: CPUParticles3D = v[0]
		var wind: CPUParticles3D = v[1]
		var on := i < follows.size() or (i == 0 and follows.is_empty())
		if i < follows.size() and is_instance_valid(follows[i]):
			rain.global_position = (follows[i] as Node3D).global_position + Vector3(0, 14, 0)
			wind.global_position = (follows[i] as Node3D).global_position + Vector3(0, 2, 0)
		var drops := 1400 if split else 2500
		if rain.amount != drops:
			rain.amount = drops
		rain.emitting = on and _rain_vis > 0.05
		rain.direction = (Vector3(0, -1, 0) + wdir * wind_s * 0.5).normalized()
		wind.emitting = on and wind_s > 0.05
		wind.direction = wdir
	var gloom := clampf(_rain_vis * 0.9 + wind_s * 0.3, 0.0, 1.0)
	if weather.phase("rain") == "warning" or weather.phase("wind") == "warning":
		gloom = maxf(gloom, 0.25)
	_gloom = move_toward(_gloom, gloom, delta * 0.25)
	if sky_mat is ShaderMaterial:
		(sky_mat as ShaderMaterial).set_shader_parameter("gloom", _gloom)
	else:
		var pm := sky_mat as ProceduralSkyMaterial
		pm.sky_top_color = SKY_TOP.lerp(STORM_TOP, _gloom)
		pm.sky_horizon_color = SKY_HORIZON.lerp(STORM_HORIZON, _gloom)
		pm.ground_horizon_color = SKY_HORIZON.lerp(STORM_HORIZON, _gloom)
	sun.light_energy = _base_sun * lerpf(1.0, 0.38, _gloom)
	env.ambient_light_energy = _base_ambient * lerpf(1.0, 0.75, _gloom)
	env.fog_enabled = _base_fog > 0.0 or _gloom > 0.05
	env.fog_density = _base_fog + 0.01 * _gloom
	# Roads get wet quickly and dry slowly; wind eases in and out.
	_wet = move_toward(_wet, _rain_vis, delta * (0.4 if _rain_vis > _wet else 0.05))
	_wind_vis = move_toward(_wind_vis, wind_s, delta * 0.5)
	RenderingServer.global_shader_parameter_set("road_wetness", _wet)
	RenderingServer.global_shader_parameter_set("wind_strength", _wind_vis)
	RenderingServer.global_shader_parameter_set("wind_dir", Vector2(wdir.x, wdir.z))
