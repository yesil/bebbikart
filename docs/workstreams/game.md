# WS3 — Big-Screen Game

**Lives in:** `apps/game` (a Godot 4 project) · **Depends on:** the message and asset formats in `contracts.md` (not on JS code)
**Read first:** [`../README.md`](../README.md) §2, [`../contracts.md`](../contracts.md) §5, §7, §8, and the original brief §2, §4, §6, §8 for tone, course beats, abilities and weather.

## Goal

A bright, readable 3D toy world on a big screen where up to 20 kid-drawn racers drive themselves through one short course at the same time. Kids should be able to **see why** their run was fast or slow. It runs as a fullscreen **Godot desktop app** on the event Mac and owns all simulation, timing and weather.

This is the largest workstream. It splits cleanly into four sub-streams that can run in parallel once the course spline exists:

| Sub-stream          | Owns                                                                                                                                            |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| **3a World & art**  | Course geometry, scenery, materials, lighting, weather visuals, sounds                                                                          |
| **3d Racer kit**    | Toy-part kit, building racers from `RacerSpec`, faces and expressions, racer animation, avatar renders, Racer Viewer scene, kit catalog for WS5 |
| **3b Simulation**   | Fixed-timestep sim, vehicle model, autopilot, forks, boost, weather state machine, fail rules, timing, splits, events, traces, coach tips       |
| **3c Presentation** | Camera director, HUD, mini-map, leaderboard, paddock, ghosts, podium, QR panel, server connection                                               |

## Stack (default)

