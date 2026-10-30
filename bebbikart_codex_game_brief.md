# BebbiKart — Game Brief for Codex

> **Update 2026-10-30:** The project plan now lives in [`docs/README.md`](docs/README.md). It changes this brief in four ways: many racers share the course at once and bump into each other, kids join and coach from a phone web app, drawings become assets through an automatic pipeline, and there are new strategy tools (three forks, driving style, boost zones, section splits, a best-run ghost and weather warnings). This brief is still the reference for the toy-world tone, course beats, abilities and weather (§2, §4, §6, §8). Where the two disagree, `docs/` wins.

**Status:** Concept brief for expansion, not a finalized technical design  
**Audience:** Codex, game developer(s), workshop organizers  
**Priority:** Deliver a complete, reliable V1 well before the event. Tablet-based controls and additional karts are optional V2 enhancements.  
**Working title:** _BebbiKart_ (replaceable)

## 1. One-paragraph concept

Create a friendly, colorful 3D obstacle-course game for a children's workshop. Children draw their own character and vehicle on paper; AI-assisted preparation turns the drawing into a recognizable game-ready character/kart appearance. Each child distributes **10 stars** among vehicle abilities, then launches the kart into a lively 3D world. **The computer drives the kart** through a short start-to-finish route while everyone watches on a big screen. The goal is **the fastest successful completion time**, not a simultaneous head-to-head race. If an attempt fails, it restarts from the beginning: **no checkpoints**. Children can change abilities or route preferences and try again throughout a **30–45-minute session**. The world stays alive, with **unpredictable, short bursts of rain and wind** affecting its physics independently of any attempt. The experience should feel playful, surprising, creative and safe, not competitive or stressful.

## 2. Experience pillars

1. **My creation is in the game.** The drawing must remain visibly recognizable after import; do not sacrifice this for elaborate character-generation technology.
2. **Watch → learn → tweak → retry.** Each short run should teach something about the child's choices.
3. **Playful chaos, not strict fairness.** The weather is not synchronized with race attempts, seeded per player, or identical for all attempts. Surprises are part of the fun.
4. **An inviting toy world.** Bright, soft, charming and comic; never frightening or punishing.
5. **Very short feedback cycles.** A clean run should take roughly **20–40 seconds** on a sensible baseline configuration. Failure and retry should be quick.
6. **Keep V1 small.** Few clear mechanics implemented well beat a large unfinished game.

## 3. Audience and setting

- Primary users: children at an in-person creative/technology workshop. Design for a range of ages; exact age range is not yet specified.
- Session length: approximately **30–45 minutes**.
- Primary display: a **large shared screen** for watching the kart, the environment, the timer and best results.
- Configuration input: a **simple computer interface**, preferably facilitator-friendly and understandable to children.
- Children do **not** manually steer the kart in V1. Autopilot/AI handles driving and jumping.
- Children can join with a design without waiting for a synchronized starting signal. In V1, because there is **one active kart at a time**, new attempts can enter a short queue while other children adjust their designs. Future architecture must permit concurrent karts.
- Do not assume each child has a tablet, smartphone, account or installed software.

## 4. The 3D world

**Theme:** A whimsical toy-land / magical playground, inspired by the cheerful energy of family party games such as _Frantics_ but not copying their assets, characters or levels.

**Visual language:** Saturated but comfortable colors; rounded geometry; soft hills; giant flowers and playful decorations; smiling finish arch or tiny castle; sunny daytime lighting; friendly sound effects; high readability from across a room.

**One compact course, not multiple maps for V1.** The world persists throughout the session. It can be a larger-looking 3D environment, but only a short navigable route is necessary. Proposed course beats, in sequence:

1. **Bouncy hills and ramps** — demonstrate speed, jump and bounce. Landings look funny rather than violent.
2. **Splash pond with a safe alternative** — shallow water slows an unprepared kart; a longer dry bridge or path creates a meaningful route choice.
3. **Breezy elevated crossing** — wind may push the kart sideways; heavier or better-controlled setups handle it differently. Visually safe, without a frightening drop.
4. **Rainbow bends** — turns reward grip, particularly during rain.
5. **Finish arch / toy castle** — clear, joyful finish feedback.

The course should remain **possible to complete under every supported weather combination** with at least some valid configurations. Obstacles should be readable and fun to watch. Keep geometry and collision simple for V1; no combat, lethal traps, dark tunnels, deep pits, scary enemies, or complex destructible environments.

**No checkpoints.** Start and finish exist; a failed attempt returns to start. Scenic milestones are not respawn points.

## 5. Core gameplay loop

