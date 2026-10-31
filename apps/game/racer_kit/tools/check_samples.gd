extends SceneTree
## Headless smoke test: builds every sample spec (racer_kit/samples, data/pkg_default and the
## WS5 designer output folder), steps the animation through all states and moods, and prints
## validation errors. Exit code 1 if any spec is invalid or fails to build.
##
##   godot --headless --path apps/game --script res://racer_kit/tools/check_samples.gd [-- --specs=<dir>]


func _initialize() -> void:
	var files := PackedStringArray()
	for dir in SpecFolders.dirs(OS.get_cmdline_user_args()):
		files.append_array(SpecFolders.list(dir))
	files.append(KitCatalog.PKG_DEFAULT_PATH)
	var failed := 0
	var missing := KitCatalog.missing_parts()
	if not missing.is_empty():
		print("catalog: parts not implemented in Godot: ", ", ".join(missing))
		failed += 1
	for f in files:
		var raw := RacerSpec.load_file(f)
		if raw.is_empty():
			print("FAIL  %s: could not read spec" % f)
			failed += 1
			continue
		var racer := RacerBuilder.build(raw)
		if racer == null:
			print("FAIL  %s: invalid spec" % f.get_file())
			for err in RacerBuilder.last_errors:
				print("        - ", err)
			failed += 1
			continue
		root.add_child(racer)
		var meshes := _count(racer)
		var box := RacerBuilder._aabb(racer.model, racer.model.transform)
		racer.set_state({"speed": 14.0, "lean": 0.6, "boost": true})
		for i in 30:
			racer._process(1.0 / 30.0)
		racer.bump()
		racer.celebrate(2)
		racer.wave()
		racer.fail()
		racer.set_state({"airborne": true})
		for i in 60:
			racer._process(1.0 / 30.0)
		for m in KitCatalog.MOODS:
			racer.set_mood(m)
			racer._process(0.05)
		racer.snap_pose()
		var ok := meshes > 10 and box.size.y > 0.5 and box.size.y < 4.0 and box.position.y > -0.01 and box.position.y < 0.5
		print("%s  %-46s %-10s %3d meshes  %.2fm tall  min y %.2f" % [
			"ok  " if ok else "FAIL", f.get_file(), racer.spec.ride.base, meshes, box.size.y, box.position.y])
		if not ok:
			failed += 1
		racer.free()
	print("%d specs, %d failed" % [files.size(), failed])
	quit(1 if failed > 0 else 0)


func _count(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for k in n.get_children():
		c += _count(k)
	return c
