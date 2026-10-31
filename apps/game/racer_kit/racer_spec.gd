class_name RacerSpec
extends RefCounted
## RacerSpec helpers (contracts §5): loading, defaults and normalisation.
## normalize() never fails. It repairs like clampRacerSpec in packages/shared: unknown part
## names snap to the nearest catalog name, numbers are clamped, extras capped. Each fix is a
## warning so the Racer Viewer can show what the designer got wrong.
## Spec frame: +y up, +z forward, +x = the racer's LEFT (see to_godot()).

const FALLBACK_PALETTE := ["#ff6b35", "#ffd23f", "#3bceac", "#2b2140"]


## pkg_default: shown for anyone without a valid spec yet (res://data/pkg_default/spec.json).
static func default_spec() -> Dictionary:
	var s := load_file(KitCatalog.PKG_DEFAULT_PATH)
	if not s.is_empty():
		return s
	return {
		"specVersion": 1, "title": "Speedy Bean", "personality": ["cheerful", "speedy"],
		"palette": FALLBACK_PALETTE.duplicate(),
		"character": {
			"body": {"shape": "bean", "color": 0, "scale": [1, 1, 1]},
			"head": {"shape": "round", "color": 1, "size": 1},
			"face": {"eyes": "big_round", "eyeColor": "#2b2140", "mouth": "smile", "brows": true, "cheeks": 0},
			"hat": {"type": "helmet", "color": 2}, "arms": {"color": 0}, "extras": [],
		},
		"ride": {
			"base": "kart", "color": 2, "accent": 1, "scale": [1, 1, 1],
			"wheels": {"count": 4, "style": "toy", "color": 3, "size": 1},
			"extras": [{"shape": "cylinder", "socket": "ride_back", "offset": [0, 0.1, -0.2],
				"scale": [0.2, 0.4, 0.2], "rotationDeg": [0, 0, 0], "color": 3}],
			"drawingSticker": false,
		},
	}


## Loads a spec JSON file. Accepts a bare RacerSpec or a wrapper with a "spec" field
## (AssetManifest, designer output). Returns {} if unreadable.
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	if typeof(data.get("spec")) == TYPE_DICTIONARY:
		return data.spec
	return data


## Spec-frame vector (x = left, z = forward) to Godot (x = right, z = back).
static func to_godot(v: Array) -> Vector3:
	return Vector3(-float(v[0]), float(v[1]), -float(v[2]))


## Spec-frame Euler degrees to Godot radians (same rotation seen through the 180° yaw flip).
static func rot_to_godot(v: Array) -> Vector3:
	return Vector3(deg_to_rad(-float(v[0])), deg_to_rad(float(v[1])), deg_to_rad(-float(v[2])))