**[Godot 4](https://godotengine.org)** (latest stable), **GDScript**, exported as a **native macOS app** (it can also just run from the Godot editor on the Mac). Why Godot over a browser engine: a real editor for building the world, lighting, particles, animation and cameras; native performance (smoother than a browser tab); and a 3D toolset that makes the "game feel" work much faster. The game talks to the Bun server only through the WebSocket messages and asset URLs in `contracts.md`, so nothing else in the project has to know it's Godot.

- **Renderer:** Forward+ (Metal on Apple Silicon). If an older Intel Mac struggles, switch to the Compatibility renderer and simplify lighting.
- **Physics:** no rigid-body vehicles in V1. An **arcade model on a course path** (`Path3D` / `Curve3D`, below) is more predictable, easier to tune and cheap with 20 racers. Godot physics only for cosmetic stuff (confetti, splashing props).
- **Scenery:** built in the Godot editor from CC0 kits (Kenney, Quaternius, restyled) or Blender glTF, textures ≤ 2K.
- **Networking:** `WebSocketPeer` polled in `_process`, `JSON.parse_string`. Message names and enums live in `res://net/protocol.gd`, generated from `packages/shared` by `bun run kit:export` (never edit it by hand).
- **Kids' assets:** download `character.png` / `vehicle.png` with `HTTPRequest`, then `Image.load_png_from_buffer` → `ImageTexture`, cached per package.
- **Target: 60 fps at 1080p on the event Mac with 20 racers.** Vsync on, fullscreen.

## Course (V1)

One loop-free course, start → finish, **~25–35 s** for a balanced build. Four timed sections, three forks:

| #   | Section (`SectionId`) | Beat                                                              | Fork                                                          | Trade-off                                                                                                                                                |
| --- | --------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `hills`               | Bouncy hills and ramps. Boost zone on the last downhill.          | **ramp**: `jump` over a big ramp, or drive `around`           | Jump route is ~2 s shorter but needs `jump` ≥ 2. Weak jump = short landing = `bad_landing` slowdown. Wind mid-air pushes sideways (`stability` resists). |
| 2   | `pond`                | Splash pond                                                       | **pond**: `water` shortcut or dry `bridge`                    | Water route is ~3 s shorter at `water` 4–5, a wash at 2, slower at 0–1 (`water_slow`). Rain doesn't matter here.                                         |
| 3   | `crossing`            | Breezy elevated crossing (safe-looking, low rails, no scary drop) | **crossing**: `exposed` fast bridge or `sheltered` hedge path | Exposed is ~2 s shorter, but in wind needs `stability` or gets `wind_push` → can go `off_track`. Sheltered ignores wind.                                 |
| 4   | `bends`               | Rainbow bends, then the finish gantry and grandstand              | none                                                          | Pure grip test. Rain cuts grip. `speed` + `daring` + rain = `slip`. Boost zone on the straight before the arch.                                          |

Forks join back before the next section line, so splits are comparable whichever route was taken.

## Simulation (3b)

- **Fixed timestep 60 Hz**, decoupled from rendering. `elapsedMs = ticks × 1000/60`. Seedable RNG for tests (`?seed=123`). Gameplay seeds randomly.
- **Racer state:** distance `s` along the active route spline, lateral offset `d`, speed `v`, vertical state (grounded / airborne with `vy`), yaw wobble. World position = spline(s) + normal × d (+ height while airborne). Simpler and more stable than rigid bodies, and still looks physical with squash, bounce and tilt.
- **Autopilot:** each spline sample has a curvature and a target speed. Target speed = min(topSpeed, cornerSpeed(grip, rain, style)). Accelerates or brakes toward it. Steers `d` back toward 0 with a gain from `grip`. Takes the fork the build chose.
- **Stat mapping (starting values; tune in M3):** each formula takes the ability's level, which is its stars ÷ 2 (0–10 stars out of 20 → level 0–5; `Tuning.STAR_STEP`).

| Level (0–5) | Effect                                                                                                 |
| ----------- | ------------------------------------------------------------------------------------------------------ |
| `speed`     | topSpeed = 12 + 2.2×speed m/s; accel slightly lower above 3                                            |
| `jump`      | ramp launch vy = 4 + 1.5×jump; also clears small bumps without slowing                                 |
| `grip`      | corner speed factor 0.7 + 0.08×grip; lateral recovery gain                                             |
| `water`     | speed multiplier in water = 0.45 + 0.12×water                                                          |
| `stability` | wind push × (1 − 0.15×stability); landing wobble ↓; accel × (1 − 0.03×stability)                       |
| `bounce`    | landing recovery time ↓ and bumps give tiny speed kicks; above 3 adds `bounce_wobble` in tight bends   |
| style       | careful 0.9× / balanced 1.0× / daring 1.12× corner target speed; daring also lowers the slip threshold |

**Design check (M3):** no single allocation should win in every weather. Keep a table of the best build per weather state from automated sweeps (below).
- **Slip:** if lateral demand > grip limit (grip × rain factor × style), the racer slides: `d` drifts and speed drops. If |d| > track half-width → `off_track` fail. Log a `slip` event with time lost.
- **Boost:** `run.boost` from the server. On a boost zone: +35% speed for 1.2 s, no penalty (`boost_perfect`). Off zone the wheels spin for 0.8 s (`boost_weak`): no surge, the kart holds 75% of its target speed, fishtails wide with grip × 0.7, and the autopilot drives to that lower grip, so it costs about 0.4 s but never throws a racer off in calm weather (rain with daring still can, rarely). The time it costs is logged as a `boost_weak` loss event, so the coach says "Boost on the glowing zones!". Regression check: `tools/start_crowd_check.gd -- --boost=onetap`. Ignored if `boostsLeft` is 0. Zones glow and pulse so the audience can shout "NOW!"
- **Fails:** `off_track`, `flipped` (bad landing at high wobble), `stuck` (no progress 3 s), `timeout` (90 s). Show a comic spin or splash, then the racer pops away in confetti. The server handles retry.
- **Events & time lost:** compare each racer to a reference "ideal" run on the same route to estimate `timeLostMs` per event. Rough is fine. It only feeds coach tips.
- **Weather state machine:** per kind (rain, wind): `calm → warning (5 s) → active → calm`, with random durations from config. Rain intensity eases in and out over 1 s. Wind direction is random per gust, strength ≤ `maxStrength`. Overlap is allowed. Emit `game.weather` on every phase change.
- **Collisions between racers (V1, M1):** racers are solid. In the path model this stays cheap: treat each racer as a circle in (distance `s`, lateral offset `d`) space, and only compare racers on the same route segment (pairwise check of ≤ 20 racers is trivial at 60 Hz). On contact:
  - Push apart along the contact line, split by mass (`mass = 1 + 0.25×stability`). The lighter racer takes more of the shove.
  - Exchange some speed along `s` (rear-ending slows the hitter and nudges the one in front). Add a small yaw wobble and, scaled by `bounce`, a little hop.
  - A hard side bump can push a racer over the edge (`off_track`) or into the water on the pond route. That is part of the fun, but tune it so it's rare.
  - Log `bumped` (with estimated `timeLostMs` and `otherPlayerId`) on the victim and `bumped_other` on the hitter.
  - **Autopilot awareness:** the autopilot tries to overtake a slower racer ahead by steering to the freer side, but with a reaction delay and imperfect judgement (daring style cuts in tighter), so bumps still happen. Never perfect avoidance: entropy is the point.
  - **Start line:** 4 start lanes. A new racer spawns in the lane with the most space and is released when the gap ahead is ≥ 2 m, so racers never spawn inside each other. The wait (if any) is before the timer starts.
  - **No blocking:** a racer stuck for 3 s fails and pops away in confetti, which also clears the track for others.
- **Ghost trace:** sample position and orientation at 10 Hz and send with `game.run.finished`.
- **Coach tips:** WS3 designs the rules (it knows the gameplay). The function lives in JS in `packages/shared/src/coach.js` and runs on the server (contracts §8). The game only has to send good `events` and `splits`.
- **Sweep tool:** `godot --headless --script res://tools/sweep.gd` runs headless sims of ~200 builds × 4 weather states × 3 crowd levels (empty, 5 and 15 other racers) and prints times, fails and best builds. This is the main balancing tool. To make it possible, keep the sim in plain GDScript classes (`RefCounted`) that don't depend on scene nodes or rendering.

## World & art (3a)

- Stylised-but-believable countryside: open meadow with gentle hills, wooded hills on the horizon, a pond and stream, a finish gantry with a grandstand, sunny HDRI light. Readable from the back of a meeting room.
- Each fork alternative has a reason in the landscape. **Ramp:** a wooden kicker over a muddy dip, or a road round a knoll. **Pond:** a cobbled ford through the pond, or a fenced lakeside lane over a stone bridge. **Crossing:** a plank causeway with low rails over a shallow valley, or a lane between hedges round the valley head.

### World pipeline

- **Source of truth:** `apps/game/sim/course.gd` (racing line), plus `world/landscape.gd` (terrain features anchored to it).
- **Tools:** Terrain3D (terrain, painting, grass instancer), Godot Road Generator (roads), ProtonScatter (trees, bushes, rocks, hedges). CC0 assets come from Quaternius, ambientCG and Poly Haven (`apps/game/assets/CREDITS.md`).
- **Re-sync roads and terrain after a course edit:** `tools/layout_map.gd` (geometry checks), then `tools/bake_world.gd` (writes `world/course_world.tscn`), then `tools/world_check.gd`.
- **Edit in the editor:** `world/decor.tscn` (landmarks) and `world/environment.tscn` (sky, sun, post-processing) are hand-editable and never overwritten by the bake. Materials in `world/materials/` and `world/vegetation/materials/` are kept across bakes.
- **Checks:** `tools/layout_map.gd` checks spacing, crossings, slope, curvature, junctions and fork angles. `tools/world_check.gd` fails on scatter on roads or water, objects more than 0.3 m off the ground, terrain through a road, anything solid inside a road's drivable corridor (`Course.corridor_half`: the band the sim lets a kart's body reach), sibling roads overlapping at different heights, or missing assets. `tools/bench.gd` reports fps with 20 racers. `tools/shots.gd` takes the fixed screenshot set. Full commands are in `apps/game/README.md`.
- **Weather visuals:** warning (clouds roll in, sky dims a little / leaves and flags start to flutter), rain (particles, puddle shine, splashes), wind (bending flowers, streaks, arrow icon). No flashes: keep changes gradual for photosensitive viewers.
- **Sound:** cheerful loop, start beep, boost whoosh, splash, boing, finish fanfare, oops. Master volume in config.

