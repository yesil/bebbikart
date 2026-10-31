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
const BOOST_ACCEL_MULT := 1.8

# Cornering. Corner speed = sqrt(CORNER_ACCEL / |k|) * gripFactor * style * rain
const CORNER_ACCEL := 17.0
const GRIP_FACTOR_BASE := 0.7
const GRIP_FACTOR_PER_STAR := 0.08
const CORNER_MIN_K := 0.004       # below this curvature a bend is treated as straight
const STYLE_CORNER := {"careful": 0.9, "balanced": 1.0, "daring": 1.12}
const STYLE_PLAN_DECEL := {"careful": 6.0, "balanced": 8.5, "daring": 11.0}  # how late it brakes
const STYLE_SLIP_MARGIN := {"careful": 1.2, "balanced": 1.15, "daring": 1.11}  # real grip limit vs. its own estimate
const STYLE_JUDGEMENT_NOISE := {"careful": 0.01, "balanced": 0.025, "daring": 0.045}
const STYLE_PASS_OFFSET := {"careful": 2.4, "balanced": 2.0, "daring": 1.6}
const STYLE_MISJUDGE := {"careful": 0.08, "balanced": 0.15, "daring": 0.25}
const STYLE_WIND_CAUTION := {"careful": 0.3, "balanced": 0.2, "daring": 0.1}

# Rain: real grip vs. what the autopilot assumes (it under-reacts, careful less so)
const RAIN_GRIP_LOSS := 0.22
const RAIN_PERCEIVED_LOSS := {"careful": 0.28, "balanced": 0.2, "daring": 0.12}

# Slip
const SLIP_MARGIN := 1.18         # real grip limit vs. the autopilot's calm estimate
const SLIP_DRIFT := 2.6           # lateral accel per m/s of excess speed
const SLIP_SCRUB := 1.6           # speed loss per m/s of excess speed

# Lateral control
const LAT_CORR_BASE := 3.0        # max correction accel (m/s^2)
const LAT_CORR_PER_GRIP := 0.9
const LAT_P := 1.4
const LAT_VMAX := 3.0
const LAT_D := 5.0
const OFF_TRACK_MARGIN := 0.9     # soft shoulder before off_track
const RAIL_TOPPLE_VD := 0.9       # lateral m/s at a low rail that tips the kart over it (off_track)

# Water
const WATER_BASE := 0.45
const WATER_PER_STAR := 0.12
const WATER_ENTRY_DRAG := 0.12    # one-off splash loss, minus 0.025 per water star

# Jumping
const GRAVITY := 16.0
const LAUNCH_VY_BASE := 1.0
const LAUNCH_VY_PER_STAR := 1.45
const BUMP_LOSS_BASE := 0.08
const BUMP_LOSS_PER_JUMP := 0.03
const BOUNCE_KICK := 0.01
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
const WIND_DRAG := 0.5            # top-speed loss at strength 1, fully exposed, 0 stability

# Boost
const BOOST_PERFECT_AMT := 0.35
const BOOST_PERFECT_S := 1.2
const BOOST_WEAK_AMT := 0.20
const BOOST_WEAK_S := 0.8
const BOOST_WEAK_GRIP := 0.7

# Collisions (circles in (s, d) space)
const RADIUS := 0.85
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
