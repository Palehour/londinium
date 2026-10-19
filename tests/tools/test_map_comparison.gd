extends GutTest

# Issue #170: the comparison image Cristian validates the map with. The sheets on the left, the cells of the map
# over them on the right, and the corner with no 1862-74 sheet (option A) hatched in both halves.

const PAPER: Color = Color(0.92, 0.9, 0.83)
const TOLERANCE: float = 0.02

var _grid: Dictionary = {"width": 3, "height": 2, "origin": [534600, 180300], "cell_metres": 50,
	"samples_per_axis": 2}


# One sheet at 1 px per metre over the two right columns; the left column has no sheet.
func _sheets() -> NlsSheets:
	var image: Image = Image.create(100, 100, false, Image.FORMAT_RGB8)
	image.fill(PAPER)
	var points: Array[PackedFloat64Array] = [PackedFloat64Array([534650.0, 180300.0]),
		PackedFloat64Array([534750.0, 180200.0])]
	var pixels: Array[PackedFloat64Array] = [PackedFloat64Array([0.0, 0.0]), PackedFloat64Array([100.0, 100.0])]
	var sheets: NlsSheets = NlsSheets.new()
	sheets.add_sheet("A", image, SheetGeoreference.fit(pixels, points), Rect2(0, 0, 100, 100))
	return sheets


# Colours come back from an 8-bit image, so they are compared to the nearest step.
func _assert_color(image: Image, at: Vector2i, expected: Color, message: String = "") -> void:
	var color: Color = image.get_pixelv(at)
	assert_true(Vector3(color.r - expected.r, color.g - expected.g, color.b - expected.b).length() < TOLERANCE,
		"%s: %s, expected %s" % [message, color, expected])


func _render() -> Image:
	var map: Dictionary = {"river_cells": [[2, 1]], "road_cells": [], "anchors": [{"name": "Church", "cell": [1, 0]}]}
	return MapComparison.new().render(_sheets(), _grid, map, Rect2i(0, 0, 1, 1), {"Church": Vector2(1.5, 0.5)})


func test_both_halves_show_the_whole_grid() -> void:
	var cell: int = MapComparison.PIXELS_PER_CELL
	assert_eq(_render().get_size(), Vector2i(3 * cell * 2 + MapComparison.GAP, 2 * cell))


func test_no_sheet_is_magenta_and_the_corner_without_one_is_marked() -> void:
	var image: Image = _render()
	var cell: int = MapComparison.PIXELS_PER_CELL
	var right: int = 3 * cell + MapComparison.GAP
	_assert_color(image, Vector2i(cell / 2 + 3, cell + cell / 2), MapComparison.NO_SHEET, "Left column, second row")
	for offset: int in [0, right]:
		_assert_color(image, Vector2i(offset + 1, 1), MapComparison.CORNER_COLOR, "The corner's border, x %d" % offset)
		_assert_color(image, Vector2i(offset + cell / 2, cell / 2), MapComparison.CORNER_COLOR, "Its hatch, x %d" % offset)


func test_the_sheet_is_tinted_with_the_map_and_anchors_are_outlined() -> void:
	var image: Image = _render()
	var cell: int = MapComparison.PIXELS_PER_CELL
	var right: int = 3 * cell + MapComparison.GAP
	var sheet: Color = image.get_pixel(2 * cell + cell / 2 + 3, cell + cell / 2 + 3)
	var tinted: Color = image.get_pixel(right + 2 * cell + cell / 2 + 3, cell + cell / 2 + 3)
	assert_almost_eq(sheet.r, PAPER.r, TOLERANCE)
	assert_almost_eq(tinted.b, PAPER.lerp(MapComparison.LAYER_COLORS["river_cells"], MapComparison.TINT).b, TOLERANCE)
	_assert_color(image, Vector2i(right + cell + 1, cell / 2), MapComparison.ANCHOR_COLOR, "Anchor outline")
	_assert_color(image, Vector2i(cell + cell / 2, cell / 2), MapComparison.PLACE_COLOR, "Where the sheet puts the church")
