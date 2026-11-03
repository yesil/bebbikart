# Big-screen audio: adaptive music, stingers, engines and weather ambience.
# There is no shared race (racers are released from a queue and finish one by one), so the
# music follows the screen: paddock music while no one races, the track's tune while racers are
# out, and its faster "climax" version while the racer on camera is on its final lap (or the
# final stretch on the countryside). Per-racer moments are rate-limited stingers on top.
# A lap's end gets one cue for its verdict (main.gd _verdict): the crown's fanfare for a new
# record or champion, a climbing one for a personal best, a short one for any other finish, a soft
# "aww" for OOPS!; the session's podium gets the crown's fanfare in full. Cues never stack: a
# bigger one cuts a smaller one off, a smaller one coming during a bigger one is left out (its
# racer still honks). The music dips under a cue for its whole length (an Amplify on the Music
# bus, audio_settings.gd), the crowd cheers just after the hit and the racer's horn comes once the
# fanfare has had its say. The cues are rendered by scripts/race-end-cues.js.
# Each racer sounds like its ride: RacerSpec.sound picks the engine loop (putter, rocket, hooves…),
# its pitch, and a horn played on a perfect boost and at the finish. A racer without a sound
# (older specs) is logged once and stays silent; nothing is guessed.
# CPU: 2 music streams, 3 engine voices (only the followed racer and the 2 nearest the camera), 3 ambience loops, a pool of 12 one-shots,
# 2 cue players, a low-pass and an amplify (the dip) on the Music bus. Decisions run at 10 Hz.
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
	"best_lap": "sfx/end_best_lap.ogg",
	"cheer": "sfx/cheer.wav",
	"failed": "sfx/failed.ogg",
	"boost": "sfx/boost.ogg",
	"bump": "sfx/bump.ogg",
	"land": "sfx/land.ogg",
	"splash": "sfx/splash.ogg",
	"thunder": "ambience/thunder.ogg",
	# Village surprises (sim/obstacles.gd): a kart hits a cow, a sheep or a cheese wheel; a cow
	# bell when a cow turns up. Village life (world/village_life.gd): the roadside crowd's cheer,
	# cow bells on the alp.
	"moo": "racers/horn_moo.wav",
	"baa": "sfx/sheep_baa.ogg",
	"boing": "racers/horn_boing.wav",
	"crowd": "sfx/cheer.wav",
	"cowbell": "racers/horn_bell.wav",
}
const AMBIENCE := {
	"countryside": "ambience/countryside_birds.ogg",
	"village": "ambience/village_fountain.ogg",
	"rain": "ambience/rain_loop.ogg",
	"wind": "ambience/wind_loop.ogg",
}
# The end-of-lap and podium cues (one plays at a time, see END_CUES).
const CUES := {
	"oops": "sfx/end_oops.ogg",
	"finish": "sfx/end_finish.ogg",
	"best": "sfx/end_best.ogg",
	"record": "sfx/end_record.ogg",
	"podium": "sfx/end_podium.ogg",
}
# Per cue: rank (a higher one cuts a lower one off), level (dB), start (s after the lap ends),
# music dip (dB, held for the cue's length), crowd cheers [[s, pitch]] and the racer's horn (s,
# -1: none). The times put the crowd just after the hit and the horn after the fanfare's last
# chord or button, where it doesn't fight the tune.
const END_CUES := {
	"oops": {"rank": 1, "db": -2.0, "start": 0.15, "dip": -8.0, "cheer": [], "horn": -1.0},
	"finish": {"rank": 2, "db": -0.5, "start": 0.0, "dip": -9.0, "cheer": [[0.25, 1.0]], "horn": 1.75},
	"best": {"rank": 3, "db": 0.5, "start": 0.0, "dip": -11.0, "cheer": [[0.2, 1.0]], "horn": 2.1},
	"record": {"rank": 4, "db": 1.5, "start": 0.0, "dip": -15.0, "cheer": [[0.15, 0.94], [0.4, 1.06]], "horn": 4.1},
	"podium": {"rank": 5, "db": 1.5, "start": 0.0, "dip": -15.0, "cheer": [[0.2, 0.94], [0.5, 1.06], [4.6, 1.0]], "horn": -1.0},
}
## main.gd's lap verdicts -> the cue they get.
const VERDICT_CUE := {"champion": "record", "record": "record", "best": "best", "keeps": "finish",
	"short": "finish", "failed": "oops"}
