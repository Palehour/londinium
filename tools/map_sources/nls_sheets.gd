class_name NlsSheets
extends RefCounted

# The NLS sheets of a map (OS London 1:1056, 1862-74, single sheets through IIIF; issue #170), georeferenced from
# the `nls` section of its sources.json. Each sheet lists control points in full-resolution pixels of the sheet:
# a street corner of the OHM export by its node id, or a neatline corner shared with a sheet listed before it, whose
# ground position that sheet's fit gives. The committed image of a sheet is a crop: `image_origin` is its top-left
# corner in full-resolution pixels and `image_scale` how many of them make one of its pixels. Only the map area inside
# the neatline (`map_area`, full-resolution pixels) counts as the sheet; outside every neatline there is no data.

const NO_DATA: float = -1.0
# Below this alpha a pixel is not part of the sheet.
const OPAQUE: float = 0.5
# Bailey's limit (issue #152): a control point further off than half a cell is explained in the report.
const EXPLAIN_METRES: float = 25.0
const NO_SHEET: Color = Color(0, 0, 0, 0)

var errors: Array[String] = []
var fits: Dictionary[String, SheetGeoreference] = {}
# One per control point, in the order of sources.json: {"sheet", "name", "metres"}.
var residuals: Array[Dictionary] = []
var _sheets: Array[Dictionary] = []
var _places: Array[Dictionary] = []


# Grid point (in cells, x right and y down from the north-west corner) to British National Grid metres.
static func grid_bng(grid: Dictionary, point: Vector2) -> PackedFloat64Array:
	var side: float = float(grid["cell_metres"])
	return PackedFloat64Array([float(grid["origin"][0]) + point.x * side, float(grid["origin"][1]) - point.y * side])


func load(folder: String, nls: Dictionary, nodes: Dictionary[int, PackedFloat64Array]) -> void:
	errors.clear()
	for sheet: Variant in nls.get("sheets", []):
		if sheet is not Dictionary or not _valid_sheet(sheet):
			errors.append("nls.sheets: %s needs sheet, image, image_origin, image_scale, map_area and control_points"
				% str(sheet).left(80))
			continue
		var fit: SheetGeoreference = _fit(sheet, nodes)
		if fit == null:
			continue
		var image: Image = Image.load_from_file(ProjectSettings.globalize_path(folder.path_join(sheet["image"])))
		if image == null:
			errors.append("nls.sheets.%s: cannot read %s" % [sheet["sheet"], sheet["image"]])
			continue
		var area: Array = sheet["map_area"]
		add_sheet(sheet["sheet"], image, fit, Rect2(area[0], area[1], area[2] - area[0], area[3] - area[1]),
			Vector2(sheet["image_origin"][0], sheet["image_origin"][1]), float(sheet["image_scale"]))
	for place: Variant in nls.get("places", []):
		if place is not Dictionary or place.get("name") is not String or not fits.has(str(place.get("sheet"))) \
				or not _is_pair(place.get("pixel")):
			errors.append("nls.places: %s needs a name, a fitted sheet and a pixel" % str(place))
			continue
		_places.append(place)


func add_sheet(sheet_name: String, image: Image, fit: SheetGeoreference, map_area: Rect2,
		image_origin: Vector2 = Vector2.ZERO, image_scale: float = 1.0) -> void:
	image.convert(Image.FORMAT_RGBA8)
	fits[sheet_name] = fit
	_sheets.append({"name": sheet_name, "image": image, "fit": fit, "area": map_area, "origin": image_origin,
		"scale": image_scale})


func is_empty() -> bool:
	return _sheets.is_empty()


# Colour at a grid point from the first sheet whose map area holds it, or NO_SHEET.
func color_at(en: PackedFloat64Array) -> Color:
	for sheet: Dictionary in _sheets:
		var full: PackedFloat64Array = (sheet["fit"] as SheetGeoreference).to_pixel(en)
		if not (sheet["area"] as Rect2).has_point(Vector2(full[0], full[1])):
			continue
		var image: Image = sheet["image"]
		var pixel: Vector2i = Vector2i(((Vector2(full[0], full[1]) - sheet["origin"]) / sheet["scale"]).floor())
		if Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel):
			return image.get_pixelv(pixel)
	return NO_SHEET


func luminance_at(en: PackedFloat64Array) -> float:
	var color: Color = color_at(en)
	return color.get_luminance() if color.a >= OPAQUE else NO_DATA


# Where the sheets put a named place of sources.json, in grid cells (or (-1, -1) for an unknown one).
func place_cell(place_name: String, grid: Dictionary) -> Vector2i:
	var points: Dictionary[String, Vector2] = place_points(grid)
	return Vector2i(points[place_name].floor()) if points.has(place_name) else Vector2i(-1, -1)


# Every named place as a grid point (cells, x right and y down), for the comparison image.
func place_points(grid: Dictionary) -> Dictionary[String, Vector2]:
	var points: Dictionary[String, Vector2] = {}
	var side: float = float(grid["cell_metres"])
	for place: Dictionary in _places:
		var en: PackedFloat64Array = fits[place["sheet"]].to_bng(PackedFloat64Array(place["pixel"]))
		points[place["name"]] = Vector2((en[0] - float(grid["origin"][0])) / side, (float(grid["origin"][1]) - en[1]) / side)
	return points


