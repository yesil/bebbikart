extends RefCounted
## Real network client (game.md "Connection"): a WebSocketPeer to the Bun server, polled from
## the 60 Hz loop. Same shape as mock_net.gd so main.gd can use either:
##   poll(dt, free_slots) -> Array of server -> game envelopes (contracts §7)
##   send(type, payload)  for game -> server messages
## Reconnects on its own. `welcome` is unpacked into roster.updated + run.start messages, and
## config updates are merged into the shared config dictionary (the sim holds the same one).
## welcome (its config only) and config.updated are passed on too: main.gd syncs the language.

const Messages = preload("res://net/messages.gd")

const RECONNECT_S := 2.0

var url := "ws://localhost:8080/ws"
var game_key := ""
var cfg: Dictionary
var log_mode := "summary"   # none | summary | full
var status := "connecting"  # connecting | online | offline (shown in the overlay)
var session_status := "?"   # idle | running | ended, from welcome and session.updated
var course = null           # unused; mock_net uses it
var players: Array = []     # unused; mock_net fills it at start-up
var sent_counts := {}
var finished := 0
var failed := 0

var _ws := WebSocketPeer.new()
var _open := false
var _retry_t := 0.0
var _inbox: Array = []
var _active := {}           # runId -> true, runs started and not yet reported back
var _nicks := {}


func _init(config: Dictionary, p_url: String, p_game_key: String) -> void:
	cfg = config
	url = p_url
	game_key = p_game_key
	_connect()


## HTTP base of the server, e.g. "http://localhost:8080", for assets and render uploads.
func http_base() -> String:
	var u := url.replace("wss://", "https://").replace("ws://", "http://")
	var i := u.find("/", u.find("//") + 2)
	return u if i < 0 else u.substr(0, i)


func _connect() -> void:
	_ws = WebSocketPeer.new()
	# A roster of 20 racers with specs is well over the 64 KB default.
	_ws.inbound_buffer_size = 4 * 1024 * 1024
	_ws.outbound_buffer_size = 1024 * 1024
	_ws.max_queued_packets = 4096
	var err := _ws.connect_to_url(url)
	status = "connecting"
	if err != OK:
		push_warning("ServerNet: can't connect to %s (%d)" % [url, err])
		_ws = null
		_retry_t = RECONNECT_S


func poll(dt: float, _free_slots: int) -> Array:
	if _ws == null:
		_retry_t -= dt
		if _retry_t <= 0.0:
			_connect()
		return _take()
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _open:
				_open = true
				status = "online"
				print("ServerNet: connected to ", url)
				_ws.send_text(JSON.stringify(Messages.make_msg("hello", {"role": "game", "gameKey": game_key})))
			while _ws.get_available_packet_count() > 0:
				_receive(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			if _open or status == "connecting":
				var code := _ws.get_close_code()
				if _open:
					push_error("ServerNet: disconnected from %s (%d %s), retrying every %d s" % [url, code, _ws.get_close_reason(), RECONNECT_S])
				else:
					push_error("ServerNet: can't reach %s, retrying every %d s (is the server running?)" % [url, RECONNECT_S])
				if code == 4001:
					push_error("ServerNet: server refused the game key; check --game-key / BK_GAME_KEY")
			_open = false
			status = "offline"
			_ws = null
			_retry_t = RECONNECT_S
			# The server aborts our runs when we drop; stop racing them here too.
			for run_id in _active.keys():
				_inbox.append(Messages.make_msg(Messages.RUN_ABORT, {"runId": run_id, "reason": "disconnected"}))
			_active.clear()
	return _take()


func _take() -> Array:
	var out := _inbox
	_inbox = []
	return out


func _receive(text: String) -> void:
	var msg = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY or not msg.has("type"):
		push_error("ServerNet: bad message " + text.left(200))
		return
	var type: String = msg["type"]
	var pl = msg.get("payload", {})
	if log_mode == "full":
		print("[server->game] ", type, " ", text.left(300))
	match type:
		Messages.WELCOME:
			cfg.merge(pl.get("config", {}), true)
			_inbox.append(Messages.make_msg(Messages.WELCOME, {"config": pl.get("config", {})}))
			_inbox.append(Messages.make_msg(Messages.ROSTER_UPDATED, pl.get("roster", [])))
			for rs in pl.get("activeRuns", []):
				_active[rs["runId"]] = true
				_inbox.append(Messages.make_msg(Messages.RUN_START, rs))
			session_status = String(pl.get("session", {}).get("status", "?"))
			print("ServerNet: welcome, %d racers, session %s" % [(pl.get("roster", []) as Array).size(), pl.get("session", {}).get("status", "?")])
		"config.updated":
			cfg.merge(pl, true)
			_inbox.append(msg)
		"session.updated":
			session_status = String(pl.get("status", "?"))
			_inbox.append(msg)
		"run.start":
			_active[pl["runId"]] = true
			_inbox.append(msg)
		"error":
			push_error("ServerNet: server error %s: %s" % [pl.get("code", "?"), pl.get("message", "")])
			_inbox.append(msg)  # the options menu shows refusals (refId = the message we sent)
		_:
			_inbox.append(msg)


## Game -> server.
func send(type: String, payload: Dictionary) -> void:
	sent_counts[type] = int(sent_counts.get(type, 0)) + 1
	match type:
		Messages.GAME_RUN_FINISHED:
			finished += 1
			_active.erase(payload.get("runId", ""))
		Messages.GAME_RUN_FAILED:
			failed += 1
			_active.erase(payload.get("runId", ""))
	if not _open:
		return
	_ws.send_text(JSON.stringify(Messages.make_msg(type, payload)))
	if log_mode != "none" and (type == Messages.GAME_RUN_FINISHED or type == Messages.GAME_RUN_FAILED):
		var who := String(_nicks.get(payload.get("runId", ""), ""))
		if type == Messages.GAME_RUN_FINISHED:
			print("[game->server] %s finished %.2f s" % [who, int(payload["elapsedMs"]) / 1000.0])
		else:
			print("[game->server] %s failed %s in %s" % [who, payload["reason"], payload["section"]])


func run_gone(run_id: String) -> void:
	_active.erase(run_id)


func remember_run(run_id: String, nickname: String) -> void:
	_nicks[run_id] = nickname
