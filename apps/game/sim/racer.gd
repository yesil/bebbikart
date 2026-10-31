extends RefCounted
## One racer's simulation state + per-tick physics/autopilot (game.md "Simulation (3b)").
## Plain data; the owning Sim passes itself in to step(). No nodes.

const Tuning = preload("res://sim/tuning.gd")
const Course = preload("res://sim/course.gd")
const Route = preload("res://sim/route.gd")

var run_id := ""
var player_id := ""
var build: Dictionary
var style := "balanced"
var st := {}  # effect level per ability: stars * Tuning.STAR_STEP (0..5)

var state := "queued"  # queued | racing | finished | failed | aborted
var fail_reason := ""
var rng := RandomNumberGenerator.new()

# Route position
var path: Array[String] = []
var segs: Array = []           # segment dicts in path order
var offsets := PackedFloat64Array()
var total_len := 0.0
var seg_idx := 0
var seg: Dictionary
var seg_id := "start"
var ls := 0.0                  # metres along current segment
var section := "hills"

# Motion
var v := 0.0
var d := 0.0
var vd := 0.0
var y := 0.0
var vy := 0.0
var airborne := false
var wobble := 0.0
var jump_air := false          # airborne from a ramp (vs. a hop)
var in_water := false
var slipping := false
var rain_capped := false       # held under the speed it dares on a wet road (grip)
var wind_capped := false       # held under the speed it dares in the open wind (stability)
var gust_phase := 0.0
var wind_lat := 0.0            # lateral wind accel applied this tick
var a_long := 0.0

# Stats (derived)
var top := 16.0
var accel := 7.0
var radius := Tuning.RADIUS    # half width of its footprint (sim.gd _collide)
var half_len := Tuning.RADIUS  # half length, nose or tail to the middle
var grip_f := 0.86
var mass := 1.5

# Autopilot
var target_v := 0.0
var ref_v := 0.0               # calm-weather undisturbed target (for time-loss accounting)
var plan_t := 0
var noise := 1.0
var noise_t := 0.0
var lane_home := 0.0
var d_target := 0.0
var replan_t := 0.0
var follow_v := -1.0
var pass_side := 0.0
var lane := 0.0

# Timers
var ticks := 0
var boosts_left := 3
var boosts_used := 0
var boost_t := 0.0
var boost_amt := 0.0
var weak_grip_t := 0.0
var recover_t := 0.0
var recover_mult := 1.0
var bumped_t := 0.0
var bumped_by := ""
var bounce_t := 0.0

# Bookkeeping
var stuck_best := 0.0
var stuck_t := 0.0
var splits := {}
var section_start_tick := 0
var events: Array = []
var episode := {}
var weather_seen := {}
var trace: Array = []
var last_progress_tick := -999

# Laps (loop tracks only, e.g. sim/village_course.gd): the racer wraps from the last segment to
# the first and keeps going. Splits and the trace restart each lap; the best lap's are kept.
var looping := false
var lap := 0                   # completed laps
var lap_start_tick := 0
var laps: Array[int] = []      # lap times, ms
var best_lap := -1             # index into laps
var best_splits := {}
var best_trace: Array = []
var pit_requested := false     # finish at the next line crossing
# Missed exits: a segment with "miss" ({at, seg, chance}) may send the racer round an extra
# loop segment from s = at, after which it rejoins the segment at the same s.
var detour := {}               # {} or {seg: Dictionary (the segment left), at: float, start_tick}
var detour_travel := 0.0       # metres driven in detours this lap (keeps the stuck check fed)
var miss_chance := -1.0        # chance of the last missed-exit roll (tools/sweep.gd prices the risk)
var course_ref                 # the course, for detour segments
var laps_max := 0
# Stretches (contracts §2d): this lap's, in driving order, [{id, ticks, lost_ms}]. Every tick
# counts to the stretch the racer is on when it starts, so they add up to the lap exactly.
var stretch_log: Array = []
var best_stretches: Array = [] # the best lap's (payload form)
var lap_weather := {}          # weather seen on this lap (game.run.lap weatherSeen)


