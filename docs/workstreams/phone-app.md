# WS4 — Phone Website (PWA) & Facilitator Console

**Lives in:** `apps/web` · **Depends on:** `packages/shared` (M0). Works fully on MSW mocks until the server is ready.
**Read first:** [`../README.md`](../README.md) §2, [`../contracts.md`](../contracts.md) §6–8

## Goal

A tiny mobile **website** (a Progressive Web App, **not** a native app; nothing to install from a store) that an adult opens from a QR code or short URL. In under a minute they can photograph two drawings, name the racer and see it appear on the big screen. After that it becomes the kid's **coach's clipboard**: tune stars, press **Go!**, steer with a thumb (contracts §2g), and see section-by-section what to improve. Plus a `/admin` console for the facilitator.

## Stack (default)

Plain JavaScript. UI with [Preact](https://preactjs.com) + [htm](https://github.com/developit/htm) (tagged templates, so no JSX and no compile step for templates), bundled with Vite under Bun. Plain CSS, no component library. Works on iOS Safari 16.4+ and Android Chrome. Portrait only. Large touch targets (≥ 56 px), big friendly type, works one-handed. No login: the device cookie is the identity.

## PWA requirements

- **Web app manifest:** name "BebbiKart", icons (192/512 + maskable), `display: standalone`, portrait, theme colour. Installable ("Add to Home Screen"), but **never required**: everything works in a normal browser tab.
- **V1 runs over plain HTTP on the local network** (`http://<mac-ip>:8080`). Browsers only allow service workers, the install prompt and the screen wake lock on HTTPS, so in V1 those are **off**. The site still works fully as a normal web page, and "Add to Home Screen" still creates a shortcut.
- **Later, once there's HTTPS** (a domain or local certificate, out of scope for now): add a service worker that precaches the app shell (never `/api/*`, `/ws` or uploads), the install prompt, and `navigator.wakeLock` during runs. Write the code so these are a small add-on, not a rewrite.
- Keep the bundle small (target < 150 KB gzipped) so the first load is instant over local Wi-Fi.
- **Vibration** when the thumb goes down, when the kart's side of the road flips and when the way at a fork ahead changes (Android only; iOS ignores it). Works over HTTP.

## Screens (phone)

1. **Welcome / Create racer.** Racer name field (1–16 chars), then two big photo buttons: "Photo of the **driver** drawing" and "Photo of the **ride** drawing" (`<input type="file" accept="image/*" capture="environment">`). Show both previews, with a "Retake" option for each. Tip line: "Lay the paper flat, fill the frame, good light." Submit.
   - Downscale on device to ≤ 2048 px JPEG before upload (faster on bad Wi-Fi). Show an upload progress bar.
2. **Making your racer…** "Looking at your drawing…" → "Building your racer…" → **the reveal**: the original drawing slides aside and the game's render of the 3D racer (`hero.png`) appears, with its title ("The Purple Flash!") and personality words. Also say "Look at the big screen!", where the racer drives into the paddock and waves. A **"Try another look"** button (max 3) calls `/reroll`. On `rejected`, show a friendly reason and a retake button for the failing image only ("That looks like a real photo. Please take a picture of the drawing!"). On `needs_review`: "A grown-up is checking it, one moment."
3. **Garage (home).** The racer's **avatar** at the top (it's the kid's identity throughout the app), nickname (tap to edit), racer title, best time and rank. Tap the avatar to see the full racer render and "drawn by me" (the original drawing). Three panels:
   - **Stars.** Six rows with icon, name and a short kid-friendly line ("Grip: stick to the road"). − / + buttons and filled stars. A big counter "Stars left: 2" that must reach 0 before Go! is enabled. Rows are capped at 5.
   - **Routes.** Three forks as two big picture cards each (Water / Bridge, Jump / Around, Windy bridge / Hedge path). A small note under each says what it rewards.
   - **Style.** Three-way toggle: 🐢 Careful · 🙂 Balanced · 🔥 Daring.
   - Weather strip: current weather plus "Rain coming in 5…" warnings, and a **track traffic** indicator ("3 racers on the track") so kids can choose to wait for a quiet moment.
   - A huge **Go!** button. Disabled with a reason when not allowed (cooldown countdown, "Your racer is still on the track").
4. **Run.** The whole run screen is a steering pad (contracts §2g): a thumb anywhere moves the kart across the road (the pad shows the kart's lane and where the thumb asks for), letting go hands it back to the autopilot; two signs show the fork coming up and which way the kart is heading for. Live timer, a progress bar with four section ticks, and "+0.8 / −1.2 vs best" after each section line. A **"📺 Show me on the big screen"** button (`phone.watch`): the big screen's camera cuts to this racer soon, the button says "Coming up on the big screen…" until then, and glows green with "You're on the big screen!" (and a short buzz) while the camera is on them (`camera.updated`).
5. **Result.** The avatar reacts: `avatar_excited` for a new best, `avatar_happy` for a finish, `avatar_sad` for a fail. Time, or "Oops!" plus the reason. 🎉 if it's a new personal best. Rank. **Section table**: four rows with time vs best, coloured green or red. **Coach tip** card that highlights the suggested change (e.g. pulses the Grip row). Buttons: "Change & try again" (back to Garage), "Go again" (same build).
6. **Leaderboard** (tab): top 20 with avatars, your row highlighted. **History** (tab): last 10 runs with splits.

Also: a session-ended screen showing the final rank. If the connection drops, the WS client simply reconnects.

## Facilitator console (`/admin`)

PIN screen, then one page:
- Session: start (duration), end, **reset** (with a confirm step), live clock.
- Show/hide QR on the big screen, and the join URL.
- Player table: avatar, name, status, connected, best time, runs. Actions: rename, remove, approve `needs_review` (shows the uploaded photo), re-upload, **launch a run for them** (for kids without a phone), edit their build.
- "Add racer without phone": same create flow as the phone, done by the facilitator.
- Live config sliders: weather calm/active ranges, max concurrent runs.
- Export results as CSV.

## Copy and tone

Short, warm, no jargon, no failure shaming. Every string goes in one `copy.js` file (easy to review, and easy to translate later: **which language will the event use?**). Coach tip text comes from `coachTip()` in shared, not from the app.

## Task list

| #   | Task                                                                      | Size | Milestone |
| --- | ------------------------------------------------------------------------- | ---- | --------- |
| 1   | App shell, routing, WS client with reconnect, device bootstrap, MSW mocks | M    | M1        |
| 2   | Create racer flow with client-side downscale + upload progress            | M    | M1        |
| 3   | Job status screen incl. reject/retake and needs-review states             | S    | M1        |
| 4   | Garage: stars editor with rules, routes, style, weather strip, Go!        | M    | M1        |
| 5   | Run screen: steering pad, fork signs, live timer, section ticks and deltas | M    | M1        |
| 6   | Result screen: splits table, coach tip highlight, PB/rank                 | M    | M1        |
| 7   | Leaderboard + history tabs                                                | S    | M2        |
| 8   | Admin console                                                             | M    | M2        |
| 8b  | PWA basics: manifest, icons, standalone display                           | S    | M2        |
| 9   | Quick check on one iPhone and one Android phone                           | S    | M3        |
| 10  | Copy review with someone who knows the kids' age group                    | S    | M3        |

## Done when

- An adult who has never seen the app creates a racer in under 60 s on their own phone.
- A 7-year-old (with help reading) can change a star, pick a route and press Go! without being told how.
- Every screen feels instant and smooth: transitions under 100 ms, no layout jumps, steering reacts on touch-down.
