class_name MapComparison
extends RefCounted

# The image Cristian validates the traced map with (issue #152): on the left the NLS sheet resampled onto the grid
# with the cell lines, on the right the same sheet tinted with what each cell became in data/maps/<id>.json.
# Magenta is where the 1862-74 series has no sheet.

const PIXELS_PER_CELL: int = 64
const GAP: int = 16
const GRID_LINE: Color = Color(0.55, 0.1, 0.1)
const NO_SHEET: Color = Color.MAGENTA
const TINT: float = 0.45
# Cell layers of the map JSON and their tint, painted in this order.
const LAYER_COLORS: Dictionary[String, Color] = {"existing_cells": Color(0.85, 0.2, 0.15),
	"dock_cells": Color(0.1, 0.6, 0.6), "river_cells": Color(0.15, 0.35, 0.85)}
const ROAD_COLOR: Color = Color(0.95, 0.6, 0.0)
# A road is drawn as a square in the middle third of its cell, so the class under it still shows.
const ROAD_INSET: int = PIXELS_PER_CELL / 3


func render(mosaic: NlsMosaic, grid: Dictionary, map: Dictionary) -> Image:
	var size: Vector2i = Vector2i(int(grid["width"]), int(grid["height"])) * PIXELS_PER_CELL
	var image: Image = Image.create(size.x * 2 + GAP, size.y, false, Image.FORMAT_RGB8)
	image.fill(Color.WHITE)
	var projection: GridProjection = GridProjection.new(grid, mosaic.zoom)
	var tints: Dictionary[Vector2i, Color] = {}
	for layer: String in LAYER_COLORS:
		for cell: Array in map.get(layer, []):
			tints[Vector2i(cell[0], cell[1])] = LAYER_COLORS[layer]
	for y: int in range(size.y):
		for x: int in range(size.x):
			var point: Vector2 = Vector2(x + 0.5, y + 0.5) / PIXELS_PER_CELL
			var color: Color = mosaic.color_at(projection.pixel(point))
			color = color if color.a >= NlsMosaic.OPAQUE else NO_SHEET
			image.set_pixel(x, y, color)
			var cell: Vector2i = Vector2i(x / PIXELS_PER_CELL, y / PIXELS_PER_CELL)
			image.set_pixel(size.x + GAP + x, y, color.lerp(tints[cell], TINT) if tints.has(cell) else color)
	for cell: Array in map.get("road_cells", []):
		var corner: Vector2i = Vector2i(size.x + GAP, 0) + Vector2i(cell[0], cell[1]) * PIXELS_PER_CELL
		image.fill_rect(Rect2i(corner + Vector2i.ONE * ROAD_INSET, Vector2i.ONE * (PIXELS_PER_CELL - 2 * ROAD_INSET)),
			ROAD_COLOR)
	for offset: int in [0, size.x + GAP]:
		for line: int in range(0, size.x + 1, PIXELS_PER_CELL):
			image.fill_rect(Rect2i(offset + mini(line, size.x - 1), 0, 1, size.y), GRID_LINE)
		for line: int in range(0, size.y + 1, PIXELS_PER_CELL):
			image.fill_rect(Rect2i(offset, mini(line, size.y - 1), size.x, 1), GRID_LINE)
	return image