## `course` is sim/course.gd or sim/village_course.gd (same segment interface; a loop track has `loop`).
## size: the built toy's half width and half length (Tuning.DEFAULT_SIZE for headless racers).
func setup(p_run_id: String, p_player_id: String, p_build: Dictionary, course, cfg: Dictionary, seed_: int, size: Vector2) -> void:
	run_id = p_run_id
	radius = clampf(size.x, Tuning.SIZE_HALF_WIDTH.x, Tuning.SIZE_HALF_WIDTH.y)
	half_len = clampf(size.y, Tuning.SIZE_HALF_WIDTH.x, Tuning.SIZE_HALF_LENGTH_MAX)
	player_id = p_player_id
	build = p_build
	style = String(build.get("style", "balanced"))
	var stars: Dictionary = build.get("stars", {})
	for a in ["speed", "jump", "grip", "water", "stability", "bounce"]:
		st[a] = int(stars.get(a, 0)) * Tuning.STAR_STEP
	rng.seed = seed_
	gust_phase = rng.randf_range(0.0, TAU)
	path = course.path_for(build.get("routes", {}))
	offsets.resize(path.size())
	total_len = 0.0
	for i in path.size():
		var sg: Dictionary = course.segments[path[i]]
		segs.append(sg)
		offsets[i] = total_len
		total_len += (sg["route"] as Route).length
	seg = segs[0]
	_enter_stretch()
	course_ref = course
	looping = course.get("loop") == true
	if looping:
		if not cfg.has("lapsPerRun"):
			push_error("racer: loop track but config has no lapsPerRun")
		laps_max = int(cfg.get("lapsPerRun", 0))
	boosts_left = int(cfg.get("boostsPerRun", 3))
	top = Tuning.TOP_SPEED_BASE + Tuning.TOP_SPEED_PER_STAR * st["speed"]
	accel = Tuning.ACCEL_BASE * (1.0 - Tuning.ACCEL_STABILITY_PENALTY * st["stability"]) \
		* (1.0 - Tuning.ACCEL_HIGH_SPEED_PENALTY * maxf(0.0, st["speed"] - 3))
	grip_f = Tuning.GRIP_FACTOR_BASE + Tuning.GRIP_FACTOR_PER_STAR * st["grip"]
	mass = 1.0 + Tuning.MASS_PER_STAB * st["stability"]
	lane_home = rng.randf_range(-0.6, 0.6)


func gs() -> float:
	# In a detour the racer is held where it left the path until it rejoins.
	if not detour.is_empty():
		return offsets[seg_idx] + float(detour["at"])
	return offsets[seg_idx] + ls


## Fraction of the course (of the current lap on a loop track).
func progress() -> float:
	return clampf(gs() / total_len, 0.0, 1.0)


func elapsed_ms() -> int:
	return int(round(ticks * 1000.0 / Tuning.HZ))


## Time on the current lap (the whole run on a point-to-point course).
func lap_ms() -> int:
	return int(round((ticks - lap_start_tick) * 1000.0 / Tuning.HZ))


func best_lap_ms() -> int:
	return laps[best_lap] if best_lap >= 0 else -1


func route() -> Route:
	return seg["route"]


## How much longer (per end) than a default-sized kart: the traffic queries measure gaps nose to
## tail, so default karts see exactly the old centre distances.
func extra_len() -> float:
	return half_len - Tuning.RADIUS


func half_width() -> float:
	return float(seg["half_width"])


func is_active() -> bool:
	return state == "racing"


# ---------------------------------------------------------------- planning

## Lowest speed the autopilot wants within its look-ahead window.
## Returns [target, calm_reference]. corner_f scales corner speeds for the "perceived" target.
func _plan(corner_f: float, decel: float) -> Array:
	var horizon := v * v / (2.0 * decel) + 6.0
	var best := top
	var best_ref := top
	var base_ref := grip_f * float(Tuning.STYLE_CORNER[style])
	var i := seg_idx
	var s0 := ls
	var x := 0.0
	while x <= horizon:
		# In a detour, look ahead round the detour itself.
		var r: Route = route() if i == seg_idx and not detour.is_empty() else segs[i]["route"]
		var s := s0 + x
		while s > r.length and i < segs.size() - 1:
			s0 -= r.length
			s -= r.length
			i += 1
			r = segs[i]["route"]
		if s > r.length:
			break
		var k := absf(r.curv_at(s))
		if k > Tuning.CORNER_MIN_K:
			var vc := sqrt(Tuning.CORNER_ACCEL / k)
			var allowed := sqrt(pow(vc * corner_f, 2) + 2.0 * decel * x)
			var allowed_ref := sqrt(pow(vc * base_ref, 2) + 2.0 * decel * x)
			best = minf(best, allowed)
			best_ref = minf(best_ref, allowed_ref)
		x += 2.0
	return [best, best_ref]


