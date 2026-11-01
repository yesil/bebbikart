# Big-screen audio: adaptive music, stingers, engines and weather ambience.
# There is no shared race (racers are released from a queue and finish one by one), so the
# music follows the screen: paddock music while no one races, the track's tune while racers are
# out, and its faster "climax" version while the racer on camera is on its final lap (or the
# final stretch on the countryside). Per-racer moments are rate-limited stingers on top.
# Each racer sounds like its ride: RacerSpec.sound picks the engine loop (putter, rocket, hooves…),
# its pitch, and a horn played on a perfect boost and at the finish. A racer without a sound
# (older specs) is logged once and stays silent; nothing is guessed.
# CPU: 2 music streams, 3 engine voices (only the followed racer and the 2 nearest the camera), 3 ambience loops, a pool of 12 one-shots, and one
# low-pass on the Music bus, bypassed when dry. Decisions run at 10 Hz.
# Every file is loaded at setup; a missing one is an error on screen and in the log.
extends Node

const AudioSettings = preload("res://audio/audio_settings.gd")
const I18n = preload("res://ui/i18n.gd")
const Racer = preload("res://sim/racer.gd")

const DIR := "res://assets/audio/"
const MUSIC := {
	"paddock": "music/paddock_racing_game_menu.ogg",
	"countryside": "music/countryside_sunny_city.ogg",
	"countryside_hot": "music/countryside_sunny_city_climax.ogg",
	"village": "music/village_pure_raceway.ogg",
	"village_hot": "music/village_pure_raceway_climax.ogg",
}
const SFX := {
	"start": "sfx/start.ogg",
	"lap": "sfx/lap.ogg",
	"best_lap": "sfx/best_lap_jingle.ogg",
	"finish": "sfx/finish_jingle.ogg",
	"cheer": "sfx/cheer.wav",
	"failed": "sfx/failed.ogg",
	"boost": "sfx/boost.ogg",
	"bump": "sfx/bump.ogg",
	"land": "sfx/land.ogg",
	"splash": "sfx/splash.ogg",
	"thunder": "ambience/thunder.ogg",
	# Village life (world/village_life.gd): the roadside crowd's cheer, cow bells on the alp.
	"crowd": "sfx/cheer.wav",
	"cowbell": "racers/horn_bell.wav",
}
const AMBIENCE := {
	"countryside": "ambience/countryside_birds.ogg",
	"village": "ambience/village_fountain.ogg",
	"rain": "ambience/rain_loop.ogg",
	"wind": "ambience/wind_loop.ogg",
}
# Per-sound level (dB) and minimum gap between plays (s).
const LEVEL := {"start": -10.0, "lap": -8.0, "best_lap": -4.0, "finish": -2.0, "cheer": -6.0,
	"failed": -6.0, "boost": -6.0, "bump": -8.0, "land": -8.0, "splash": -4.0, "thunder": -3.0,
	"crowd": -15.0, "cowbell": -17.0}
const GAP := {"start": 0.5, "lap": 0.3, "best_lap": 3.0, "finish": 3.0, "cheer": 3.0,
	"failed": 2.0, "boost": 0.15, "bump": 0.4, "land": 0.3, "splash": 0.5, "thunder": 0.0,
	"crowd": 2.5, "cowbell": 0.8}

const RACERS_DIR := "racers/"   # engine_<name>.wav loops and horn_<name>.wav one-shots
const HORN_DB := -4.0
const HORN_GAP := 0.6           # any horn; the same racer honks at most every 3 s
const HORN_RACER_GAP := 3.0

const DECIDE_HZ := 10.0
const HOLD_S := 4.0             # a music state must be wanted this long before it switches
const FADE_S := 2.0             # music crossfade
const HOT_STRETCH := 0.8        # countryside: progress() past this is the final stretch
const PADDOCK_DB := -4.5        # paddock music sits lower (about 60%)
const DUCK_DB := -6.0           # music under a finish
const DUCK_S := 2.0
const VOICES := 12
const ALP_SEGS := ["farm", "cobbles", "ridge", "alpbach"]   # village: where cow bells ring
const COWBELL_EVERY := Vector2(2.0, 5.5)
const ENGINES := 3
const ENGINE_RANGE := 45.0      # metres from the camera where an engine fades out
const DRY_CUTOFF := 20000.0
const STORM_CUTOFF := 4000.0