# The georeferencing report in Markdown: each sheet's fit and the error of every control point, then every named
# place as the sheets put it against the cell the map gives it (`map` is data/maps/<id>.json).
func report(map: Dictionary, grid: Dictionary) -> String:
	var lines: Array[String] = ["# Georeferencing of the NLS sheets", "",
		"Generated by tools/map_sources (--compare) from sources.json: do not edit by hand.", "",
		"| Sheet | Control point | Error (m) |", "|---|---|---|"]
	for residual: Dictionary in residuals:
		var over: bool = residual["metres"] > EXPLAIN_METRES
		var flag: String = " (over %d m: see sources.json)" % int(EXPLAIN_METRES) if over else ""
		lines.append("| %s | %s | %.1f%s |" % [residual["sheet"], residual["name"], residual["metres"], flag])
	lines.append_array(["", "| Sheet | Scale (px/m, full resolution) | Rotation (degrees) |", "|---|---|---|"])
	for sheet: Dictionary in _sheets:
		var fit: SheetGeoreference = sheet["fit"]
		lines.append("| %s | %.3f | %.2f |" % [sheet["name"], fit.scale, fit.rotation_degrees])
	var cells: Dictionary[String, String] = {}
	for field: String in ["anchors", "named_sites"]:
		for entry: Variant in map.get(field, []):
			if entry is Dictionary and entry.get("cell") is Array:
				cells[str(entry.get("name"))] = "(%d, %d)" % [int(entry["cell"][0]), int(entry["cell"][1])]
	lines.append_array(["", "| Place | Sheet | Cell on the sheet | Cell in the map |", "|---|---|---|---|"])
	for place: Dictionary in _places:
		var cell: Vector2i = place_cell(place["name"], grid)
		lines.append("| %s | %s | (%d, %d) | %s |" % [place["name"], place["sheet"], cell.x, cell.y,
			cells.get(place["name"], "none")])
	return "\n".join(lines) + "\n"


func _fit(sheet: Dictionary, nodes: Dictionary[int, PackedFloat64Array]) -> SheetGeoreference:
	var pixels: Array[PackedFloat64Array] = []
	var points: Array[PackedFloat64Array] = []
	var names: Array[String] = []
	for point: Variant in sheet["control_points"]:
		var en: PackedFloat64Array = _ground(point, nodes, sheet["sheet"])
		if en.is_empty():
			continue
		pixels.append(PackedFloat64Array(point["pixel"]))
		points.append(en)
		names.append(str(point.get("name", "")))
	var fit: SheetGeoreference = SheetGeoreference.fit(pixels, points)
	if fit == null:
		errors.append("nls.sheets.%s: needs at least two distinct control points" % sheet["sheet"])
		return null
	for index: int in range(points.size()):
		residuals.append({"sheet": sheet["sheet"], "name": names[index],
			"metres": fit.residual_metres(pixels[index], points[index])})
	return fit


# Ground position of a control point, or an empty array with the error noted.
func _ground(point: Variant, nodes: Dictionary[int, PackedFloat64Array], sheet_name: String) -> PackedFloat64Array:
	if point is not Dictionary or not _is_pair(point.get("pixel")):
		errors.append("nls.sheets.%s: control point %s needs a pixel" % [sheet_name, str(point)])
		return PackedFloat64Array()
	if typeof(point.get("ohm_node")) in [TYPE_INT, TYPE_FLOAT]:
		var node: int = int(point["ohm_node"])
		if not nodes.has(node):
			errors.append("nls.sheets.%s: OHM node %d is not in the export" % [sheet_name, node])
			return PackedFloat64Array()
		return nodes[node]
	var same_as: Variant = point.get("same_as")
	if same_as is Dictionary and fits.has(str(same_as.get("sheet"))) and _is_pair(same_as.get("pixel")):
		return fits[same_as["sheet"]].to_bng(PackedFloat64Array(same_as["pixel"]))
	errors.append("nls.sheets.%s: %s needs an ohm_node or same_as a sheet listed before it (%s)"
		% [sheet_name, str(point.get("name", "")), str(same_as.get("sheet", "")) if same_as is Dictionary else ""])
	return PackedFloat64Array()


func _valid_sheet(sheet: Dictionary) -> bool:
	return sheet.get("sheet") is String and sheet.get("image") is String and _is_pair(sheet.get("image_origin")) \
		and typeof(sheet.get("image_scale")) in [TYPE_INT, TYPE_FLOAT] and float(sheet["image_scale"]) > 0.0 \
		and sheet.get("map_area") is Array and sheet["map_area"].size() == 4 and sheet.get("control_points") is Array


static func _is_pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and typeof(value[0]) in [TYPE_INT, TYPE_FLOAT] \
		and typeof(value[1]) in [TYPE_INT, TYPE_FLOAT]

