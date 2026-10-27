class_name RegionMap
extends RefCounted
## Farming-landscape regions (data/heightmap/region_types.png, baked by tools/bake_regions.py from
## data/regions_1940.json): R = bocage, G = open field / downland, B = polder / fen, A = Weald.
##
## The terrain shader samples the same image (TerrainChunkManager passes it as region_tex over map_rect) to change the
## field patchwork; Scatter.field_edge() samples it here so the hedge meshes keep sitting on the painted field
## boundaries. Both use bilinear filtering on texel centres and the same 0.5 thresholds (see type_weights()).
##
## Thread-safe after load(): the pixel bytes are only read.

const PNG := "res://data/heightmap/region_types.png"

static var _data: PackedByteArray = PackedByteArray()
static var _w: int = 0
static var _h: int = 0
static var _loaded: bool = false
static var _img: Image = null


static func load_map() -> void:
	if _loaded:
		return
	_loaded = true
	# load the imported texture, not the raw PNG: Image.load() on an imported resource warns (and fails in
	# an exported build, where the source PNG is not packed)
	var tex: Texture2D = load(PNG) as Texture2D
	if tex == null:
		push_warning("RegionMap: %s missing (run tools/bake_regions.py) - no regional field patterns" % PNG)
		return
	var img: Image = tex.get_image()
	if img == null:
		push_warning("RegionMap: %s has no readable image - no regional field patterns" % PNG)
		return
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_img = img
	_w = img.get_width()
	_h = img.get_height()
	_data = img.get_data()


static func ready() -> bool:
	return _w > 0


static func image() -> Image:
	load_map()
	return _img


## Bilinear RGBA 0..1 at a world XZ point (texel centres, clamped), as the GPU's linear filter does.
static func sample(x: float, z: float) -> Color:
	if _w == 0:
		return Color(0, 0, 0, 0)
	var b: Rect2 = WorldCoords.world_bounds()
	var u: float = clampf((x - b.position.x) / b.size.x, 0.0, 1.0) * float(_w) - 0.5
	var v: float = clampf((z - b.position.y) / b.size.y, 0.0, 1.0) * float(_h) - 0.5
	var i0: int = clampi(floori(u), 0, _w - 1)
	var j0: int = clampi(floori(v), 0, _h - 1)
	var i1: int = mini(i0 + 1, _w - 1)
	var j1: int = mini(j0 + 1, _h - 1)
	var fx: float = clampf(u - floorf(u), 0.0, 1.0)
	var fy: float = clampf(v - floorf(v), 0.0, 1.0)
	var out := Color(0, 0, 0, 0)
	for c in 4:
		var a: float = lerpf(float(_data[(j0 * _w + i0) * 4 + c]), float(_data[(j0 * _w + i1) * 4 + c]), fx)
		var bb: float = lerpf(float(_data[(j1 * _w + i0) * 4 + c]), float(_data[(j1 * _w + i1) * 4 + c]), fx)
		out[c] = lerpf(a, bb, fy) / 255.0
	return out


## Hard region flags [bocage, open, polder, weald] (each 0/1, mutually exclusive in that priority order) - the same
## step(0.5) logic as terrain.gdshader.
static func type_weights(x: float, z: float) -> Vector4:
	var c: Color = sample(x, z)
	var boc: float = 1.0 if c.r >= 0.5 else 0.0
	var opn: float = (1.0 if c.g >= 0.5 else 0.0) * (1.0 - boc)
	var pol: float = (1.0 if c.b >= 0.5 else 0.0) * (1.0 - boc) * (1.0 - opn)
	var wld: float = (1.0 if c.a >= 0.5 else 0.0) * (1.0 - boc) * (1.0 - opn) * (1.0 - pol)
	return Vector4(boc, opn, pol, wld)
