extends GutTest

# Issue #152: the standing buildings (existing_cells) of the riverside strip are read from the grey fill of the
# buildings on the NLS sheets (OS London 1:1056, 1862-74). The decision of Cristian of 2026-10-18 keeps water out of
# the digitizer: it comes from OpenHistoricalMap.

const PAPER: Color = Color(0.92, 0.9, 0.83)
const DARK_PAPER: Color = Color(0.8, 0.76, 0.67)
const BUILDING: Color = Color(0.78, 0.77, 0.72)
const DARK_BUILDING: Color = Color(0.66, 0.64, 0.58)
# The synthetic sheet: 2 px per metre, north up, two cells of margin around the grid.
const PIXELS_PER_METRE: float = 2.0
const MARGIN_CELLS: float = 2.0

var _grid: Dictionary
var _settings: Dictionary


func before_each() -> void:
	# A 4×1 grid of 50 m cells around Wapping, sampled 2×2 per cell.
	_grid = {"width": 4, "height": 1, "origin": [534400, 180300], "cell_metres": 50, "samples_per_axis": 2}
	_settings = {"probes_per_axis": 4, "paper_window_metres": 100, "paper_percentile": 0.95, "ink_contrast": 0.06,
		"building_min_fraction": 0.5}


# One sheet that covers the grid with a margin, filled with `paper` and with `paint` (Rect2 in grid cells → colour).
func _sheets(paper: Color, paint: Dictionary = {}) -> NlsSheets:
	var size: Vector2i = Vector2i(_pixel_of(Vector2(_grid["width"], _grid["height"]) + Vector2.ONE * MARGIN_CELLS))
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(paper)
	for area: Rect2 in paint:
		var corner: Vector2 = _pixel_of(area.position)
		image.fill_rect(Rect2i(Vector2i(corner), Vector2i(_pixel_of(area.end) - corner)), paint[area])
	var points: Array[PackedFloat64Array] = [NlsSheets.grid_bng(_grid, Vector2.ZERO),
		NlsSheets.grid_bng(_grid, Vector2(_grid["width"], _grid["height"]))]
	var pixels: Array[PackedFloat64Array] = []
	for corner: Vector2 in [_pixel_of(Vector2.ZERO), _pixel_of(Vector2(_grid["width"], _grid["height"]))]:
		pixels.append(PackedFloat64Array([corner.x, corner.y]))
	var sheets: NlsSheets = NlsSheets.new()
	sheets.add_sheet("A", image, SheetGeoreference.fit(pixels, points), Rect2(Vector2.ZERO, Vector2(size)))
	return sheets


func _pixel_of(cell: Vector2) -> Vector2:
	return (cell + Vector2.ONE * MARGIN_CELLS) * float(_grid["cell_metres"]) * PIXELS_PER_METRE


func _existing(sheets: NlsSheets) -> Array[Vector2i]:
	var digitizer: NlsDigitizer = NlsDigitizer.new()
	var layer: Dictionary = digitizer.buildings(sheets, _grid, _settings)
	assert_eq(digitizer.errors, [] as Array[String])
	var importer: MapImporter = MapImporter.new()
	var config: Dictionary = _grid.duplicate()
	config["id"] = "fixture"
	config["priority"] = ["river", "dock", "marsh", "existing", "land"]
	var map: Dictionary = importer.import_documents(config, {"existing": layer}, {})
	assert_eq(importer.errors, [] as Array[String])
	var cells: Array[Vector2i] = []
	for cell: Array in map.get("existing_cells", []):
		cells.append(Vector2i(cell[0], cell[1]))
	return cells


func test_grey_fill_is_a_standing_building_and_paper_is_not() -> void:
	var sheets: NlsSheets = _sheets(PAPER, {Rect2(1, 0, 1, 1): BUILDING, Rect2(3, 0, 0.1, 1): BUILDING})
	assert_eq(_existing(sheets), [Vector2i(1, 0)] as Array[Vector2i], "A sliver of building is not the cell")


# The sheets do not share a paper tone: VII.78 is darker than VII.87, about as dark as a building on VII.87.
func test_buildings_are_read_against_the_paper_around_them() -> void:
	var sheets: NlsSheets = _sheets(DARK_PAPER, {Rect2(2, 0, 1, 1): DARK_BUILDING})
	assert_eq(_existing(sheets), [Vector2i(2, 0)] as Array[Vector2i])


# Option A of Cristian (2026-10-18): where the 1862-74 series has no sheet, the blocks stay free land.
func test_without_a_sheet_there_is_no_building() -> void:
	var sheets: NlsSheets = _sheets(PAPER, {Rect2(0, 0, 2, 1): Color(0, 0, 0, 0), Rect2(3, 0, 1, 1): BUILDING})
	assert_eq(_existing(sheets), [Vector2i(3, 0)] as Array[Vector2i])


func test_the_same_sheet_always_gives_the_same_text() -> void:
	var sheets: NlsSheets = _sheets(PAPER, {Rect2(1, 0, 2, 1): BUILDING})
	var digitizer: NlsDigitizer = NlsDigitizer.new()
	var first: String = digitizer.to_text(digitizer.buildings(sheets, _grid, _settings))
	var second: String = digitizer.to_text(digitizer.buildings(sheets, _grid, _settings))
	assert_eq(first, second)
	var parsed: Variant = JSON.parse_string(first)
	assert_true(parsed is Dictionary and parsed["type"] == "FeatureCollection")


func test_missing_settings_are_reported() -> void:
	_settings.erase("ink_contrast")
	var digitizer: NlsDigitizer = NlsDigitizer.new()
	digitizer.buildings(_sheets(PAPER), _grid, _settings)
	assert_string_contains("\n".join(digitizer.errors), "ink_contrast")
