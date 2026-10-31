extends RefCounted
## Weather state machine (game.md "Weather"): rain and wind run independently,
## calm -> warning -> active -> calm, timings from config.weather. Deterministic per RNG.

const DT := 1.0 / 60.0

var rng := RandomNumberGenerator.new()
var cfg: Dictionary
var forced := false

# Per-kind state: phase, timer (s left in phase), active duration
var rain := {"phase": "calm", "t": 0.0, "intensity": 0.0, "target": 1.0}
var wind := {"phase": "calm", "t": 0.0, "strength": 0.0, "target": 1.0, "dir_deg": 0.0, "gust_t": 0.0, "gust_phase": 0.0}
var changed := false        # set when a phase changed during the last step
var changed_at := ""
var time := 0.0


func _init(weather_cfg: Dictionary, seed_: int) -> void:
	cfg = weather_cfg
	rng.seed = seed_
	rain["t"] = _calm_time("rain")
	wind["t"] = _calm_time("wind")
	wind["dir_deg"] = rng.randf_range(0.0, 360.0)


func _calm_time(kind: String) -> float:
	var c: Dictionary = cfg[kind]
	return rng.randf_range(float(c["minCalmMs"]), float(c["maxCalmMs"])) / 1000.0


func _active_time(kind: String) -> float:
	var c: Dictionary = cfg[kind]
	return rng.randf_range(float(c["minMs"]), float(c["maxMs"])) / 1000.0


## Pins the weather (used by the sweep and debug keys). Pass -1 for direction to keep current.
func force(rain_intensity: float, wind_strength: float, wind_dir_deg: float = -1.0) -> void:
	forced = true
	rain["phase"] = "active" if rain_intensity > 0.0 else "calm"
	rain["intensity"] = rain_intensity
	rain["target"] = rain_intensity
	wind["phase"] = "active" if wind_strength > 0.0 else "calm"
	wind["strength"] = wind_strength
	wind["target"] = wind_strength
	if wind_dir_deg >= 0.0:
		wind["dir_deg"] = wind_dir_deg
	changed = true


## Debug: jump a kind to its next phase now.
func advance(kind: String) -> void:
	forced = false
	var st: Dictionary = rain if kind == "rain" else wind
	st["t"] = 0.0


func step() -> void:
	time += DT
	changed = false
	if not forced:
		_tick_kind("rain", rain)
		_tick_kind("wind", wind)
	# Rain eases in/out over ~1 s.
	var rain_goal: float = rain["target"] if rain["phase"] == "active" else 0.0
	rain["intensity"] = move_toward(float(rain["intensity"]), rain_goal, DT)
	# Wind: eased base strength with gust modulation; direction swings per gust.
	var wind_goal: float = wind["target"] if wind["phase"] == "active" else 0.0
	if forced:
		wind["strength"] = wind_goal
	else:
		wind["gust_phase"] = float(wind["gust_phase"]) + DT * 1.3
		var gust := 0.75 + 0.25 * sin(float(wind["gust_phase"]))
		wind["strength"] = move_toward(float(wind["strength"]), wind_goal * gust, DT * 0.8)
		wind["gust_t"] = float(wind["gust_t"]) - DT
		if float(wind["gust_t"]) <= 0.0 and wind["phase"] == "active":
			wind["gust_t"] = rng.randf_range(4.0, 9.0)
			wind["dir_deg"] = fposmod(float(wind["dir_deg"]) + rng.randf_range(-70.0, 70.0), 360.0)


func _tick_kind(kind: String, st: Dictionary) -> void:
	st["t"] = float(st["t"]) - DT
	if float(st["t"]) > 0.0:
		return
	var c: Dictionary = cfg[kind]
	match st["phase"]:
		"calm":
			st["phase"] = "warning"
			st["t"] = float(c["warningMs"]) / 1000.0
			if kind == "wind":
				var mx := float(c.get("maxStrength", 1.0))
				st["target"] = rng.randf_range(0.5 * mx, mx)
				st["dir_deg"] = rng.randf_range(0.0, 360.0)
			else:
				st["target"] = rng.randf_range(0.6, 1.0)
		"warning":
			st["phase"] = "active"
			st["t"] = _active_time(kind)
		_:
			st["phase"] = "calm"
			st["t"] = _calm_time(kind)
	changed = true
	changed_at = Time.get_datetime_string_from_system(true) + "Z"


func rain_intensity() -> float:
	return float(rain["intensity"])


func wind_strength() -> float:
	return float(wind["strength"])


## Direction the wind blows towards, horizontal unit vector. dirDeg 0 = +x, 90 = +z.
func wind_dir() -> Vector3:
	var a := deg_to_rad(float(wind["dir_deg"]))
	return Vector3(cos(a), 0.0, sin(a))


## Acceleration vector (world, horizontal) at full exposure, before stability resistance.
func wind_vec() -> Vector3:
	return wind_dir() * wind_strength()


func phase(kind: String) -> String:
	return String(rain["phase"] if kind == "rain" else wind["phase"])


## contracts §4 WeatherState.
func state() -> Dictionary:
	return {
		"rain": {"phase": rain["phase"], "intensity": snappedf(rain_intensity(), 0.01)},
		"wind": {"phase": wind["phase"], "strength": snappedf(wind_strength(), 0.01), "dirDeg": snappedf(float(wind["dir_deg"]), 0.1)},
		"changedAt": changed_at if changed_at != "" else Time.get_datetime_string_from_system(true) + "Z",
	}
