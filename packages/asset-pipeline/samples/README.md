# Sample drawings

Raw test input for the Racer designer (WS5). There are 20 images: 15 hand-made kid-style drawings,
3 real historical children's drawings, and 2 real photos. Every file is either openly licensed or
made by this project.

We have no real BebbiKart kid drawings yet. Swap these out as soon as real ones arrive (with
parental consent; see the privacy notes in `docs/workstreams/asset-pipeline.md`).

## Generated drawings (made by this project, CC0 1.0)

`scripts/make-samples.js` draws these with seeded random "kid" strokes: wobbly crayon or marker
lines, loops that overshoot their start, scribble fills that go over the lines, and a lumpy paper
texture. It then "photographs" each sheet: slightly rotated, on a table, with a shadow. Run
`bun run samples` to regenerate them. The output is deterministic.

| File                                | Shows                                                                          | Expected outcome                                    |
| ----------------------------------- | ------------------------------------------------------------------------------ | --------------------------------------------------- |
| `pair01-character-cat.jpg`          | purple cat with pink ears, whiskers, orange collar                             | character, ok                                       |
| `pair01-vehicle-kart.jpg`           | red kart, flames out the back, number 1, sun                                   | ride `kart`                                         |
| `pair02-character-robot.jpg`        | boxy blue/grey robot, antenna, green eyes, buttons                             | character, ok                                       |
| `pair02-vehicle-rocket-shoe.jpg`    | green sneaker with rocket flames and fins                                      | ride `rocket` (non-kart)                            |
| `pair03-character-dino.jpg`         | green three-horned dino, red back spikes, blue spots                           | character, ok                                       |
| `pair03-vehicle-bike.jpg`           | yellow bike with a flower basket                                               | ride `bike`                                         |
| `pair04-character-girl-crown.jpg`   | girl with orange hair, gold crown, pink dress                                  | character, ok                                       |
| `pair04-vehicle-horse.jpg`          | brown horse with rainbow mane, blue saddle                                     | ride `animal4` (non-kart)                           |
| `pair05-character-alien.jpg`        | one-eyed lime alien, antennae, toothy grin                                     | character, ok                                       |
| `pair05-vehicle-dragon.jpg`         | red dragon with orange wings, yellow spikes                                    | ride `bird` (flying)                                |
| `pair06-character-blob-monster.jpg` | blue blob monster, big eyes, one tooth, stars                                  | character, ok                                       |
| `pair06-vehicle-boat.jpg`           | brown sailboat, portholes, waves, sun                                          | ride `boat`                                         |
| `tricky-scribble.jpg`               | random multicolour scribble                                                    | reject `unreadable`, or a playful blob (borderline) |
| `tricky-blank-page.jpg`             | empty sheet with one stray pencil tick                                         | reject `empty_page`                                 |
| `tricky-both-on-one-page.jpg`       | kid on a skateboard, both on one sheet; upload it as character **and** vehicle | character + ride `board`                            |

## Real children's drawings (public domain)

These come from Wikimedia Commons. All are pre-1900 and in the public domain worldwide (author
died more than 100 years ago). They are real, sparse 19th-century pencil sketches, which is a good
test of "is this readable?".

| File                                 | Shows                                                                                                        | Expected outcome                                                   | Source                                                                                     | Licence       |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ | ------------- |
| `pd-franzjoseph-1842-horse-race.jpg` | pencil horse race drawn by Franz Joseph of Austria (1830–1916) at about age 11, "Wettrennen am 29. May 1842" | ride `animal4` (horse)                                             | <https://commons.wikimedia.org/wiki/File:Franz_Joseph_Kinderzeichnung_Wettrennen_1842.jpg> | Public domain |
| `pd-rudolf-deer-eagle-face.jpg`      | red-pencil deer, eagle and a face by Crown Prince Rudolf (1858–1889) as a child                              | character (face) or ride `animal4`/`bird`; tests multiple subjects | <https://commons.wikimedia.org/wiki/File:Kronprinz_Rudolf_Kinderzeichnung_r.jpg>           | Public domain |
| `pd-rudolf-chamois.jpg`              | chamois (mountain goat), same artist                                                                         | ride `animal4`                                                     | <https://commons.wikimedia.org/wiki/File:Kronprinz_Rudolf_Kinderzeichnung_v.jpg>           | Public domain |

## Real photos (tricky cases, CC0)

| File                           | Shows                                            | Expected outcome                          | Source                                                                                                                       | Licence |
| ------------------------------ | ------------------------------------------------ | ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------- |
| `tricky-photo-gokart.jpg`      | photo of a real go-kart on a track               | reject `not_a_drawing`                    | Goh Rhy Yan (gryshoots) via Unsplash, 2017. <https://commons.wikimedia.org/wiki/File:Go-kart_on_a_race_track_(Unsplash).jpg> | CC0 1.0 |
| `tricky-photo-boy-toy-car.jpg` | old photo of a boy in a toy car (Van Wert, 1917) | reject `real_person` (or `not_a_drawing`) | Uploaded by Cbaile19. <https://commons.wikimedia.org/wiki/File:Boy_with_toy_car,_Van_Wert,_1917.jpg>                         | CC0 1.0 |

## Mock specs

`src/mock.js` holds a hand-written spec or rejection for each sample pair, so
`bun run design --mock` produces output without a DeepSeek key.