## Racer kit (3d)

Racers are **built in 3D from a `RacerSpec`** (contracts §5) that DeepSeek writes from the kid's drawing. This sub-stream makes that look great.

- **Toy-part kit:** a library of soft, rounded, vinyl-toy style parts built in Blender or the Godot editor: ~6 body shapes, ~5 head shapes, eye styles, mouth styles, brows, ~6 hair styles, ~8 hats, arms, 8 ride bases (`kart`, `bike`, `animal4`, `bird`, `board`, `rocket`, `boat`, `blob`) with wheel / leg / wing / tail variants. Each part has named **sockets** (`head_top`, `body_front`, `ride_back`…) where extras attach. Materials take palette colours; one shared toon/soft-shading material keeps everything in one style.
- **Builder:** `RacerBuilder.build(spec) → Node3D`. Picks parts, applies palette colours and scales, attaches extras (primitives) to sockets, mirrors where asked, and puts the kid's drawing as a rounded sticker decal on the ride if `drawingSticker` is set. Must be fast (< 50 ms) so racers appear the moment the spec arrives.
- **Kit catalog:** export the list of part names, one-line descriptions and sockets to `packages/shared/src/racer-kit.js` (via a small Godot tool script), so DeepSeek can only pick parts that exist.
- **Faces and expressions:** eyes, mouth and brows switch by `Mood`: `determined` while driving, `excited` on boost, `happy` in the paddock, `dizzy` (swirly eyes) after a bump, `sad` on a fail, `cheering` at the finish. Blinks every few seconds. Faces can be textures on a face plane or small swappable meshes, whatever looks best.
- **Animation (procedural, no hand-made clips needed):** body bob and lean into corners, arms on the handlebars or reins, wheels spin / legs cycle / wings flap by ride base, squash-and-stretch on landings and bumps, a jump tuck, a dizzy wobble after a bump, arms-up celebration, a wave in the paddock. `personality` tunes it: "bouncy" racers bounce more, "calm" ones less.
- **Avatar renders:** after building a racer, render it in an offscreen `SubViewport` with fixed lighting: `hero` (full racer, 3/4 view, 1024 px, transparent) and `avatar_happy/excited/sad` (head and shoulders, 512 px). Upload them with `PUT /api/game/renders/:playerId/:key`.
- **Racer Viewer scene:** watches a folder of spec files (from the WS5 CLI) and shows each racer on a turntable cycling through moods and animations. This is the main tool for tuning the kit and the DeepSeek prompt together.
- **Name tag** above each racer in its palette colour, with the `title` underneath on close-ups.

