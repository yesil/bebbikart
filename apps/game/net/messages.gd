extends RefCounted
## Helpers around the generated res://net/protocol.gd (do not edit that file; it is
## generated from packages/shared). Envelope + id helpers per contracts §1/§7.


const ID_ALPHABET := "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

# Game -> Server message types (contracts §7)
const GAME_RUN_STARTED := "game.run.started"
const GAME_RUN_PROGRESS := "game.run.progress"
const GAME_RUN_SECTION := "game.run.section"
const GAME_RUN_LAP := "game.run.lap"
const GAME_RUN_FINISHED := "game.run.finished"
const GAME_RUN_FAILED := "game.run.failed"
const GAME_WEATHER := "game.weather"
const GAME_CAMERA := "game.camera"
# Server -> Game
const RUN_START := "run.start"
const RUN_BOOST := "run.boost"
const RUN_STOP := "run.stop"
const RUN_ABORT := "run.abort"
const RUN_WATCH := "run.watch"
const ROSTER_UPDATED := "roster.updated"
const WELCOME := "welcome"
const SESSION_UPDATED := "session.updated"
const LEADERBOARD_UPDATED := "leaderboard.updated"


static func default_config() -> Dictionary:
	return Protocol.DEFAULT_CONFIG.duplicate(true)


static func now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


static func make_id(prefix: String, rng: RandomNumberGenerator = null) -> String:
	var s := prefix + "_"
	for i in 12:
		var k := rng.randi_range(0, ID_ALPHABET.length() - 1) if rng != null else randi_range(0, ID_ALPHABET.length() - 1)
		s += ID_ALPHABET[k]
	return s


## Wraps a payload in the WS envelope: { v, type, id, ts, payload }. The payload is usually a
## Dictionary; roster.updated and leaderboard.updated carry a bare Array.
static func make_msg(type: String, payload: Variant) -> Dictionary:
	return {"v": Protocol.PROTOCOL_VERSION, "type": type, "id": make_id("msg"), "ts": now_iso(), "payload": payload}


## Star rule: integers, each 0..max, sum == total.
static func validate_stars(stars: Dictionary, cfg: Dictionary = Protocol.DEFAULT_CONFIG) -> bool:
	var total := 0
	for a in Protocol.ABILITIES:
		if not stars.has(a):
			return false
		var n := int(stars[a])
		if n < 0 or n > int(cfg["starsMaxPerAbility"]):
			return false
		total += n
	return total == int(cfg["starsTotal"])
