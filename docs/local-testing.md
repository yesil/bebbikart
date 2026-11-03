# Testing the full player flow locally

Phone → photos of two drawings → racer designed (asset pipeline) → server registers it → it races in the Godot game on the Mac screen.

## One-time setup

On a new Mac, first install Bun, Godot 4.7.2 with its export templates and the API key: see
[Setting up a Mac](../README.md#setting-up-a-mac).

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

The server prints the phone URL at start-up: Vite's on :5173 under `bun run dev`, its own :8080 otherwise (it detects the Mac's Wi-Fi IP and follows it when the Mac changes network; set `PUBLIC_URL` to override). Until a phone has opened it, it says the address is unproven; it logs the first phone that gets through, and says in capitals when the address changes, the Mac has no network, or the macOS firewall blocks phones. The big screen shows the same address with a QR code in its options menu (Esc), for people to scan with the phone camera; it says in red when it can't (mock mode, server unreachable, no network, phone site not built).
A session starts automatically so you can race straight away. A session lasts `sessionMinutes` (30); when it runs out the next one starts right away with a fresh leaderboard, and a server that boots on an ended session starts a new one. With `BK_AUTOSTART=0` the session stays ended until the game manager or the admin API starts the next one, and phones show "This race is over".

On the phone (same Wi-Fi as the Mac), open `http://<mac-ip>:5173`:

1. Type a racer name, take a photo of the **driver** drawing and of the **ride** drawing, tap **Make my racer!**
2. The phone shows "Looking at your drawing…", then the reveal with the racer's title. The game window shows `NEW  <name> · <title>` in its overlay, builds the racer with the kit and uploads its hero/avatar renders (the phone's reveal and avatar switch to them).
3. Tap **Let's race!**, tune stars, tap **Go!** Your racer appears on the track in the game.
4. During the race, drag a thumb left or right anywhere on the phone to steer: the side of the road at a fork picks the way (the phone shows which), and the glowing arrows on the road give a boost. Let go and the kart drives itself. Section deltas show on the phone after the first finished run.
5. The result screen shows time or fail reason, splits vs best, rank and a coach tip. The leaderboard tab updates.

macOS may ask whether `bun` may accept incoming connections: allow it, or phones can't reach the Mac.

### Real play (release build)

`bun run dev` runs the game on Godot's debug runtime: "(DEBUG)" in the window title, slower scripts and the test keys (R, W, K, B) live. For real play on the big screen:

```bash
bun run play
```

This builds the phone site, starts the server without watching files (phones open `http://<mac-ip>:8080`, no Vite) and launches the game's **release build** connected to it. Quitting the game (⌘Q) or Ctrl+C stops both; if either one stops, so does the other. Extra arguments go to the game (`bun run play -- --quality=high`).

The release build is `apps/game/export/BebbiKart.app` (git-ignored), exported with the `macOS` preset in `apps/game/export_presets.cfg`. `bun run play` exports it first when it is missing or older than any file in `apps/game`; `bun run game:export` exports it on demand. In the release build H still shows the status overlay and Esc the options menu; the test keys do nothing.

One-time setup: Godot's export templates for your Godot version, `bun run game:templates` (1.3 GB). Without them `bun run play` stops before exporting and says to run it.

### Without Vite (debug game)

`bun run start` builds the phone site and serves everything from the server on `http://<mac-ip>:8080`. Start the game separately with `bun run dev:game`.

### Without Godot

`bun run fake-game` connects a stand-in game that "races" each run in about 12 s with fake splits, so you can test the phone flow on its own (run it instead of the Godot game; only one game connection is kept).

## Several phones at once (sim-players)

`bun run sim-players` drives N scripted phones over real HTTP and WebSocket, exactly like the phone
site: device cookie, join, two sample drawings, the design job (real Claude), the big screen's
renders, a random build, **Go** (all at once or staggered), a few steers (`--steers N`), the result, and
racing again. It prints a timeline, then timings (join → racer ready, Go → on track, countdown green
→ on track, steer → the kart's lane moving on the phone, finish → result), message counts per phone and every error, and exits 1
on any error.

Use your own server so you don't touch anyone else's racers:

```bash
PORT=8090 BK_DATA_DIR=/tmp/bk-mp PUBLIC_URL=http://localhost:8090 bun apps/server/src/index.js
```

```bash
godot --path apps/game --resolution 1920x1080 -- --server=ws://localhost:8090/ws --shots=/tmp/bk-shots --shot-every=2
```

```bash
bun run sim-players -- --players 8 --url http://localhost:8090 --races 2
```

- Racers are kept between runs (`--state`, default `apps/server/data/.sim-players.json`): the second
  run reuses them and designs nothing. `--fresh` makes new ones; `--max-new` (8) caps how many real
  Claude designs one run may start.
- Every Go joins the line (contracts §2i): two race at a time, one per half of the big screen,
  each with its own start lights. `--stagger 700` presses Go 0.7 s apart; `--join-stagger`
  spreads the joins; `--names Mia,Mia,Noah` tests duplicate names; `--track village` switches
  track over the admin API (new session).
- With `bun run fake-game` instead of Godot, add `--renders 0` (the stand-in renders nothing).
- `--shots=DIR` on the game saves a screenshot every `--shot-every` seconds while racers are on the
  track (start, mid-lap, finish).
- Findings and numbers from the multiplayer rounds: [multiplayer-findings.md](multiplayer-findings.md).

## Village loop (laps)

A fresh start races the village loop: it is the default track (`DEFAULT_CONFIG.track`). The game manager picks the track in the game's options menu on the big screen, in one click (phones never set options). Switching track ends the session, stops the karts on the track and starts a new session on the new track with an empty leaderboard; racers stay. **New session** in the same menu starts over on the same track. Scripts can do the same over the admin API (the track can't change while a session runs):

