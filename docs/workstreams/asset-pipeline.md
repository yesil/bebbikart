# WS5 — Racer Designer (drawing → living 3D racer)

**Lives in:** `packages/asset-pipeline` · **Depends on:** `packages/shared` and the racer kit catalog from WS3 (§3). Can start **now** as a standalone CLI.
**Read first:** [`../contracts.md`](../contracts.md) §5 (`RacerSpec`)

## Goal

Kids' drawings will be **very raw**: a few lines, scribbled colour, maybe a face. We don't copy the lines. We capture the **spirit and the colours** and turn them into a **living 3D toy racer** that drives, jumps, gets dizzy, celebrates and waves, with facial expressions and an **avatar** on the kid's phone.

**How:** Claude looks at the drawings and **writes a design**, not a picture: a small JSON `RacerSpec` that says which toy parts to use, their colours, sizes and positions, the face, and up to a dozen extra shapes for the unique details. The Godot game **builds the racer in 3D** from that spec and animates it. Two AI passes per racer (design, then review against a 3D render), no image generation, cost in cents for the whole event.

Why this beats generating images:
- **Real 3D**, so every pose and expression is just animation: unlimited, smooth, always the same character.
- **One house style for free:** every racer is assembled from the same toy-part kit, so they all belong in the toy world.
- **Cheap, and worth the wait:** two Claude passes (30–60 s), no image model, no background removal. A single fast call (~5 s) gave flat, samey racers, so we trade time for likeness and personality.
- **Editable:** a spec is small JSON, so a facilitator (or the kid, later) can tweak a colour or swap a hat.

## 1. Pipeline

```
photos ─► 1 Normalise ─► 2 Look ─► 3 Design ─► 4 Critique ─► 5 Refine ─► validate ─► game builds ─► avatars ─► phone
              (sharp)    (vision)    (text)     (vision)      (text)       (zod)
```

