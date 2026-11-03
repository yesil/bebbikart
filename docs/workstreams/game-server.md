# WS2 — Game Server

**Lives in:** `apps/server` · **Depends on:** `packages/shared` (M0), `packages/asset-pipeline` (interface only; stub until WS5 lands)
**Read first:** [`../README.md`](../README.md) §2–3, [`../contracts.md`](../contracts.md) §4–7

## Goal

One small Bun process. It is the single source of truth for **who is playing, what they built, and what times they set**, and it relays messages between phones, the facilitator console and the big-screen game. Keep it minimal: it's a one-time event, so no hardening beyond what makes the game feel smooth. SQLite is there so a page reload or a quick restart doesn't wipe the leaderboard, not for recovery engineering.

## Owns / doesn't own

| Owns                                                                                                                      | Doesn't own                                       |
| ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| REST API and WS hub (contracts §6–7)                                                                                      | Physics, timing, weather. The game decides those. |
| SQLite persistence, uploads on disk                                                                                       | Image analysis. It calls the asset pipeline.      |
| Session clock, run admission, cooldowns, leaderboard                                                                      | UI of any kind                                    |
| Running the asset job queue                                                                                               |                                                   |
| Serving the built `apps/web` and `/assets` (the game is a separate desktop app that connects to `ws://localhost:8080/ws`) |                                                   |
| Admin auth, config loading and live config changes                                                                        |                                                   |

## Stack (default)

**Bun** (latest stable) · `Bun.serve` with its built-in WebSocket support (pub/sub topics per role) · [Hono](https://hono.dev) for REST routing · `Request.formData()` for uploads · `bun:sqlite` · `console` logging. One process, no Redis, no Docker.

## Key design notes

- **Run admission.** On `phone.go` / `POST …/runs`: check that the session is running, the player is `ready`, they have no active run, the cooldown has passed, and `running < maxConcurrentRuns`. Then create a `Run{status:"queued"}`, send `run.start` to the game, and mark it `running` on `game.run.started`. If the game isn't connected, refuse with `game_offline`.
- **Game is authoritative** for results. On `game.run.finished`: store the run, update the best if faster (store `GhostTrace` only for the best), recompute ranks, compute `coachTip()` from shared, then push `run.ended` to the phone and `leaderboard.updated` to everyone.
- **Relays.** `phone.steer` → `run.steer` to the game (contracts §2g), only if the run is the player's active run (drop otherwise); a phone that disconnects while steering gets `run.steer { x: null }` sent for it. The ways each lap took (`game.run.lap.routes`) are kept as `run.lapRoutes`, the finish's as `run.routes`; setups use them. Game progress and section messages → the owning phone only. `game.weather` → all phones.
- **Session end.** At `endsAt`: status `ended`, reject new runs, let running runs finish (or abort after `runTimeCapMs`), then broadcast. The game shows the podium on `session.updated`.
- **Presence.** `connected` = has an open phone socket. Use a 15 s heartbeat (ping/pong). Broadcast `roster.updated` to the game on change, debounced 250 ms.
- **Restart.** On boot, load the current session and mark any `running` run as `aborted`. That's all.
- **Uploads.** Save originals to `data/uploads/<playerId>/` and hand paths to the pipeline. Never serve the full-size originals. Only specs, game renders and the downscaled drawing copies are served via `/assets`. On session reset with `deleteUploadsOnReset`, delete uploads and assets.
- **Design jobs.** In-process queue, 3 jobs at once. Call `runDesignJob(input, onStatus)` from `@bebbikart/asset-pipeline`. On `ready`, save `spec.json`, mark the player `ready`, push `player.updated` and `roster.updated`. 60 s timeout → `failed`, and the phone shows "Try again". `POST …/reroll` reruns it (max 3).
- **Renders.** Accept `PUT /api/game/renders/:playerId/:key` from the game (PNG, `x-game-key`), save into the package, update the manifest, push `player.updated`.
- **Networking.** Bind `0.0.0.0`. Plain **HTTP** on port 8080. Detect the Mac's LAN IP at startup and follow it when the network changes (override with `PUBLIC_URL`); say loudly when phones can't reach it (no network, firewall) and that it is unproven until a phone gets through (`apps/server/src/network.js`) and use it for the join QR code at `GET /api/join-qr.svg`, which the big screen shows. HTTPS is out of scope for V1.
- **Limits.** Upload size limit 15 MB. Nothing else.

## Task list

| #   | Task                                                                                      | Size | Milestone |
| --- | ----------------------------------------------------------------------------------------- | ---- | --------- |
| 1   | Bun.serve + Hono skeleton, config loading (file + env)                                    | S    | M1        |
| 2   | SQLite schema + migrations for session, device, player, build, run, asset_job, best_trace | M    | M1        |
| 3   | Device cookie + player endpoints + nickname filter                                        | S    | M1        |
| 4   | Build endpoint with shared validation                                                     | S    | M1        |
| 5   | WS hub: hello/welcome per role, heartbeat, typed routing, rate limits                     | M    | M1        |
| 6   | Run admission, cooldowns, queue-while-game-offline, abort rules                           | M    | M1        |
| 7   | Result handling: best time, trace storage, ranks, `coachTip`, broadcasts                  | M    | M1        |
| 8   | Session clock, start/end/reset, end-of-session behaviour                                  | S    | M1        |
| 9   | Upload endpoint + job queue calling the pipeline (stub → real)                            | M    | M1→M2     |
| 10  | Admin endpoints + admin WS role                                                           | M    | M1        |
| 11  | Static serving of web, game, assets; QR endpoint                                          | S    | M2        |

## Done when

- All contract routes and messages work with the real phone app and game.
- Go! and steering feel instant: a tap or a thumb move reaches the big screen in well under 100 ms on the event Wi-Fi.