## Returns { "spec": Dictionary (clean copy), "warnings": PackedStringArray }.
static func normalize(raw: Dictionary) -> Dictionary:
	var w := PackedStringArray()
	var d := default_spec()
	var out := {"specVersion": 1}

	var title := str(raw.get("title", "")).strip_edges()
	if title == "":
		w.append("title missing")
		title = str(d.get("title", "Racer"))
	var tmax: int = KitCatalog.limit("titleMax")
	if title.length() > tmax:
		w.append("title longer than %d chars, cut" % tmax)
		title = title.substr(0, tmax)
	out.title = title

	var pers := []
	for p in _arr(raw.get("personality", [])):
		pers.append(str(p).to_lower())
	out.personality = pers.slice(0, KitCatalog.limit("personalityMax")) if not pers.is_empty() else d.personality

	var palette := []
	for c in _arr(raw.get("palette", [])):
		if typeof(c) == TYPE_STRING and Color.html_is_valid(c):
			palette.append(c)
		else:
			w.append("palette: invalid colour %s dropped" % str(c))
	var pmax: int = KitCatalog.limit("paletteMax")
	if palette.size() > pmax:
		w.append("palette: kept %d of %d" % [pmax, palette.size()])
		palette.resize(pmax)
	var i := 0
	while palette.size() < KitCatalog.limit("paletteMin"):
		w.append("palette has fewer than 3 colours, padded")
		palette.append(FALLBACK_PALETTE[i])
		i += 1
	out.palette = palette
	var n := palette.size()

	var rc := _dict(raw.get("character"))
	var c := {}
	var body := _dict(rc.get("body"))
	c.body = {
		"shape": _part(body.get("shape"), "bodyShapes", "character.body.shape", w),
		"color": _ref(body.get("color", 0), n, "character.body.color", w),
		"scale": _vec3(body.get("scale"), "bodyScale", "character.body.scale", w),
	}
	var head := _dict(rc.get("head"))
	c.head = {
		"shape": _part(head.get("shape"), "headShapes", "character.head.shape", w),
		"color": _ref(head.get("color", c.body.color), n, "character.head.color", w),
		"size": _num(head.get("size", 1.0), "headSize", "character.head.size", w),
	}
	var face := _dict(rc.get("face"))
	var eye_color := str(face.get("eyeColor", "#2b2140"))
	if not Color.html_is_valid(eye_color):
		w.append("character.face.eyeColor invalid, using dark")
		eye_color = "#2b2140"
	c.face = {
		"eyes": _part(face.get("eyes"), "eyes", "character.face.eyes", w),
		"eyeColor": eye_color,
		"mouth": _part(face.get("mouth"), "mouths", "character.face.mouth", w),
		"brows": bool(face.get("brows", true)),
	}
	if face.get("cheeks") != null:
		c.face.cheeks = _ref(face.cheeks, n, "character.face.cheeks", w)
	if typeof(rc.get("hair")) == TYPE_DICTIONARY:
		c.hair = {"style": _part(rc.hair.get("style"), "hairStyles", "character.hair.style", w),
			"color": _ref(rc.hair.get("color", 0), n, "character.hair.color", w)}
	if typeof(rc.get("hat")) == TYPE_DICTIONARY:
		c.hat = {"type": _part(rc.hat.get("type"), "hatTypes", "character.hat.type", w),
			"color": _ref(rc.hat.get("color", 0), n, "character.hat.color", w)}
	c.arms = {"color": _ref(_dict(rc.get("arms")).get("color", c.body.color), n, "character.arms.color", w)}
	c.extras = _extras(rc.get("extras", []), "characterExtrasMax", "character", n, w)
	out.character = c

	var rr := _dict(raw.get("ride"))
	var r := {}
	r.base = _part(rr.get("base"), "rideBases", "ride.base", w)
	r.color = _ref(rr.get("color", 0), n, "ride.color", w)
	r.accent = _ref(rr.get("accent", 1), n, "ride.accent", w)
	r.scale = _vec3(rr.get("scale"), "rideScale", "ride.scale", w)
	if typeof(rr.get("wheels")) == TYPE_DICTIONARY:
		var wh: Dictionary = rr.wheels
		var cnt := int(wh.get("count", 4))
		if cnt not in [2, 3, 4]:
			w.append("ride.wheels.count %d → %d" % [cnt, clampi(cnt, 2, 4)])
			cnt = clampi(cnt, 2, 4)
		r.wheels = {
			"count": cnt,
			"style": _part(wh.get("style"), "wheelStyles", "ride.wheels.style", w),
			"color": _ref(wh.get("color", r.accent), n, "ride.wheels.color", w),
			"size": _num(wh.get("size", 1.0), "wheelSize", "ride.wheels.size", w),
		}
	if typeof(rr.get("legs")) == TYPE_DICTIONARY:
		r.legs = {"style": _part(rr.legs.get("style"), "legStyles", "ride.legs.style", w),
			"color": _ref(rr.legs.get("color", r.color), n, "ride.legs.color", w)}
	if typeof(rr.get("wings")) == TYPE_DICTIONARY:
		r.wings = {"style": _part(rr.wings.get("style"), "wingStyles", "ride.wings.style", w),
			"color": _ref(rr.wings.get("color", r.accent), n, "ride.wings.color", w),
			"size": _num(rr.wings.get("size", 1.0), "wingSize", "ride.wings.size", w)}
	if typeof(rr.get("tail")) == TYPE_DICTIONARY:
		r.tail = {"style": _part(rr.tail.get("style"), "tailStyles", "ride.tail.style", w),
			"color": _ref(rr.tail.get("color", r.accent), n, "ride.tail.color", w)}
	r.extras = _extras(rr.get("extras", []), "rideExtrasMax", "ride", n, w)
	r.drawingSticker = bool(rr.get("drawingSticker", false))
	out.ride = r
	return {"spec": out, "warnings": w}


static func palette_colors(spec: Dictionary) -> Array[Color]:
	var out: Array[Color] = []
	for c in spec.get("palette", FALLBACK_PALETTE):
		out.append(Color.html(c))
	return out


## Closest catalog name by edit distance, case- and separator-insensitive (as in racer-spec.js).
static func nearest_name(value: String, options: Array) -> String:
	if options.is_empty():
		return value
	var v := value.to_lower().replace(" ", "_").replace("-", "_")
	var best: String = options[0]
	var best_d := 1 << 30
	for o in options:
		var dist := _edit_distance(v, str(o).to_lower().replace(" ", "_").replace("-", "_"))
		if dist < best_d:
			best = o
			best_d = dist
	return best