func _replan_lane(sim) -> void:
	follow_v = -1.0
	var hw := half_width() - 0.7
	# Fresh off the grid, keep the start slot's line: karts released side by side don't swerve
	# across each other towards their own lines until the group has strung out.
	var home := lane_home * hw
	if lap == 0 and gs() < Tuning.START_HOLD_M:
		home = lane
	var ahead = sim.racer_ahead(self, 4.0 + 0.6 * v, 2.0)
	if ahead == null or ahead.v >= v - 0.3:
		pass_side = 0.0
		d_target = clampf(home, -hw, hw)
		return
	var off: float = Tuning.STYLE_PASS_OFFSET[style]
	var best_side := 0.0
	var best_free := -1.0
	for side in [-1.0, 1.0]:
		var cand: float = ahead.d + side * off
		if absf(cand) > hw:
			continue
		var free: float = sim.lane_free(self, cand, 4.0 + 0.6 * v)
		if free > best_free:
			best_free = free
			best_side = side
	if best_side != 0.0 and rng.randf() < float(Tuning.STYLE_MISJUDGE[style]):
		var other: float = ahead.d - best_side * off
		if absf(other) <= hw + 0.6:
			best_side = -best_side
	if best_side == 0.0 or best_free < 1.0:
		# No room: tuck in behind (daring keeps its foot down and may bump).
		if style != "daring":
			follow_v = ahead.v
		d_target = ahead.d
		return
	pass_side = best_side
	d_target = clampf(ahead.d + best_side * off, -hw - 0.5, hw + 0.5)


# ---------------------------------------------------------------- step

