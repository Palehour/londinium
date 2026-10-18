class_name NlsDigitizer
extends RefCounted

# Reads the standing buildings of a map grid from the georeferenced NLS sheets of OS London 1:1056 (1862-74) and
# writes them as the existing.geojson that tools/map_import rasterizes (issues #152 and #170). Buildings are the grey
# fill of the sheets; water and streets are the same cream as yards, so water comes from OpenHistoricalMap instead
# (decision of Cristian, 2026-10-18). Each cell is split like the importer splits it (samples_per_axis² squares): a
# square is a building when most of its probes are clearly darker than the paper around the cell, since every sheet
# has its own tone.

const SETTINGS: Array[String] = ["probes_per_axis", "paper_window_metres", "paper_percentile", "ink_contrast",
	"building_min_fraction"]
# How many cells of sheet the paper window may reach on each side of a cell.
const WINDOW_MARGIN: int = 2
const RING_FORMAT: String = "[[%.2f, %.2f], [%.2f, %.2f], [%.2f, %.2f], [%.2f, %.2f], [%.2f, %.2f]]"

var errors: Array[String] = []
var _grid: Dictionary


# A FeatureCollection with one rectangle per run of building squares in a row.
func buildings(sheets: NlsSheets, grid: Dictionary, settings: Dictionary) -> Dictionary:
	errors.clear()
	var collection: Dictionary = {"type": "FeatureCollection", "features": []}
	for field: String in SETTINGS:
		if typeof(settings.get(field)) not in [TYPE_INT, TYPE_FLOAT]:
			errors.append("nls.%s: expected a number" % field)
	if not errors.is_empty():
		return collection
	var size: Vector2i = Vector2i(int(grid["width"]), int(grid["height"]))
	var samples: int = int(grid["samples_per_axis"])
	var cell_metres: float = float(grid["cell_metres"])
	if float(settings["paper_window_metres"]) > cell_metres * (1 + 2 * WINDOW_MARGIN):
		errors.append("nls.paper_window_metres: at most %d" % int(cell_metres * (1 + 2 * WINDOW_MARGIN)))
		return collection
	_grid = grid
	var squares: Dictionary[Vector2i, bool] = {}
	for y: int in range(size.y):
		for x: int in range(size.x):
			var paper: float = _paper(sheets, Vector2i(x, y), cell_metres, settings)
			if paper == NlsSheets.NO_DATA:
				continue
			for sy: int in range(samples):
				for sx: int in range(samples):
					var square: Vector2i = Vector2i(x * samples + sx, y * samples + sy)
					if _is_building(sheets, square, samples, paper, settings):
						squares[square] = true
	collection["features"] = _rectangles(squares, size * samples, grid)
	return collection


func to_text(collection: Dictionary) -> String:
	var lines: Array[String] = []
	for feature: Dictionary in collection["features"]:
		var ring: Array = feature["geometry"]["coordinates"][0]
		var values: Array = []
		for point: Array in ring:
			values.append_array(point)
		lines.append('    {"type": "Feature", "properties": {}, "geometry": {"type": "Polygon", "coordinates": [%s]}}'
			% (RING_FORMAT % values))
	return '{\n  "type": "FeatureCollection",\n  "features": [\n%s\n  ]\n}\n' % ",\n".join(lines)


# The paper tone around a cell: a high percentile of the luminance in a window centred on it, or NO_DATA when the
# window has no sheet.
func _paper(sheets: NlsSheets, cell: Vector2i, cell_metres: float, settings: Dictionary) -> float:
	var window: float = float(settings["paper_window_metres"]) / cell_metres
	var steps: int = int(settings["probes_per_axis"]) * ceili(window * 2)
	var start: Vector2 = Vector2(cell) + Vector2.ONE * (0.5 - window / 2.0)
	var values: Array[float] = []
	for j: int in range(steps):
		for i: int in range(steps):
			var point: Vector2 = start + Vector2(i + 0.5, j + 0.5) * window / steps
			var value: float = sheets.luminance_at(NlsSheets.grid_bng(_grid, point))
			if value != NlsSheets.NO_DATA:
				values.append(value)
	if values.is_empty():
		return NlsSheets.NO_DATA
	values.sort()
	return values[int(float(settings["paper_percentile"]) * (values.size() - 1))]


func _is_building(sheets: NlsSheets, square: Vector2i, samples: int, paper: float, settings: Dictionary) -> bool:
	var probes: int = int(settings["probes_per_axis"])
	var valid: int = 0
	var ink: int = 0
	for j: int in range(probes):
		for i: int in range(probes):
			var point: Vector2 = (Vector2(square) + Vector2(i + 0.5, j + 0.5) / probes) / samples
			var value: float = sheets.luminance_at(NlsSheets.grid_bng(_grid, point))
			if value == NlsSheets.NO_DATA:
				continue
			valid += 1
			if value <= paper - float(settings["ink_contrast"]):
				ink += 1
	# A square mostly off the sheets has no data: it stays free land (option A of Cristian, 2026-10-18).
	if valid * 2 < probes * probes:
		return false
	return float(ink) / valid >= float(settings["building_min_fraction"])


# Row by row, joining neighbouring building squares, so the text never depends on dictionary order.
func _rectangles(squares: Dictionary[Vector2i, bool], size: Vector2i, grid: Dictionary) -> Array:
	var features: Array = []
	var side: float = float(grid["cell_metres"]) / int(grid["samples_per_axis"])
	var east: float = float(grid["origin"][0])
	var north: float = float(grid["origin"][1])
	for y: int in range(size.y):
		var x: int = 0
		while x < size.x:
			if not squares.has(Vector2i(x, y)):
				x += 1
				continue
			var end: int = x
			while squares.has(Vector2i(end + 1, y)):
				end += 1
			var west: float = east + x * side
			var far: float = east + (end + 1) * side
			var top: float = north - y * side
			var bottom: float = top - side
			features.append({"type": "Feature", "properties": {}, "geometry": {"type": "Polygon", "coordinates": [
				[[west, top], [far, top], [far, bottom], [west, bottom], [west, top]]]}})
			x = end + 1
	return features
