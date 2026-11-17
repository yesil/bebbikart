# BebbiKart

A local multiplayer kart game: kids' drawings become 3D racers, phones steer,
and a Godot game runs on the big screen. Racers are designed with Claude.

## Setting up a Mac

Requires [Bun 1.4+](https://bun.sh), the standard
[Godot 4.7.2](https://github.com/godotengine/godot/releases/tag/4.7.2-stable)
with `godot` on your PATH, and an Anthropic API key.
Audio generation needs FluidSynth, FFmpeg with `libvorbis`, and the
[MuseScore General soundfont](https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/)
(see [audio build notes](scripts/race-end-cues.js)).

From the repo root:

```sh
bun install --frozen-lockfile
cp .env.example .env
```

Set `ANTHROPIC_API_KEY` and `SOUNDFONT` (path to `MuseScore_General.sf2`) in `.env`,
then generate the game assets and play:

```sh
bun run setup
bun run game:templates
bun run play
```

Setup downloads dependencies and texture sources, then generates worlds, maps,
samples and sound cues. Build outputs stay ignored. The first play exports the
macOS game; allow a few minutes.
Join phones to the same local network, allow Bun's incoming connections, and
open the phone URL printed by the server (`http://<mac-ip>:8080`). The game's
options menu (Esc) also shows a QR code. Quit the game or press Ctrl+C to stop.

Drawing uploads go to Anthropic and incur API usage charges. Keep `.env` local;
racers, uploads and the leaderboard live in `apps/server/data/`. Both are ignored by Git.
Use a trusted local network: the default admin PIN is `1234` (`BK_ADMIN_PIN`)
and the game key is `bebbikart-dev` (`BK_GAME_KEY`).

## Development

| Command              | Purpose                                                       |
| -------------------- | ------------------------------------------------------------- |
| `bun run dev`        | Server on :8080, phone site on :5173, Godot game              |
| `bun run game:mock`  | Game preview without a server or API key                      |
| `bun run start`      | Build and serve the phone site on :8080                       |
| `bun run dev:game`   | Connect the debug game to the server                          |
| `bun run test`       | Run Bun tests                                                 |
| `bun run lint`       | Check JavaScript formatting and lint                          |
| `bun run setup`      | Regenerate assets and install the Terrain3D native dependency |
| `bun run kit:export` | Regenerate Godot contracts after changing `packages/shared`   |

## Layout

```text
apps/game/                Godot game
apps/server/              Bun server, WebSockets and racer jobs
apps/web/                 Phone site and admin console (Preact + Vite)
packages/shared/          Schemas, protocol and racer kit
packages/asset-pipeline/  Drawings → RacerSpec
```

[Local testing and settings](docs/local-testing.md) ·
[Game controls](apps/game/README.md) ·
[Contracts](docs/contracts.md) ·
[Asset credits](apps/game/assets/CREDITS.md) ·
[Audio credits](apps/game/assets/audio/CREDITS.md)
