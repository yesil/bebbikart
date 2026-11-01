extends RefCounted
## All gameplay tuning numbers in one place (game.md "Stat mapping"). Tune with tools/sweep.gd.

const HZ := 60
const DT := 1.0 / 60.0

# Stars: players spend 20 (max 10 per ability). Every per-star number below is tuned on the
# original 10-star scale (max 5), so one star counts as half of one of those steps; racer.gd
# turns stars into that effect level. A 10-star ability is as strong as a 5-star one was.
const STAR_STEP := 0.5

# Speed / acceleration
const TOP_SPEED_BASE := 14.0      # m/s
const TOP_SPEED_PER_STAR := 2.4
const ACCEL_BASE := 9.0           # m/s^2
const ACCEL_HIGH_SPEED_PENALTY := 0.05  # per speed star above 3
const ACCEL_STABILITY_PENALTY := 0.03   # per stability star
const BRAKE := 14.0
const RAIN_BRAKE_LOSS := 0.4      # braking in full rain, whatever the tyres (daring plans for 11)
const BOOST_ACCEL_MULT := 1.8

# Cornering. Corner speed = sqrt(CORNER_ACCEL / |k|) * gripFactor * style * rain
const CORNER_ACCEL := 17.0
const GRIP_FACTOR_BASE := 0.7
const GRIP_FACTOR_PER_STAR := 0.08
const CORNER_MIN_K := 0.004       # below this curvature a bend is treated as straight
const STYLE_CORNER := {"careful": 0.93, "balanced": 1.0, "daring": 1.03}
const STYLE_PLAN_DECEL := {"careful": 7.0, "balanced": 8.5, "daring": 11.0}  # how late it brakes
const STYLE_SLIP_MARGIN := {"careful": 1.2, "balanced": 1.15, "daring": 1.11}  # real grip limit vs. its own estimate
const STYLE_JUDGEMENT_NOISE := {"careful": 0.01, "balanced": 0.025, "daring": 0.045}
const STYLE_PASS_OFFSET := {"careful": 2.4, "balanced": 2.0, "daring": 1.6}
const STYLE_MISJUDGE := {"careful": 0.08, "balanced": 0.15, "daring": 0.25}
const STYLE_WIND_CAUTION := {"careful": 0.15, "balanced": 0.1, "daring": 0.05}

# Steering (contracts §2g): the kid's thumb sets the lane, x in [-1, 1] across the road (+ is
# right, as the big screen shows it). Let go and the kart holds that lane STEER_HOLD_S, then the
# autopilot takes over again; a thumb that steered within FORK_APPROACH_M of a fork keeps its lane
# until the fork, and the side the kart is on there picks the way. Hands off, the autopilot
# leans towards the way its stars like from FORK_APPROACH_M out and takes it.
const STEER_LANE_MARGIN := 0.15   # m inside the rail limit the full-lock lane sits
const STEER_LANE_MARGIN_LOW := 0.6  # on a low rail (the causeway), so a gust there doesn't tip it over
const STEER_HOLD_S := 1.2
const STEER_LAT_VMAX := 4.5       # m/s sideways towards a steered lane (the autopilot: LAT_VMAX)
const STEER_DEADBAND := 0.25      # m from the middle at a fork: no side, the stars choose
const FORK_APPROACH_M := 60.0
const FORK_LEAN := 0.5            # share of the lane the autopilot leans towards its way

# Rails everywhere: no road lets a kart off. On an open road the kart's centre stops this far
# inside half_width (its body overhangs onto the shoulder); railed lanes stop it at
# Course.RAIL_INSET. Scraping along one costs speed.
const OPEN_RAIL_INSET := 0.2
const RAIL_SCRAPE_DRAG := 0.8     # share of speed lost per second scraping

# Rain: real grip vs. what the autopilot assumes (it under-reacts, careful less so)
const RAIN_GRIP_LOSS := 0.22
const WET_GRIP_PER_STAR := 0.12   # grip level cuts the grip rain and mud (segment "grip") take away
# Safe speed (m/s) a kart drives flat out at in full rain / full open wind: grip / stability raise
# it. A faster kart is held towards it (rain intensity, exposure x wind strength).
const RAIN_SAFE_BASE := 15.0
const RAIN_SAFE_PER_GRIP := 0.9
const WIND_SAFE_BASE := 15.0
const WIND_SAFE_PER_STAB := 1.6
const WIND_SAFE_FULL := 0.8        # exposure x wind strength at which the whole cap applies
const RAIN_PERCEIVED_LOSS := {"careful": 0.23, "balanced": 0.19, "daring": 0.05}

# Slip
const SLIP_MARGIN := 1.18         # real grip limit vs. the autopilot's calm estimate
const SLIP_DRIFT := 2.0           # lateral accel per m/s of excess speed
const SLIP_SCRUB := 2.2           # speed loss per m/s of excess speed