# Per-sound level (dB) and minimum gap between plays (s). The cheer file is quiet (about -29
# LUFS), hence its boost; the roadside crowd ("crowd") is the same file kept far back.
const LEVEL := {"start": -10.0, "lap": -8.0, "best_lap": -3.0, "cheer": 8.0,
	"failed": -6.0, "boost": -6.0, "bump": -8.0, "land": -8.0, "splash": -4.0, "thunder": -3.0,
	"moo": -3.0, "baa": -4.0, "boing": -5.0, "cowbell": -15.0, "coin": -9.0, "crowd": -15.0}
const GAP := {"start": 0.5, "lap": 0.3, "best_lap": 1.0, "cheer": 0.0,
	"failed": 0.3, "boost": 0.15, "bump": 0.4, "land": 0.3, "splash": 0.5, "thunder": 0.0,
	"moo": 0.8, "baa": 0.4, "boing": 0.3, "cowbell": 0.8, "coin": 0.05, "crowd": 2.5}

const RACERS_DIR := "racers/"   # engine_<name>.wav loops and horn_<name>.wav one-shots
const HORN_DB := -4.0
const HORN_GAP := 0.6           # any horn; the same racer honks at most every 3 s
const HORN_RACER_GAP := 3.0

const DECIDE_HZ := 10.0
const HOLD_S := 4.0             # a music state must be wanted this long before it switches
const FADE_S := 2.0             # music crossfade
const HOT_STRETCH := 0.8        # countryside: progress() past this is the final stretch
const PADDOCK_DB := -4.5        # paddock music sits lower (about 60%)
const DIP_IN := 100.0           # dB/s the music dips under a cue (15 dB in 0.15 s)
const DIP_OUT := 10.0           # dB/s it comes back (15 dB in 1.5 s)
const DIP_TAIL_S := 0.5         # the music starts coming back this long before a cue ends
const BEST_LAP_DIP := -5.0
const CUE_CUT := 300.0          # dB/s a cue fades out when a bigger one cuts it off
const LOG_MAX := 400            # cue_log entries kept
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
var _dip: AudioEffectAmplify    # on the Music bus: the dip under a cue
var _dip_depth := 0.0           # dB the music dips to while a cue holds it
var _dip_until := 0.0           # the dip holds until then (and while a music switch is pending)
var _voices: Array[AudioStreamPlayer] = []
var _cues: Array[AudioStreamPlayer] = []   # two, so a cue cut off can fade under the next
var _cue := 0                   # the deck of the cue playing (or last played)
var _cue_rank := 0
var _cue_until := 0.0           # when the cue playing ends
var _cue_id := 0                # numbers each cue, so a cut one's crowd and horn are dropped too
var _later: Array = []          # [{at, cue, what, fn}] crowd cheers and horns placed after a cue's hit
## What the end cues did, for tools/end_sound_check.gd: {t, what (run_end, cue, left_out, cheer,
## horn, start), verdict, kind, run, rank, len, id}. The last LOG_MAX entries.
var cue_log: Array = []
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
	if _music_bus == -1:
		problems.append("no Music bus")
	else:
		_dip = AudioServer.get_bus_effect(_music_bus, AudioSettings.DIP_SLOT) as AudioEffectAmplify
		if _dip == null:
			problems.append("the Music bus has no dip (AudioEffectAmplify in slot %d)" % AudioSettings.DIP_SLOT)
		else:
			_dip.volume_db = 0.0  # a scene reload may leave it dipped
	if not MUSIC.has(track) or not AMBIENCE.has(track):
		problems.append("no music or ambience for track \"%s\"" % track)
	for table in [MUSIC, SFX, AMBIENCE, CUES]:
		for key in table:
			var path: String = DIR + table[key]
			var s := load(path) as AudioStream
			if s == null:
				problems.append("missing audio file %s" % path)
			_streams[_key(table, key)] = s
	for key in CUES:
		if not END_CUES.has(key):
			problems.append("cue \"%s\" has no END_CUES entry" % key)
	for v in VERDICT_CUE:
		if not END_CUES.has(VERDICT_CUE[v]):
			problems.append("verdict \"%s\" has no cue" % v)
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
	# A chocolate coin's "bling" (sim/coins.gd) is made here, not loaded: two quick bell notes.
	_streams["sfx:coin"] = _coin_sound()
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
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		_cues.append(p)
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
	if table == MUSIC:
		return "music:" + key
	if table == AMBIENCE:
		return "amb:" + key
	if table == CUES:
		return "cue:" + key
	return "sfx:" + key