func step(sim) -> void:
	var dt := Tuning.DT
	ticks += 1
	stretch_log.back()["ticks"] += 1
	var weather = sim.weather
	var rain: float = weather.rain_intensity()
	if rain > 0.05:
		weather_seen["rain"] = true
		lap_weather["rain"] = true
	if weather.wind_strength() > 0.05:
		weather_seen["wind"] = true
		lap_weather["wind"] = true

	var r := route()
	var k := r.curv_at(ls)
	var n := r.normal_at(ls)
	var hw := half_width()
	var exposure: float = seg["exposure"]
	in_water = not airborne and Course.in_ranges(seg["water"], ls)

	# Timers
	boost_t = maxf(0.0, boost_t - dt)
	if boost_t <= 0.0:
		boost_amt = 0.0
	weak_grip_t = maxf(0.0, weak_grip_t - dt)
	recover_t = maxf(0.0, recover_t - dt)
	bumped_t = maxf(0.0, bumped_t - dt)
	noise_t -= dt
	if noise_t <= 0.0:
		noise_t = 1.0
		noise = 1.0 + rng.randfn(0.0, float(Tuning.STYLE_JUDGEMENT_NOISE[style]))
	replan_t -= dt
	if replan_t <= 0.0:
		replan_t = 0.3 * rng.randf_range(0.7, 1.3)
		_replan_lane(sim)

	# ---- autopilot target speed
	# Loose surfaces (a segment's "grip", e.g. the muddy farm track) cut grip like rain does.
	# Grip stars bite through rain and mud: they shrink how much grip both take away.
	var bite: float = 1.0 - Tuning.WET_GRIP_PER_STAR * st["grip"]
	# Wet planks (a segment's "rain_slick") lose more grip in the rain, whatever the tyres.
	var wet: float = rain * (bite + float(seg.get("rain_slick", 1.0)) - 1.0)
	var rain_true := (1.0 - Tuning.RAIN_GRIP_LOSS * wet) * (1.0 - (1.0 - float(seg.get("grip", 1.0))) * bite)
	# The autopilot knows its tyres: its rain estimate shrinks with grip too (wrong by style).
	# Mud it sees (the stretch's sign); rain it misjudges.
	var rain_seen := (1.0 - float(Tuning.RAIN_PERCEIVED_LOSS[style]) * wet) * (1.0 - (1.0 - float(seg.get("grip", 1.0))) * bite)
	var boost_grip := Tuning.BOOST_WEAK_GRIP if weak_grip_t > 0.0 else 1.0
	plan_t -= 1
	if plan_t <= 0:
		plan_t = 3
		# Spinning wheels after an off-zone tap: the autopilot knows and drives to the lower grip.
		var corner_f := grip_f * float(Tuning.STYLE_CORNER[style]) * rain_seen * boost_grip * noise
		var p := _plan(corner_f, float(Tuning.STYLE_PLAN_DECEL[style]))
		target_v = p[0]
		ref_v = p[1]
	var tv := target_v * (1.0 + boost_amt)
	if weak_grip_t > 0.0:
		tv *= Tuning.BOOST_WEAK_DRIVE
	var cap := top * (1.0 + boost_amt)
	tv = minf(tv, cap)
	if in_water:
		# Rain swells the fords; water stars wade through anyway.
		var deep: float = Tuning.WATER_RAIN_LOSS * rain * (1.0 - st["water"] / 5.0)
		var wade: float = Tuning.WATER_BASE + Tuning.WATER_SPAN * pow(st["water"] / 5.0, Tuning.WATER_CURVE)
		tv = minf(tv, top * (wade - deep))
	# Flat out only when the kart can hold its speed: grip on a wet road, stability in the open
	# wind. A fast kart without them is held back towards the safe speed.
	rain_capped = false
	wind_capped = false
	var wet_safe: float = Tuning.RAIN_SAFE_BASE + Tuning.RAIN_SAFE_PER_GRIP * st["grip"]
	var wet_cap := (top - rain * maxf(0.0, top - wet_safe)) * (1.0 + boost_amt)
	if tv > wet_cap:
		tv = wet_cap
		rain_capped = true
	var gale := clampf(exposure * weather.wind_strength() / Tuning.WIND_SAFE_FULL, 0.0, 1.0)
	var wind_safe: float = Tuning.WIND_SAFE_BASE + Tuning.WIND_SAFE_PER_STAB * st["stability"]
	var wind_cap := (top - gale * maxf(0.0, top - wind_safe)) * (1.0 + boost_amt)
	if tv > wind_cap:
		tv = wind_cap
		wind_capped = true
	var wind_res: float = 1.0 - Tuning.WIND_RESIST_PER_STAB * st["stability"]
	var wind_a: float = Tuning.WIND_ACCEL * weather.wind_vec().dot(n) * wind_res
	if exposure > 0.0:
		# Gusts on open ground; headwind/side drag slows light, unstable racers.
		wind_a *= 1.0 + Tuning.WIND_GUST * sin(float(ticks) * 0.045 + gust_phase)
		var drag: float = Tuning.WIND_DRAG * weather.wind_strength() * exposure * wind_res
		tv *= 1.0 - drag
	if exposure > 0.5 and absf(wind_a) > 0.5:
		tv *= 1.0 - float(Tuning.STYLE_WIND_CAUTION[style]) * minf(1.0, absf(wind_a) / Tuning.WIND_ACCEL)
	if recover_t > 0.0:
		tv *= recover_mult
	if not detour.is_empty():
		tv *= 0.85  # gone round again by mistake: the racer slows while finding the exit
	if follow_v >= 0.0:
		tv = minf(tv, follow_v + 0.2)

	# ---- longitudinal
	if not airborne:
		var acc := accel * (Tuning.BOOST_ACCEL_MULT if boost_t > 0.0 else 1.0)
		if in_water:
			acc *= 0.6
		if v < tv:
			v = minf(tv, v + acc * dt)
		else:
			# Brakes bite less on a wet road: a late braker (daring) arrives too fast and slides.
			var brk := Tuning.BRAKE * (2.0 if in_water else 1.0) * (1.0 - Tuning.RAIN_BRAKE_LOSS * rain)
			v = maxf(tv, v - brk * dt)

	# ---- lateral
	slipping = false
	var exp_now := exposure
	if airborne and exposure > 0.0:
		exp_now = Tuning.WIND_EXPOSURE_AIR
	wind_lat = wind_a * exp_now
	vd += wind_lat * dt
	if not airborne:
		var corr_max: float = (Tuning.LAT_CORR_BASE + Tuning.LAT_CORR_PER_GRIP * st["grip"]) * rain_true * boost_grip
		var ak := absf(k)
		if ak > Tuning.CORNER_MIN_K:
			var vlim := sqrt(Tuning.CORNER_ACCEL / ak) * grip_f * rain_true * boost_grip * Tuning.SLIP_MARGIN
			if v > vlim:
				slipping = true
				var excess := v - vlim
				vd += signf(k) * excess * Tuning.SLIP_DRIFT * dt
				v -= excess * Tuning.SLIP_SCRUB * dt
				corr_max *= 0.5
		var want := clampf((d_target - d) * Tuning.LAT_P, -Tuning.LAT_VMAX, Tuning.LAT_VMAX)
		var corr := clampf((want - vd) * Tuning.LAT_D, -corr_max, corr_max)
		vd += corr * dt
		# Bouncy racers wobble in tight bends.
		if st["bounce"] >= Tuning.BOUNCE_WOBBLE_MIN_STARS and ak > Tuning.BOUNCE_WOBBLE_K and v > 6.0:
			bounce_t += dt
			vd += sin(bounce_t * 14.0) * (st["bounce"] - 3) * 2.0 * dt
			v -= (st["bounce"] - 3) * 0.9 * dt
			wobble += 0.15 * dt
		else:
			bounce_t = 0.0
	else:
		wobble += absf(wind_lat) * 0.12 * dt
	d += vd * dt
	if not airborne:
		wobble = maxf(0.0, wobble - (0.5 + 0.1 * st["stability"]) * dt)

	if bool(seg["rails"]) or bool(seg.get("low_rails", false)):
		var lim := hw - 0.45
		if absf(d) > lim:
			# A low rail (the causeway) stops a kart that reaches it slowly; one blown into it
			# hard tips over it. Either way the kart never drives through the rail.
			if bool(seg.get("low_rails", false)) and absf(vd) > Tuning.RAIL_TOPPLE_VD:
				d = clampf(d, -lim, lim)
				_fail(sim, "off_track")
				return
			d = clampf(d, -lim, lim)
			vd = 0.0
			v *= 1.0 - 0.8 * dt
	elif not airborne and absf(d) > hw + float(seg["edge"]):
		_fail(sim, "off_track")
		return

	# ---- advance along the route
	var prev_ls := ls
	ls += v * dt
	var was_water := in_water
	if detour.is_empty() and seg.has("miss") and prev_ls < float(seg["miss"]["at"]) and ls >= float(seg["miss"]["at"]):
		_maybe_miss_exit(sim, rain)
	while ls > route().length:
		if not detour.is_empty():
			_end_detour(sim)
			continue
		if seg_idx >= segs.size() - 1:
			if not looping or _lap_done(sim):
				ls = route().length
				_account(sim, dt, k, rain, exposure)
				_finish(sim)
				return
			ls -= route().length
			prev_ls = -1.0
			seg_idx = 0
			seg = segs[0]
			seg_id = seg["id"]
			_enter_stretch()
			section = seg["section"]
			stuck_best = 0.0
			detour_travel = 0.0
			continue
		ls -= route().length
		prev_ls = -1.0
		seg_idx += 1
		seg = segs[seg_idx]
		seg_id = seg["id"]
		_enter_stretch()
		var new_section: String = seg["section"]
		if new_section != section:
			_close_split(sim)
			section = new_section
		if absf(d) > half_width() - 0.3:
			d = signf(d) * (half_width() - 0.3)
	# Water entry splash
	if not was_water and not airborne and Course.in_ranges(seg["water"], ls):
		v *= 1.0 - maxf(0.0, Tuning.WATER_ENTRY_DRAG - 0.025 * st["water"])

	# ---- vertical
	var ground: float = sim.course.surface_y(seg, ls)
	if airborne:
		vy -= Tuning.GRAVITY * dt
		y += vy * dt
		if y <= ground:
			y = ground
			_land(sim)
			if state != "racing":
				return
	else:
		var ramp: Dictionary = seg["ramp"]
		if not ramp.is_empty() and prev_ls < float(ramp["lip_s"]) and ls >= float(ramp["lip_s"]):
			airborne = true
			jump_air = true
			# Take off from the top of the lip (`ground` is already the pit floor past it).
			y = sim.course.surface_y(seg, float(ramp["lip_s"]))
			vy = Tuning.LAUNCH_VY_BASE + Tuning.LAUNCH_VY_PER_STAR * st["jump"]
		else:
			for b in seg["bumps"]:
				if prev_ls < float(b) and ls >= float(b):
					# Springy (bounce) karts soak a bump: less speed lost and a smaller hop.
					v *= 1.0 - maxf(0.0, Tuning.BUMP_LOSS_BASE - Tuning.BUMP_LOSS_PER_BOUNCE * st["bounce"])
					airborne = true
					jump_air = false
					vy = maxf(0.3, Tuning.BUMP_HOP_BASE - Tuning.BUMP_HOP_PER_BOUNCE * st["bounce"])
					# ...and rattles on a while after it (a stiff kart more): logged as a bumpy landing.
					var rattle := Tuning.BUMP_RATTLE_S * maxf(0.0, 1.0 - Tuning.BUMP_RATTLE_PER_BOUNCE * st["bounce"])
					if rattle > recover_t:
						recover_t = rattle
						recover_mult = Tuning.BUMP_RATTLE_MULT
			y = ground

	_account(sim, dt, k, rain, exposure)

	# ---- fails
	var g := gs() + detour_travel + (ls if not detour.is_empty() else 0.0)
	if g > stuck_best + 1.0:
		stuck_best = g
		stuck_t = 0.0
	else:
		stuck_t += dt
		if stuck_t * 1000.0 >= float(sim.config.get("stuckTimeoutMs", 3000)):
			_fail(sim, "stuck")
			return
	# On a loop the cap is per lap: a lap that slow means the racer is in trouble.
	if (lap_ms() if looping else elapsed_ms()) >= int(sim.config.get("runTimeCapMs", 90000)):
		_fail(sim, "timeout")
		return

	# ---- outputs
	if ticks % 6 == 0:
		_trace_sample()
	if ticks - last_progress_tick >= 12:
		last_progress_tick = ticks
		var pr := {
			"runId": run_id, "progress": snappedf(progress(), 0.001), "elapsedMs": elapsed_ms(),
			"section": section, "boostsLeft": boosts_left,
		}
		if looping:
			pr["lap"] = lap + 1
			pr["lapMs"] = lap_ms()
		sim.emit("game.run.progress", pr)