# Lateral control
const LAT_CORR_BASE := 3.0        # max correction accel (m/s^2)
const LAT_CORR_PER_GRIP := 0.9
const LAT_P := 1.4
const LAT_VMAX := 3.0
const LAT_D := 5.0
const OFF_TRACK_MARGIN := 0.9     # soft shoulder of a road's corridor (Course.corridor_half: keep props out)
const RAIL_TOPPLE_VD := 0.9       # lateral m/s at a low rail that tips the kart over it (off_track, the one left)

# Water
# Speed in water, share of top speed: BASE + SPAN x (level / 5)^CURVE, so 10 stars wade at 0.95
# (never faster than the dry road) and the stars pay off most at the top end.
const WATER_BASE := 0.30
const WATER_SPAN := 0.65
const WATER_CURVE := 1.7
const WATER_RAIN_LOSS := 0.14      # fords in full rain, at 0 water stars (none at 10)
const WATER_ENTRY_DRAG := 0.12    # one-off splash loss, minus 0.025 per water star

# Jumping
const GRAVITY := 16.0
const LAUNCH_VY_BASE := 1.0
const LAUNCH_VY_PER_STAR := 1.45
const BUMP_LOSS_BASE := 0.10       # speed lost per bump (cobbles, humps), minus this per bounce level
const BUMP_LOSS_PER_BOUNCE := 0.018
const BUMP_HOP_BASE := 1.6         # hop vy off a bump (no drive while in the air)
const BUMP_HOP_PER_BOUNCE := 0.2
const BUMP_RATTLE_S := 0.6         # after a bump the kart holds BUMP_RATTLE_MULT of its speed this long,
const BUMP_RATTLE_PER_BOUNCE := 0.18  # shorter per bounce level
const BUMP_RATTLE_MULT := 0.75
const LANDING_RECOVER := 0.3      # s, reduced by bounce
const BAD_LANDING_RECOVER := 2.2
const FLIP_WOBBLE := 1.25         # + 0.1 per stability

# Bounce wobble in tight bends
const BOUNCE_WOBBLE_MIN_STARS := 4  # effect level, i.e. 8 stars
const BOUNCE_WOBBLE_K := 1.0 / 22.0

# Wind
const WIND_ACCEL := 6.0          # lateral accel at strength 1, perpendicular, fully exposed
const WIND_RESIST_PER_STAB := 0.15
const WIND_EXPOSURE_AIR := 0.7
const WIND_GUST := 0.5           # +-50% gusting on exposed ground
const WIND_DRAG := 0.3            # top-speed loss at strength 1, fully exposed, 0 stability

# Boost arrows: glowing strips on one side of the road (a course's boosts, [a, b, side]). A kart
# that drives over one surges, once per strip per lap. Hands off, the autopilot keeps clear of
# them: they are the steering kid's.
const BOOST_PERFECT_AMT := 0.35
const BOOST_PERFECT_S := 1.2
const BOOST_ARROW_HALF := 1.1     # half width of a strip (m)
const BOOST_ARROW_CATCH := 0.3    # the kart's centre may be this far outside the strip and still catch it

# Collisions. Each racer is its footprint rectangle along its yaw, as wide and long as its built
# toy (main.gd measures it). Sizes are clamped so a big hat or wings never make a racer a wall.
# Headless tools and mock racers pass DEFAULT_SIZE.
const RADIUS := 0.85               # the old fixed circle's radius; also the kart clearance of course.gd
const DEFAULT_SIZE := Vector2(0.6, 0.85)       # half width, half length (m): a typical kart
const SIZE_HALF_WIDTH := Vector2(0.45, 0.95)   # clamp (two of the widest still fit the 2 m start lanes)
const SIZE_HALF_LENGTH_MAX := 1.3
const RESTITUTION := 0.3
const MASS_PER_STAB := 0.25
const BUMP_LOG_IMPULSE := 1.2
const BUMPED_WINDOW_S := 1.5

# Start
const START_LANES: Array[float] = [-3.0, -1.0, 1.0, 3.0]
const START_GAP := 2.0            # free metres ahead of the racer's body before release
const START_HOLD_M := 35.0        # first lap: drive the start slot's line this far before the own line

# Events
const EVENT_MIN_LOSS_MS := 60
const EVENT_IDLE_CLOSE_S := 0.6
const MAX_EVENTS := 40

# Missed roundabout exit (village): (course chance + boosting + rain) x style. Careful drivers
# almost never miss; daring ones, boosting in the rain, do.
const MISS_STYLE := {"careful": 0.1, "balanced": 0.4, "daring": 1.6}
const MISS_BOOST := 0.08
const MISS_RAIN := 0.15