var sim
var track := ""
var camera: Node3D
var follow_run := ""            # set by main each frame
## player_id -> RacerSpec.sound ({engine, pitch, horn}) or {} if the racer has none. Set by main.
var sound_of: Callable

var _streams := {}              # key -> AudioStream
var _music: Array[AudioStreamPlayer] = []   # two decks for crossfades
var _deck := 0
var _music_key := ""
var _want_key := ""
var _want_since := 0.0
var _duck := 0.0                # seconds of duck left
var _voices: Array[AudioStreamPlayer] = []
var _last := {}                 # sound -> time it last played
var _engines: Array[AudioStreamPlayer] = []
var _amb := {}                  # key -> AudioStreamPlayer
var _decide_t := 0.0
var _now := 0.0
var _thunder_t := 20.0
var _was_air := false
var _was_water := false
var _rng := RandomNumberGenerator.new()
var _cowbell_at := 0.0
var _horn_last := {}            # run_id -> time of its last horn
var _no_sound := {}             # player_id -> true once its missing sound was logged
var _music_bus := -1
var _banner: Label


## Returns false (after showing the error) if a file is missing or the buses could not be set up.
func setup(p_sim, p_track: String, p_camera: Node3D, mute: bool) -> bool:
	sim = p_sim
	track = p_track
	camera = p_camera
	var problems: Array[String] = []
	var err := AudioSettings.ensure_buses()
	if err != "":
		problems.append(err)
	_music_bus = AudioServer.get_bus_index("Music")
	if not MUSIC.has(track) or not AMBIENCE.has(track):
		problems.append("no music or ambience for track \"%s\"" % track)
	for table in [MUSIC, SFX, AMBIENCE]:
		for key in table:
			var path: String = DIR + table[key]
			var s := load(path) as AudioStream
			if s == null:
				problems.append("missing audio file %s" % path)
			_streams[_key(table, key)] = s
	for kind in ["engine", "horn"]:
		var names := KitCatalog.names(kind + "Sounds")
		if names.is_empty():
			problems.append("racer kit has no %sSounds (%s)" % [kind, KitCatalog.load_error()])
		for n in names:
			var path: String = DIR + RACERS_DIR + "%s_%s.wav" % [kind, n]
			var s := load(path) as AudioStream
			if s == null:
				problems.append("missing audio file %s" % path)
			_streams["%s:%s" % [kind, n]] = s
	if not problems.is_empty():
		_show_errors(problems)
		return false
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_music.append(p)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		_voices.append(p)
	for i in ENGINES:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		p.volume_db = -80.0
		add_child(p)
		_engines.append(p)
	for key in [track, "rain", "wind"]:
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		p.stream = _streams["amb:" + key]
		p.volume_db = -80.0
		add_child(p)
		p.play()
		_amb[key] = p
	_rng.randomize()
	if mute:
		AudioServer.set_bus_mute(0, true)
	_switch_music("paddock")
	return true


func _key(table: Dictionary, key: String) -> String:
	return ("music:" if table == MUSIC else "amb:" if table == AMBIENCE else "sfx:") + key


## Sim outbox events, called by main before it forwards them to the server.
func on_event(type: String, pl: Dictionary) -> void:
	if _music.is_empty():
		return
	match type:
		"game.run.started":
			_play("start")
		"game.run.lap":
			if pl.get("isBest", false) and int(pl["lap"]) > 1:
				_play("best_lap")
			elif pl["runId"] == follow_run:
				_play("lap")
		"game.run.finished":
			_horn(pl["runId"])
			if _play("finish"):
				_play("cheer")
				_duck = DUCK_S
		"game.run.failed":
			_play("failed")
		"sim.boost":
			if _near(pl["runId"]):
				_play("boost", 1.15 if pl["kind"] == "boost_perfect" else 0.9)
				if pl["kind"] == "boost_perfect":
					_horn(pl["runId"])
		"sim.bump":
			if _near(pl["hitter"]) or _near(pl["victim"]):
				_play("bump")


func _physics_process(_delta: float) -> void:
	if _music.is_empty():
		return
	# Landing and splash edges of the followed racer only, every tick so short hops count.
	var r: Racer = sim.by_run.get(follow_run)
	if r == null:
		_was_air = false
		_was_water = false
		return
	if _was_air and not r.airborne:
		_play("land")
	if r.in_water and not _was_water:
		_play("splash")
	_was_air = r.airborne
	_was_water = r.in_water


