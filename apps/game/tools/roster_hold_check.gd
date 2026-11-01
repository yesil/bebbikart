extends SceneTree
## A racer never changes in the middle of a run (net/roster_assets.gd): the designer's review
## rounds send better versions of a ready racer as new packages, and one that arrives while the
## racer's kart is on the track waits until the kart has left it. No server needed:
##   godot --headless --path apps/game --script res://tools/roster_hold_check.gd
## Exits 1 if the new package shows up mid-run, doesn't after it, or the next run would race
## without the ride drawing sticker.

const RosterAssets = preload("res://net/roster_assets.gd")

var problems: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


## A ready racer's roster entry with package `pkg`, already rendered (nothing to render here).
func _entry(pkg: String, title: String, status := "ready", nick := "Ava") -> Dictionary:
	return {
		"playerId": "ply_ava", "nickname": nick, "connected": true, "status": status,
		"assetBaseUrl": "http://localhost:1/assets/%s/" % pkg,
		"asset": {
			"packageId": pkg, "playerId": "ply_ava", "spec": {"title": title},
			"drawings": {"character": "", "vehicle": ""},
			"renders": {"hero": "/h.png"},
		},
	}


func _check(what: String, ok: bool) -> void:
	print("%s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		problems.append(what)


func _run() -> void:
	var assets = RosterAssets.new()
	assets.http_base = "http://localhost:1"
	root.add_child(assets)
	var racing := {"on": false}
	assets.is_racing = func(pid: String) -> bool: return racing["on"] and pid == "ply_ava"
	var ready_seen: Array = []
	assets.racer_ready.connect(func(pid: String): ready_seen.append(pid))
	var sticker := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGB8))

	assets.update([_entry("pkg_1", "First")])
	assets._drawings["pkg_1"] = sticker  # as if downloaded
	_check("a new racer is ready", ready_seen.size() == 1 and assets.spec_for("ply_ava").get("title") == "First")

	racing["on"] = true
	assets.update([_entry("pkg_2", "Better", "ready", "Ava B")])
	await process_frame
	_check("mid-run the racer stays as it started", assets.spec_for("ply_ava").get("title") == "First")
	_check("mid-run the rest of the entry is current (name)", assets.nickname("ply_ava") == "Ava B")
	_check("mid-run no new racer moment", ready_seen.size() == 1)
	assets.update([_entry("pkg_3", "Best", "ready", "Ava B")])  # another round, still racing
	await process_frame
	_check("a later round mid-run waits too", assets.spec_for("ply_ava").get("title") == "First")

	racing["on"] = false
	await process_frame
	await process_frame
	_check("after the run the latest version takes over", assets.spec_for("ply_ava").get("title") == "Best")
	_check("its sticker is there for the next run at once", assets.drawing_for("ply_ava") == sticker)
	_check("the switch is a racer moment (once)", ready_seen.size() == 2)

	# New drawings (the racer was being made again): no old sticker on the new look.
	assets.update([_entry("pkg_3", "Best", "processing")])
	assets.update([_entry("pkg_4", "Other", "ready")])
	_check("new drawings never borrow the old sticker", assets.drawing_for("ply_ava") == null)
	_check("between runs a new package applies at once", assets.spec_for("ply_ava").get("title") == "Other")

	assets.update([])
	_check("a racer who left is gone", assets.spec_for("ply_ava").is_empty())
	if problems.is_empty():
		print("ROSTER HOLD CHECK PASSED")
		quit(0)
	else:
		print("ROSTER HOLD CHECK FAILED (%d problems)" % problems.size())
		quit(1)