```bash
curl -X POST -H 'x-admin-pin: 1234' localhost:8080/api/admin/session/end
curl -X PATCH -H 'x-admin-pin: 1234' -H 'content-type: application/json' -d '{"track":"countryside"}' localhost:8080/api/admin/config
curl -X POST -H 'x-admin-pin: 1234' -H 'content-type: application/json' -d '{}' localhost:8080/api/admin/session/start
```

Or set `"track": "countryside"` in `bebbikart.config.json` at the repo root before starting to begin on the countryside instead. On the village each run is one lap: the phone shows the lap timer and the lap's time vs your best lap, and the best lap ranks. `bun run fake-game` races laps too.

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
| `PUBLIC_URL` | `http://<wifi-ip>:8080` | Used in asset URLs and the printed join URL; when set, it stays as given (no network detection) |
| `BK_GAME_KEY` | `bebbikart-dev` | Game must send the same key (`--game-key=` or `BK_GAME_KEY`) |
| `BK_ADMIN_PIN` | `1234` | Header `x-admin-pin` for `/api/admin/*` |
| `BK_AUTOSTART` | `1` | Keep a session running: start one at boot and the next one when time runs out |
| `BK_DATA_DIR` | `apps/server/data` | SQLite db, uploads and asset packages (git-ignored) |
| `BK_DESIGN_CONCURRENCY` | `8` | Racers designed at once; more wait in line (the phone says so) |

Handy admin calls:

```bash
curl -X POST -H 'x-admin-pin: 1234' localhost:8080/api/admin/session/reset   # wipe players and runs
curl -H 'x-admin-pin: 1234' localhost:8080/api/admin/players                   # everyone, with jobs
```

## Troubleshooting

- **Phone can't load the page:** same Wi-Fi? Then the Wi-Fi most likely keeps its devices apart (client isolation, usual on guest Wi-Fi, hotels and offices): the phone's request never reaches the Mac, so the server can't log anything about it. The server warns about the macOS firewall and a missing network itself, and names what on the Mac may block phones without it being able to tell: a connected VPN (allow LAN connections in its app, or disconnect it) and CrowdStrike Falcon (its firewall is set by IT and can block incoming connections on networks it doesn't trust; if phones can't get through even on a phone's hotspot, use a Mac without it or ask IT). To tell isolation apart, check that the server still says `No phone has opened it yet` while the phone times out. Ways round it:
  - **A phone's Personal Hotspot.** Turn it on (iPhone: Settings › Personal Hotspot › Allow Others to Join), join it from the Mac and the other phones. Devices on an iPhone hotspot normally reach each other (try it with one phone first), and the drawings still get to Claude over mobile data. The server picks up the new address by itself: reopen the big screen's menu (Esc) for the new code. An iPhone hotspot takes only a handful of devices, so it suits a test or a small group.
  - **A travel router** (or any Wi-Fi router you control, with its guest/isolation mode off): Mac and phones on it, the router's own internet from the venue's Wi-Fi (repeater mode) or a cable. The best fit for an event.
  - **Another network** where phones can reach each other: ask the venue for the staff network or to turn client isolation off for the day.
  - The Mac's own Wi-Fi sharing (System Settings › General › Sharing › Internet Sharing) only works when the Mac gets its internet another way (Ethernet, or an iPhone over USB): its Wi-Fi can't join the guest network and host one at once.
- **"The big screen isn't connected yet" on Go!:** the game isn't connected. Its overlay says `SERVER online` when it is; check the game key.
- **Racer stuck on "Looking at your drawing…":** see the server log (`[job] …`). Jobs time out after 300 s (`BK_JOB_TIMEOUT_MS`; the look, design, critique and refine passes take about 60 to 150 s) and the phone shows the error.
- **Fresh start:** stop the server and delete `apps/server/data/`, or call the reset endpoint above.