# --- helpers ---

static func _edit_distance(a: String, b: String) -> int:
	var row := []
	for j in b.length() + 1:
		row.append(j)
	for i in range(1, a.length() + 1):
		var prev: int = row[0]
		row[0] = i
		for j in range(1, b.length() + 1):
			var tmp: int = row[j]
			row[j] = mini(mini(row[j] + 1, row[j - 1] + 1), prev + (0 if a[i - 1] == b[j - 1] else 1))
			prev = tmp
	return row[b.length()]


static func _arr(v: Variant) -> Array:
	return v if typeof(v) == TYPE_ARRAY else []


static func _dict(v: Variant) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}


static func _part(v: Variant, list: String, field: String, w: PackedStringArray) -> String:
	var options := KitCatalog.names(list)
	var s := str(v) if v != null else ""
	if s in options:
		return s
	var best := nearest_name(s, options) if s != "" else str(options[0])
	w.append("%s: unknown part \"%s\" → \"%s\"" % [field, s, best])
	return best


static func _ref(v: Variant, n: int, field: String, w: PackedStringArray) -> int:
	var i := int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0
	var c := clampi(i, 0, n - 1)
	if c != i:
		w.append("%s: palette ref %d → %d" % [field, i, c])
	return c


static func _num(v: Variant, limit_key: String, field: String, w: PackedStringArray) -> float:
	var rng: Array = KitCatalog.limit(limit_key)
	if typeof(v) not in [TYPE_INT, TYPE_FLOAT]:
		return clampf(1.0, rng[0], rng[1])
	var f := float(v)
	var c := clampf(f, rng[0], rng[1])
	if not is_equal_approx(c, f):
		w.append("%s: %s → %s" % [field, str(f), str(c)])
	return c


static func _vec3(v: Variant, limit_key: String, field: String, w: PackedStringArray, fallback := 1.0) -> Array:
	var rng: Array = KitCatalog.limit(limit_key)
	var out := [fallback, fallback, fallback]
	if typeof(v) == TYPE_ARRAY and v.size() == 3:
		for k in 3:
			var f := float(v[k]) if typeof(v[k]) in [TYPE_INT, TYPE_FLOAT] else fallback
			out[k] = clampf(f, rng[0], rng[1])
			if not is_equal_approx(out[k], f):
				w.append("%s[%d]: %s → %s" % [field, k, str(f), str(out[k])])
	elif v != null:
		w.append("%s: not a [x,y,z] array" % field)
	return out


static func _extras(v: Variant, max_key: String, on: String, n: int, w: PackedStringArray) -> Array:
	var out := []
	var list := _arr(v)
	var max_count: int = KitCatalog.limit(max_key)
	if list.size() > max_count:
		w.append("%s.extras: kept %d of %d" % [on, max_count, list.size()])
	var sockets := KitCatalog.sockets_on(on)
	for idx in mini(list.size(), max_count):
		var e = list[idx]
		if typeof(e) != TYPE_DICTIONARY:
			w.append("%s.extras[%d]: not an object, dropped" % [on, idx])
			continue
		var where := "%s.extras[%d]" % [on, idx]
		var sock := str(e.get("socket", ""))
		if sock not in sockets:
			var best := nearest_name(sock, sockets)
			w.append("%s.socket: unknown \"%s\" → \"%s\"" % [where, sock, best])
			sock = best
		var max_off: float = float(KitCatalog.socket(sock).get("maxOffset", 0.2))
		var off := [0.0, 0.0, 0.0]
		var raw_off = e.get("offset")
		if typeof(raw_off) == TYPE_ARRAY and raw_off.size() == 3:
			var clamped := false
			for k in 3:
				var f := float(raw_off[k]) if typeof(raw_off[k]) in [TYPE_INT, TYPE_FLOAT] else 0.0
				off[k] = clampf(f, -max_off, max_off)
				clamped = clamped or not is_equal_approx(off[k], f)
			if clamped:
				w.append("%s: %s offset clamped to ±%s" % [where, sock, str(max_off)])
		out.append({
			"shape": _part(e.get("shape"), "extraShapes", where + ".shape", w),
			"socket": sock,
			"offset": off,
			"scale": _vec3(e.get("scale"), "extraScale", where + ".scale", w, 0.3),
			"rotationDeg": _vec3(e.get("rotationDeg"), "extraRotationDeg", where + ".rotationDeg", w, 0.0),
			"color": _ref(e.get("color", 0), n, where + ".color", w),
			"mirror": bool(e.get("mirror", false)),
		})
	return out
