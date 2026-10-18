class_name MapSourceConverter
extends RefCounted

# Turns the raw downloads kept in data/maps/sources/<id>/ (listed in its sources.json) into the GeoJSON layers that
# tools/map_import rasterizes (issue #152): streets and water from the OpenHistoricalMap export, standing buildings
# (when the manifest asks for them) from the georeferenced NLS sheets. Nothing here goes online: the downloads are
# committed with their date.

const MANIFEST: String = "sources.json"
const GRID: String = "import.json"
const ROADS: String = "roads.geojson"
const EXISTING: String = "existing.geojson"
# Written by tools/map_sources --compare beside the sources: the georeferencing of the NLS sheets.
const REPORT: String = "nls_report.md"

var errors: Array[String] = []


# Each generated layer's file name and text, or {} with `errors` filled.
func generate_folder(folder: String) -> Dictionary[String, String]:
	errors.clear()
	var layers: Dictionary[String, String] = {}
	var manifest: Variant = _read_json(folder.path_join(MANIFEST))
	if manifest is not Dictionary or typeof(manifest.get("year")) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s: expected an object with the map's year" % MANIFEST)
		return layers
	var year: int = int(manifest["year"])
	var ohm: Variant = manifest.get("ohm")
	if ohm is Dictionary and ohm.get("export") is String:
		var export: Variant = _read_json(folder.path_join(ohm["export"]))
		var converter: OhmConverter = OhmConverter.new()
		layers[ROADS] = converter.to_text(converter.roads(export, year))
		errors.append_array(converter.errors)
		var water: Dictionary[String, Dictionary] = converter.water(export, year)
		errors.append_array(converter.errors)
		for layer: String in water:
			layers[layer] = converter.to_text(water[layer])
	if manifest.get("nls") is Dictionary and manifest["nls"].get("buildings") is Dictionary:
		layers[EXISTING] = _buildings(folder, manifest)
	if not errors.is_empty():
		layers.clear()
	return layers


# The georeferenced NLS sheets of a folder, fitted to the OHM street corners of its export (issue #170); empty, with
# `errors` filled, when the manifest lists none.
func sheets(folder: String) -> NlsSheets:
	var result: NlsSheets = NlsSheets.new()
	var manifest: Variant = _read_json(folder.path_join(MANIFEST))
	if manifest is not Dictionary or manifest.get("nls") is not Dictionary or manifest.get("ohm") is not Dictionary:
		errors.append("%s: expected its nls and ohm sections" % MANIFEST)
		return result
	var converter: OhmConverter = OhmConverter.new()
	var nodes: Dictionary[int, PackedFloat64Array] = converter.node_positions(
		_read_json(folder.path_join(str(manifest["ohm"].get("export", "")))))
	errors.append_array(converter.errors)
	result.load(folder, manifest["nls"], nodes)
	errors.append_array(result.errors)
	return result


# The georeferencing report of a folder (NlsSheets.report) against its imported map, data/maps/<id>.json.
func report(folder: String, map: Variant) -> String:
	var grid: Variant = _read_json(folder.path_join(GRID))
	var nls_sheets: NlsSheets = sheets(folder)
	if grid is not Dictionary or map is not Dictionary:
		errors.append("%s and the imported map are needed for %s" % [GRID, REPORT])
		return ""
	return nls_sheets.report(map, grid)


# The cells with no 1862-74 sheet (nls.gap.cells, [x, y, width, height]), hatched in the comparison image.
func gap_cells(folder: String) -> Rect2i:
	var manifest: Variant = _read_json(folder.path_join(MANIFEST))
	var gap: Variant = manifest.get("nls", {}).get("gap") if manifest is Dictionary else null
	var cells: Variant = gap.get("cells") if gap is Dictionary else null
	if cells is not Array or cells.size() != 4:
		return Rect2i()
	return Rect2i(int(cells[0]), int(cells[1]), int(cells[2]), int(cells[3]))


# The standing buildings read on the sheets with the settings of nls.buildings; option A of the riverside strip
# (2026-10-18) has none, so its manifest leaves them out.
func _buildings(folder: String, manifest: Dictionary) -> String:
	var grid: Variant = _read_json(folder.path_join(GRID))
	var nls_sheets: NlsSheets = sheets(folder)
	if grid is not Dictionary or nls_sheets.is_empty():
		errors.append("%s and the sheets of %s.nls are needed to read the buildings" % [GRID, MANIFEST])
		return ""
	var digitizer: NlsDigitizer = NlsDigitizer.new()
	var text: String = digitizer.to_text(digitizer.buildings(nls_sheets, grid, manifest["nls"]["buildings"]))
	errors.append_array(digitizer.errors)
	return text


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s: missing file" % path)
		return null
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
