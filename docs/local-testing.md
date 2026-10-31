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
A session starts automatically so you can race straight away (`BK_AUTOSTART=0` to start it from the admin API instead).

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

## Asset pipeline: mock or DeepSeek

- With `DEEPSEEK_API_KEY` set (e.g. in `.env`), the server uses DeepSeek to check and design each racer. Photos of real people, blank pages etc. are rejected, and the phone asks to retake that photo.
- Without a key it runs in **mock** mode: no checks, and each phone photo gets one of the pipeline's hand-written sample designs (picked from the photo), so every test racer still looks different. Force a mode with `BK_PIPELINE=mock|deepseek`.

## Settings (env)

| Var | Default | |
|---|---|---|
| `PORT` | `8080` | |
| `PUBLIC_URL` | `http://<wifi-ip>:8080` | Used in asset URLs and the printed join URL |
| `BK_GAME_KEY` | `bebbikart-dev` | Game must send the same key (`--game-key=` or `BK_GAME_KEY`) |
| `BK_ADMIN_PIN` | `1234` | Header `x-admin-pin` for `/api/admin/*` |
| `BK_AUTOSTART` | `1` | Start a session at boot |
| `BK_DATA_DIR` | `apps/server/data` | SQLite db, uploads and asset packages (git-ignored) |

Handy admin calls:

```bash
curl -X POST -H 'x-admin-pin: 1234' localhost:8080/api/admin/session/reset   # wipe players and runs
curl -H 'x-admin-pin: 1234' localhost:8080/api/admin/players                   # everyone, with jobs
```

## Troubleshooting

- **Phone can't load the page:** same Wi-Fi? Guest networks often block device-to-device traffic. Check the IP the server printed, and the macOS firewall prompt.
- **"The big screen isn't connected yet" on Go!:** the game isn't connected. Its overlay says `SERVER online` when it is; check the game key.
- **Racer stuck on "Looking at your drawing…":** see the server log (`[job] …`). Jobs time out after 60 s and the phone offers a retry.
- **Fresh start:** stop the server and delete `apps/server/data/`, or call the reset endpoint above.
