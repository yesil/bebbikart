extends SceneTree
## Writes the phone's track maps (tools/track_maps.gd) into packages/shared/src/track-maps:
##   godot --headless --path apps/game --script res://tools/export_track_maps.gd   (bun run maps:export)
## With `-- --check` it writes nothing and exits 1 if a map is missing or out of date.

const TrackMaps = preload("res://tools/track_maps.gd")


func _init() -> void:
	if "--check" in OS.get_cmdline_user_args():
		var problems := TrackMaps.stale()
		for p in problems:
			print("STALE TRACK MAP ", p)
		if problems.is_empty():
			print("TRACK MAPS CURRENT")
		else:
			print("Run: bun run maps:export")
		quit(1 if not problems.is_empty() else 0)
		return
	var cs := TrackMaps.courses()
	if cs.is_empty():
		quit(1)
		return
	for track in cs:
		var f := TrackMaps.path(track)
		var fa := FileAccess.open(f, FileAccess.WRITE)
		if fa == null:
			push_error("export_track_maps: can't write %s (%s)" % [f, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		var text := TrackMaps.map_json(track, cs[track])
		fa.store_string(text)
		fa.close()
		print("wrote %s (%d bytes)" % [f, text.length()])
	quit(0)
