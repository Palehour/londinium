extends GutTest

# Issue #170: the NLS sheets of a map, as sources.json lists them. Each sheet is fitted to British National Grid from
# OHM street corners (the node ids of the export) or from a neatline corner it shares with a sheet fitted before it.
# The tool reports every residual and reads each named place back onto the grid, so the anchors of the map can be
# checked against the sheets.

const FOLDER: String = "user://test_nls_sheets"
const PAPER: Color = Color(0.92, 0.9, 0.83)
const INK: Color = Color(0.3, 0.3, 0.3)
# Both synthetic sheets are 2 px per metre with north up; B is the sheet east of A.
const PIXELS_PER_METRE: float = 2.0
const SHEET_SIZE: Vector2i = Vector2i(220, 120)
const NEATLINE: Rect2i = Rect2i(10, 10, 200, 100)
const A_ORIGIN: PackedFloat64Array = [534600.0, 180300.0]
const TOLERANCE: float = 0.01

var _grid: Dictionary = {"width": 4, "height": 1, "origin": [534600, 180300], "cell_metres": 50,
	"samples_per_axis": 2}


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	for sheet: String in ["A", "B"]:
		var image: Image = Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGB8)
		image.fill(PAPER)
		image.fill_rect(Rect2i(30, 30, 10, 10), INK)
		image.save_png(FOLDER.path_join("%s.png" % sheet))


func after_all() -> void:
	for file: String in DirAccess.get_files_at(FOLDER):
		DirAccess.remove_absolute(FOLDER.path_join(file))
	DirAccess.remove_absolute(FOLDER)


# Sheet pixel of a grid point: A's neatline starts at A_ORIGIN; B's starts 100 m east of it.
func _pixel(en: Array, east_metres: float = 0.0) -> Array:
	return [NEATLINE.position.x + (en[0] - A_ORIGIN[0] - east_metres) * PIXELS_PER_METRE,
		NEATLINE.position.y + (A_ORIGIN[1] - en[1]) * PIXELS_PER_METRE]


func _nodes() -> Dictionary[int, PackedFloat64Array]:
	return {1: PackedFloat64Array([534610.0, 180290.0]), 2: PackedFloat64Array([534690.0, 180290.0]),
		3: PackedFloat64Array([534650.0, 180260.0]), 4: PackedFloat64Array([534780.0, 180270.0])}


func _nls() -> Dictionary:
	var nodes: Dictionary[int, PackedFloat64Array] = _nodes()
	var off: Array = _pixel(nodes[3])
	off[0] += 4.0
	return {"sheets": [
		{"sheet": "A", "image": "A.png", "image_origin": [0, 0], "image_scale": 1,
			"map_area": [NEATLINE.position.x, NEATLINE.position.y, NEATLINE.end.x, NEATLINE.end.y], "control_points": [
				{"name": "First corner", "pixel": _pixel(nodes[1]), "ohm_node": 1},
				{"name": "Second corner", "pixel": _pixel(nodes[2]), "ohm_node": 2},
				{"name": "Corner read 4 px off", "pixel": off, "ohm_node": 3}]},
		{"sheet": "B", "image": "B.png", "image_origin": [0, 0], "image_scale": 1,
			"map_area": [NEATLINE.position.x, NEATLINE.position.y, NEATLINE.end.x, NEATLINE.end.y], "control_points": [
				{"name": "Neatline corner shared with A", "pixel": [NEATLINE.position.x, NEATLINE.position.y],
					"same_as": {"sheet": "A", "pixel": [NEATLINE.end.x, NEATLINE.position.y]}},
				{"name": "Fourth corner", "pixel": _pixel(nodes[4], 100.0), "ohm_node": 4}]}],
		"places": [{"name": "Church", "sheet": "B", "pixel": _pixel([534735.0, 180285.0], 100.0)}]}


func _load() -> NlsSheets:
	var sheets: NlsSheets = NlsSheets.new()
	sheets.load(FOLDER, _nls(), _nodes())
	assert_eq(sheets.errors, [] as Array[String])
	return sheets


