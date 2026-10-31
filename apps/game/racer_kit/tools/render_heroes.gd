extends SceneTree
## Renders the hero PNG of every *.spec.json in a folder (needs a window, not --headless):
##   godot --path apps/game --script res://racer_kit/tools/render_heroes.gd -- <specsDir> <outDir>
## Writes <outDir>/<name>.png. Exits 1 if any spec fails to build or render.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: render_heroes.gd -- <specsDir> <outDir>")
		quit(2)
		return
	var src: String = args[0]
	var dst: String = args[1]
	DirAccess.make_dir_recursive_absolute(dst)
	var r := AvatarRenderer.new()
	root.add_child(r)
	await process_frame
	var failed := 0
	var files := DirAccess.get_files_at(src)
	files.sort()
	for f in files:
		if not f.ends_with(".spec.json"):
			continue
		var path := src.path_join(f)
		var name := f.trim_suffix(".spec.json")
		var png: String = await r.render_hero(RacerSpec.load_file(path), dst.path_join(name + ".png"), SpecFolders.drawing_for(path))
		if png == "":
			push_error("render_heroes: %s failed: %s" % [name, ", ".join(RacerBuilder.last_errors)])
			failed += 1
		else:
			print(name, ": ", png)
	quit(1 if failed else 0)