func _land(sim) -> void:
	airborne = false
	vy = 0.0
	if absf(d) > half_width() + float(seg["edge"]) and not bool(seg["rails"]) and not bool(seg.get("low_rails", false)):
		_fail(sim, "off_track")
		return
	if not jump_air:
		return
	jump_air = false
	var ramp: Dictionary = seg["ramp"]
	if not ramp.is_empty() and ls < float(ramp["land_s"]):
		var short := float(ramp["land_s"]) - ls
		v *= clampf(0.45 - 0.04 * short, 0.15, 0.45)
		recover_t = Tuning.BAD_LANDING_RECOVER
		recover_mult = 0.45
		wobble += 0.35 + 0.06 * short
		_episode_force("bad_landing")
		if wobble > Tuning.FLIP_WOBBLE + 0.1 * st["stability"]:
			_fail(sim, "flipped")
	else:
		v *= 1.0 + 0.01 * st["bounce"]
		recover_t = Tuning.LANDING_RECOVER * (1.0 - 0.12 * st["bounce"])
		recover_mult = 0.95
		if wobble > Tuning.FLIP_WOBBLE + 0.6 + 0.1 * st["stability"]:
			_fail(sim, "flipped")


# ---------------------------------------------------------------- boost / bumps

func boost(sim) -> void:
	if state != "racing" or boosts_left <= 0:
		return
	boosts_left -= 1
	boosts_used += 1
	var perfect := Course.in_ranges(seg["boosts"], ls) and not airborne
	if perfect:
		boost_amt = Tuning.BOOST_PERFECT_AMT
		boost_t = Tuning.BOOST_PERFECT_S
		v *= 1.06
	else:
		# Off a zone the wheels spin: no surge, the kart fishtails wide and loses a little time.
		boost_amt = 0.0
		boost_t = Tuning.BOOST_WEAK_S
		weak_grip_t = Tuning.BOOST_WEAK_S
		if airborne:
			wobble += 0.4
		else:
			var k := route().curv_at(ls)
			var side := signf(k) if absf(k) > Tuning.CORNER_MIN_K else (1.0 if rng.randf() < 0.5 else -1.0)
			vd += side * Tuning.BOOST_WEAK_KICK
			wobble += Tuning.BOOST_WEAK_WOBBLE
	var kind := "boost_perfect" if perfect else "boost_weak"
	_add_event({"kind": kind, "section": section, "atMs": elapsed_ms()})
	sim.emit("sim.boost", {"runId": run_id, "kind": kind})