func _process(delta: float) -> void:
	if _music.is_empty():
		return
	_now += delta
	_duck = maxf(0.0, _duck - delta)
	_fade_music(delta)
	_decide_t -= delta
	if _decide_t > 0.0:
		return
	_decide_t = 1.0 / DECIDE_HZ
	_decide_music()
	_update_engines()
	_update_weather()
	_update_alp()


# ---------------------------------------------------------------- village life

## The roadside crowd cheers the kart the music follows (world/village_life.gd).
func crowd_cheer() -> void:
	if not _music.is_empty():
		_play("crowd", _rng.randf_range(0.95, 1.1))


## Cow bells now and then while the followed kart is out on the alp (village).
func _update_alp() -> void:
	if track != "village" or _now < _cowbell_at:
		return
	var r: Racer = sim.by_run.get(follow_run)
	if r == null or not r.seg_id in ALP_SEGS:
		return
	_play("cowbell", _rng.randf_range(0.85, 1.2))
	_cowbell_at = _now + _rng.randf_range(COWBELL_EVERY.x, COWBELL_EVERY.y)


# ---------------------------------------------------------------- music

func _decide_music() -> void:
	var want := "paddock"
	if not sim.racers.is_empty():
		want = track + ("_hot" if _is_hot() else "")
	if want != _want_key:
		_want_key = want
		_want_since = _now
	if want != _music_key and _now - _want_since >= HOLD_S:
		_switch_music(want)


## The racer on camera is on its final lap (loop) or final stretch (point to point).
func _is_hot() -> bool:
	var r: Racer = sim.by_run.get(follow_run)
	if r == null:
		return false
	if r.looping:
		return r.laps_max > 0 and r.lap >= r.laps_max - 1
	return r.progress() >= HOT_STRETCH


func _switch_music(key: String) -> void:
	print("audio: music %s -> %s (%d racing)" % [_music_key if _music_key != "" else "-", key, sim.racers.size()])
	_music_key = key
	_want_key = key
	_deck = 1 - _deck
	var p := _music[_deck]
	p.stream = _streams["music:" + key]
	p.volume_db = -40.0
	# Same tune at another tempo: start at the same fraction of the loop so the switch flows.
	var other := _music[1 - _deck]
	var from := 0.0
	if other.playing and other.stream != null and key.trim_suffix("_hot") == _music_base(other.stream):
		from = other.get_playback_position() / other.stream.get_length() * p.stream.get_length()
	p.play(from)


func _music_base(s: AudioStream) -> String:
	for k in MUSIC:
		if _streams["music:" + k] == s:
			return String(k).trim_suffix("_hot")
	return ""


func _fade_music(delta: float) -> void:
	var target := (PADDOCK_DB if _music_key == "paddock" else 0.0) + (DUCK_DB if _duck > 0.0 else 0.0)
	var step := 40.0 * delta / FADE_S  # dB per frame
	var cur := _music[_deck]
	cur.volume_db = move_toward(cur.volume_db, target, step)
	var old := _music[1 - _deck]
	if old.playing:
		old.volume_db = move_toward(old.volume_db, -40.0, step)
		if old.volume_db <= -40.0:
			old.stop()


# ---------------------------------------------------------------- one-shots

## Plays a one-shot unless it played too recently or all voices are busy (dropped, not queued).
func _play(key: String, pitch: float = 1.0) -> bool:
	if _now - float(_last.get(key, -100.0)) < GAP[key]:
		return false
	for p in _voices:
		if not p.playing:
			_last[key] = _now
			p.stream = _streams["sfx:" + key]
			p.volume_db = LEVEL[key]
			p.pitch_scale = pitch
			p.play()
			return true
	return false


## The followed racer, or one of the racers the engines are voicing.
func _near(run_id: String) -> bool:
	if run_id == follow_run:
		return true
	for p in _engines:
		if p.get_meta("run", "") == run_id:
			return true
	return false


## A racer's horn, if it has a sound and has not honked lately.
func _horn(run_id: String) -> void:
	var r: Racer = sim.by_run.get(run_id)
	if r == null:
		return
	var so := _sound(r)
	if so.is_empty() or _now - float(_horn_last.get(run_id, -100.0)) < HORN_RACER_GAP:
		return
	if _now - float(_last.get("horn", -100.0)) < HORN_GAP:
		return
	for p in _voices:
		if not p.playing:
			_last["horn"] = _now
			_horn_last[run_id] = _now
			p.stream = _streams["horn:" + String(so["horn"])]
			p.volume_db = HORN_DB
			p.pitch_scale = float(so["pitch"])
			p.play()
			return


