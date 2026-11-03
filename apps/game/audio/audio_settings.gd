# Audio buses and their volumes. The buses are made in code (no default_bus_layout.tres),
# once per process: Master → Music, Sfx, Ambience. Music carries two effects: a low-pass the
# director closes in the rain, and an amplify it turns down to dip the music under a race-end
# cue (both live on the bus, so they never touch the volume the options menu sets).
# Volumes are linear 0..1 per bus, saved to user://audio.cfg. The options menu owns the sliders
# and calls set_volume / get_volume.
extends RefCounted

const BUSES := ["Master", "Music", "Sfx", "Ambience"]
const PATH := "user://audio.cfg"
const DEFAULTS := {"Master": 0.8, "Music": 0.7, "Sfx": 0.8, "Ambience": 0.6}
const LOWPASS_SLOT := 0  # effect index on the Music bus
const DIP_SLOT := 1      # the dip (AudioEffectAmplify) on the Music bus


## Creates the buses if missing and applies the saved volumes. Returns "" or an error text.
static func ensure_buses() -> String:
	for name in BUSES:
		if name == "Master" or AudioServer.get_bus_index(name) != -1:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")
		if name == "Music":
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 20000.0
			AudioServer.add_bus_effect(i, lp, LOWPASS_SLOT)
			AudioServer.set_bus_effect_enabled(i, LOWPASS_SLOT, false)
			AudioServer.add_bus_effect(i, AudioEffectAmplify.new(), DIP_SLOT)
	return _load()


static func set_volume(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i == -1:
		push_error("audio: unknown bus \"%s\" (known: %s)" % [bus, ", ".join(BUSES)])
		return
	v = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_volume_linear(i, v)
	AudioServer.set_bus_mute(i, v <= 0.0)
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # a missing file is fine: we are about to write it
	cfg.set_value("volume", bus, v)
	var err := cfg.save(PATH)
	if err != OK:
		push_error("audio: could not save %s: %s" % [PATH, error_string(err)])


static func get_volume(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	if i == -1:
		push_error("audio: unknown bus \"%s\" (known: %s)" % [bus, ", ".join(BUSES)])
		return 0.0
	return 0.0 if AudioServer.is_bus_mute(i) else AudioServer.get_bus_volume_linear(i)


static func _load() -> String:
	var cfg := ConfigFile.new()
	var err := cfg.load(PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		return "could not read %s (%s)" % [PATH, error_string(err)]
	for name in BUSES:
		var v := clampf(float(cfg.get_value("volume", name, DEFAULTS[name])), 0.0, 1.0)
		var i := AudioServer.get_bus_index(name)
		AudioServer.set_bus_volume_linear(i, v)
		AudioServer.set_bus_mute(i, v <= 0.0)
	return ""
