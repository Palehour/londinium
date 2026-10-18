class_name MapComparison
extends RefCounted

# The image Cristian validates the traced map with (issues #152 and #170). On the left, the georeferenced NLS sheets
# resampled onto the grid, with the cell lines and a dot where each named place sits on its sheet. On the right, the
# same sheets tinted with what each cell became in data/maps/<id>.json, with the streets as squares and the anchors
# outlined. Magenta is where no 1862-74 sheet reaches; the corner with no sheet (option A) is hatched in both halves.

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
const CORNER_COLOR: Color = Color(0.5, 0.0, 0.5)
const CORNER_BORDER: int = 4
const HATCH_STEP: int = 16
const ANCHOR_COLOR: Color = Color.BLACK
const ANCHOR_BORDER: int = 3
const PLACE_COLOR: Color = Color(0.0, 0.45, 0.1)
const PLACE_RADIUS: int = 5


# `corner` is the rectangle of cells with no sheet; `places` maps each named place to its grid point on the sheets.
func render(sheets: NlsSheets, grid: Dictionary, map: Dictionary, corner: Rect2i = Rect2i(),
		places: Dictionary[String, Vector2] = {}) -> Image:
	var size: Vector2i = Vector2i(int(grid["width"]), int(grid["height"])) * PIXELS_PER_CELL
	var right: int = size.x + GAP
	var image: Image = Image.create(size.x * 2 + GAP, size.y, false, Image.FORMAT_RGB8)
	image.fill(Color.WHITE)
	var tints: Dictionary[Vector2i, Color] = {}
	for layer: String in LAYER_COLORS:
		for cell: Array in map.get(layer, []):
			tints[Vector2i(cell[0], cell[1])] = LAYER_COLORS[layer]
	for y: int in range(size.y):
		for x: int in range(size.x):
			var point: Vector2 = Vector2(x + 0.5, y + 0.5) / PIXELS_PER_CELL
			var color: Color = sheets.color_at(NlsSheets.grid_bng(grid, point))
			color = Color(color, 1.0) if color.a >= NlsSheets.OPAQUE else NO_SHEET
			image.set_pixel(x, y, color)
			var cell: Vector2i = Vector2i(x / PIXELS_PER_CELL, y / PIXELS_PER_CELL)
			image.set_pixel(right + x, y, color.lerp(tints[cell], TINT) if tints.has(cell) else color)
	for cell: Array in map.get("road_cells", []):
		var at: Vector2i = Vector2i(right, 0) + Vector2i(cell[0], cell[1]) * PIXELS_PER_CELL
		image.fill_rect(Rect2i(at + Vector2i.ONE * ROAD_INSET, Vector2i.ONE * (PIXELS_PER_CELL - 2 * ROAD_INSET)),
			ROAD_COLOR)
	for offset: int in [0, right]:
		for line: int in range(0, size.x + 1, PIXELS_PER_CELL):
			image.fill_rect(Rect2i(offset + mini(line, size.x - 1), 0, 1, size.y), GRID_LINE)
		for line: int in range(0, size.y + 1, PIXELS_PER_CELL):
			image.fill_rect(Rect2i(offset, mini(line, size.y - 1), size.x, 1), GRID_LINE)
		if corner.has_area():
			_hatch(image, Rect2i(Vector2i(offset, 0) + corner.position * PIXELS_PER_CELL, corner.size * PIXELS_PER_CELL))
	for anchor: Variant in map.get("anchors", []):
		if anchor is Dictionary and anchor.get("cell") is Array:
			var at: Vector2i = Vector2i(right, 0) + Vector2i(anchor["cell"][0], anchor["cell"][1]) * PIXELS_PER_CELL
			_outline(image, Rect2i(at, Vector2i.ONE * PIXELS_PER_CELL), ANCHOR_BORDER, ANCHOR_COLOR)
	for place: String in places:
		_dot(image, Vector2i((places[place] * PIXELS_PER_CELL).round()))
	return image


# Diagonal lines every HATCH_STEP pixels and a border, so the corner reads as "no sheet" over whatever it shows.
func _hatch(image: Image, area: Rect2i) -> void:
	for start: int in range(-area.size.y, area.size.x, HATCH_STEP):
		for step: int in range(area.size.y):
			var x: int = start + step
			if x >= 0 and x < area.size.x:
				image.set_pixel(area.position.x + x, area.position.y + step, CORNER_COLOR)
	_outline(image, area, CORNER_BORDER, CORNER_COLOR)


func _outline(image: Image, area: Rect2i, width: int, color: Color) -> void:
	image.fill_rect(Rect2i(area.position, Vector2i(area.size.x, width)), color)
	image.fill_rect(Rect2i(area.position + Vector2i(0, area.size.y - width), Vector2i(area.size.x, width)), color)
	image.fill_rect(Rect2i(area.position, Vector2i(width, area.size.y)), color)
	image.fill_rect(Rect2i(area.position + Vector2i(area.size.x - width, 0), Vector2i(width, area.size.y)), color)


func _dot(image: Image, centre: Vector2i) -> void:
	for y: int in range(-PLACE_RADIUS, PLACE_RADIUS + 1):
		for x: int in range(-PLACE_RADIUS, PLACE_RADIUS + 1):
			var pixel: Vector2i = centre + Vector2i(x, y)
			if x * x + y * y <= PLACE_RADIUS * PLACE_RADIUS and Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel):
				image.set_pixelv(pixel, PLACE_COLOR)
