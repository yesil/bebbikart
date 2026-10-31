extends SceneTree
## FPS benchmark of the real game: main.tscn with 20 mock racers, windowed 1920x1080, vsync off.
##   godot --path apps/game --resolution 1920x1080 --script res://tools/bench.gd -- [--seconds=30] [--cam=follow|wide|forks]
## Warms up for 3 s, then records every frame for --seconds and prints the average fps and the
## 1% low (fps at the 99th-percentile frame time). Exits 1 if the average is below 60.

var seconds := 30.0
var warmup := 3.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			seconds = float(a.get_slice("=", 1))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("bench: needs a window (run without --headless)")
		quit(1)
		return
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	var warm_until := Time.get_ticks_usec() + int(warmup * 1e6)
	while Time.get_ticks_usec() < warm_until:
		await process_frame
	var frames := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	var t0 := last
	while (Time.get_ticks_usec() - t0) / 1e6 < seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1e6)
		last = now
	var racing: int = main.get("sim").racers.size()
	frames.sort()
	var total := 0.0
	for f in frames:
		total += f
	var avg_fps := frames.size() / total
	var p99: float = frames[int(frames.size() * 0.99)]
	var size := get_root().get_visible_rect().size
	print("bench: %dx%d, %d frames over %.1f s, %d racers on track at the end" % [size.x, size.y, frames.size(), total, racing])
	print("bench: average %.1f fps, 1%% low %.1f fps (p99 frame %.1f ms), worst frame %.1f ms" % [
		avg_fps, 1.0 / p99, p99 * 1000.0, frames[frames.size() - 1] * 1000.0])
	quit(0 if avg_fps >= 60.0 else 1)