func got_bumped(other_player: String) -> void:
	bumped_t = Tuning.BUMPED_WINDOW_S
	bumped_by = other_player
	if not airborne:
		airborne = true
		jump_air = false
		vy = 1.0 + 0.4 * st["bounce"]
	wobble += 0.15
	_episode_force("bumped")


func bumped_other(other_player: String) -> void:
	_add_event({"kind": "bumped_other", "section": section, "atMs": elapsed_ms(), "otherPlayerId": other_player})


# ---------------------------------------------------------------- time-loss events

func _cause(k: float, exposure: float) -> String:
	if slipping:
		return "slip"
	if weak_grip_t > 0.0:
		return "boost_weak"
	if rain_capped:
		return "slip"
	if wind_capped:
		return "wind_push"
	if bumped_t > 0.0:
		return "bumped"
	if recover_t > 0.0 and recover_mult < 0.9:
		return "bad_landing"
	if absf(wind_lat) > 1.0 or (exposure > 0.5 and absf(wind_lat) > 0.5):
		return "wind_push"
	if in_water:
		return "water_slow"
	if bounce_t > 0.0:
		return "bounce_wobble"
	if absf(k) > Tuning.CORNER_MIN_K * 3.0 and target_v < top * 0.97:
		return "slow_corner"
	return ""