1. **Create:** Child draws a character and vehicle on paper.
2. **Import:** A facilitator or an external AI-assisted workflow prepares the drawing as a game-ready asset and submits it to the game. The game does not need an integrated scanner or in-game image-generation pipeline in V1.
3. **Customize:** Child assigns exactly **10 stars** across available abilities and optionally chooses route preferences.
4. **Launch:** The saved configuration becomes the active kart when available, and an independent **attempt timer** begins at the start line.
5. **Watch:** The kart drives itself. Show a clear close-up/follow camera, optional cinematic views and a small overhead map.
6. **Outcome:** On reaching the finish, save the completion time and update the child's personal best. On failure, stop that attempt, give a brief funny/friendly cue, then automatically retry from the beginning after a short delay unless the child chooses to pause and edit.
7. **Reflect and retry:** Display a one-line understandable hint (e.g. “Slipped on the rainbow turn” or “Water slowed you down”). Let the child redistribute stars and/or choose a different route. Repeat as often as the session allows.

**Important timing model:**

- **World/session time:** One continuous 30–45-minute workshop clock. Weather continues even if no kart is currently running.
- **Attempt time:** A separate stopwatch, reset every new start and stopped at finish/failure. A successful baseline attempt should be ~20–40 seconds.
- **Personal best:** Minimum completion time across a child's _successful_ attempts. Failed attempts do not set a best time.
- Do not reset, delay, normalize or standardize weather around a launch. A kart can start in sunshine and encounter rain partway through.

## 6. Kart configuration and abilities

Each attempt uses **exactly 10 stars**, assigned before launch. A proposed V1 set of **six understandable abilities** follows. Final labels, ranges, cap per trait and physics tuning are for Codex to recommend; a simple cap (e.g. 0–5 stars per trait) avoids one-trait domination.

| Ability                | What children understand | What it changes / trade-off                                                         |
| ---------------------- | ------------------------ | ----------------------------------------------------------------------------------- |
| **Speed**              | “Go faster!”             | Top speed, but high-speed cornering is harder without grip.                         |
| **Jump**               | “Leap over bumps!”       | Jump strength / obstacle clearance, but airtime can expose the kart to wind.        |
| **Grip**               | “Stick to the road!”     | Steering control, especially on wet bends.                                          |
| **Water skill**        | “Splash through water!”  | Reduced slowdown in shallow water, making shortcuts viable.                         |
| **Weight / stability** | “Don't get blown away!”  | Greater resistance to wind and bumps, with weaker acceleration or jumping.          |
| **Bounce**             | “Boing!”                 | More playful landings/recovery, but excessive bouncing can destabilize tight turns. |

**Do not implement all originally brainstormed abilities in V1.** Acceleration, width, height, turbo, toughness, temporary flight, obstacle-smashing and other quirky accessories are candidates for future versions, if they add clear choices. For V1, appearance may vary without changing hitbox size; configurable vehicle dimensions can wait.

**Design principle:** Every ability should be visible in the world and have at least one meaningful trade-off or obstacle interaction. Avoid a universally optimal 10-star allocation. Provide an understandable default distribution for first-time players.

## 7. Autopilot and route choices

The driving system need not use machine learning. A **simple deterministic or reactive autopilot** is entirely acceptable in V1; “AI-powered” primarily refers to bringing children's drawings into the game and the autonomous behavior. Make it reliable, inspectable and fun to watch.

- Use a course path / waypoints / simple route graph.
- Autopilot handles steering, acceleration, slowing, ramps and recovery without user input.
- Kart stats influence outcomes through physics or simple tunable rules.
- At **one or two forks**, the child may select **safe versus risky/shorter** routes. Example: shallow-water shortcut vs longer dry bridge. V1 may use a simple route selector rather than moment-to-moment control.
- If the kart is overturned, outside the track, unable to progress for a short configurable period, or exceeds a generous time cap, the attempt fails and returns to start.
- Use comic, non-scary failure feedback: a little spin, wobble, splash or “oops!” message; no crash damage or punishment.

## 8. Unpredictable world-wide weather

Weather is **global world state** and **independent of attempts or players**. The objective is a feeling of surprising, playful chaos. **No fixed five-minute schedule and no repeating predefined sequence.**

**V1 effects only:**

- **Rain:** A sudden short shower, approximately **10 seconds** as an initial example; makes relevant surfaces more slippery by reducing effective grip. Visible rain and a quick “Rain!” label communicate the effect.
- **Wind:** Unexpected gusts/periods of wind push karts sideways, especially on jumps and exposed bridges. Direction and strength can vary within safe limits; a wind icon and animated scenery show the effect.
- Rain and wind may **overlap**. Calm intervals may be short or long. Both events have randomized start times and durations. Wind may occasionally last much longer than rain; tune the range based on playtesting.

