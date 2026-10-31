class_name RacerSpec
extends RefCounted
## RacerSpec helpers (contracts §5): loading and validation.
## validate() repairs nothing and fills in nothing: every unknown part name, out-of-range
## number, invalid colour or palette reference, missing required field or over-long list is
## reported as an error, and a spec with errors must not be built. Only the fields contracts §5
## marks optional (tagline, motion, sound, sound, cheeks, hair, hat, patterns, finishes, ride number,
## wheels/legs/wings/tail, extra.mirror) may be absent.
## Spec frame: +y up, +z forward, +x = the racer's LEFT (see to_godot()).


## Loads a spec JSON file. Accepts a bare RacerSpec or a wrapper with a "spec" field
## (AssetManifest, designer output). Returns {} and pushes an error if unreadable.
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("RacerSpec: file not found: %s" % path)
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("RacerSpec: not a JSON object: %s" % path)
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


## Returns { "spec": Dictionary (clean copy), "errors": PackedStringArray }. The spec must not
## be used when errors is non-empty.
static func validate(raw: Dictionary) -> Dictionary:
	var e := PackedStringArray()
	if not KitCatalog.load_error().is_empty():
		e.append(KitCatalog.load_error())
		return {"spec": {}, "errors": e}
	var out := {"specVersion": 1}

	var title := str(raw.get("title", "")).strip_edges()
	if title == "":
		e.append("title missing")
	var tmax: int = KitCatalog.limit("titleMax")
	if title.length() > tmax:
		e.append("title longer than %d chars" % tmax)
	out.title = title

	if raw.get("tagline") != null:
		var tag := str(raw.tagline).strip_edges()
		if tag == "" or tag.length() > int(KitCatalog.limit("taglineMax")):
			e.append("tagline: empty or longer than %d chars" % int(KitCatalog.limit("taglineMax")))
		out.tagline = tag
	if raw.get("motion") != null:
		var mo := _dict(raw.motion, "motion", e)
		out.motion = {"style": _part(mo.get("style"), "motionStyles", "motion.style", e),
			"energy": _num(mo.get("energy"), "motionEnergy", "motion.energy", e)}
	if raw.get("sound") != null:
		var so := _dict(raw.sound, "sound", e)
		out.sound = {"engine": _part(so.get("engine"), "engineSounds", "sound.engine", e),
			"pitch": _num(so.get("pitch"), "soundPitch", "sound.pitch", e),
			"horn": _part(so.get("horn"), "hornSounds", "sound.horn", e)}

	var pers := []
	for p in _arr(raw.get("personality"), "personality", e):
		pers.append(str(p).to_lower())
	if pers.size() < KitCatalog.limit("personalityMin") or pers.size() > KitCatalog.limit("personalityMax"):
		e.append("personality: %d words, need %d-%d" % [pers.size(), KitCatalog.limit("personalityMin"), KitCatalog.limit("personalityMax")])
	out.personality = pers

	var palette := []
	for c in _arr(raw.get("palette"), "palette", e):
		if typeof(c) == TYPE_STRING and Color.html_is_valid(c):
			palette.append(c)
		else:
			e.append("palette: invalid colour %s" % str(c))
	if palette.size() < KitCatalog.limit("paletteMin") or palette.size() > KitCatalog.limit("paletteMax"):
		e.append("palette: %d colours, need %d-%d" % [palette.size(), KitCatalog.limit("paletteMin"), KitCatalog.limit("paletteMax")])
	out.palette = palette
	var n := palette.size()

	var rc := _dict(raw.get("character"), "character", e)
	var c := {}
	var body := _dict(rc.get("body"), "character.body", e)
	c.body = {
		"shape": _part(body.get("shape"), "bodyShapes", "character.body.shape", e),
		"color": _ref(body.get("color"), n, "character.body.color", e),
		"scale": _vec3(body.get("scale"), "bodyScale", "character.body.scale", e),
	}
	_look(body, c.body, n, "character.body", e)
	var head := _dict(rc.get("head"), "character.head", e)
	c.head = {
		"shape": _part(head.get("shape"), "headShapes", "character.head.shape", e),
		"color": _ref(head.get("color"), n, "character.head.color", e),
		"size": _num(head.get("size"), "headSize", "character.head.size", e),
	}
	if head.get("pattern") != null:
		c.head.pattern = _pattern(head.pattern, n, "character.head.pattern", e)
	var face := _dict(rc.get("face"), "character.face", e)
	var eye_color := str(face.get("eyeColor", ""))
	if not Color.html_is_valid(eye_color):
		e.append("character.face.eyeColor: invalid colour %s" % eye_color)
	c.face = {
		"eyes": _part(face.get("eyes"), "eyes", "character.face.eyes", e),
		"eyeColor": eye_color,
		"mouth": _part(face.get("mouth"), "mouths", "character.face.mouth", e),
		"brows": _bool(face.get("brows"), "character.face.brows", e),
	}
	if face.get("cheeks") != null:
		c.face.cheeks = _ref(face.cheeks, n, "character.face.cheeks", e)
	if rc.get("hair") != null:
		var hair := _dict(rc.hair, "character.hair", e)
		c.hair = {"style": _part(hair.get("style"), "hairStyles", "character.hair.style", e),
			"color": _ref(hair.get("color"), n, "character.hair.color", e)}
	if rc.get("hat") != null:
		var hat := _dict(rc.hat, "character.hat", e)
		c.hat = {"type": _part(hat.get("type"), "hatTypes", "character.hat.type", e),
			"color": _ref(hat.get("color"), n, "character.hat.color", e)}
	var arms := _dict(rc.get("arms"), "character.arms", e)
	c.arms = {"color": _ref(arms.get("color"), n, "character.arms.color", e)}
	c.extras = _extras(rc.get("extras"), "characterExtrasMax", "character", n, e)
	out.character = c

	var rr := _dict(raw.get("ride"), "ride", e)
	var r := {}
	r.base = _part(rr.get("base"), "rideBases", "ride.base", e)
	r.color = _ref(rr.get("color"), n, "ride.color", e)
	r.accent = _ref(rr.get("accent"), n, "ride.accent", e)
	r.scale = _vec3(rr.get("scale"), "rideScale", "ride.scale", e)
	_look(rr, r, n, "ride", e)
	if rr.get("number") != null:
		var num := _dict(rr.number, "ride.number", e)
		var v = num.get("value")
		var rng: Array = KitCatalog.limit("rideNumber")
		if typeof(v) not in [TYPE_INT, TYPE_FLOAT] or float(v) != floorf(float(v)) or v < rng[0] or v > rng[1]:
			e.append("ride.number.value: %s, need a whole number %d-%d" % [str(v), rng[0], rng[1]])
		r.number = {"value": int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0,
			"color": _ref(num.get("color"), n, "ride.number.color", e)}
	if rr.get("wheels") != null:
		var wh := _dict(rr.wheels, "ride.wheels", e)
		var cnt = wh.get("count")
		if typeof(cnt) not in [TYPE_INT, TYPE_FLOAT] or int(cnt) not in [2, 3, 4]:
			e.append("ride.wheels.count: %s, need 2, 3 or 4" % str(cnt))
		r.wheels = {
			"count": int(cnt) if typeof(cnt) in [TYPE_INT, TYPE_FLOAT] else 0,
			"style": _part(wh.get("style"), "wheelStyles", "ride.wheels.style", e),
			"color": _ref(wh.get("color"), n, "ride.wheels.color", e),
			"size": _num(wh.get("size"), "wheelSize", "ride.wheels.size", e),
		}
	if rr.get("legs") != null:
		var legs := _dict(rr.legs, "ride.legs", e)
		r.legs = {"style": _part(legs.get("style"), "legStyles", "ride.legs.style", e),
			"color": _ref(legs.get("color"), n, "ride.legs.color", e)}
	if rr.get("wings") != null:
		var wings := _dict(rr.wings, "ride.wings", e)
		r.wings = {"style": _part(wings.get("style"), "wingStyles", "ride.wings.style", e),
			"color": _ref(wings.get("color"), n, "ride.wings.color", e),
			"size": _num(wings.get("size"), "wingSize", "ride.wings.size", e)}
	if rr.get("tail") != null:
		var tail := _dict(rr.tail, "ride.tail", e)
		r.tail = {"style": _part(tail.get("style"), "tailStyles", "ride.tail.style", e),
			"color": _ref(tail.get("color"), n, "ride.tail.color", e)}
	r.extras = _extras(rr.get("extras"), "rideExtrasMax", "ride", n, e)
	r.drawingSticker = _bool(rr.get("drawingSticker"), "ride.drawingSticker", e)
	out.ride = r
	return {"spec": out, "errors": e}


