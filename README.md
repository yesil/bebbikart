# BebbiKart

A one-time kart game for kids: drawings become 3D racers, phones coach, the computer drives.
The plan lives in [`docs/`](docs/README.md); the shared rules are in [`docs/contracts.md`](docs/contracts.md).

## Setting up a Mac

Everything the build needs is in the repo (game assets, Godot `.import` and `.uid` files, the
generated Godot copies of the contracts). What a fresh clone does not have: the API key, the
release build, Godot's import cache (`apps/game/.godot/`) and the server's data (racers,
leaderboard, uploads in `apps/server/data/`, which starts empty).

1. **Git**: `xcode-select --install` (Command Line Tools), and access to the GitHub repo.
2. **Bun 1.4** or newer ([bun.sh](https://bun.sh)): `curl -fsSL https://bun.sh/install | bash`
3. **Godot 4.7.2**, the standard build (not .NET), with `godot` on the PATH:
   `brew install --cask godot` installs it and links `godot`. Check with `godot --version`
   (`4.7.2.stable…`). If Homebrew has moved on, take `Godot_v4.7.2-stable_macos.universal.zip`
   from the [4.7.2 release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable), put
   `Godot.app` in `/Applications` and link
   `ln -s /Applications/Godot.app/Contents/MacOS/Godot /opt/homebrew/bin/godot`.
4. **Godot's export templates** for that exact version (1.3 GB; `bun run play` needs them). Either
   open the project once (`godot -e --path apps/game`) and use Editor → Manage Export Templates →
   Download and Install, or:
   ```bash
   curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
   unzip -q Godot_v4.7.2-stable_export_templates.tpz
   mkdir -p ~/Library/Application\ Support/Godot/export_templates/4.7.2.stable
   mv templates/* ~/Library/Application\ Support/Godot/export_templates/4.7.2.stable/
   ```
5. **The Anthropic API key** (racers are designed from drawings by Claude; the server refuses to
   start without it). Put it in `packages/asset-pipeline/.env`, which is git-ignored:
   ```
   ANTHROPIC_API_KEY=sk-ant-...
   ```
   The server also reads `apps/server/.env`, `.env` at the repo root, or the environment.
6. Install and play:
   ```bash
   bun install
   bun run play
   ```
   The first `bun run play` imports every asset and exports the release build, which takes a few
   minutes; later runs only re-export when a file in `apps/game` changed. macOS asks whether `bun`
   may accept incoming connections: allow it, or phones can't reach the Mac.

To bring the racers and leaderboard from another Mac, stop the server there and copy its
`apps/server/data/` folder over before starting. Keep the clone at the same path on both Macs:
the database stores the design jobs' uploads by absolute path.

For development, `bun run dev` runs the server :8080, the phone site on Vite :5173 and the game on
Godot's debug runtime. To try the whole thing with a phone on the same Wi-Fi, see
[`docs/local-testing.md`](docs/local-testing.md).

| Command | What it does |
|---|---|
| `bun run dev` | Starts server, phone site and game together |
| `bun run play` | Real play on the big screen: built phone site on :8080 and the game's release build (no debug runtime); exports the game when needed |
| `bun run game:export` | Exports the game's release build to `apps/game/export/BebbiKart.app` (needs Godot's export templates) |
| `bun run start` | Builds the phone site and serves everything from the server on :8080 |
| `bun run dev:game` / `game:mock` | Godot game against the server / in mock mode |
| `bun run fake-game` | Stand-in game for testing phones without Godot |
| `bun run test` | Runs all Bun tests |
| `bun run lint` / `bun run format` | Biome check / fix |
| `bun run kit:export` | Regenerates `apps/game/net/protocol.gd`, `data/racer_kit.json`, `data/pkg_default/spec.json` (committed; run it after changing `packages/shared`) |

## Layout

```
packages/shared/          zod schemas, enums, config, messages, racer kit, coach tips (WS1)
  testing/                fixtures (@bebbikart/shared/testing) and MSW handlers (@bebbikart/shared/msw)
packages/asset-pipeline/  drawing → RacerSpec designer (WS5)
apps/server/              Bun game server (WS2)
apps/web/                 phone site + /admin, Preact + htm on Vite (WS4)
apps/game/                big-screen game, Godot 4 (WS3)
```
