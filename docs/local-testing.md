# Testing the full player flow locally

Phone → photos of two drawings → racer designed (asset pipeline) → server registers it → it races in the Godot game on the Mac screen.

## One-time setup

```bash
bun install            # also links the asset pipeline into the server
bun run kit:export     # Godot copies of the contracts
cd apps/game && godot --headless --import && cd ../..   # first time / after pulling
```

## Run it

```bash
bun run dev
```

This starts three things:

| Process | Where |
|---|---|
| Server | `http://<mac-ip>:8080` (REST, `/ws`, `/assets`) |
| Phone site (Vite, hot reload) | `http://<mac-ip>:5173` |
| Godot game, connected with `--server` | a window on the Mac |

The server prints the exact phone URLs at start-up (it detects the Mac's Wi-Fi IP; set `PUBLIC_URL` to override).
A session starts automatically so you can race straight away. A session lasts `sessionMinutes` (30); when it runs out the next one starts right away with a fresh leaderboard, and a server that boots on an ended session starts a new one. With `BK_AUTOSTART=0` the session stays ended until the game manager or the admin API starts the next one, and phones show "This race is over".

On the phone (same Wi-Fi as the Mac), open `http://<mac-ip>:5173`:

1. Type a racer name, take a photo of the **driver** drawing and of the **ride** drawing, tap **Make my racer!**
2. The phone shows "Looking at your drawing…", then the reveal with the racer's title. The game window shows `NEW  <name> · <title>` in its overlay, builds the racer with the kit and uploads its hero/avatar renders (the phone's reveal and avatar switch to them).
3. Tap **Let's race!**, tune stars, routes and style, tap **Go!** Your racer appears on the track in the game.
4. Tap **BOOST!** during the race (3 charges). Section deltas show on the phone after the first finished run.
5. The result screen shows time or fail reason, splits vs best, rank and a coach tip. The leaderboard tab updates.

macOS may ask whether `bun` may accept incoming connections: allow it, or phones can't reach the Mac.

### Without Vite

`bun run start` builds the phone site and serves everything from the server on `http://<mac-ip>:8080`. Start the game separately with `bun run dev:game`.

### Without Godot

`bun run fake-game` connects a stand-in game that "races" each run in about 12 s with fake splits, so you can test the phone flow on its own (run it instead of the Godot game; only one game connection is kept).

## Village loop (laps)

The game manager picks the track, laps and session length in the game's options menu on the big screen (phones never set options). Switching track ends the session and starts a new one with an empty leaderboard; racers stay. Scripts can do the same over the admin API (the track can't change while a session runs):

```bash
curl -X POST -H 'x-admin-pin: 1234' localhost:8080/api/admin/session/end
curl -X PATCH -H 'x-admin-pin: 1234' -H 'content-type: application/json' -d '{"track":"village"}' localhost:8080/api/admin/config
curl -X POST -H 'x-admin-pin: 1234' -H 'content-type: application/json' -d '{}' localhost:8080/api/admin/session/start
```

Or set `"track": "village"` in `bebbikart.config.json` at the repo root before starting. On the village the phone shows "Lap 2 of 3", the lap timer, each lap's time vs your best lap, and a **Pit in** button (finish at the next line). The best lap ranks. `bun run fake-game` races laps too.

## Claude API key (required, no fallbacks)

The server designs every racer from the kid's drawings with Claude (`claude-sonnet-5-5`, high effort). It reads `ANTHROPIC_API_KEY` from the environment or from the first of these `.env` files that sets it: `apps/server/.env`, `.env` (repo root), `packages/asset-pipeline/.env`. The start-up banner says which file it used.

There is no mock or sample-design fallback:
- No key → the server refuses to start and says where to put it.
- Claude fails (network, bad key, timeout, refusal, invalid reply three times) → the job fails, the server logs `[job] … FAILED: <reason>`, and the phone shows the reason in a red box with a retry.
- Claude says a photo isn't a usable drawing → the phone asks to retake that photo.
- In the game, a racer without a spec, a drawing that doesn't download, or a render/upload that fails shows as an `ERROR …` line in the overlay and in the Godot log.

The garage has a **New drawings** button to redo a racer's photos without resetting anything.

## Settings (env)

| Var | Default | |
|---|---|---|
| `PORT` | `8080` | |
| `PUBLIC_URL` | `http://<wifi-ip>:8080` | Used in asset URLs and the printed join URL |
| `BK_GAME_KEY` | `bebbikart-dev` | Game must send the same key (`--game-key=` or `BK_GAME_KEY`) |
| `BK_ADMIN_PIN` | `1234` | Header `x-admin-pin` for `/api/admin/*` |
| `BK_AUTOSTART` | `1` | Keep a session running: start one at boot and the next one when time runs out |
| `BK_DATA_DIR` | `apps/server/data` | SQLite db, uploads and asset packages (git-ignored) |

Handy admin calls:

```bash
curl -X POST -H 'x-admin-pin: 1234' localhost:8080/api/admin/session/reset   # wipe players and runs
curl -H 'x-admin-pin: 1234' localhost:8080/api/admin/players                   # everyone, with jobs
```

## Troubleshooting

- **Phone can't load the page:** same Wi-Fi? Guest networks often block device-to-device traffic. Check the IP the server printed, and the macOS firewall prompt.
- **"The big screen isn't connected yet" on Go!:** the game isn't connected. Its overlay says `SERVER online` when it is; check the game key.
- **Racer stuck on "Looking at your drawing…":** see the server log (`[job] …`). Jobs time out after 300 s (`BK_JOB_TIMEOUT_MS`; the look, design, critique and refine passes take about 60 to 150 s) and the phone shows the error.
- **Fresh start:** stop the server and delete `apps/server/data/`, or call the reset endpoint above.