func _account(sim, dt: float, k: float, rain: float, exposure: float) -> void:
	var cause := _cause(k, exposure)
	var loss := 0.0
	if cause == "slow_corner":
		# Compared to a reference driver with grip 3.75 and balanced style.
		var refc := minf(top, ref_v / (grip_f * float(Tuning.STYLE_CORNER[style])))
		loss = maxf(0.0, 1.0 - v / maxf(refc, 0.1))
	elif cause != "":
		loss = maxf(0.0, 1.0 - v / maxf(minf(ref_v, top), 0.1))
	if cause != "" and not episode.is_empty() and episode["kind"] == cause:
		episode["loss"] = float(episode["loss"]) + loss * dt
		episode["idle"] = 0.0
	elif cause != "":
		_close_episode()
		episode = {"kind": cause, "section": section, "stretch": seg["stretch"], "atMs": elapsed_ms(),
			"loss": loss * dt, "idle": 0.0, "other": bumped_by if cause == "bumped" else ""}
	elif not episode.is_empty():
		episode["idle"] = float(episode["idle"]) + dt
		if float(episode["idle"]) >= Tuning.EVENT_IDLE_CLOSE_S:
			_close_episode()


func _episode_force(kind: String) -> void:
	if not episode.is_empty() and episode["kind"] == kind:
		return
	_close_episode()
	episode = {"kind": kind, "section": section, "stretch": seg["stretch"], "atMs": elapsed_ms(),
		"loss": 0.0, "idle": 0.0, "other": bumped_by if kind == "bumped" else ""}


func _close_episode() -> void:
	if episode.is_empty():
		return
	var ms := int(round(float(episode["loss"]) * 1000.0))
	if ms >= Tuning.EVENT_MIN_LOSS_MS or episode["kind"] == "bumped" or episode["kind"] == "bad_landing":
		var e := {"kind": episode["kind"], "section": episode["section"], "stretch": episode["stretch"],
			"atMs": episode["atMs"], "timeLostMs": ms}
		if String(episode["other"]) != "":
			e["otherPlayerId"] = episode["other"]
		_add_event(e)
		_stretch_lost(episode["stretch"], ms)
	episode = {}


## Every event names the stretch it happened on (episodes: where they began).
func _add_event(e: Dictionary) -> void:
	if not e.has("stretch"):
		e["stretch"] = seg["stretch"]
	if events.size() < Tuning.MAX_EVENTS:
		events.append(e)


# ---------------------------------------------------------------- stretches

## The racer is on a new segment: start its stretch unless it is the same one (mill into farm,
## round the roundabout again).
func _enter_stretch() -> void:
	var id: String = seg["stretch"]
	if stretch_log.is_empty() or stretch_log.back()["id"] != id:
		stretch_log.append({"id": id, "ticks": 0, "lost_ms": 0})


## A loss event's time goes to its stretch on this lap (one that began on the last lap is dropped).
func _stretch_lost(id: String, ms: int) -> void:
	for i in range(stretch_log.size() - 1, -1, -1):
		if stretch_log[i]["id"] == id:
			stretch_log[i]["lost_ms"] += ms
			return


## Payload form: [{id, ms, lostMs}].
func _stretch_times(log: Array) -> Array:
	var out: Array = []
	for s in log:
		out.append({"id": s["id"], "ms": int(round(s["ticks"] * 1000.0 / Tuning.HZ)), "lostMs": s["lost_ms"]})
	return out


# ---------------------------------------------------------------- splits / end

## At a segment's "miss" point: maybe carry on round the loop segment instead of exiting.
## Daring drivers, boosting and rain make it likelier; careful drivers rarely miss.
func _maybe_miss_exit(sim, rain: float) -> void:
	var m: Dictionary = seg["miss"]
	var chance := (float(m["chance"]) + (Tuning.MISS_BOOST if boost_t > 0.0 else 0.0) + Tuning.MISS_RAIN * rain) \
		* float(Tuning.MISS_STYLE[style])
	miss_chance = chance
	if rng.randf() >= chance:
		return
	var loop_seg: Dictionary = course_ref.segments[m["seg"]]
	detour = {"seg": seg, "at": float(m["at"]), "start_tick": ticks}
	ls -= float(m["at"])
	seg = loop_seg
	seg_id = seg["id"]


func _end_detour(sim) -> void:
	var loop_len := route().length
	ls -= loop_len
	detour_travel += loop_len
	var lost := int(round((ticks - int(detour["start_tick"])) * 1000.0 / Tuning.HZ))
	_add_event({"kind": "missed_exit", "section": section, "atMs": elapsed_ms(), "timeLostMs": lost})
	_stretch_lost(seg["stretch"], lost)
	seg = detour["seg"]
	seg_id = seg["id"]
	ls += float(detour["at"])
	detour = {}


