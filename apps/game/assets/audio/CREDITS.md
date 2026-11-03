# Audio credits

All audio here is CC0 1.0 (public domain) except `sfx/cheer.wav` (CC BY 4.0) and `racers/horn_neigh.wav` (CC BY 3.0), which need the credits below, and the race-end cues `sfx/end_*.ogg`, which are composed for BebbiKart and rendered with the MIT-licensed MuseScore General soundfont (see Race-end cues). Licence texts are in `licenses/`. Files were renamed for the game. `sfx/cheer.wav` was cut to 4.5 s, faded and made mono 32 kHz. Other `sfx/`, `music/` and `ambience/` files are the originals. Every `racers/` file was converted to mono 32 kHz WAV and level-matched; the edits per file are noted in its row.

| Path | Original file | Source | Author | Licence |
|---|---|---|---|---|
| `music/paddock_racing_game_menu.ogg` | `racing_game_menu_bpm165.ogg` | [Racing Game Menu](https://opengameart.org/content/racing-game-menu) | MintoDog | CC0 1.0 |
| `music/countryside_sunny_city.ogg` | `sunny_city_bpm120.ogg` | [Sunny City](https://opengameart.org/content/sunny-city) | MintoDog | CC0 1.0 |
| `music/countryside_sunny_city_climax.ogg` | `sunny_city_climax_bpm135.ogg` | [Sunny City](https://opengameart.org/content/sunny-city) | MintoDog | CC0 1.0 |
| `music/village_pure_raceway.ogg` | `pure_raceway_bpm160.ogg` | [Pure Raceway](https://opengameart.org/content/pure-raceway) | MintoDog | CC0 1.0 |
| `music/village_pure_raceway_climax.ogg` | `pure_raceway_climax_bpm175.ogg` | [Pure Raceway](https://opengameart.org/content/pure-raceway) | MintoDog | CC0 1.0 |
| `sfx/finish_jingle.ogg` | `jingles_SAX07.ogg` | [Music Jingles](https://kenney.nl/assets/music-jingles) | Kenney | CC0 1.0 (`licenses/Kenney_music-jingles.txt`) |
| `sfx/best_lap_jingle.ogg` | `jingles_STEEL07.ogg` | [Music Jingles](https://kenney.nl/assets/music-jingles) | Kenney | CC0 1.0 (`licenses/Kenney_music-jingles.txt`) |
| `sfx/start.ogg` | `confirmation_001.ogg` | [Interface Sounds](https://kenney.nl/assets/interface-sounds) | Kenney | CC0 1.0 (`licenses/Kenney_interface-sounds.txt`) |
| `sfx/lap.ogg` | `tick_001.ogg` | [Interface Sounds](https://kenney.nl/assets/interface-sounds) | Kenney | CC0 1.0 (`licenses/Kenney_interface-sounds.txt`) |
| `sfx/land.ogg` | `impactSoft_heavy_000.ogg` | [Impact Sounds](https://kenney.nl/assets/impact-sounds) | Kenney | CC0 1.0 (`licenses/Kenney_impact-sounds.txt`) |
| `sfx/bump.ogg` | `impactPunch_medium_000.ogg` | [Impact Sounds](https://kenney.nl/assets/impact-sounds) | Kenney | CC0 1.0 (`licenses/Kenney_impact-sounds.txt`) |
| `sfx/failed.ogg` | `impactSoft_medium_000.ogg` | [Impact Sounds](https://kenney.nl/assets/impact-sounds) | Kenney | CC0 1.0 (`licenses/Kenney_impact-sounds.txt`) |
| `sfx/boost.ogg` | `sfx100v2_air_02.ogg` | [100 CC0 SFX #2](https://opengameart.org/content/100-cc0-sfx-2) | rubberduck | CC0 1.0 |
| `sfx/splash.ogg` | `splash_04.ogg` | [40 CC0 water / splash / slime SFX](https://opengameart.org/content/40-cc0-water-splash-slime-sfx) | rubberduck | CC0 1.0 |
| `sfx/sheep_baa.ogg` | `sheep_baa.ogg`, cut from `Sheep bleat.wav` ([Freesound 414342](https://freesound.org/s/414342/), mikewest, CC0 1.0) | [Sheep Baa](https://opengameart.org/node/132779) | AntumDeluge (recording by mikewest) | CC0 1.0 |
| `sfx/cheer.wav` | `Gregor Quendel - Crowd Cheering Sounds - 04 - Strong cheering - II - Short.mp3` | [Free Crowd Cheering Sounds](https://opengameart.org/content/free-crowd-cheering-sounds) | Gregor Quendel | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) (`licenses/CC-BY-4.0.txt`) |
| `ambience/rain_loop.ogg` | `amb_rain_loop_1.ogg` | [Amb Rain Loop 1](https://opengameart.org/content/amb-rain-loop-1) | Kresiek The Furry | CC0 1.0 |
| `ambience/wind_loop.ogg` | `noise_01.ogg` | [30 CC0 SFX loops](https://opengameart.org/content/30-cc0-sfx-loops) | rubberduck | CC0 1.0 |
| `ambience/village_fountain.ogg` | `water_flowing.ogg` | [30 CC0 SFX loops](https://opengameart.org/content/30-cc0-sfx-loops) | rubberduck | CC0 1.0 |
| `ambience/thunder.ogg` | `sfx100v2_thunder_01.ogg` | [100 CC0 SFX #2](https://opengameart.org/content/100-cc0-sfx-2) | rubberduck | CC0 1.0 |
| `ambience/countryside_birds.ogg` | `birds-isaiah658.ogg` | [Ambient Bird Sounds](https://opengameart.org/content/ambient-bird-sounds) | isaiah658 | CC0 1.0 |

## Race-end cues (`sfx/end_*.ogg`)

Short brass fanfares composed for BebbiKart, all in F major so they sit with the village (D minor) and countryside (F major) music they dip. `scripts/race-end-cues.js` holds the notes, renders them with FluidSynth and the MuseScore General soundfont, and levels them with ffmpeg (Vorbis, true peak under -1.5 dBFS). The director (`audio/audio_director.gd`, `END_CUES`) picks one per lap's verdict.

| Path | Plays for | Length | Loudness |
|---|---|---|---|
| `sfx/end_record.ogg` | NEW CHAMPION! or NEW RECORD! (the crown's motif) | 5.6 s | -13 LUFS |
| `sfx/end_best.ogg` | a personal best, short of the crown | 3.0 s | -13.5 LUFS |
| `sfx/end_finish.ogg` | any other finished lap | 2.6 s | -14 LUFS |
| `sfx/end_oops.ogg` | OOPS! (a failed lap), after `sfx/failed.ogg` | 2.3 s | -16 LUFS |
| `sfx/end_podium.ogg` | the podium at a session's end (the crown's motif in full) | 7.9 s | -13 LUFS |
| `sfx/end_best_lap.ogg` | a best lap in a run of more than one lap | 1.4 s | -14 LUFS |

Soundfont: MuseScore General by S. Christian Collins, based on Fluid (R3) by Frank Wen and FluidR3 Mono by Michael Cowgill, MIT (`licenses/MuseScore_General-MIT.txt`).

## Racer engines and horns (`racers/`)

Each racer's `RacerSpec.sound` picks `engine_<engine>.wav` (a loop) and `horn_<horn>.wav`. The files are built by a one-off ffmpeg script from the sources below.

| Path | Made from | Source | Author | Licence |
|---|---|---|---|---|
| `racers/engine_putter.wav` | `motor_looping.mp3` | [Motor sound effect](https://opengameart.org/content/motor-sound-effect) | EZduzziteh | CC0 1.0 |
| `racers/engine_vroom.wav` | `loop_0.wav` | [Racing car engine sound loops](https://opengameart.org/content/racing-car-engine-sound-loops) | BlackCortex | CC0 1.0 |
| `racers/engine_electric.wav` | `loop_generator_1.mp3`, pitched up 1.6x, high-passed | [Generator loop](https://opengameart.org/content/generator-loop) | YCbCr | CC0 1.0 |
| `racers/engine_rocket.wav` | `whoosh2_0.wav` | [Air whoosh](https://opengameart.org/content/air-whoosh) | pyranostudios | CC0 1.0 |
| `racers/engine_hooves.wav` | `Trot.ogg`, first 4 s | [Horse trotting](https://opengameart.org/content/horse-trotting) | EZduzziteh | CC0 1.0 |
| `racers/engine_paws.wav` | `footstep_grass_000..004.ogg`, sequenced at 0.16 s | [Impact Sounds](https://kenney.nl/assets/impact-sounds) | Kenney | CC0 1.0 |
| `racers/engine_flap.wav` | `wings_flap_large.ogg` | [Large wings flap](https://opengameart.org/content/large-wings-flap) | AntumDeluge | CC0 1.0 |
| `racers/engine_splash.wav` | `loop_water_01.ogg` | [40 CC0 water / splash / slime SFX](https://opengameart.org/content/40-cc0-water-splash-slime-sfx) | rubberduck | CC0 1.0 |
| `racers/engine_magic.wav` | `beam-wowow.wav` | [Sci-fi aliens and cows pack](https://opengameart.org/content/sci-fi-aliens-and-cows-pack) | qubodup | CC0 1.0 |
| `racers/engine_squelch.wav` | `slime_01..04.ogg`, sequenced at 0.3 s | [40 CC0 water / splash / slime SFX](https://opengameart.org/content/40-cc0-water-splash-slime-sfx) | rubberduck | CC0 1.0 |
| `racers/horn_honk.wav` | `bicycle_horn-1.ogg` | [Bicycle sounds](https://opengameart.org/content/bicycle-sounds) | AntumDeluge | CC0 1.0 |
| `racers/horn_beep.wav` | `beep_02.ogg` | [50 CC0 sci-fi SFX](https://opengameart.org/content/50-cc0-sci-fi-sfx) | rubberduck | CC0 1.0 |
| `racers/horn_toot.wav` | `steam_whistle.wav`, first 1.5 s | [Steam whistle](https://opengameart.org/content/steam-whistle) | bart | CC0 1.0 |
| `racers/horn_squeak.wav` | `cute_01.ogg` | [80 CC0 creature SFX](https://opengameart.org/content/80-cc0-creature-sfx) | rubberduck | CC0 1.0 |
| `racers/horn_bell.wav` | `rotating_bicycle_bell-1.ogg` | [Bicycle sounds](https://opengameart.org/content/bicycle-sounds) | AntumDeluge | CC0 1.0 |
| `racers/horn_roar.wav` | `roar_01.ogg` | [80 CC0 creature SFX](https://opengameart.org/content/80-cc0-creature-sfx) | rubberduck | CC0 1.0 |
| `racers/horn_meow.wav` | `Meow.ogg` | [Meow](https://opengameart.org/content/meow) | IgnasD | CC0 1.0 |
| `racers/horn_woof.wav` | `barking_01.ogg` | [80 CC0 creature SFX](https://opengameart.org/content/80-cc0-creature-sfx) | rubberduck | CC0 1.0 |
| `racers/horn_neigh.wav` | `zebra.ogg` | [Zebra whinny](https://opengameart.org/content/zebra-whinny) | Peet J van Eeden (extracted by AntumDeluge) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| `racers/horn_moo.wav` | `moo-notification.wav` | [Sci-fi aliens and cows pack](https://opengameart.org/content/sci-fi-aliens-and-cows-pack) | qubodup | CC0 1.0 |
| `racers/horn_boing.wav` | `boing.ogg`, first 1.6 s | [Boing](https://opengameart.org/content/boing) | Aeva | CC0 1.0 |

Required attribution:

- "Zebra whinny" by Peet J van Eeden (extracted by AntumDeluge), https://opengameart.org/content/zebra-whinny, licensed under CC BY 3.0, converted and level-matched.
- (CC BY 4.0) "Crowd Cheering Sounds" by Gregor Quendel, https://opengameart.org/content/free-crowd-cheering-sounds, licensed under CC BY 4.0, cut and faded.