## Sim outbox events, called by main before it forwards them to the server. A run's end is not
## here: main calls run_end with the lap's verdict.
func on_event(type: String, pl: Dictionary) -> void:
	if _music.is_empty():
		return
	match type:
		"game.run.started":
			_play("start")
		"game.run.lap":
			# The lap that ends the run gets its verdict's cue (run_end), nothing here.
			var r: Racer = sim.by_run.get(pl["runId"])
			if r == null or r.state == "finished":
				return
			if pl.get("isBest", false) and int(pl["lap"]) > 1:
				if _play("best_lap"):
					_dip_for(BEST_LAP_DIP, 0.6)
			elif pl["runId"] == follow_run:
				_play("lap")
		"sim.boost":
			if _near(pl["runId"]):
				_play("boost", 1.15 if pl["kind"] == "boost_perfect" else 0.9)
				if pl["kind"] == "boost_perfect":
					_horn(pl["runId"])
		"sim.bump":
			if _near(pl["hitter"]) or _near(pl["victim"]):
				_play("bump")
		"sim.obstacle":
			_play("bump")
			match String(pl["kind"]):
				"cow":
					_play("moo", _rng.randf_range(0.9, 1.05))
					_play("cowbell", 1.3)    # its bell clangs as it spins
				"sheep":
					_play("baa", _rng.randf_range(0.95, 1.15))
				"cheese":
					_play("boing", 0.9)
				"hay":
					_play("land", 0.7)
		"sim.obstacle_spawned":
			if pl["kind"] == "cow":
				_play("cowbell", _rng.randf_range(0.95, 1.1))
		"sim.coin":
			if _near(pl["runId"]):
				# Each coin of a line a little higher; the whole line surges like a boost arrow.
				_play("coin", 1.0 + 0.07 * (int(pl["inLine"]) - 1))
				if pl["lineDone"]:
					_play("boost", 1.15)


## A run ended (game.run.finished or game.run.failed), judged by main.gd _verdict: champion,
## record, best, keeps, short or failed. Plays that verdict's cue with its crowd and horn.
func run_end(run_id: String, verdict: String) -> void:
	if _music.is_empty():
		return
	if not VERDICT_CUE.has(verdict):
		push_error("audio: run %s ended with an unknown verdict \"%s\" (known: %s)" % [run_id, verdict, ", ".join(VERDICT_CUE.keys())])
		return
	_log({"what": "run_end", "run": run_id, "verdict": verdict})
	if verdict == "failed":
		_play("failed")  # the bump of the fall, at once; the "aww" follows
	_cue_play(VERDICT_CUE[verdict], run_id)


