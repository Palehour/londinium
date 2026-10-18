extends GutTest

# Issue #152: the standing buildings (existing_cells) of the riverside strip are read from the grey fill of the
# buildings on the NLS sheets (OS London 1:1056, 1862-74). The decision of Cristian of 2026-10-18 keeps water out of
# the digitizer: it comes from OpenHistoricalMap.

const ZOOM: int = 17
const PAPER: Color = Color(0.92, 0.9, 0.83)
const DARK_PAPER: Color = Color(0.8, 0.76, 0.67)
const BUILDING: Color = Color(0.78, 0.77, 0.72)
const DARK_BUILDING: Color = Color(0.66, 0.64, 0.58)

var _grid: Dictionary
var _settings: Dictionary


func before_each() -> void:
	# A 4×1 grid of 50 m cells around Wapping, sampled 2×2 per cell.
	_grid = {"width": 4, "height": 1, "origin": [534400, 180300], "cell_metres": 50, "samples_per_axis": 2}
	_settings = {"zoom": ZOOM, "probes_per_axis": 4, "paper_window_metres": 100, "paper_percentile": 0.95,
		"ink_contrast": 0.06, "building_min_fraction": 0.5}


# A mosaic of the tiles that cover the grid with a margin, filled with `paper` and with `paint` (Rect2 in grid
# cells → colour) drawn through the same projection the digitizer uses.
func _mosaic(paper: Color, paint: Dictionary = {}) -> NlsMosaic:
	var corner: PackedFloat64Array = _pixel_of(Vector2(-2, -2))
	var far: PackedFloat64Array = _pixel_of(Vector2(_grid["width"] + 2, _grid["height"] + 2))
	var first: Vector2i = Vector2i(int(corner[0] / 256.0), int(corner[1] / 256.0))
	var last: Vector2i = Vector2i(int(far[0] / 256.0), int(far[1] / 256.0))
	var tiles: Dictionary[Vector2i, Image] = {}
	for x: int in range(first.x, last.x + 1):
		for y: int in range(first.y, last.y + 1):
			var image: Image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
			image.fill(paper)
			tiles[Vector2i(x, y)] = image
	for area: Rect2 in paint:
		var top_left: PackedFloat64Array = _pixel_of(area.position)
		var bottom_right: PackedFloat64Array = _pixel_of(area.end)
		for py: int in range(int(top_left[1]), int(bottom_right[1]) + 1):
			for px: int in range(int(top_left[0]), int(bottom_right[0]) + 1):
				var tile: Vector2i = Vector2i(px / 256, py / 256)
				if tiles.has(tile):
					tiles[tile].set_pixel(px % 256, py % 256, paint[area])
	return NlsMosaic.new(ZOOM, tiles)


func _pixel_of(cell: Vector2) -> PackedFloat64Array:
	var en: PackedFloat64Array = PackedFloat64Array([float(_grid["origin"][0]) + cell.x * float(_grid["cell_metres"]),
		float(_grid["origin"][1]) - cell.y * float(_grid["cell_metres"])])
	return OsgbProjection.wgs84_to_tile_pixel(OsgbProjection.bng_to_wgs84(en), ZOOM)


func _existing(mosaic: NlsMosaic) -> Array[Vector2i]:
	var digitizer: NlsDigitizer = NlsDigitizer.new()
	var layer: Dictionary = digitizer.buildings(mosaic, _grid, _settings)
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
	var mosaic: NlsMosaic = _mosaic(PAPER, {Rect2(1, 0, 1, 1): BUILDING, Rect2(3, 0, 0.2, 1): BUILDING})
	assert_eq(_existing(mosaic), [Vector2i(1, 0)] as Array[Vector2i], "A sliver of building is not the cell")


# The sheets do not share a paper tone: VII.78 is darker than VII.87, about as dark as a building on VII.87.
func test_buildings_are_read_against_the_paper_around_them() -> void:
	var mosaic: NlsMosaic = _mosaic(DARK_PAPER, {Rect2(2, 0, 1, 1): DARK_BUILDING})
	assert_eq(_existing(mosaic), [Vector2i(2, 0)] as Array[Vector2i])


# Option A of Cristian (2026-10-18): where the 1862-74 series has no sheet, the blocks stay free land.
func test_without_a_sheet_there_is_no_building() -> void:
	var mosaic: NlsMosaic = _mosaic(PAPER, {Rect2(0, 0, 2, 1): Color(0, 0, 0, 0), Rect2(3, 0, 1, 1): BUILDING})
	assert_eq(_existing(mosaic), [Vector2i(3, 0)] as Array[Vector2i])


func test_the_same_tiles_always_give_the_same_text() -> void:
	var mosaic: NlsMosaic = _mosaic(PAPER, {Rect2(1, 0, 2, 1): BUILDING})
	var digitizer: NlsDigitizer = NlsDigitizer.new()
	var first: String = digitizer.to_text(digitizer.buildings(mosaic, _grid, _settings))
	var second: String = digitizer.to_text(digitizer.buildings(mosaic, _grid, _settings))
	assert_eq(first, second)
	var parsed: Variant = JSON.parse_string(first)
	assert_true(parsed is Dictionary and parsed["type"] == "FeatureCollection")


func test_missing_settings_are_reported() -> void:
	_settings.erase("ink_contrast")
	var digitizer: NlsDigitizer = NlsDigitizer.new()
	digitizer.buildings(_mosaic(PAPER), _grid, _settings)
	assert_string_contains("\n".join(digitizer.errors), "ink_contrast")
