class_name KitCatalog
extends RefCounted
## The toy-part kit catalog, as seen by the game.
## Source of truth: packages/shared/src/racer-kit.js (contracts §5). `bun run kit:export`
## writes it to res://data/racer_kit.json, which is loaded here. There is no built-in copy: if
## the JSON is missing or broken, load_error() says why and no spec validates.
## Adding a part = add it to racer-kit.js + build it in kit_parts / kit_ride_parts + export.
## tools/check_catalog.gd fails if a catalog name has no Godot implementation.

const DATA_PATH := "res://data/racer_kit.json"
const PKG_DEFAULT_PATH := "res://data/pkg_default/spec.json"

const MOODS := ["happy", "excited", "determined", "dizzy", "sad", "cheering"]

## Every part name the Godot builder implements, by catalog list.
const IMPLEMENTED := {
	"bodyShapes": ["bean", "round", "tall", "box", "pear", "star"],
	"headShapes": ["round", "oval", "square", "wide", "drop"],
	"eyes": ["dots", "big_round", "sleepy", "googly", "one_eye", "visor", "star", "heart", "lashes", "angry", "wink"],
	"mouths": ["smile", "grin", "open", "fangs", "beak", "none", "tongue", "buck_teeth", "mustache"],
	"hairStyles": ["spiky", "curly", "long", "ponytail", "mohawk", "tuft"],
	"hatTypes": ["cap", "crown", "helmet", "wizard", "beanie", "tophat", "bow", "party"],
	"rideBases": ["kart", "bike", "animal4", "bird", "board", "rocket", "boat", "blob"],
	"wheelStyles": ["toy", "spoked", "monster", "donut"],
	"legStyles": ["hooves", "paws", "claws", "stumpy"],
	"wingStyles": ["feather", "bat", "fairy", "plane"],
	"tailStyles": ["fluffy", "dino", "flame", "feathers"],
	"extraShapes": ["sphere", "capsule", "box", "cone", "cylinder", "torus", "star", "heart",
		"lightning", "flame", "moon", "flower", "leaf", "cloud", "diamond", "drop", "bowtie", "glasses", "cape"],
	"patterns": ["stripes", "spots", "stars", "hearts", "zigzag", "checks", "crayon", "swirl"],
	"finishes": ["matte", "glossy", "metallic", "sparkle", "glow"],
	# Sounds are data for the audio side; the kit builds nothing for them.
	"engineSounds": ["putter", "vroom", "electric", "rocket", "hooves", "paws", "flap", "splash", "magic", "squelch"],
	"hornSounds": ["honk", "beep", "toot", "squeak", "bell", "roar", "meow", "woof", "neigh", "moo", "boing"],
	"motionStyles": ["bouncy", "smooth", "wobbly", "jittery", "floaty", "proud", "sneaky"],
	"sockets": ["head_top", "head_side", "head_front", "body_front", "body_back", "hand",
		"ride_front", "ride_back", "ride_side", "ride_top", "ride_bottom"],
}

static var _data: Dictionary = {}


static var _error := ""


## The raw catalog (racer_kit.json contents). Empty (with load_error() set) if it can't be read.
static func data() -> Dictionary:
	if not _data.is_empty() or not _error.is_empty():
		return _data
	if not FileAccess.file_exists(DATA_PATH):
		_error = "KitCatalog: %s missing (run `bun run kit:export`)" % DATA_PATH
	else:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if typeof(parsed) != TYPE_DICTIONARY:
			_error = "KitCatalog: %s is not a JSON object" % DATA_PATH
		elif typeof(parsed.get("limits")) != TYPE_DICTIONARY:
			_error = "KitCatalog: %s has no limits" % DATA_PATH
		else:
			_data = parsed
	if not _error.is_empty():
		push_error(_error)
	return _data


## Why the catalog could not be loaded, or "" when it is fine.
static func load_error() -> String:
	data()
	return _error


static func reload() -> void:
	_data = {}
	_error = ""


## Part names of one catalog list, e.g. names("eyes").
static func names(list: String) -> Array:
	var out := []
	for e in data().get(list, []):
		out.append(e if typeof(e) == TYPE_STRING else str(e.get("name", "")))
	return out


static func limit(key: String) -> Variant:
	var limits: Dictionary = data().get("limits", {})
	if not limits.has(key):
		push_error("KitCatalog: limit \"%s\" missing from %s" % [key, DATA_PATH])
		return null
	return limits[key]


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