static func palette_colors(spec: Dictionary) -> Array[Color]:
	var out: Array[Color] = []
	for c in spec.palette:
		out.append(Color.html(c))
	return out


# --- helpers ---

## Copies the optional pattern and finish of src into dst.
static func _look(src: Dictionary, dst: Dictionary, n: int, field: String, e: PackedStringArray) -> void:
	if src.get("pattern") != null:
		dst.pattern = _pattern(src.pattern, n, field + ".pattern", e)
	if src.get("finish") != null:
		dst.finish = _part(src.finish, "finishes", field + ".finish", e)


static func _pattern(v: Variant, n: int, field: String, e: PackedStringArray) -> Dictionary:
	var p := _dict(v, field, e)
	return {"type": _part(p.get("type"), "patterns", field + ".type", e),
		"color": _ref(p.get("color"), n, field + ".color", e),
		"scale": _num(p.get("scale"), "patternScale", field + ".scale", e)}


static func _arr(v: Variant, field: String, e: PackedStringArray) -> Array:
	if typeof(v) != TYPE_ARRAY:
		e.append("%s: missing or not a list" % field)
		return []
	return v


static func _bool(v: Variant, field: String, e: PackedStringArray) -> bool:
	if typeof(v) != TYPE_BOOL:
		e.append("%s: missing or not true/false" % field)
		return false
	return v


