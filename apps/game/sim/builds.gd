extends RefCounted
## Build helpers: default, random valid builds (starsTotal stars, max starsMaxPerAbility each) and enumeration for the sweep.



static func default_build() -> Dictionary:
	return Protocol.DEFAULT_BUILD.duplicate(true)


static func random_stars(rng: RandomNumberGenerator, total: int = int(Protocol.DEFAULT_CONFIG["starsTotal"]),
		max_per: int = int(Protocol.DEFAULT_CONFIG["starsMaxPerAbility"])) -> Dictionary:
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


## The way the stars take at each fork (contracts §2h, Protocol.ROUTE_STARS); the server does the
## same (routesFor in packages/shared), so a build from the server already carries them.
static func routes_for(stars: Dictionary) -> Dictionary:
	var r := {}
	for f in Protocol.ROUTE_STARS:
		var rule: Dictionary = Protocol.ROUTE_STARS[f]
		var risky: String = rule["choice"]
		var safe: String = Protocol.FORK_CHOICES[f][1] if Protocol.FORK_CHOICES[f][0] == risky else Protocol.FORK_CHOICES[f][0]
		r[f] = risky if int(stars.get(rule["ability"], 0)) >= int(rule["stars"]) else safe
	return r


static func random_build(rng: RandomNumberGenerator) -> Dictionary:
	var stars := random_stars(rng)
	return {"stars": stars, "routes": routes_for(stars)}


static func describe(build: Dictionary) -> String:
	var st: Dictionary = build["stars"]
	var r: Dictionary = build["routes"]
	return "spd%d jmp%d grp%d wat%d stb%d bnc%d %s/%s/%s" % [
		int(st["speed"]), int(st["jump"]), int(st["grip"]), int(st["water"]), int(st["stability"]), int(st["bounce"]),
		r["ramp"], r["pond"], r["crossing"],
	]