1. **Normalise** (`sharp`): EXIF rotate, strip metadata, longest side ≤ 1536 px. Also save a cropped copy of the drawing for the "drawn by me" view and the optional **drawing sticker** on the ride (§4).
2. **Two Claude passes** (`claude-sonnet-5-5`, adaptive thinking at high effort, `src/claude.js`; `ANTHROPIC_API_KEY`; prompts in `src/prompt.js`; ~30–60 s per racer):
   - **design** (vision): sees both drawings; checks them (real photo, real person, empty page, unreadable → `rejected` with a friendly retake message), writes `observations` (every feature, the child's written labels in any language, "sketch" or "detailed"), a `featureMap` and the `RacerSpec`. Its thinking is reported as stage `looking`, its written reply as `designing`.
   - **render**: Godot builds the spec and renders a front 3/4 and a side view (`render_heroes.gd --side`, ~1 s, `BK_GODOT_BIN`).
   - **review** (vision): sees the drawings and the renders and returns only a patch (`set` / `remove` / `add` ops on the spec), so it writes little. Stages `critiquing` then `refining`. `BK_REVIEW_ROUNDS=2` renders and reviews the patched racer again (~+25 s, small gains).
   - **Progressive (server):** the racer is ready after the design pass (~20–60 s) so the kid can play; up to 3 review rounds (`BK_REFINE_ROUNDS`, ~20 s each) then run in the background. Each improved spec becomes a new asset package (`game.improveManifest`: the player's status is untouched, the game sees the new packageId and rebuilds/re-renders). A round whose patch is empty ends refining; a failed round stops refining with the error logged, keeping the last good racer. Newer drawings from the same player drop pending rounds. CLI: `--progressive`.
   - **Names:** title and tagline are chosen last and plainly describe what is drawn ("Silver Braid Rider"); they never reshape the design.
   - **Loyalty rule (ilyas):** a detailed drawing is reproduced as closely as the kit allows with nothing invented; only a bare line sketch may be enhanced. Written labels ("schwarze Räder") are instructions.
   Each pass retries up to 3 times with the validation errors; a failed call, a refusal or a failed render fails the job with the reason (no default racer). New racers must have `tagline`, `motion` and `sound`. `_meta/<name>.json` keeps observations, first design, review and timings.
   History: DeepSeek four passes (look, design, critique, refine) until 2026-10-31, then Claude four passes (~2.5 min), then two passes. Medium effort was 20–30 s but visibly less faithful.
3. **Validate & clamp** with the zod schema: unknown part names → nearest valid part, numbers clamped to ranges, extras capped. If it's badly broken, retry once with the validation errors added to the prompt. Still broken → the job fails with the reason.
4. **Build:** the server stores the spec (`player.updated`, `roster.updated`). The game assembles the racer immediately. The player is `ready` as soon as the spec is valid.
5. **Avatars:** right after building, the game renders the racer offscreen (a `SubViewport`) as `hero.png` (full racer, 3/4 view) and `avatar_happy/excited/sad.png` (head and shoulders, 512 px), and uploads them to the server (contracts §6). The phone shows those. If the game isn't running, the phone shows a placeholder in the racer's colours until it is.

"**Try another look**" (max 3) reruns the passes with a "make a different interpretation" hint in the design pass.

## 2. What the spec captures (summary; full schema in contracts §5)

- **Spirit:** `title` ("The Purple Flash"), `personality` (2–3 words), which also tunes idle animation (bouncy vs calm), engine sound pitch and celebration style.
- **Look:** `tagline` (a funny one-line bio for the reveal), `motion` (idle style: bouncy, wobbly, proud, sneaky… and energy), `sound` (engine loop, pitch, horn), patterns (stripes, spots, crayon strokes…) and finishes (matte, metallic, sparkle, glow) on body, head and ride, and a racing number.
- **Palette:** 3–8 colours taken from the drawing. Parts reference palette slots, so the whole racer stays in the kid's colours.
- **Character:** body shape, head shape, skin/fur colour, **face** (eye style, eye colour, mouth style, brows, cheeks), hair, hat, arms.
- **Ride:** a base (`kart`, `car`, `bike`, `animal4`, `bird`, `board`, `rocket`, `boat`, `sailboat`, `blob`, or a bare `chassis` whose body is built from extras for everyday objects like a sofa or a teapot) with wheels / legs / wings / tail options, colours and proportions.
- **Extras:** up to 10 on the character and 12 on the ride. Each is a shape from the kit (primitives plus flat stickers like `lightning`, `flame`, `moon`, `flower`, and `glasses`, `cape`) attached to a named socket with offset, scale, rotation and palette colour. This is where the unique bits go: three horns, a lightning bolt, a propeller, spots.
- **Drawing sticker:** optional. The kid's actual drawing, as a rounded sticker on the side of the ride, so the link to the paper stays visible.

## 3. Kit catalog (shared with WS3)

WS3 (art) builds the toy-part kit in Godot. WS5 needs its **catalog**: part names, a one-line description of each, and socket names. Keep it in `packages/shared/src/racer-kit.js` and have the game read the same list (exported to JSON for Godot). Adding a part = model it in Godot + add one line to the catalog, and the AI can use it immediately.

## 4. Tuning loop (this is most of the work)

- `bun run pipeline design driver.jpg ride.jpg` → prints the spec and writes `out/<name>.spec.json`.
- The Godot project has a **Racer Viewer** scene that watches `out/` and shows every spec as a 3D racer on a turntable, cycling through its poses and expressions. Change the prompt, rerun, look.
- Use 10–15 real raw kid drawings. Tune the prompt, examples and kit until most results make you smile and look clearly "like the drawing".

## 5. Interface (what WS2 calls; TS-style notation, code is plain JS)

```ts
export function runDesignJob(
  input: {
    jobId: string;
    playerId: string;
    characterPath: string;
    vehiclePath: string;
    outDir: string;
    skipCheck?: boolean;
    reroll?: boolean;
  },
  onStatus: (s: JobStage | "ready" | "rejected") => void, // looking → designing → critiquing → refining
): Promise<
  | { status: "ready"; spec: RacerSpec }
  | { status: "rejected"; reason: RejectReason; image: "character" | "vehicle"; message: string }
  | { status: "needs_review"; notes: string }
  | { status: "failed"; error: string }
>;
```

## Privacy

Drawing photos go to Anthropic (Claude API) only, downscaled, with metadata stripped, never with the kid's name. **Confirm the company is OK with that.** Everything on the Mac is deleted on session reset.

## Task list

| #   | Task                                                                | Size | Milestone |
| --- | ------------------------------------------------------------------- | ---- | --------- |
| 1   | Collect 10–15 raw sample drawings                                   | S    | M1        |
| 2   | `RacerSpec` zod schema + clamping (with WS1)                        | S    | M1        |
| 3   | Kit catalog format, first version with WS3                          | S    | M1        |
| 4   | DeepSeek call: prompt, catalog, examples, JSON mode, check + design | M    | M1        |
| 5   | Validation retry + default-spec fallback                            | S    | M1        |
| 6   | CLI writing spec files for the Godot Racer Viewer                   | S    | M1        |
| 7   | Prompt + example tuning with the art lead                           | M    | M2→M3     |
| 8   | Reroll                                                              | S    | M2        |

## Later (V2)

Let kids tweak their racer on the phone (swap hat, recolour) by editing the spec. Optional image-generated "poster" of the racer for a take-home print.