## The session's podium came up (ui/race_hud.gd): the crown's fanfare in full.
func podium() -> void:
	if not _music.is_empty():
		_cue_play("podium", "")


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
	_run_later()
	_update_dip(delta)
	_fade_cut_cue(delta)
	_fade_music(delta)
	_decide_t -= delta
	if _decide_t > 0.0:
		return
	_decide_t = 1.0 / DECIDE_HZ
	_decide_music()
	_update_engines()
	_update_weather()
	_update_alp()


# ---------------------------------------------------------------- end cues

## Plays a cue unless a bigger (or as big) one is still playing; a smaller one playing is cut
## off. The crowd and the horn are placed after the hit; the music dips for the cue's length.
func _cue_play(kind: String, run_id: String) -> void:
	var c: Dictionary = END_CUES[kind]
	var horn: Dictionary = _horn_sound(run_id) if run_id != "" and float(c["horn"]) >= 0.0 else {}
	if _now < _cue_until and int(c["rank"]) <= _cue_rank:
		# A bigger moment is still sounding: this racer only honks, once it is over.
		print("audio: %s cue for %s left out under a playing cue (rank %d)" % [kind, run_id, _cue_rank])
		_log({"what": "left_out", "kind": kind, "run": run_id, "rank": int(c["rank"]), "id": _cue_id})
		if not horn.is_empty():
			_later.append({"at": _cue_until, "cue": _cue_id, "what": "horn", "fn": _horn_play.bind(run_id, horn)})
		return
	if _now < _cue_until:
		# A smaller cue is sounding (or about to start): it fades out under this one
		# (_fade_cut_cue), and its crowd, horn or delayed start are dropped.
		_cues[_cue].set_meta("cut", true)
		var cut_id := _cue_id
		_later = _later.filter(func(e): return int(e["cue"]) != cut_id)
	_cue_id += 1
	_cue = 1 - _cue
	var p := _cues[_cue]
	var stream: AudioStream = _streams["cue:" + kind]
	var start := float(c["start"])
	var length := stream.get_length()
	p.set_meta("cut", false)
	p.stream = stream
	p.volume_db = float(c["db"])
	p.pitch_scale = 1.0
	_cue_rank = int(c["rank"])
	_cue_until = _now + start + length
	if start > 0.0:
		_later.append({"at": _now + start, "cue": _cue_id, "what": "start", "fn": p.play})
	else:
		p.play()
	for ch in c["cheer"]:
		_later.append({"at": _now + float(ch[0]), "cue": _cue_id, "what": "cheer", "fn": _start.bind("cheer", LEVEL["cheer"], float(ch[1]))})
	if not horn.is_empty():
		_later.append({"at": _now + float(c["horn"]), "cue": _cue_id, "what": "horn", "fn": _horn_play.bind(run_id, horn)})
	_dip_for(float(c["dip"]), start + length - DIP_TAIL_S)
	_log({"what": "cue", "kind": kind, "run": run_id, "rank": int(c["rank"]), "len": start + length, "id": _cue_id})
	print("audio: %s cue%s at %.2f s (%.1f s, music %+.0f dB)" % [kind, " for " + run_id if run_id != "" else "", _now, length, float(c["dip"])])


func _log(e: Dictionary) -> void:
	e["t"] = _now
	cue_log.append(e)
	if cue_log.size() > LOG_MAX:
		cue_log.pop_front()


## Runs the crowd cheers and horns that are due.
func _run_later() -> void:
	if _later.is_empty():
		return
	var due: Array = []
	var keep: Array = []
	for e in _later:
		if _now >= float(e["at"]):
			due.append(e)
		else:
			keep.append(e)
	_later = keep
	for e in due:
		(e["fn"] as Callable).call()
		_log({"what": e["what"], "id": e["cue"]})