func test_each_sheet_is_fitted_and_every_point_reports_its_error() -> void:
	var sheets: NlsSheets = _load()
	assert_eq(sheets.residuals.size(), 5)
	var by_name: Dictionary = {}
	for residual: Dictionary in sheets.residuals:
		by_name[residual["name"]] = residual["metres"]
	assert_gt(by_name["Corner read 4 px off"], 0.5, "4 px are 2 m: the fit spreads them over three points")
	assert_almost_eq(by_name["Neatline corner shared with A"], 0.0, 0.5)
	var b: SheetGeoreference = sheets.fits["B"]
	var shared: PackedFloat64Array = b.to_bng(PackedFloat64Array([NEATLINE.position.x, NEATLINE.position.y]))
	assert_almost_eq(shared[0], A_ORIGIN[0] + 100.0, 1.0, "B starts where A's neatline ends")


func test_the_colour_comes_from_the_sheet_that_covers_the_point() -> void:
	var sheets: NlsSheets = _load()
	# The ink square sits 10 px into each neatline: 5 m from its north-west corner.
	var in_a: Color = sheets.color_at(PackedFloat64Array([A_ORIGIN[0] + 12.5, A_ORIGIN[1] - 12.5]))
	var in_b: Color = sheets.color_at(PackedFloat64Array([A_ORIGIN[0] + 112.5, A_ORIGIN[1] - 12.5]))
	assert_almost_eq(in_a.r, INK.r, TOLERANCE)
	assert_almost_eq(in_b.r, INK.r, TOLERANCE)
	assert_almost_eq(sheets.color_at(PackedFloat64Array([A_ORIGIN[0] + 50.0, A_ORIGIN[1] - 25.0])).r, PAPER.r, TOLERANCE)
	assert_eq(sheets.luminance_at(PackedFloat64Array([A_ORIGIN[0] - 50.0, A_ORIGIN[1]])), NlsSheets.NO_DATA,
		"Outside every neatline there is no sheet")


func test_a_named_place_is_read_back_onto_the_grid() -> void:
	var sheets: NlsSheets = _load()
	assert_eq(sheets.place_cell("Church", _grid), Vector2i(2, 0))
	var map: Dictionary = {"anchors": [{"name": "Church", "cell": [2, 0], "building": "", "source": "B",
		"history": "[FACT] Built."}]}
	var report: String = sheets.report(map, _grid)
	assert_eq(report, _load().report(map, _grid), "The same sources always give the same report")
	assert_string_contains(report, "Corner read 4 px off")
	assert_string_contains(report, "| Church | B | (2, 0) | (2, 0) |")


func test_a_tie_to_a_sheet_not_fitted_yet_is_an_error() -> void:
	var nls: Dictionary = _nls()
	nls["sheets"].reverse()
	var sheets: NlsSheets = NlsSheets.new()
	sheets.load(FOLDER, nls, _nodes())
	assert_string_contains("\n".join(sheets.errors), "A")
	var unknown: NlsSheets = NlsSheets.new()
	var missing_node: Dictionary = _nls()
	missing_node["sheets"][0]["control_points"][0]["ohm_node"] = 99
	unknown.load(FOLDER, missing_node, _nodes())
	assert_string_contains("\n".join(unknown.errors), "99")


# Bailey's review requirement: a committed report is what its sources give, so a moved control point or place shows.
func test_every_committed_report_is_what_its_sheets_give() -> void:
	var sources_root: String = "res://data/maps/sources"
	for folder: String in DirAccess.get_directories_at(sources_root):
		var path: String = sources_root.path_join(folder)
		if not FileAccess.file_exists(path.path_join(MapSourceConverter.REPORT)):
			continue
		var map: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % folder))
		var sources: MapSourceConverter = MapSourceConverter.new()
		var text: String = sources.report(path, map)
		assert_eq(sources.errors, [] as Array[String], folder)
		assert_eq(text, FileAccess.get_file_as_string(path.path_join(MapSourceConverter.REPORT)),
			"%s/%s is out of date: run tools/map_sources --compare" % [folder, MapSourceConverter.REPORT])
	pass_test("Every committed report checked")
