extends SceneTree
## Race-camera screenshots for look comparisons (windowed, not headless):
##   godot --path apps/game --resolution 1920x1080 --script res://tools/race_cam_shots.gd -- --track=village --racers=1 --seed=3 --weather=calm --duration=62 --shots=DIR --shot-every=3 --mute
## The real game (main.tscn reads every option after --, e.g. --shots), in a window that stays on
## top, so the Mac keeps drawing it under other windows, and never takes keyboard focus, so it
## doesn't catch keys meant for other apps while it runs.

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("race_cam_shots: needs a window (run without --headless)")
		quit(1)
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	if not "--shots" in " ".join(OS.get_cmdline_user_args()):
		push_error("race_cam_shots: --shots=DIR is required")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	get_root().add_child((load("res://main.tscn") as PackedScene).instantiate())
