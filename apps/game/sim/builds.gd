extends RefCounted
## Build helpers: default, random valid builds (10 stars, max 5 each) and enumeration for the sweep.



static func default_build() -> Dictionary:
	return Protocol.DEFAULT_BUILD.duplicate(true)


static func random_stars(rng: RandomNumberGenerator, total: int = 10, max_per: int = 5) -> Dictionary:
	var stars := {}
	for a in Protocol.ABILITIES:
		stars[a] = 0
	var left := total
	while left > 0:
		var a: String = Protocol.ABILITIES[rng.randi_range(0, Protocol.ABILITIES.size() - 1)]
		if int(stars[a]) < max_per:
			stars[a] = int(stars[a]) + 1
			left -= 1
	return stars


static func random_routes(rng: RandomNumberGenerator) -> Dictionary:
	var r := {}
	for f in Protocol.FORK_IDS:
		var ch: Array = Protocol.FORK_CHOICES[f]
		r[f] = ch[rng.randi_range(0, 1)]
	return r


static func random_build(rng: RandomNumberGenerator) -> Dictionary:
	var stars := random_stars(rng)
	var routes := random_routes(rng)
	# Players tend to pick routes that suit their stars.
	if rng.randf() < 0.6:
		routes["ramp"] = "jump" if int(stars["jump"]) >= 4 else "around"
		routes["pond"] = "water" if int(stars["water"]) >= 3 else "bridge"
		routes["crossing"] = "exposed" if int(stars["stability"]) >= 2 else "sheltered"
	return {
		"stars": stars,
		"routes": routes,
		"style": Protocol.DRIVING_STYLES[rng.randi_range(0, 2)],
	}


static func describe(build: Dictionary) -> String:
	var st: Dictionary = build["stars"]
	var r: Dictionary = build["routes"]
	return "spd%d jmp%d grp%d wat%d stb%d bnc%d %s %s/%s/%s" % [
		int(st["speed"]), int(st["jump"]), int(st["grip"]), int(st["water"]), int(st["stability"]), int(st["bounce"]),
		String(build["style"]).substr(0, 4), r["ramp"], r["pond"], r["crossing"],
	]
