extends SceneTree
## Packs ambientCG PBR sets into the channel layout Terrain3D expects (game.md "World pipeline"):
##   <name>_albedo_height.webp  RGB albedo + A height (from Displacement)
##   <name>_normal_rough.webp   RGB normal (OpenGL convention) + A roughness
## Uses only Image, so it runs without the project (no addons loaded):
##   godot --headless --script apps/game/tools/pack_textures.gd -- <ambientcg_dir> <out_dir> [size]
## <ambientcg_dir> holds one unzipped folder per set (e.g. Grass004/Grass004_1K-JPG_Color.jpg).

const LAYERS := {
	"grass": "Grass004",
	"grass_dirt": "Ground037",
	"dirt": "Ground054",
	"gravel": "Gravel022",
	"mud": "Ground048",
	"rock": "Rock030",
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: pack_textures.gd -- <ambientcg_dir> <out_dir> [size]")
		quit(1)
		return
	var src := args[0]
	var out := args[1]
	var size := int(args[2]) if args.size() > 2 else 1024
	DirAccess.make_dir_recursive_absolute(out)
	var failed := false
	for name in LAYERS:
		var id: String = LAYERS[name]
		var base := "%s/%s/%s_1K-JPG_" % [src, id, id]
		var color := _load(base + "Color.jpg", size)
		var disp := _load(base + "Displacement.jpg", size)
		var normal := _load(base + "NormalGL.jpg", size)
		var rough := _load(base + "Roughness.jpg", size)
		if color == null or disp == null or normal == null or rough == null:
			push_error("missing maps for %s (%s)" % [name, id])
			failed = true
			continue
		var ah := _pack(color, disp)
		var nr := _pack(normal, rough)
		ah.save_webp("%s/%s_albedo_height.webp" % [out, name], true, 0.9)
		nr.save_webp("%s/%s_normal_rough.webp" % [out, name], true, 0.92)
		print("packed %s <- %s" % [name, id])
	quit(1 if failed else 0)


func _load(path: String, size: int) -> Image:
	if not FileAccess.file_exists(path):
		push_error("not found: " + path)
		return null
	var img := Image.load_from_file(path)
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != size:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return img


## RGB from `rgb`, alpha from the red channel of `a`.
func _pack(rgb: Image, a: Image) -> Image:
	var out := Image.create(rgb.get_width(), rgb.get_height(), false, Image.FORMAT_RGBA8)
	for y in rgb.get_height():
		for x in rgb.get_width():
			var c := rgb.get_pixel(x, y)
			c.a = a.get_pixel(x, y).r
			out.set_pixel(x, y, c)
	return out
