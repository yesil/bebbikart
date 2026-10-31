# BebbiKart

A one-time kart game for kids: drawings become 3D racers, phones coach, the computer drives.
The plan lives in [`docs/`](docs/README.md); the shared rules are in [`docs/contracts.md`](docs/contracts.md).

## Setup

Needs [Bun](https://bun.sh) and [Godot 4](https://godotengine.org) (`godot` on the PATH).

```bash
bun install
bun run kit:export   # writes the Godot copies of the contracts into apps/game
bun run dev          # server :8080, phone site :5173, and the Godot game (--server)
```

To try the whole thing with a phone on the same Wi-Fi, see [`docs/local-testing.md`](docs/local-testing.md).

| Command | What it does |
|---|---|
| `bun run dev` | Starts server, phone site and game together |
| `bun run start` | Builds the phone site and serves everything from the server on :8080 |
| `bun run dev:game` / `game:mock` | Godot game against the server / in mock mode |
| `bun run fake-game` | Stand-in game for testing phones without Godot |
| `bun run test` | Runs all Bun tests |
| `bun run lint` / `bun run format` | Biome check / fix |
| `bun run kit:export` | Regenerates `apps/game/net/protocol.gd`, `data/racer_kit.json`, `data/pkg_default/spec.json` |

## Layout

```
packages/shared/          zod schemas, enums, config, messages, racer kit, coach tips (WS1)
  testing/                fixtures (@bebbikart/shared/testing) and MSW handlers (@bebbikart/shared/msw)
packages/asset-pipeline/  drawing → RacerSpec designer (WS5)
apps/server/              Bun game server (WS2)
apps/web/                 phone site + /admin, Preact + htm on Vite (WS4)
apps/game/                big-screen game, Godot 4 (WS3)
```
