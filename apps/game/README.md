# BebbiKart game (Godot 4)

The kiosk game: toy-world course, 60 Hz driving sim, weather, and a mock network so everything runs without the server.

## Run

First run `bun run setup` from the repo root to install dependencies and generate
the worlds, textures and audio (see the [setup instructions](../../README.md#setting-up-a-mac)).

From `apps/game`:

```sh
godot --headless --import                     # first time / after pulling
godot --path .                                # windowed, mock mode (default)
godot --path . -- --server                    # connect to the Bun server on ws://localhost:8080/ws
godot --headless --path . -- --duration=40 --speed=8 --seed=5 --log=summary
godot --headless --script res://tools/sweep.gd -- --builds=60 --seeds=2
```

These run on Godot's debug runtime. For real play, `bun run play` (repo root) runs the release
build `export/BebbiKart.app`, exported with the `macOS` preset in `export_presets.cfg` (needs
Godot's export templates; see [docs/local-testing.md](../../docs/local-testing.md#real-play-release-build)).

Game flags (after `--`):

| Flag | Meaning |
|---|---|
| `--mock` | Mock network. This is the default. |
| `--server[=URL]` | Real server (default `ws://localhost:8080/ws`): phone players race; their racers are built from their `RacerSpec` with the racer kit, and the game renders and uploads their hero/avatar PNGs |
| `--game-key=KEY` | Must match the server's `BK_GAME_KEY` (default `bebbikart-dev`; env `BK_GAME_KEY` also works) |
| `--racers=N` | Number of fake players in the line (default 20; 1 races full screen) |
| `--kit` | Mock mode: build the fake racers with the racer kit from `racer_kit/samples` (in turn) instead of placeholder boxes |
| `--seed=N` | RNG seed for mock players and weather |
| `--weather=calm\|rain\|wind\|storm` | Force the weather (default: the state machine) |
| `--speed=X` | Sim speed multiplier (raises the physics tick rate) |
| `--duration=SEC` | Quit after SEC wall seconds and print a summary |
| `--log=none\|summary\|full` | What outgoing messages to print |
| `--screenshot=PATH [--shot-at=SEC]` | Save a screenshot (windowed only: headless refuses it; one that can't be saved makes the run exit 1) |
| `--shots=DIR [--shot-every=SEC]` | A screenshot every SEC seconds (2) while racers are on the track, named by time and racer count, into DIR (made if missing); a frame that can't be saved makes the run exit 1 (windowed only: headless refuses it; the multiplayer harness uses it) |
| `--overlay` | Start with the debug text overlay shown (H toggles it); by default the halves' HUD is all you see |
| `--track=countryside\|village` | Mock mode: the course (default: `village`, the config's default track; with `--server` the session config picks it) |
| `--quality=low\|medium\|high` | Graphics preset (default: the options menu's last pick, else medium) |
| `--language=en\|de` | Big-screen language (default: the options menu's last pick, else the config's) |

Keys:

| Key | Action |
|---|---|
| R / W | Advance the rain / wind phase |
| K | Toggle forced calm |
| H | Show / hide the debug overlay (hidden at start) |
| Esc, or Cmd+, (also in the app menu as "Options…") | Options menu: fullscreen, graphics, sound, language, track, session, the phone address with its QR code, quit |
| Ctrl+Cmd+F, or F11 | Toggle fullscreen (on a Mac keyboard F11 may need fn) |
| Cmd+Q, or closing the window | Quit (prints the run summary) |

The options menu is where the game manager sets the game options on the big screen (phones only
join and quit). It does not pause the race.

- **Track** (one click, no question): mock mode reloads on the new course. Server mode sends
  `game.session.end`, `game.config.set {track}` and `game.session.start`: the server stops the
  karts on the track, so the course reloads on `config.updated` right away, and a new session
  with an empty leaderboard runs on it (racers stay). Refusals (`error`) and a disconnected
  server show in red in the menu.
- **Language** (English / Deutsch; `--language=en|de`, saved in `user://settings.cfg`): switches
  every big-screen string at once (`data/strings.json`, read by `ui/i18n.gd`; same keys in each
  language, checked by `bun test`). Server mode sends `game.config.set {language}`, also after
  every `welcome` when the server says otherwise, and every phone follows via `config.updated`.
  A missing key shows as `⚠ de:key` on screen and in the log, never as English.
- **Session** (server mode): **New session** (one click, any time) starts over on the same
  track: `game.session.end` then `game.session.start`. The podium shows, the karts on the track
  stop, the leaderboard starts empty, the racers stay. Mock mode has no session and says so.
  `tools/session_check.gd` clicks New session and both track changes against a running server.
- **Graphics** (`--quality=low|medium|high`, saved in `user://settings.cfg`, default Medium):
  caps the 3D resolution (Low 720p, Medium 1080p, High native; MetalFX upscaling on Metal, FSR
  elsewhere) and scales shadows, SSAO, glow and vegetation range. On a 5K Retina screen in
  fullscreen, High renders 5120×2880; Medium cut the GPU load from about +45 to +9 points on an
  M4 Max.
- Frame rate is capped at 60 fps (also on 120 Hz screens) and 30 fps while the window is in the
  background.

Sweep flags:

| Flag | Meaning |
|---|---|
| `--builds=N --seeds=N` | Number of random builds and seeds per build |
| `--quick` | Short run |
| `--steer=kid\|off` | The bots' thumbs (contracts §2g): kid steers onto the boost arrows and the stars' way; off is hands off |
| `--json=PATH` | Dump results as JSON |
| `--trace=PATH` | Write a trace |

## Layout

- `sim/`: the simulation. Plain `RefCounted` GDScript with no scene nodes, so it runs headless in the sweep.
  - `tuning.gd`: every constant.
  - `route.gd`, `course.gd`: the course and all fork variants, with section lines, boost arrow strips, rails and widths. Routes are drawn from straights and constant-radius arcs, and every fork is a Y-split with a shared 3 m stub.
  - `weather.gd`: the weather state machine.
  - `builds.gd`: stars → stats, plus random builds.
  - `forks.gd`: which side of the road each way of a fork leaves on (the side a steered kart is on at the junction picks the way, contracts §2g).
  - `racer.gd`: racer state (s/d/v/vy), autopilot, thumb steering, rails, boost arrows, fails, events, splits and traces, timed in sim ticks.
  - `sim.gd`: the fixed step, the start queue (4 lanes), collisions and the outbox.
- `net/`:
  - `protocol.gd`: generated by WS1. Do not edit.
  - `messages.gd`: envelope helpers.
  - `server_net.gd`: the real WebSocket client (`--server`): hello with the game key, auto-reconnect, unpacks `welcome`, merges `config.updated`.
  - `roster_assets.gd`: per-player specs from the roster, ride-drawing downloads, and hero/avatar renders + uploads via `AvatarRenderer`.
  - `mock_net.gd`: the fake server and phones. It spawns players with random builds (the stars choose the routes), lines them up and launches them onto the halves like the server (same split rule), steers like kids (some forks hands off, some onto the stars' way, some the other way; skilled players onto the boost arrows), and logs the `game.run.*` messages it would send.
- `world/`: the countryside world (see **World pipeline** below).
  - `course_world.tscn`: baked from the course by `tools/bake_world.gd`. Don't hand-edit.
  - `decor.tscn`, `environment.tscn`: hand-editable landmarks, sky and lighting.
  - `landscape.gd`, `terrain_shape.gd`, `viewpoints.gd`, `mesh_batch.gd`: data and helpers the bake uses.
  - `racer_view.gd`: placeholder racers (mock mode without `--kit`).
  - `weather_fx.gd`: rain, wind and storm visuals, plus the global shader parameters `road_wetness`, `wind_strength` and `wind_dir`.
  - `camera_rig.gd`: follow, wide and fork cameras. Fork shots come from `viewpoints.gd`.
  - `camera_blockers.gd`: the village boxes the chase cameras keep out of (see **Camera** below).
- `tools/camera_check.gd`: headless test of the camera blockers (no village house box on a road, pulled-in cameras outside every house), exit 1 on failure: `godot --headless --path . --script res://tools/camera_check.gd`.
- `world/duel_screen.gd`, `ui/duel_hud.gd`: the split screen and the halves' HUD (see **The line**).
- `ui/race_hud.gd`: what sits over the halves: the leaderboard (the top 6 with their picture, name and best time; top right on the full screen, under the crown on the split screen; a picture missing after 10 s shows red and is reported), problems in red for the facilitator, and the podium when a session ends. Racer colours come from its palette in join order.
- `main.gd` / `main.tscn`: wires net → sim → views and draws the debug overlay.
- `tools/sweep.gd`: the headless balance sweep.
- `tools/duel_check.gd`: headless check of the line: one player alone (full screen, left half only), then six who stop coming after a while (the split turns on once two play and off `splitHoldMs` after the last lap), the champion who rests, one-lap runs without bumps, two racers waiting for green at once in grid slots of their own (not inside each other), steering reaching the racers (steered forks, arrows caught), then the split screen and HUD driven for a few frames. Exit 1 on a broken rule: `godot --headless --path . --script res://tools/duel_check.gd`.
- `tools/verdict_check.gd`: the real mock duel with kit racers: while a half shows a lap's verdict (new champion, the time, OOPS!) its racer is still in the shot; prints each verdict's seconds without the racer and exits 1 above 0.2 s or if no verdict showed: `godot --headless --fixed-fps 60 --path . --script res://tools/verdict_check.gd -- --kit --racers=4 [--secs=240]`.
- `tools/end_sound_check.gd`: the real mock duel with kit racers, listening to the race-end sounds (see **Race-end sounds**): every lap that ends gets its verdict's cue, cues never stack, the music dips under a cue and comes back after it, the crowd cheers on time, and the podium at a session's end gets its fanfare. Exit 1 on a broken rule or if no lap ended: `godot --headless --fixed-fps 60 --path . --script res://tools/end_sound_check.gd -- --kit --racers=4 [--secs=240]`.
- `tools/start_crowd_check.gd`: groups of 4, 6 and 8 pressing Go together on both tracks (with the start countdown), with the bots steering (`--steer=wild|kid|off`; wild swings from edge to edge): start bumps, early crashes and release spread; exits 1 if the crowd knocks racers off.
- `tools/hud_check.gd` (windowed): renders the leaderboard (full and split screen, with a picture that never comes) and the podium from test data; exits 1 if either is missing, doesn't fit the screen, covers the crown, or a missing picture isn't shown and reported.
- `tools/roster_hold_check.gd` (headless, no server): a racer never changes in the middle of a run. The designer's review rounds send up to 3 better versions of a ready racer (new packages, same drawings); one that arrives while the racer's kart is on the track waits until the kart has left it, and the next run has its ride drawing sticker at once.
- `tools/session_check.gd`: against a running server (`-- --server[=URL]`), checks the options menu shows the phone address the server prints (with its QR code), clicks New session and switches the track there and back like the game manager; exits 1 if a step doesn't reach its state within 20 s.
- `tools/menu_check.gd` (windowed): opens the options menu in English and German, mock and server mode (idle, running, starting a new session, with the phone address and QR code) and saves screenshots with `--out=DIR`; exits 1 if the menu doesn't fit the screen or the join column doesn't say why there is no code (mock mode, server unreachable) or what stops the phones (the macOS firewall) or may (no phone has got through yet: a guest Wi-Fi that keeps devices apart). `--server=http://localhost:8080` also shows that server's real address and code; any QR reader can decode the saved `menu_*_join*.png`.
- `tools/layout_map.gd`: top-down layout map (`docs/layout_map.png`) plus geometry checks (spacing, crossings, slopes, curvature, junctions, fork angles, terrain features). Exits 1 on failure: `godot --headless --path . --script res://tools/layout_map.gd`.
- `world/landscape.gd`: the terrain features each fork alternative is built around (pond, inflow stream, jump dip, knoll, valley, hills), anchored to the course.

## World pipeline (countryside)

`sim/course.gd` is the single source of truth for the racing line. The world is built from it with three CC0/MIT tools in `addons/`: **Terrain3D** (terrain, texture painting and the grass instancer), **Godot Road Generator** (road meshes) and **ProtonScatter** (trees, bushes, rocks and hedges). Assets and licences are listed in `assets/CREDITS.md`.

| Step | Command | Output |
|---|---|---|
| 1. Check the layout | `godot --headless --path . --script res://tools/layout_map.gd` | `docs/layout_map.png`, exit 1 on bad geometry |
| 2. Bake the world | `godot --headless --path . --script res://tools/bake_world.gd` | `world/course_world.tscn`, `world/terrain_data/`, `world/baked/`, `world/vegetation/` |
| 3. Check the world | `godot --headless --path . --script res://tools/world_check.gd` | exit 1 if anything is scattered on a road or in water, floats or sinks more than 0.3 m, the terrain pokes through a road, anything solid (prop, post, sign, rail, plant) stands where a kart's body can reach on any road, sibling roads overlap at different heights, or an asset is missing |
| 4. Benchmark | `godot --path . --resolution 1920x1080 --script res://tools/bench.gd -- --seconds=30 [--racers=1]` | average and 1% low fps, split screen (or full screen with one racer), exit 1 below 60 |
| 5. Screenshots | `godot --path . --resolution 1920x1080 --script res://tools/shots.gd -- --out=DIR` | fixed viewpoints from `world/viewpoints.gd` |

- **Re-sync after editing the course:** run steps 1–3. The bake rebuilds the terrain (meadow levelled to the roads, pond, stream, dip, knoll, valley), the roads, water, course structures (kicker, causeway rails, lane fence) and vegetation. `--only=roads` (or `water`, `structures`) re-bakes single stages; vegetation needs the terrain stage too.
- **Editing in the Godot editor:** open `world/course_world.tscn` to inspect, but its contents are regenerated, so tune the bake or the materials in `world/materials/` and `world/vegetation/materials/` instead. Those are created once and kept on later bakes. `world/decor.tscn` (gantries, grid, flags, grandstand, signposts, stone bridge, ford posts) and `world/environment.tscn` (HDRI sky, sun, post-processing) are yours to edit. They come from `tools/seed_decor.gd` and `tools/seed_environment.gd`, which refuse to overwrite them without `--force`.
- **No fallbacks:** a missing scene, texture or model stops the bake (nothing is saved) and the game quits with an error.
- Local add-on patches are listed in `assets/CREDITS.md`.

Current results (2026-10-31, M4 Max, 1920×1080, 20 racers, vsync off): about 105–120 fps on average (the 120 looks like the display's cap); 1% low 94–102 fps across the follow, wide and fork cameras. The world check covers about 5,000 scattered and 35,000 ground-cover instances, 16 grounded landmarks and 3,270 road samples. Generate screenshots locally with `tools/shots.gd`; `docs/` is ignored.

## Village circuit (second track)

A Swiss village loop, raced lap after lap: start in the square by the Gasthaus, up the main street to the church hill (fork: ski-jump kicker or round the churchyard), down to the brook (ford through the duck pond or the covered wooden bridge), past the mill, out onto the alp (muddy farm track, cobbles by the dairy, the alp pass: a long climb with a kink to a wide hairpin and back down, a mountain stream), along the south edge (open causeway over the windy meadow or the sheltered Laubengasse), then round the fountain to the line. A lap is about 890 to 930 m (about a minute); the alp pass alone is 188 m. Same sections and forks as the countryside, so builds, splits and coach tips carry over. A run on the big screen is one lap (contracts §2i) and the best lap ranks; the sim and the tools can race more laps (`lapsPerRun`). It is the default track (`config.track`), so a fresh `bun run play` starts on it; the game manager switches track in the options menu, and in mock mode `--track=countryside` races the countryside instead.

| File | What |
|---|---|
| `sim/village_course.gd` | The loop (solves two straights so it closes exactly) |
| `world/village/village_plan.gd` | Pond, brook, square, church, mill, school and every house, anchored to the course |
| `world/village/village_terrain.gd` | Terrain heights and layers: village slope, mountain ring with snow |
| `world/village/chalet_builder.gd` | The buildings as real geometry: stone plinths, plaster and log storeys, recessed windows with shutters and geraniums, balconies, roofs with rafters and purlins, the church, arcades and covered bridge |
| `world/village/village_houses.gd` | Builds them when the village loads from a few numbers per building (the `Buildings/Houses` node of the baked scene) |
| `world/village/house.gdshader` | Building materials (`world/village/materials/house_*.tres`): ambientCG textures in metres, log courses, flame-striped shutters, grime, rain streaks, sun-faded timber |
| `world/village/village_kit.gd` | Props from the Kenney Fantasy Town Kit (Swiss palette) and Quaternius plants |
| `tools/village_map.gd` | `docs/village_map.svg` plus geometry checks (exit 1 on failure) |
| `tools/village_laps.gd` | Headless lap test: routes x weather, random builds, a 20-racer crowd |
| `tools/bake_village.gd` | Bakes `world/village/village_world.tscn` (stages terrain, roads, water, structures, buildings, props) |
| `tools/village_world_check.gd` | Checks the baked world: parts present, terrain under the roads, nothing on the track, nothing floating |
| `tools/village_shots.gd` | Fixed-viewpoint screenshots (windowed, `-- --track=village --out=DIR`) |
| `tools/seed_village_environment.gd` | Seeds `world/village/village_environment.tscn`: alpine sky (the Poly Haven panorama turned so its sun is in the north-east), sun, fog with aerial perspective (hand-editable; `-- --force` re-seeds) |
| `tools/race_cam_shots.gd` | Race-camera screenshots of the real game for look comparisons (windowed, never takes keyboard focus): `-- --track=village --racers=1 --seed=3 --weather=calm --duration=62 --shots=DIR --shot-every=3 --mute` |

After editing the village course or plan:

```sh
godot --headless --path . --script res://tools/village_map.gd
godot --headless --path . --script res://tools/village_laps.gd
godot --headless --path . --script res://tools/bake_village.gd
godot --headless --path . --script res://tools/village_world_check.gd
```

`world/village/village_decor.tscn` (optional) is loaded on top for hand-placed extras; the bake never touches it.

The alp pass (`ridge`) is the longer road: `VillageCourse.PASS_*` add a straight and a kink to the way up to the hairpin and the same to the way down. The two kinks move the road sideways and back, so the pass ends exactly where a bare hairpin would and nothing else on the loop moves; the plan, terrain and props follow it at the next bake. Lengthening it means: edit `PASS_*`, then `village_map.gd` (its `LAP_RANGE` bounds the lap), `village_laps.gd`, `bun run maps:export`, `bake_village.gd`, `village_world_check.gd` and the windowed `collision_probe.gd -- --track=village`. With the longer lap the per-lap time cap is 100 s (`runTimeCapMs`): slow builds in a storm ran past 90 s.

Look: the buildings are built in code at load (`chalet_builder.gd`, about 0.7 s on an M4 Max), merged per material in 96 m chunks; small pieces (geraniums, glazing bars, log ends, cut-out boards, rafters) sit in meshes on a 48 m grid without shadows, hidden 100 m from their centre. Geraniums are a lumpy leaf cushion plus round heads, with leaves and florets painted by `house_flowers.gdshader`. The Kenney kit (props only now) has its colour map recoloured to a Swiss palette at every bake (`village_kit.gd` `_recolour`). Close street views of each building kind: `tools/village_shots.gd` `house_*` viewpoints. Trees and flowers are the countryside's prepared plant meshes (`world/vegetation/meshes/`, from `tools/bake_world.gd`), so they sway with the wind. The village roads use their own calmer asphalt (`world/village/materials/road_asphalt.tres`, `VILLAGE_ROAD` in the bake): the shared texture's stones and red flecks stood out in the village sun. Animals are skinned models posed on their rest pose for the MultiMesh (`instanced_model.gd`).

### Village surprises

Cows wander onto the road and graze there, sheep cross it in little flocks, cheese wheels roll across and a cart drops hay bales, at random times and places (contracts §2j). Steering round them costs nothing; hitting one knocks the kart about (about 1.4 s); hands off, the autopilot slows down and steers round them (about 0.5 s each). Both halves share them, like the weather.

| File | What |
|---|---|
| `sim/obstacles.gd` | Where and when they turn up (`VillageCourse.obstacle_spots`), how they move, what a kart hits, what the autopilot sees ahead |
| `world/obstacle_views.gd` | Draws them: the animals turning smoothly and watching the karts, cheese wheels, hay bales, the "!" over each group, the "MOO!" a hit pops up, a puff of wool when a sheep is hit |
| `world/toy_animal.gd` | The toy cow (Swiss dairy cow with a brass bell) and Valais Blacknose sheep, built from the racer kit's parts (each moving part one merged, vertex-coloured mesh, cached) and moved in code: walk, graze and chew, gallop or bounce off, look at karts, hop at a near miss, spin or tumble with dizzy eyes when hit |
| `tools/obstacle_check.gd` | Hands off, kid-steered and wild-thumbed karts with and without them: met and hit per lap, the time a hit and a careful pass cost, no new fails |
| `tools/obstacle_shots.gd` | Screenshots (windowed): each kind on its road, `--close` the cow and sheep up close and reacting to a knock, `--hit` the race camera round a kart hitting each kind |

The game manager switches them on or off in the options menu ("Surprises on the road", kept for the next start); `--no-obstacles` leaves them out of a game run. The balance tools (sweep, village_laps, start_crowd_check) build their sims without them, so their baselines mean the same.

```sh
godot --headless --path . --script res://tools/obstacle_check.gd
```

### Chocolate coins

Every racer gets its own gold-foil chocolate coins on the village road: seven short lines of five, laid afresh each lap at random places on the plain stretches (never on a fork's way, its run-in, a boost strip, the start or the roundabout), straight, slanting across the road or curving. Each coin counts (the half's plate shows "12/35"); a whole line taken surges the kart like a boost arrow, a little less. Hands off, the autopilot doesn't go for them. In a split screen each half shows only its own racer's coins (`DuelScreen.COIN_LAYER`, which the other half's camera leaves out). A kid steering through them gains about 1.5 s a lap (`tools/coin_check.gd`).

| File | What |
|---|---|
| `sim/coins.gd` | Lays a lap of lines from `VillageCourse.coin_ranges` |
| `sim/racer.gd` `_catch_coins` | Takes them, surges the kart on a whole line; bots go for them |
| `world/coin_views.gd` | The spinning coins, each racer's on its side's layer; a taken one jumps and spins away |
| `tools/coin_check.gd` | Hands off and kid-steered karts with and without coins; 500 layouts checked |

The coin's "bling" is made in `audio/audio_director.gd` (`_coin_sound`), no file. `--no-coins` leaves them out of a game run; the balance tools build their sims without them.

```sh
godot --headless --path . --script res://tools/coin_check.gd
```

### Village life

`world/village_life.gd` makes the village busy without touching the race: a crowd of toy racers parked along the start line, the main street, the church hill, the mill, the dairy and the square, facing the oncoming karts, turning their heads to each kart and cheering, waving or clapping as it passes (the crowd's cheer plays for the kart the music follows); red, white and yellow bunting across the main street, the start line, the cobbles and the square, fluttering harder in the wind; pigeons on the roundabout's island that take off as a kart comes round, circle the fountain and settle again; two hot-air balloons drifting over the valley; and cow bells while the followed kart is out on the alp.

The crowd is the session's own racers in server mode (each ready racer stands in up to three places, different groups first; a racer leaving the session leaves the crowd) and the kit's sample racers in mock mode. The places are found once the village plan is laid out (clear of houses, water and every road's corridor, on flat ground, 15 m apart). `--no-life` leaves it all out.

```sh
godot --path . --resolution 1280x720 --script res://tools/village_life_shots.gd -- --kit --out=/tmp/life
```


## Balance snapshot

Results from `sweep --builds=60 --seeds=2`, solo racers with perfect boosts (before thumb steering: the sweep now steers with `--steer=kid`), on the 2026-10-31 course redesign (arc-built routes, Y-split forks).

Route lengths: jump 67.8 m / around 75.6 m, water 100.0 m / bridge 130.0 m, exposed 63.7 m / sheltered 76.1 m. Full path 430.6 m (jump/water/exposed) to 480.7 m (around/bridge/sheltered).

**Default build** (balanced style, around/bridge/sheltered):

| Weather | Time |
|---|---|
| calm | 31.6 s |
| rain | 37.7 s |
| wind | 34.6 s |
| storm | 41.2 s |

**Driving style, calm:** careful 34.6 s, balanced 31.6 s, daring 29.3 s.

**Random builds:**

| Weather | Median | Best–worst | Fail rate |
|---|---|---|---|
| calm | 32.2 s | 27.8–39.1 s | 0% |
| rain | 37.0 s | 29.7–49.7 s | 4.2% |
| wind | 36.8 s | 31.6–45.2 s | 4.2% |
| storm | 40.5 s | 34.1–56.9 s | 13.3% |

**Forks:**
- **Ramp:** jumping is worse at jump 0–3 (+0.3–0.9 s) and better at jump 4–5 (about −1 s).
- **Pond:** water loses at water 0–1 (+0.6–1.4 s calm), is about even at 2 and wins from 3 upward (−1.7 to −2.8 s calm). It wins at every level in rain and storm.
- **Crossing:** the exposed route is about 1.4–2.3 s faster in calm. In wind, sheltered wins at stability 0 (+1.0 s) and it is roughly even at 1–3.

## Camera

Each half has its own chase camera (`world/camera_rig.gd`) on its racer; it keeps about 10 m
from its racer at any speed (it eases only its direction, so bumps and wobbles don't swing it).
In the village the chase camera never sits in a house or looks through a wall: when a house or
the covered bridge's roof is between the racer and the camera, the camera pulls in towards the
racer (`world/camera_blockers.gd`: a box per house of the village plan, standing on the
terrain). The mock summary says how long the camera was pulled in.

## The line (the only way to race)

King of the hill (contracts §2i): the fastest lap holds the crown and rests; everyone else lines
up on their phone (Go) to beat it, one lap each against the clock. At most two race at a time,
one per half, and each starts when their half is free, so the two halves start at different
times. The sim runs every run solo (`sim.solo`): each gets its own start lights, the karts pass
through each other and the autopilot ignores the other kart.

- **When the screen splits** (`queue.updated.split`, decided by the server; the mock does the
  same): one person playing races full screen on the left half's camera. Once a second person
  plays (racing, or waiting in the line) the screen splits, and it stays split while anyone
  plays. It goes whole again only when nobody has raced for `splitHoldMs` (30 s) and nobody
  waits. While the screen is whole only the left half takes racers.
- **Split screen:** two SubViewports on the main viewport's World3D, left red, right blue, each
  with its own `CameraRig` chasing its racer (an idle half shows the fork shots and who is next).
  The main viewport stops drawing 3D; its camera sits between the two halves' cameras, where the
  terrain's detail and the audio centre.
- **Front shots:** while a racer waits on the grid for its lights, and while it cheers (or slumps)
  after its lap, its camera swings round in front of it, a little to one side, and the
  character looks into that camera; the racer sits low in the picture, under the lights and the
  verdict. At GO the camera swings back behind in 0.9 s. Never while racing: the kid steering
  needs the road ahead (`world/camera_rig.gd` `front`, set per half by `main.gd`). Each half's
  racer is on its own render layer (`DuelScreen.SIDE_LAYER`), and the front shot leaves the
  other half's racer out: the two duelists wait in separate grid slots, but their karts drive
  through each other on their own lines. It leaves the fork sign names out too
  (`SteerMarks.SIGN_LAYER`: they draw through everything); the chase keeps them.
- **HUD** (`ui/duel_hud.gd`): per half a live face cam of the racer (`ui/face_cam.gd`: a small
  camera in front of the character framing its face and hands, so its gestures show while it
  drives; the other half's racer is left out; drawn at half rate, the two halves' cams taking
  turns frame by frame), name, lap time, best lap, record, BOOST! while a
  boost arrow's boost lasts, its own start lights and the lap's verdict for
  `duelResultMs`; the crown and the line top centre. `ui/race_hud.gd` adds the leaderboard,
  problems and the podium on top.
- **Performance (Mac M3):** each half has half the pixels, so the 3D pixel count is the same as
  full screen; what doubles is culling, draw calls and the sun's shadow cascades. In split screen
  the sun casts two cascades within 80 m (instead of the preset's distance and four), vegetation
  ranges are 0.8 of the preset, and each camera has its own rain volume with half the drops.
  Measure with `tools/bench.gd -- --racers=4 --track=village`.

## Race-end sounds

A lap's end gets one cue for its verdict (`main.gd` `_verdict`, the same one the half's HUD
shows), played by `audio/audio_director.gd` (`END_CUES`):

| Verdict | Cue | Music dips | Then |
|---|---|---|---|
| NEW CHAMPION! / NEW RECORD! | `end_record.ogg`: the crown's motif, landing on a held chord and a button (5.6 s) | -15 dB | a big crowd (two cheers) after the hit, the racer's horn after the button |
| a personal best, short of the crown | `end_best.ogg`: climbing steps to a ringing chord (3 s) | -11 dB | the crowd, then the horn |
| any other finish (also the champion keeping the crown) | `end_finish.ogg`: short and bright (2.6 s) | -9 dB | the crowd, then the horn |
| OOPS! | `failed.ogg` (the bump), then `end_oops.ogg`: a soft trombone "aww" (2.3 s) | -8 dB | nothing |
| the podium at a session's end | `end_podium.ogg`: the crown's motif in full (7.9 s) | -15 dB | three cheers |

- **One at a time:** a bigger cue (record over best over finish over oops) cuts a smaller one off
  with a quick fade, together with its crowd and horn; a smaller one coming while a bigger one
  sounds is left out: its racer gets a short ding at once and honks once the bigger one is over.
  Both halves can end their laps a second apart, so this decides what the room hears. The crowd,
  horns and dings of the cues have 4 voices of their own, so coins and cow bells never crowd
  them out.
- **The dip** is an `AudioEffectAmplify` on the Music bus (`audio_settings.gd` `DIP_SLOT`), so
  it never touches the volume set in the options menu. It goes down in 0.15 s, holds until half
  a second before the cue ends, and while the music is about to switch (the climax to the
  paddock tune after the last racer) so the old tune doesn't swell back first, then comes back
  over about 1.5 s.
- **The cues** are short brass fanfares composed for the game, all in F major, which shares its
  notes with the village's D minor and the countryside's F major. `scripts/race-end-cues.js`
  holds the notes and renders them (FluidSynth, the MuseScore General soundfont, ffmpeg with
  libvorbis): `SOUNDFONT=/path/to/MuseScore_General.sf2 bun scripts/race-end-cues.js`. Credits
  and loudness in `assets/audio/CREDITS.md`.
- A best lap in the middle of a run (runs of more than one lap, the tools) gets a bright chime
  (`end_best_lap.ogg`) and a small dip; the lap that ends a run gets only its verdict's cue.

## Known issues and deviations

- Split screen: the terrain's level of detail centres between the two cameras, so the far
  ends of the village may show coarser terrain in a half; check on the Mac (Terrain3D's
  `mesh_size` can go up in split screen if it shows).

- Racers are placeholder shapes in mock mode (`--kit` builds them with the racer kit).
- `splitMs` is the time spent in each section.
- Wind direction is `(cos dirDeg, 0, sin dirDeg)` in world XZ.
- Crowded storms fail often: about 30% in the sweep. In mock mode the fail rate is about 13% in calm and about 25% in rain, mostly `off_track` in bends from collisions and daring slips.
