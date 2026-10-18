class_name NlsMosaic
extends RefCounted

# The Web Mercator tiles of an NLS georeferenced layer, kept in data/maps/sources/<id>/ as <zoom>_<x>_<y>.png
# (issue #152). A pixel outside every tile, or a transparent one (no sheet of the series there), has no data.

const TILE_PIXELS: int = 256
const NO_DATA: float = -1.0
const OPAQUE: float = 0.5

var zoom: int
var _tiles: Dictionary[Vector2i, Image]


func _init(tile_zoom: int, tiles: Dictionary[Vector2i, Image]) -> void:
	zoom = tile_zoom
	_tiles = tiles
	for tile: Vector2i in _tiles:
		_tiles[tile].convert(Image.FORMAT_RGBA8)


static func load_folder(folder: String, tile_zoom: int) -> NlsMosaic:
	var tiles: Dictionary[Vector2i, Image] = {}
	var prefix: String = "%d_" % tile_zoom
	for file: String in DirAccess.get_files_at(folder):
		var parts: PackedStringArray = file.get_basename().split("_")
		if file.get_extension() != "png" or not file.begins_with(prefix) or parts.size() != 3:
			continue
		var image: Image = Image.load_from_file(ProjectSettings.globalize_path(folder.path_join(file)))
		if image != null:
			tiles[Vector2i(int(parts[1]), int(parts[2]))] = image
	return NlsMosaic.new(tile_zoom, tiles)


func is_empty() -> bool:
	return _tiles.is_empty()


# Luminance (0 black, 1 white) of the global pixel, or NO_DATA.
func luminance_at(pixel: PackedFloat64Array) -> float:
	var color: Color = color_at(pixel)
	return color.get_luminance() if color.a >= OPAQUE else NO_DATA


func color_at(pixel: PackedFloat64Array) -> Color:
	var x: int = floori(pixel[0])
	var y: int = floori(pixel[1])
	var tile: Vector2i = Vector2i(floori(float(x) / TILE_PIXELS), floori(float(y) / TILE_PIXELS))
	if not _tiles.has(tile):
		return Color(0, 0, 0, 0)
	return _tiles[tile].get_pixel(x - tile.x * TILE_PIXELS, y - tile.y * TILE_PIXELS)