static func _dict(v: Variant, field: String, e: PackedStringArray) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		e.append("%s: missing or not an object" % field)
		return {}
	return v


static func _part(v: Variant, list: String, field: String, e: PackedStringArray) -> String:
	var s := str(v) if v != null else ""
	if s == "":
		e.append("%s: missing" % field)
	elif s not in KitCatalog.names(list):
		e.append("%s: unknown part \"%s\" (kit has: %s)" % [field, s, ", ".join(KitCatalog.names(list))])
	return s


static func _ref(v: Variant, n: int, field: String, e: PackedStringArray) -> int:
	if typeof(v) not in [TYPE_INT, TYPE_FLOAT]:
		e.append("%s: missing palette index" % field)
		return 0
	var i := int(v)
	if i < 0 or i >= n:
		e.append("%s: palette index %d out of range 0-%d" % [field, i, n - 1])
	return i


static func _num(v: Variant, limit_key: String, field: String, e: PackedStringArray) -> float:
	var rng: Array = KitCatalog.limit(limit_key)
	if typeof(v) not in [TYPE_INT, TYPE_FLOAT]:
		e.append("%s: not a number" % field)
		return 0.0
	var f := float(v)
	if f < rng[0] or f > rng[1]:
		e.append("%s: %s outside %s-%s" % [field, str(f), str(rng[0]), str(rng[1])])
	return f


static func _vec3(v: Variant, limit_key: String, field: String, e: PackedStringArray) -> Array:
	var rng: Array = KitCatalog.limit(limit_key)
	if typeof(v) != TYPE_ARRAY or v.size() != 3:
		e.append("%s: not a [x,y,z] array" % field)
		return [0.0, 0.0, 0.0]
	var out := [0.0, 0.0, 0.0]
	for k in 3:
		if typeof(v[k]) not in [TYPE_INT, TYPE_FLOAT]:
			e.append("%s[%d]: not a number" % [field, k])
			continue
		out[k] = float(v[k])
		if out[k] < rng[0] or out[k] > rng[1]:
			e.append("%s[%d]: %s outside %s-%s" % [field, k, str(out[k]), str(rng[0]), str(rng[1])])
	return out


static func _extras(v: Variant, max_key: String, on: String, n: int, e: PackedStringArray) -> Array:
	var out := []
	var list := _arr(v, on + ".extras", e)
	var max_count: int = KitCatalog.limit(max_key)
	if list.size() > max_count:
		e.append("%s.extras: %d, at most %d" % [on, list.size(), max_count])
	var sockets := KitCatalog.sockets_on(on)
	for idx in list.size():
		var where := "%s.extras[%d]" % [on, idx]
		var x := _dict(list[idx], where, e)
		if x.is_empty():
			continue
		var sock := str(x.get("socket", ""))
		if sock not in sockets:
			e.append("%s.socket: unknown \"%s\" (sockets on %s: %s)" % [where, sock, on, ", ".join(sockets)])
		var max_off: float = float(KitCatalog.socket(sock).get("maxOffset", 0.0))
		var off := [0.0, 0.0, 0.0]
		var raw_off = x.get("offset")
		if typeof(raw_off) != TYPE_ARRAY or raw_off.size() != 3:
			e.append("%s.offset: not a [x,y,z] array" % where)
		else:
			for k in 3:
				if typeof(raw_off[k]) not in [TYPE_INT, TYPE_FLOAT]:
					e.append("%s.offset[%d]: not a number" % [where, k])
					continue
				off[k] = float(raw_off[k])
				if absf(off[k]) > max_off:
					e.append("%s.offset[%d]: %s beyond the %s socket's ±%s" % [where, k, str(off[k]), sock, str(max_off)])
		out.append({
			"shape": _part(x.get("shape"), "extraShapes", where + ".shape", e),
			"socket": sock,
			"offset": off,
			"scale": _vec3(x.get("scale"), "extraScale", where + ".scale", e),
			"rotationDeg": _vec3(x.get("rotationDeg"), "extraRotationDeg", where + ".rotationDeg", e),
			"color": _ref(x.get("color"), n, where + ".color", e),
			"mirror": bool(x.get("mirror", false)),
		})
	return out