## Presentation (3c)

- **Layout (1920×1080):** main camera view; top-left session clock; top-right weather icons with warning countdown; right column leaderboard (top 10 with avatars); bottom strip **paddock** (connected racers standing by their rides, waving when they join, a ring around those on course); bottom-right mini-map with all racers as coloured dots; small QR "Join" panel in the corner (hidden during podium).
- **Camera director:** one main camera, with cuts every 4–8 s between: (1) a racer who just launched (show their name big for 2 s: everyone gets a moment), (2) the racer closest to beating the top time, (3) a racer near a fork or boost zone, (4) a wide shot when nobody is running. Never cut mid-jump.
  **Built so far** (`world/camera_director.gd`, `ui/camera_hud.gd`, see the game README): turns between the racers every 8 s (options menu: never / 5 / 8 / 10 / 15 s), longest off camera first, never mid-jump or onto a finishing racer; Tab / Shift+Tab and A on the keyboard; a phone's "Show me on the big screen" queues its racer; name pop on each cut; a face or side picture-in-picture second camera. (2)–(4) are not in yet.
- **Ghosts:** a racer's best-run ghost (white, 40% opacity) is drawn only while the camera follows that racer, to avoid clutter. At each section line, show a "+1.2 / −0.8" bubble in green or red.
- **Other racers:** all drawn and all solid. Bumps get a comic "boing" with a star burst, and a big bump gets a quick camera shake when the camera is on that racer.
- **Podium:** on session end, a short top-3 ceremony with confetti, then the full leaderboard.
- **Connection:** simple auto-reconnect WS client.
- **Mock mode:** a `--mock` launch flag (or editor setting) swaps the network autoload for a fake one that spawns fake racers from the bundled sample `RacerSpec`s, launches runs and taps boosts at random, so all of 3a and 3c work without the server.

## Task list

| #   | Task                                                                                              | Sub   | Size | Milestone |
| --- | ------------------------------------------------------------------------------------------------- | ----- | ---- | --------- |
| 1   | Course: route splines for all fork variants, section lines, boost zones, track widths              | 3a/3b | M    | M1        |
| 2   | Sim core: fixed step, racer state, autopilot, forks, stat mapping, fails                          | 3b    | L    | M1        |
| 2b  | Racer-to-racer collisions, overtaking, start lanes                                                | 3b    | M    | M1        |
| 3   | Weather state machine + effects on sim                                                            | 3b    | M    | M1        |
| 4   | Boost, events, splits, traces                                                                     | 3b    | M    | M1        |
| 5   | Headless sweep tool                                                                               | 3b    | M    | M1        |
| 6   | Toy-part kit, first version (2 bodies, 2 heads, 3 faces, 3 ride bases) + builder + catalog export | 3d    | M    | M1        |
| 6b  | Faces and moods, procedural racer animation, avatar renders + upload                              | 3d    | M    | M1        |
| 6c  | Racer Viewer scene                                                                                | 3d    | S    | M1        |
| 6d  | Full kit (all parts) and polish with WS5 prompt tuning                                            | 3d    | L    | M3        |
| 7   | Mock mode + WS client wired to contracts                                                          | 3c    | M    | M1        |
| 8   | HUD, leaderboard, paddock, mini-map, QR panel                                                     | 3c    | M    | M1        |
| 9   | Camera director + ghost display + split bubbles                                                   | 3c    | M    | M2        |
| 10  | Coach tip rules (written with WS1/WS2, implemented in `coach.js`)                                 | 3b    | S    | M2        |
| 11  | Final toy-world art pass, weather visuals, sounds                                                 | 3a    | L    | M3        |
| 12  | Podium + session end flow                                                                         | 3c    | S    | M3        |
| 13  | Balancing with sweeps + playtests                                                                 | 3b    | M    | M3        |
| 14  | macOS export + performance pass on the event Mac (20 racers, 60 fps)                              | all   | S    | M4        |

## Done when

- 20 racers run at once at 60 fps on the event Mac, in mock mode and with the real server.
- Every fork choice is the right choice for _some_ build and weather, as shown by sweep results.
- A balanced default build finishes in 25–35 s in calm weather. A deliberately bad build fails sometimes but not always.
- Each run produces correct splits, events, a trace and a sensible coach tip.
- It feels smooth: no stutter when racers spawn, finish or the weather changes (pool racers and particles, preload all assets at startup).
