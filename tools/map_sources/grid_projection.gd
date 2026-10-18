class_name GridProjection
extends RefCounted

# Points of a map grid (x east, y south, in cells from the north-west corner of import.json) to global pixels of a
# Web Mercator tile pyramid (issue #152). Every cell corner is projected exactly (OsgbProjection) and points inside a
# cell are interpolated between its corners: across 50 m the projection is linear to well under a pixel.

# Cells of the lattice past each edge of the grid, so a window around an edge cell still has corners.
const MARGIN: int = 2

# Global tile pixel of every cell corner from -MARGIN to size + MARGIN.
var _lattice: Dictionary[Vector2i, PackedFloat64Array] = {}


func _init(grid: Dictionary, zoom: int) -> void:
	var cell: float = float(grid["cell_metres"])
	for y: int in range(-MARGIN, int(grid["height"]) + MARGIN + 1):
		for x: int in range(-MARGIN, int(grid["width"]) + MARGIN + 1):
			var en: PackedFloat64Array = PackedFloat64Array([float(grid["origin"][0]) + x * cell,
				float(grid["origin"][1]) - y * cell])
			_lattice[Vector2i(x, y)] = OsgbProjection.wgs84_to_tile_pixel(OsgbProjection.bng_to_wgs84(en), zoom)


func pixel(point: Vector2) -> PackedFloat64Array:
	var cell: Vector2i = Vector2i(floori(point.x), floori(point.y))
	var f: Vector2 = point - Vector2(cell)
	var a: PackedFloat64Array = _lattice[cell]
	var b: PackedFloat64Array = _lattice[cell + Vector2i.RIGHT]
	var c: PackedFloat64Array = _lattice[cell + Vector2i.DOWN]
	var d: PackedFloat64Array = _lattice[cell + Vector2i.ONE]
	return PackedFloat64Array([lerpf(lerpf(a[0], b[0], f.x), lerpf(c[0], d[0], f.x), f.y),
		lerpf(lerpf(a[1], b[1], f.x), lerpf(c[1], d[1], f.x), f.y)])
