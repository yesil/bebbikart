# Racer kit (WS3d)

Builds toy racers from a `RacerSpec` (contracts §5). Everything is procedural (primitives and generated meshes, one shared toon material); no external assets.

## API

```gdscript
var racer: ToyRacer = RacerBuilder.build(spec_dict, drawing_texture_or_null)
add_child(racer)
racer.set_state({"speed": 9.0, "lean": -0.4, "airborne": false, "boost": false})  # every frame
racer.bump(); racer.land(); racer.fail(); racer.celebrate(3); racer.wave(); racer.reset_anim()
racer.set_mood("dizzy")      # lock a Mood; set_auto_mood() lets state pick it
racer.set_name_tag("Mila"); racer.show_name_tag(true)
racer.warnings               # fixes applied while normalising the spec
```

Auto mood: fail → dizzy, celebrate → cheering, bump → sad (0.8 s), boost/airborne → excited, speed > 12 → determined, else happy.
The racer's origin is on the ground, facing -Z. Sockets are `Marker3D` nodes named `Socket_<name>`.

Units for extras (not set by the contract): character extras 1.0 = 0.5 m, ride extras 1.0 = 1 m; offsets are metres in the socket's space. `ride_side` is the racer's left; `mirror` copies to the other side.

## Avatar renders

`AvatarRenderer` (a Node) renders `hero` (1024) and `avatar_happy/excited/sad` (512) to `user://renders/<playerId>/`. `upload()` PUTs to `/api/game/renders/:playerId/:key` when `base_url` is set; otherwise it is a logging stub. It needs a real display (not headless).

```
godot --path apps/game --script res://racer_kit/tools/render_avatars.gd -- <spec.json> [playerId]
```

## Racer Viewer

```
godot --path apps/game res://racer_viewer/racer_viewer.tscn [-- --specs=<dir>[,<dir>]]
```

It watches `res://racer_kit/samples`, `<repo>/packages/asset-pipeline/out` (WS5 output), `--specs=` and `BEBBI_SPECS_DIR`. It reloads within 1 s and jumps to new files. A matching drawing (`<stem>.vehicle.png`, or `samples/<prefix>-vehicle-*`) becomes the ride sticker.

Keys: ←/→ racer, A auto-demo, Space next action, 1–6 mood (0 auto), T turntable, N name tag, G lineup, R render avatars.

## Checks

```
godot --headless --path apps/game --script res://racer_kit/tools/check_samples.gd [-- --specs=<dir>]
```

This builds every spec, steps the animations and moods, checks size and grounding, and reports catalog parts with no Godot builder.