## A cue cut off by a bigger one fades out fast instead of stopping mid-note.
func _fade_cut_cue(delta: float) -> void:
	for p in _cues:
		if p.playing and p.get_meta("cut", false):
			p.volume_db = move_toward(p.volume_db, -60.0, CUE_CUT * delta)
			if p.volume_db <= -60.0:
				p.stop()


## Dips the music to depth_db (or keeps a deeper dip) for hold seconds.
func _dip_for(depth_db: float, hold: float) -> void:
	if _now >= _dip_until:
		_dip_depth = depth_db
	else:
		_dip_depth = minf(_dip_depth, depth_db)
	_dip_until = maxf(_dip_until, _now + hold)


## The dip holds while its cue plays, and while a music switch is pending, so the old tune
## doesn't swell back for a moment before the crossfade.
func _update_dip(delta: float) -> void:
	var dipped := _dip.volume_db < -0.05
	var switching := _want_key != _music_key and _now - _want_since < HOLD_S + 0.5
	var hold := _now < _dip_until or (dipped and switching)
	var target := _dip_depth if hold else 0.0
	_dip.volume_db = move_toward(_dip.volume_db, target, (DIP_IN if target < _dip.volume_db else DIP_OUT) * delta)


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
	var target := PADDOCK_DB if _music_key == "paddock" else 0.0
	var step := 40.0 * delta / FADE_S  # dB per frame
	var cur := _music[_deck]
	cur.volume_db = move_toward(cur.volume_db, target, step)
	var old := _music[1 - _deck]
	if old.playing:
		old.volume_db = move_toward(old.volume_db, -40.0, step)
		if old.volume_db <= -40.0:
			old.stop()


# ---------------------------------------------------------------- one-shots

## A chocolate coin's "bling": B5 then E6, a sine with a soft octave, each note dying away.
static func _coin_sound() -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * 0.26)
	var data := PackedByteArray()
	data.resize(n * 2)
	var step := 0.07
	for i in n:
		var t := float(i) / rate
		var second := t >= step
		var f := 1318.5 if second else 987.8
		var tn := t - step if second else t
		var env := minf(1.0, tn / 0.003) * exp(-tn * (11.0 if second else 22.0))
		var a := (sin(TAU * f * t) * 0.7 + sin(TAU * f * 2.0 * t) * 0.18) * env
		data.encode_s16(i * 2, int(clampf(a, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


## Plays a one-shot unless it played too recently or all voices are busy (dropped, not queued).
func _play(key: String, pitch: float = 1.0) -> bool:
	if _now - float(_last.get(key, -100.0)) < GAP[key]:
		return false
	if _start(key, LEVEL[key], pitch):
		_last[key] = _now
		return true
	return false


## Starts a one-shot on a free voice; false if all are busy.
func _start(key: String, db: float, pitch: float) -> bool:
	for p in _voices:
		if not p.playing:
			p.stream = _streams["sfx:" + key]
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return true
	print("audio: all %d voices busy, %s left out" % [VOICES, key])
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
	var h := _horn_sound(run_id)
	if not h.is_empty():
		_horn_play(run_id, h)


## A racer's horn stream and pitch ({} if it has no sound), looked up now: a horn placed after
## a cue plays when the racer may already have left the sim.
func _horn_sound(run_id: String) -> Dictionary:
	var r: Racer = sim.by_run.get(run_id)
	if r == null:
		return {}
	var so := _sound(r)
	if so.is_empty():
		return {}
	return {"stream": _streams["horn:" + String(so["horn"])], "pitch": float(so["pitch"])}


func _horn_play(run_id: String, h: Dictionary) -> void:
	if _now - float(_horn_last.get(run_id, -100.0)) < HORN_RACER_GAP:
		return
	if _now - float(_last.get("horn", -100.0)) < HORN_GAP:
		return
	for p in _voices:
		if not p.playing:
			_last["horn"] = _now
			_horn_last[run_id] = _now
			p.stream = h["stream"]
			p.volume_db = HORN_DB
			p.pitch_scale = h["pitch"]
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