**Implementation suggestion, not a hard requirement:** Separate lightweight weather state machines with randomized cool-downs, probability of starting and durations. Keep probabilities and intensity editable in configuration so workshop organizers can tune the chaos without code changes. Use transitions/limits to avoid frequent impossible runs or seizure-like visual flashes.

**Explicit non-goal:** Do not make weather “fair” by freezing it per race, matching it for each child or enforcing a predictable pattern. Nonetheless, keep it comprehensible and technically stable.

## 9. Spectator experience and UI

**Big-screen view:**

- Attractive 3D camera following the kart; keep the kart easy to see.
- Small **top-down mini-map** indicating kart position, route and finish.
- Visible **current attempt timer** and **personal best**.
- Current world condition: sunshine, rain and/or wind, with a clear visual indicator.
- Brief finish celebration or friendly failure animation.
- Optional small recent-best leaderboard; use nicknames rather than full names.

**Simple configuration interface:**

- Current child's nickname and imported creation preview.
- Six large star-allocation controls; **10 stars in total** at all times when launching.
- Optional safe/shortcut route choice.
- A large **Try again** or **Launch** action.
- Concise outcome hint and best-time feedback, e.g. “Your fastest time: 27.4 seconds.”
- No need for children to understand technical concepts, physics parameters or weather probabilities.

Avoid lengthy menus and lengthy start or finish animations. The game needs to be understandable from a distance and respond quickly.

## 10. Drawing-to-game asset workflow

The child's paper drawing is central, but **arbitrary automated 2D-to-3D model generation is a risky dependency for V1**. Separate the creative import workflow from real-time gameplay.

**V1 minimum:**

1. Receive a prepared image or small asset package via file upload or a simple import endpoint. A facilitator may photograph the drawing and use an external AI/Codex-assisted preparation workflow.
2. Render the drawing as a **recognizable character and vehicle** on a standardized in-game kart (for example, a textured body, cut-out character sprite, or simple 2.5D driver on a 3D chassis).
3. Preserve the original style/colors where practical. Validate the input and fall back to a standard kart if it cannot be processed.
4. Associate imported visuals with a player profile and their saved star allocation.

**Future ambition:** Generate richer stylized 3D meshes and accessory variants automatically, with a consistent art style and collision rules. Keep this separate from core race physics.

**Do not require** a physical document scanner, a custom trained image model or per-player full 3D rig generation to get V1 working.

## 11. V1 scope versus future versions

### V1 — must be working well before the event

- One shared, colorful 3D world; one short start-to-finish course.
- **One active kart in the simulation at a time.** Multiple saved children's designs/configurations should be representable; quick attempt queue if needed.
- Autonomous driving; no direct steering controls.
- Import and display child-created character/kart visuals on a standard rig.
- 10-star allocation across a deliberately limited set of attributes.
- A few distinct obstacles, with at least one route choice if affordable.
- Quick automatic restart after failure, with an easy pause/edit option; **no checkpoints**.
- Global stochastic rain and wind, independent of each kart attempt.
- Timer, successful-run history, personal best and simple results display.
- Big-screen camera and overhead mini-map.
- Basic persistence/recovery for session continuity; reliable local running is preferable to elaborate cloud dependencies.

### V2 — desirable only if V1 is stable early

- **Tablet-based controls** for selecting abilities, routes or spectating (not a V1 prerequisite).
- Multiple karts running concurrently in the same persistent world.
- More playful abilities/accessories and vehicle shape effects (width, height, floating, turbo, etc.).
- More camera options, dynamic route selections, animations, richer AI-assisted asset generation.

### Not in scope for the initial workshop

- Synchronized multiplayer start, direct kart-to-kart collisions or elimination.
- Combat, weapons, online matchmaking or accounts.
- Large open world, multiple courses, procedural level generation.
- Full manual driving, networked physics or sophisticated ML driving agents.
- A strict competitive fairness / balancing system.

## 12. Technical design guidance for Codex

Keep the product technology-agnostic initially: **Codex should propose the simplest engine/stack that can reliably deliver the experience on the event hardware**, not assume any particular cloud provider or database.

Suggested logical modules:

