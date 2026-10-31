class_name KitCatalog
extends RefCounted
## The toy-part kit catalog, as seen by the game.
## Source of truth: packages/shared/src/racer-kit.js (contracts §5). `bun run kit:export`
## writes it to res://data/racer_kit.json, which is loaded here. FALLBACK mirrors the same
## names so the kit still works if the JSON is missing.
## Adding a part = add it to racer-kit.js + build it in kit_parts / kit_ride_parts + export.
## tools/check_catalog.gd fails if a catalog name has no Godot implementation.

const DATA_PATH := "res://data/racer_kit.json"
const PKG_DEFAULT_PATH := "res://data/pkg_default/spec.json"

const MOODS := ["happy", "excited", "determined", "dizzy", "sad", "cheering"]

## Every part name the Godot builder implements, by catalog list.
const IMPLEMENTED := {
	"bodyShapes": ["bean", "round", "tall", "box", "pear", "star"],
	"headShapes": ["round", "oval", "square", "wide", "drop"],
	"eyes": ["dots", "big_round", "sleepy", "googly", "one_eye", "visor"],
	"mouths": ["smile", "grin", "open", "fangs", "beak", "none"],
	"hairStyles": ["spiky", "curly", "long", "ponytail", "mohawk", "tuft"],
	"hatTypes": ["cap", "crown", "helmet", "wizard", "beanie", "tophat", "bow", "party"],
	"rideBases": ["kart", "bike", "animal4", "bird", "board", "rocket", "boat", "blob"],
	"wheelStyles": ["toy", "spoked", "monster", "donut"],
	"legStyles": ["hooves", "paws", "claws", "stumpy"],
	"wingStyles": ["feather", "bat", "fairy", "plane"],
	"tailStyles": ["fluffy", "dino", "flame", "feathers"],
	"extraShapes": ["sphere", "capsule", "box", "cone", "cylinder", "torus", "star", "heart"],
	"sockets": ["head_top", "head_side", "head_front", "body_front", "body_back", "hand",
		"ride_front", "ride_back", "ride_side", "ride_top", "ride_bottom"],
}

const FALLBACK_SOCKETS := {
	"head_top": ["character", 0.3], "head_side": ["character", 0.2], "head_front": ["character", 0.15],
	"body_front": ["character", 0.2], "body_back": ["character", 0.25], "hand": ["character", 0.2],
	"ride_front": ["ride", 0.4], "ride_back": ["ride", 0.4], "ride_side": ["ride", 0.35],
	"ride_top": ["ride", 0.4], "ride_bottom": ["ride", 0.3],
}

const FALLBACK_LIMITS := {
	"titleMax": 24, "bodyScale": [0.6, 1.4], "headSize": [0.6, 1.5], "rideScale": [0.6, 1.4],
	"wheelSize": [0.5, 2.0], "wingSize": [0.5, 2.0], "extraScale": [0.1, 2.0],
	"extraRotationDeg": [-180.0, 180.0], "characterExtrasMax": 6, "rideExtrasMax": 8,
	"paletteMin": 3, "paletteMax": 5, "personalityMin": 2, "personalityMax": 3,
}

static var _data: Dictionary = {}


## The raw catalog (racer_kit.json contents, or a fallback built from IMPLEMENTED).
static func data() -> Dictionary:
	if not _data.is_empty():
		return _data
	if FileAccess.file_exists(DATA_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			_data = parsed
	if _data.is_empty():
		push_warning("KitCatalog: %s missing, using built-in fallback" % DATA_PATH)
		for list in IMPLEMENTED:
			if list == "sockets":
				var socks := []
				for s in FALLBACK_SOCKETS:
					socks.append({"name": s, "desc": "", "on": FALLBACK_SOCKETS[s][0], "maxOffset": FALLBACK_SOCKETS[s][1]})
				_data.sockets = socks
			elif list == "extraShapes":
				_data.extraShapes = IMPLEMENTED.extraShapes.duplicate()
			else:
				_data[list] = IMPLEMENTED[list].map(func(n): return {"name": n, "desc": ""})
		_data.kitVersion = 1
		_data.limits = FALLBACK_LIMITS.duplicate()
	if not _data.has("limits"):
		_data.limits = FALLBACK_LIMITS.duplicate()
	return _data


static func reload() -> void:
	_data = {}


## Part names of one catalog list, e.g. names("eyes").
static func names(list: String) -> Array:
	var out := []
	for e in data().get(list, []):
		out.append(e if typeof(e) == TYPE_STRING else str(e.get("name", "")))
	return out


static func limit(key: String) -> Variant:
	return data().limits.get(key, FALLBACK_LIMITS.get(key))


static func socket(name: String) -> Dictionary:
	for s in data().get("sockets", []):
		if s.get("name") == name:
			return s
	return {}


static func sockets_on(on: String) -> Array:
	var out := []
	for s in data().get("sockets", []):
		if s.get("on") == on:
			out.append(str(s.name))
	return out


## Catalog names the builder can't build yet (should be empty; checked by tools/check_catalog.gd).
static func missing_parts() -> PackedStringArray:
	var out := PackedStringArray()
	for list in IMPLEMENTED:
		for n in names(list):
			if n not in IMPLEMENTED[list]:
				out.append("%s.%s" % [list, n])
	return out
