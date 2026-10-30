# Hello-world (M0): loads the shared kit catalog and says hello to the server.
# WS3 replaces this with the real game and its --mock mode.
extends Control

const SERVER_URL := "ws://localhost:8080/ws"

var _ws := WebSocketPeer.new()
var _said_hello := false

@onready var _label: Label = $Label


func _ready() -> void:
	var kit = JSON.parse_string(FileAccess.get_file_as_string("res://data/racer_kit.json"))
	if kit == null:
		_show("Could not read res://data/racer_kit.json. Run `bun run kit:export`.")
		return
	_show("BebbiKart — protocol v%d, %d ride bases in the kit\nConnecting to %s…" % [
		Protocol.PROTOCOL_VERSION, kit.rideBases.size(), SERVER_URL])
	var err := _ws.connect_to_url(SERVER_URL)
	if err != OK:
		_show("Could not connect to %s (error %d)" % [SERVER_URL, err])


func _process(_delta: float) -> void:
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _said_hello:
				_said_hello = true
				_send("hello", {"role": "game", "gameKey": OS.get_environment("BK_GAME_KEY")})
				_show("Connected to %s" % SERVER_URL)
			while _ws.get_available_packet_count() > 0:
				print("[ws] ", _ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			if _said_hello:
				_said_hello = false
				_show("Disconnected from server (%d %s)" % [_ws.get_close_code(), _ws.get_close_reason()])


func _send(type: String, payload: Dictionary) -> void:
	_ws.send_text(JSON.stringify({
		"v": Protocol.PROTOCOL_VERSION,
		"type": type,
		"id": "msg_%d" % Time.get_ticks_usec(),
		"ts": Time.get_datetime_string_from_system(true) + "Z",
		"payload": payload,
	}))


func _show(text: String) -> void:
	_label.text = text
	print(text)
