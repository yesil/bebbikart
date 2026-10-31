# Asset credits

Every third-party asset in this folder is CC0 1.0 (public domain). Sizes were reduced for the repo: textures are at most 1K and HDRIs 2K.

| Path | Source | Author | Licence |
|---|---|---|---|
| `nature/quaternius/` (trees, pines, twisted trees, bushes, ferns, flowers, grass, clover, plants, rocks, pebbles, mushroom + their textures) | [Stylized Nature MegaKit (Standard)](https://quaternius.itch.io/stylized-nature-megakit) | Quaternius | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (see `nature/quaternius/LICENSE_Quaternius.txt`) |
| `village/kenney_fantasy_town/` (walls, roofs, balconies, chimneys, fountain, fences, lanterns, benches, stalls, banners, water wheel, cart; GLB + colour map) | [Fantasy Town Kit 2.0](https://kenney.nl/assets/fantasy-town-kit) (mirror: [OpenGameArt](https://opengameart.org/content/fantasy-town-kit)) | Kenney | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (see `village/kenney_fantasy_town/License_Kenney.txt`) |
| `textures/terrain/grass_*` | [Grass004](https://ambientcg.com/view?id=Grass004) | ambientCG | CC0 1.0 |
| `textures/terrain/grass_dirt_*` | [Ground037](https://ambientcg.com/view?id=Ground037) | ambientCG | CC0 1.0 |
| `textures/terrain/dirt_*` | [Ground054](https://ambientcg.com/view?id=Ground054) | ambientCG | CC0 1.0 |
| `textures/terrain/gravel_*` | [Gravel022](https://ambientcg.com/view?id=Gravel022) | ambientCG | CC0 1.0 |
| `textures/terrain/mud_*` | [Ground048](https://ambientcg.com/view?id=Ground048) | ambientCG | CC0 1.0 |
| `textures/terrain/rock_*` | [Rock030](https://ambientcg.com/view?id=Rock030) | ambientCG | CC0 1.0 |
| `textures/Asphalt012/` | [Asphalt012](https://ambientcg.com/view?id=Asphalt012) | ambientCG | CC0 1.0 |
| `textures/Planks037A/` | [Planks037A](https://ambientcg.com/view?id=Planks037A) | ambientCG | CC0 1.0 |
| `textures/Planks021/` | [Planks021](https://ambientcg.com/view?id=Planks021) | ambientCG | CC0 1.0 |
| `textures/Bricks076C/` | [Bricks076C](https://ambientcg.com/view?id=Bricks076C) | ambientCG | CC0 1.0 |
| `sky/kloofendal_48d_partly_cloudy_puresky_2k.hdr` | [Kloofendal 48d Partly Cloudy (Pure Sky)](https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky) | Greg Zaal, Jarod Guest (Poly Haven) | CC0 1.0 |

The village (`../world/village/`) recolours the Kenney colour map to a Swiss palette at bake time (`world/village/village_kit.gd`, saved as `world/village/materials/kenney_swiss_colormap.res`); the original files are unchanged. Its snow layer reuses the gravel textures, brightened.

The terrain textures are channel-packed for Terrain3D by `tools/pack_textures.gd`: `*_albedo_height.webp` holds albedo in RGB and height in A, and `*_normal_rough.webp` holds the OpenGL normal in RGB and roughness in A.

Editor and runtime add-ons live in `../addons/` and keep their own licence files: Terrain3D (MIT), Godot Road Generator (MIT) and ProtonScatter (MIT).