func _close_split(sim) -> void:
	var ms := elapsed_ms() - int(round(section_start_tick * 1000.0 / Tuning.HZ))
	splits[section] = ms
	section_start_tick = ticks
	sim.emit("game.run.section", {"runId": run_id, "section": section, "splitMs": ms})


func _trace_sample() -> void:
	var p := world_pos()
	trace.append_array([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01),
		snappedf(route().heading_at(ls), 0.01), snappedf(-ground_pitch(), 0.01)])


func _summary() -> Dictionary:
	events.sort_custom(func(a, b): return int(a["atMs"]) < int(b["atMs"]))
	var p := {
		"runId": run_id, "section": section, "elapsedMs": elapsed_ms(), "splits": splits.duplicate(),
		"events": events.duplicate(true), "boostsUsed": boosts_used, "weatherSeen": weather_seen.keys(),
	}
	if looping:
		p["laps"] = laps.duplicate()
		if best_lap >= 0:
			p["bestLapMs"] = best_lap_ms()
			p["splits"] = best_splits.duplicate()
	return p


## The racer crossed the line on a loop track: book the lap and say whether the run ends here
## (pit requested or lap cap reached). Otherwise start the next lap.
func _lap_done(sim) -> bool:
	_close_split(sim)
	_trace_sample()
	var ms := lap_ms()
	laps.append(ms)
	lap += 1
	var is_best := best_lap < 0 or ms < laps[best_lap]
	var stretches := _stretch_times(stretch_log)
	if is_best:
		best_lap = laps.size() - 1
		best_splits = splits.duplicate()
		best_trace = trace.duplicate()
		best_stretches = stretches
	sim.emit("game.run.lap", {"runId": run_id, "lap": lap, "lapMs": ms, "elapsedMs": elapsed_ms(),
		"splits": splits.duplicate(), "stretches": stretches, "weatherSeen": lap_weather.keys(), "isBest": is_best})
	if pit_requested or (laps_max > 0 and lap >= laps_max):
		return true
	lap_start_tick = ticks
	section_start_tick = ticks
	splits = {}
	trace = []
	stretch_log = []
	lap_weather = {}
	return false


func _finish(sim) -> void:
	_close_episode()
	if not looping:
		_close_split(sim)
		_trace_sample()
	state = "finished"
	var p := _summary()
	p.erase("section")
	p["stretches"] = best_stretches if looping else _stretch_times(stretch_log)
	# On a loop the ghost is the best lap.
	p["trace"] = {"runId": run_id, "hz": 10, "samples": best_trace if looping else trace}
	sim.emit("game.run.finished", p)


func _fail(sim, reason: String) -> void:
	_close_episode()
	state = "failed"
	fail_reason = reason
	var p := _summary()
	p["reason"] = reason
	# The stretches done on this lap; the one it failed on is unfinished.
	p["stretches"] = _stretch_times(stretch_log.slice(0, stretch_log.size() - 1))
	p["stretch"] = seg["stretch"]
	sim.emit("game.run.failed", p)


func abort() -> void:
	state = "aborted"


# ---------------------------------------------------------------- rendering helpers

func world_pos() -> Vector3:
	var p := route().world_at(ls, d)
	p.y = y
	return p


func yaw() -> float:
	return route().heading_at(ls) + clampf(vd * 0.08, -0.5, 0.5)


func pitch() -> float:
	if airborne:
		return clampf(-vy * 0.04, -0.5, 0.5)
	return -ground_pitch()


## Slope of the surface under the kart, including the kicker and the landing wedge (the bare
## centre line is flat there, so a kart pitched by it noses into the kicker).
func ground_pitch() -> float:
	var r := route()
	var s0 := ls - 0.75
	var s1 := ls + 0.75
	var ramp: Dictionary = seg["ramp"]
	if not ramp.is_empty():
		# Don't measure across the drop at the lip.
		var lip: float = ramp["lip_s"]
		if ls <= lip:
			s1 = minf(s1, lip)
		else:
			s0 = maxf(s0, lip + 0.01)
	var a := r.pos_at(s0)
	var b := r.pos_at(s1)
	var ya := a.y + Course.surface_offset(seg, s0)
	var yb := b.y + Course.surface_offset(seg, s1)
	var h := Vector2(b.x - a.x, b.z - a.z).length()
	return atan2(yb - ya, maxf(h, 0.001))


func roll() -> float:
	return sin(ticks * 0.4) * minf(wobble, 1.5) * 0.35 + (0.25 if slipping else 0.0) * signf(route().curv_at(ls))