## The racer's RacerSpec.sound, or {} (logged once per player) when it has none.
func _sound(r: Racer) -> Dictionary:
	var so: Dictionary = sound_of.call(r.player_id) if sound_of.is_valid() else {}
	if so.is_empty() or not _streams.has("engine:" + String(so.get("engine", ""))) \
			or not _streams.has("horn:" + String(so.get("horn", ""))) or not so.has("pitch"):
		if not _no_sound.has(r.player_id):
			_no_sound[r.player_id] = true
			push_error("audio: racer %s has no usable sound in its spec (%s); its engine stays silent" % [r.player_id, JSON.stringify(so)])
		return {}
	return so


# ---------------------------------------------------------------- engines

func _update_engines() -> void:
	var cam := camera.global_position
	var picks: Array = []
	var followed: Racer = sim.by_run.get(follow_run)
	if followed != null:
		picks.append(followed)
	var rest: Array = []
	for o in sim.racers:
		if o != followed:
			rest.append([cam.distance_squared_to(o.world_pos()), o])
	rest.sort_custom(func(a, b): return a[0] < b[0])
	for e in rest:
		if picks.size() >= ENGINES:
			break
		picks.append(e[1])
	for i in ENGINES:
		var p := _engines[i]
		if i >= picks.size():
			p.set_meta("run", "")
			if p.playing:
				p.stop()
			continue
		var r: Racer = picks[i]
		var so := _sound(r)
		if so.is_empty():
			p.set_meta("run", r.run_id)  # still counts as near for boosts and bumps
			if p.playing:
				p.stop()
			continue
		var stream: AudioStream = _streams["engine:" + String(so["engine"])]
		if p.stream != stream:
			p.stop()
			p.stream = stream
		var dist := cam.distance_to(r.world_pos())
		var near := clampf(1.0 - dist / ENGINE_RANGE, 0.0, 1.0)
		var speed := clampf(r.v / maxf(1.0, r.top), 0.0, 1.2)
		p.set_meta("run", r.run_id)
		p.pitch_scale = float(so["pitch"]) * (0.8 + 0.5 * speed + (0.1 if r.airborne else 0.0))
		p.volume_db = linear_to_db(maxf(0.0001, near * (0.35 + 0.4 * speed))) - (3.0 if i > 0 else 0.0)
		if near <= 0.0:
			if p.playing:
				p.stop()
		elif not p.playing:
			p.play(_rng.randf() * p.stream.get_length())  # desync the shared loop


# ---------------------------------------------------------------- weather

func _update_weather() -> void:
	var rain: float = sim.weather.rain_intensity()
	var wind: float = sim.weather.wind_strength()
	_amb_level(track, 0.6 * (1.0 - 0.7 * rain))
	_amb_level("rain", rain)
	_amb_level("wind", 0.8 * wind)
	var lp := AudioServer.get_bus_effect(_music_bus, AudioSettings.LOWPASS_SLOT) as AudioEffectLowPassFilter
	var wet := rain > 0.02
	AudioServer.set_bus_effect_enabled(_music_bus, AudioSettings.LOWPASS_SLOT, wet)
	if wet:
		lp.cutoff_hz = lerpf(DRY_CUTOFF, STORM_CUTOFF, clampf(rain, 0.0, 1.0))
	_thunder_t -= 1.0 / DECIDE_HZ
	if _thunder_t <= 0.0:
		_thunder_t = _rng.randf_range(15.0, 40.0)
		if rain > 0.6 and wind > 0.4:
			_play("thunder", _rng.randf_range(0.85, 1.1))


func _amb_level(key: String, lin: float) -> void:
	var p: AudioStreamPlayer = _amb[key]
	p.volume_db = linear_to_db(maxf(0.0001, lin))
	p.stream_paused = lin < 0.01   # a silent loop costs no decode


# ---------------------------------------------------------------- errors

func _show_errors(problems: Array[String]) -> void:
	for t in problems:
		push_error("audio: " + t)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_banner = Label.new()
	_banner.text = I18n.t("audio.error") + "\n" + "\n".join(problems)
	_banner.add_theme_font_size_override("font_size", 28)
	_banner.add_theme_color_override("font_color", Color(1, 0.25, 0.2))
	_banner.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_banner.position.y -= 160
	layer.add_child(_banner)
