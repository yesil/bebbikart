# WS6 — Event Setup

**Depends on:** nothing. Venue questions can **start now**.
**Read first:** [`../README.md`](../README.md)

## Goal

On the day, the big screen is up and phones join in seconds. Keep it light: this is a one-time event, so the setup is simple and there is no test or recovery process. If something misbehaves, reload the page.

## 1. Venue facts to collect

| Question                                                  | Why it matters                                                                               |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Event date and room                                       | Sets the real deadline                                                                       |
| Which Wi-Fi? Is **client isolation** on?                  | Guest Wi-Fi often stops phones from reaching the Mac. This is the main thing to check early. |
| Internet on that network?                                 | Needed for the DeepSeek drawing check. Without it, the facilitator approves drawings by eye. |
| Number of kids, ages, phones, adults                      | Racer count, whether the facilitator creates racers for kids                                 |
| Language                                                  | UI copy                                                                                      |
| Speakers                                                  | Sound                                                                                        |
| Is sending drawing photos to DeepSeek OK for the company? | Drawing check on or off                                                                      |

## 2. Setup

- **One Mac** runs the server (`bun run start`) and the **Godot game** fullscreen on the big screen (any display plugged into the Mac; set it as the main display or move the game window there). The game connects to the server at `ws://localhost:8080/ws`. Power cable plugged in, sleep and notifications off (Focus mode).
- **macOS firewall:** the first time the server starts, macOS may ask whether to accept incoming connections for `bun`. Click **Allow**, otherwise phones can't connect.
- **Local network, plain HTTP.** Phones and the Mac on the same Wi-Fi. The server prints its LAN address at startup (e.g. `http://192.168.1.10:8080`), and the big screen shows it as a QR code. Print the QR on paper too. No domain or certificate in V1.
- If the venue Wi-Fi blocks phone-to-Mac traffic, bring a cheap travel router (or use a phone hotspot) and put the Mac and phones on that.
- If phones can't join at all, the facilitator creates racers in `/admin` on the Mac and launches runs for the kids. The game still works.

## 3. Before the event

One rehearsal in the real room (or as close as possible) with the real Mac, screen and Wi-Fi and a handful of phones: create racers, run a few races, check sound and readability from the back of the room.

## Task list

| #   | Task                                                                                   | Size | Milestone |
| --- | -------------------------------------------------------------------------------------- | ---- | --------- |
| 1   | Collect venue facts (§1)                                                               | S    | now       |
| 2   | Check the Wi-Fi with 2–3 phones and the Mac (can phones reach `http://<mac-ip>:8080`?) | S    | M2        |
| 3   | Rehearsal                                                                              | S    | M4        |
