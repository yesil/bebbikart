extends SceneTree
## Renders hero + avatar PNGs for a spec (needs a window, not --headless):
##   godot --path apps/game --script res://racer_kit/tools/render_avatars.gd -- <spec.json> [playerId]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://racer_kit/samples/bunny_bike.json"
	var pid: String = args[1] if args.size() > 1 else path.get_file().get_basename().get_basename()
	var r := AvatarRenderer.new()
	root.add_child(r)
	await process_frame
	var out := await r.render_all(RacerSpec.load_file(path), pid, SpecFolders.drawing_for(path))
	for k in out:
		print(k, ": ", out[k])
	await r.upload_all(pid, out)
	quit(0 if out.size() == 4 else 1)
