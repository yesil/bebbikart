extends Node3D
## Weather visuals driven by the sim weather state: rain particles + darker sky + wet look,
## wind streaks blowing along the wind direction, warning tint before a phase starts.

var weather = null   # sim/weather.gd
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var follow: Node3D   # rain volume follows this (usually the camera)

var _rain: CPUParticles3D
var _wind: CPUParticles3D
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


func _process(delta: float) -> void:
	if weather == null:
		return
	var rain_i: float = weather.rain_intensity()
	var wind_s: float = weather.wind_strength()
	if follow != null:
		_rain.global_position = follow.global_position + Vector3(0, 14, 0)
		_wind.global_position = follow.global_position + Vector3(0, 2, 0)
	_rain_vis = move_toward(_rain_vis, rain_i, delta * 0.5)
	_rain.emitting = _rain_vis > 0.05
	(_rain.mesh.material as StandardMaterial3D).albedo_color.a = 0.15 + 0.45 * _rain_vis
	var wdir: Vector3 = weather.wind_dir()
	_rain.direction = (Vector3(0, -1, 0) + wdir * wind_s * 0.5).normalized()
	_wind.emitting = wind_s > 0.05
	(_wind.mesh.material as StandardMaterial3D).albedo_color.a = 0.1 + 0.4 * wind_s
	_wind.direction = wdir
	var gloom := clampf(_rain_vis * 0.9 + wind_s * 0.3, 0.0, 1.0)
	if weather.phase("rain") == "warning" or weather.phase("wind") == "warning":
		gloom = maxf(gloom, 0.25)
	sky_mat.sky_top_color = SKY_TOP.lerp(STORM_TOP, gloom)
	sky_mat.sky_horizon_color = SKY_HORIZON.lerp(STORM_HORIZON, gloom)
	sky_mat.ground_horizon_color = SKY_HORIZON.lerp(STORM_HORIZON, gloom)
	sun.light_energy = lerpf(1.25, 0.45, gloom)
	env.fog_enabled = gloom > 0.05
	env.fog_density = 0.004 + 0.012 * gloom
	env.ambient_light_energy = lerpf(1.0, 0.7, gloom)