1. **World / Course:** fixed geometry, obstacle triggers, waypoint graph and route alternatives.
2. **Weather Manager:** global randomized weather state, tunable intensity/durations and observable events.
3. **Kart Entity:** one controllable physics object with interchangeable cosmetic assets and stats; design entities to support more than one later.
4. **Autopilot:** route selection, steering decisions, ramp behavior, recovery and failure conditions.
5. **Attempt Manager:** launch, per-attempt timer, success, failure and retry.
6. **Player / Build Manager:** saved nickname, asset references, star distribution and route preference.
7. **Results Store:** attempt history and personal bests; local persistence suffices initially.
8. **Presentation:** follow camera, overhead map, status overlay, sound/animations.
9. **Asset Import:** accepts validated prepared assets without blocking the live simulation.

**Architectural invariant:** Weather belongs to the **world**, not a run. Player profile/build belongs to a **child**, not the physical kart. An attempt ties together one child/build, one kart instance and timestamps. Set the V1 max concurrent active karts to **1 as a configurable limit**, instead of deeply hard-coding a single global player everywhere.

**Illustrative data objects:**

- `Player`: `id`, `nickname`, `artAssetId`, `createdAt`.
- `KartBuild`: `id`, `playerId`, `stars` (`speed`, `jump`, `grip`, `water`, `stability`, `bounce`), `routePreference`, `version`.
- `Attempt`: `id`, `playerId`, `buildId`, `startTime`, `endTime`, `elapsedMs`, `outcome`, `failureReason`, `weatherEventsObserved`.
- `WorldWeather`: `rainActive`, `rainIntensity`, `windActive`, `windVector`, `changedAt`.
- `Session`: `id`, `startedAt`, `plannedDurationMinutes`, `endsAt`.

Consider an offline-friendly mode, recoverable local state, basic performance telemetry and deterministic test seeds for debugging (while gameplay itself stays unpredictable). Make the application friendly for a facilitator to reset between groups.

## 13. Acceptance criteria for the V1 demo

A V1 demo is credible when all of the following work:

- A facilitator can load at least one child's drawing-derived asset and recognize it in the 3D scene.
- A child can change a legal 10-star allocation and launch without developer assistance.
- The computer navigates an obstacle course, finishes in ~20–40 seconds on a sensible setup, and may fail on poorly suited setups.
- A failed attempt restarts at the **start**, never at a midpoint checkpoint.
- Finishing saves an accurate time; repeat completions can lower the child's personal best.
- Rain and wind trigger at **unpredictable** times even between attempts, have visible effects and modify handling; they can overlap.
- An attempt can begin during an existing weather event, or see weather change mid-run.
- A spectator can follow the kart on the large screen and locate it on a mini-map.
- At least two different children/builds can be stored and tried sequentially, without requiring a synchronized race.
- The app remains usable after repeated runs throughout a 30–45-minute session without memory/performance degradation or manual restarts.

## 14. Open decisions — propose defaults rather than blocking work

Codex should recommend pragmatic defaults and mark assumptions for:

- Target event hardware, operating system, display resolution and whether the game runs in a browser or native app.
- Approximate age range and number of children, which determines whether a simple queue is enough.
- How children's paper drawings are photographed or uploaded, and whether preparation is done beforehand or during the workshop.
- Final ability set, star limits, initial balance and realistic fail conditions.
- Exact course layout and how many route forks belong in V1.
- Weather onset/duration probabilities and visible effects.
- Whether a local database is useful, or simple files/local storage are enough.
- Whether only the fastest time counts, or a secondary fun score/achievement system is worth adding later.

These are **design choices to resolve**, not reasons to expand the scope.

## 15. What Codex should produce next

**Please expand this concept, but do not immediately build a massive game.** First deliver:

1. A coherent **Game Design Document (GDD)** with the gameplay loop, toy-world theme, obstacle-by-obstacle layout, user journeys and clear rules.
2. A **V1 technical architecture proposal** (engine/stack options and a recommended choice) optimized for a short, reliable event-ready build.
3. A **small vertical-slice prototype plan**: one generic kart, one short obstacle track, one star-adjustable behavior, autopilot, timer and one random weather effect.
4. A prioritized **implementation backlog with milestones and explicit V1/V2 boundaries**. V1 must be ready well ahead of the event; tablet controls are a stretch goal.
5. A minimal **data model and asset-import contract**, with a path to multiple karts later.
6. A **playtesting and balancing plan**: aim for 20–40-second successful runs, fast retry, readable physics and a reassuring visual tone.
7. Key **risks, assumptions and suggested compromises**, especially drawing-to-game integration and complexity of autonomous driving.

**Guiding principle:** Make the smallest delightful, functioning game that children can understand in seconds and enjoy experimenting with for 30–45 minutes. Preserve the one-world / short-attempt / random-weather concept. Avoid building extra features merely because they are technically possible.
