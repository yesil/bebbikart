# Multiplayer findings (4 to 8 players)

Running list from the multiplayer rounds: what was tested, what was found, what was fixed, with
numbers. The harness is `bun run sim-players` (see [local-testing.md](local-testing.md#several-phones-at-once-sim-players)),
run against my own server (port 8090, its own data folder) and the real Godot game.

## Round 1 (2026-10-31): 8 phones, real Claude racers, real game, 2 races of 8 at once

| Area | Found | Status |
|---|---|---|
| Joining | 8 simultaneous joins in 2-3 ms each; no errors. | fine |
| Racers generating at once | Only 3 designs ran at a time, so the 8th kid of a group waited **240 s** (median 176 s) for a racer that takes 54-106 s alone. | **fixed**: `BK_DESIGN_CONCURRENCY`, default 8 (2d4684e) |
| Renders | Game rendered and uploaded each racer's 4 images ~1 s after it was ready. | fine |
| Start | **4 of 16 runs** ended off the road in the first hills ~8 s after Go. Karts released side by side swerved across each other to their own lines (1.0-1.2 bumps per racer in the first 4 s, 0.4 s lost each). | **fixed** (24ab1f4): free slot nearest the own line, slot line held for 35 m. Start bumps 0.06-0.15 per racer, 0.01 s lost (`tools/start_crowd_check.gd`) |
| Start | An off-zone Boost tap in the first bends sends a racer off the road even alone: village 59 % (tap at 3 s), countryside 49 % (tap at 6 s). Kids tap Boost right after Go. | reported to the gameplay thread (their area: boost/slip tuning) |
| Big screen | Only a debug text box covering two thirds of the screen and tiny 3D name tags: no places, no results, nobody could tell who is who. | **fixed**: race HUD (66b6b76) |
| Group start | Kids press Go a few seconds apart and never really race each other. | **fixed**: 3 s lights countdown, everyone in it leaves together (412735c) |
| Latency | Boost tap → seen by the game and back: median 84 ms, max 199 ms (includes the 200 ms progress interval). Result on the phone 0-1 ms after the server has it. | fine |
| Messages | 5 progress updates/s per racing phone; ~150 KB per phone for 2 races; weather 20 updates per phone in 5 min. | fine |

## Round 2 (2026-10-31): 8 new phones (duplicate names), real Claude, real game, 2 races of 8

| Area | Result |
|---|---|
| Racers generating at once | All 8 designed at the same time: ready after 48-84 s (median 65 s), was up to 240 s. No rate-limit errors with 8 parallel Claude jobs. |
| Duplicate names | Two "Mia" joining at once became "Mia 2" and "Mia 3" (round 1's racers held the plain names). |
| Countdown start | All 8 on the grid; the front row leaves at green (phone's green within 25-38 ms of the release), the second row 0.88-0.92 s later. Go → on track 3.0-3.96 s. |
| Start | 1 early crash in 16 runs (a second-row kart bumped off in the hills), down from 4 in 16. The weak-boost slide is with the gameplay thread. |
| Results | Results reached the phones within 20-28 s of each other (spread of race times plus one early oops). |
| Big screen | 60 fps (min 54) with 8 kit racers at 1920x1080, Godot 53 % of one core (max 78 %), 720 MB. Server < 1 % CPU. |
| Messages | ~180 KB per phone for 2 races; boost tap → seen median 89 ms. No errors. |

Screens ([countdown](screens/multiplayer-round2-countdown.jpg), [mid-race](screens/multiplayer-round2-midrace.jpg),
[results](screens/multiplayer-round2-results.jpg)): the lights panel names the racers on the grid with the karts parked in the four slots;
GO! as they leave; place tags over every kart; the race board turns into the results as they
finish. Polished after this round: tags that slide under a HUD panel are hidden; compact standings
rows fit 20 racers above the camera's name tag.

## Big-screen HUD (`apps/game/ui/race_hud.gd`)

- A tag over every kart: place badge and name in the racer's colour, pushed apart so tags never
  overlap, smaller with distance. Colours come from a 12-colour palette in join order (the camera's
  name tags use the same colours).
- Race board (top right): place, avatar, name, lap or section, time. Finishers keep their time
  (gold, silver, bronze) until the group is home; the title switches to Results.
- Standings (top left): everyone in the session by best time, with avatar, or what the designer is
  doing while their racer is made; offline phones dimmed; compact rows past 10 racers.
- Banners for each finish ("New best!") and oops; the podium when a session ends; problems in red.
- The camera director owns the bottom of the screen (on-camera tag, picture-in-picture, cut pop).

## Duplicate names

Two kids called Mia were both "Mia" on the big screen and the leaderboard. The server now makes
the second one "Mia 2" (join and rename, case-insensitive; c6a794d).
