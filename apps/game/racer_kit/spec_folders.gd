class_name SpecFolders
extends RefCounted
## Where the Racer Viewer and check tool look for RacerSpec files.
##   1. res://racer_kit/samples
##   2. the WS5 designer output: <repo>/packages/asset-pipeline/out (*.spec.json)
##   3. any extra folder from `-- --specs=<dir>` or the BEBBI_SPECS_DIR env var
##      (several folders can be separated with ',').

const SAMPLES := "res://racer_kit/samples"
const WS5_REL := "../../packages/asset-pipeline/out"


static func ws5_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join(WS5_REL).simplify_path()


static func dirs(user_args: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var out := PackedStringArray([SAMPLES, ws5_dir()])
	var extra := []
	for a in user_args:
		if a.begins_with("--specs="):
			extra.append(a.trim_prefix("--specs="))
	if OS.has_environment("BEBBI_SPECS_DIR"):
		extra.append(OS.get_environment("BEBBI_SPECS_DIR"))
	for e in extra:
		for d in str(e).split(",", false):
			var p := str(d).strip_edges()
			if p.is_relative_path():
				p = OS.get_environment("PWD").path_join(p).simplify_path()
			if p not in out:
				out.append(p)
	return out


## *.json files directly inside dir (sub-folders such as _meta are skipped), sorted.
static func list(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		if f.ends_with(".json") and not f.begins_with("."):
			out.append(dir.path_join(f))
	out.sort()
	return out


## File modification times, used by the viewer to notice changed or new specs.
static func stamp(files: PackedStringArray) -> Dictionary:
	var out := {}
	for f in files:
		out[f] = FileAccess.get_modified_time(f)
	return out


## The kid's vehicle drawing for a spec, if one can be found next to it:
## <stem>.vehicle.png|jpg, or (WS5 samples) ../samples/<pairNN>-vehicle-*.jpg|png.
static func drawing_for(spec_path: String) -> Texture2D:
	var dir := spec_path.get_base_dir()
	var stem := spec_path.get_file().trim_suffix(".json").trim_suffix(".spec")
	var tries := []
	for ext in ["png", "jpg", "jpeg", "webp"]:
		tries.append(dir.path_join("%s.vehicle.%s" % [stem, ext]))
	var prefix := stem.get_slice("-", 0)
	var sdir := dir.path_join("../samples").simplify_path()
	var da := DirAccess.open(sdir)
	if da:
		for f in da.get_files():
			if f.begins_with(prefix + "-vehicle"):
				tries.append(sdir.path_join(f))
	for t in tries:
		if FileAccess.file_exists(t):
			var img := Image.load_from_file(t)
			if img and not img.is_empty():
				return ImageTexture.create_from_image(img)
	return null
