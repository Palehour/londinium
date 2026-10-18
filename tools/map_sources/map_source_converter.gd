class_name MapSourceConverter
extends RefCounted

# Turns the raw downloads kept in data/maps/sources/<id>/ (listed in its sources.json) into the GeoJSON layers that
# tools/map_import rasterizes (issue #152): streets and water from the OpenHistoricalMap export, standing buildings
# from the NLS tiles. Nothing here goes online: the downloads are committed with their date.

const MANIFEST: String = "sources.json"
const GRID: String = "import.json"
const ROADS: String = "roads.geojson"
const EXISTING: String = "existing.geojson"

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
	var nls: Variant = manifest.get("nls")
	if nls is Dictionary and nls.get("tiles") is String:
		layers[EXISTING] = _buildings(folder, nls)
	if not errors.is_empty():
		layers.clear()
	return layers


func _buildings(folder: String, nls: Dictionary) -> String:
	var grid: Variant = _read_json(folder.path_join(GRID))
	if grid is not Dictionary or typeof(nls.get("zoom")) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s and %s.nls.zoom are needed to read the NLS tiles" % [GRID, MANIFEST])
		return ""
	var mosaic: NlsMosaic = NlsMosaic.load_folder(folder.path_join(nls["tiles"]), int(nls["zoom"]))
	if mosaic.is_empty():
		errors.append("%s: no tiles of zoom %d" % [nls["tiles"], int(nls["zoom"])])
		return ""
	var digitizer: NlsDigitizer = NlsDigitizer.new()
	var text: String = digitizer.to_text(digitizer.buildings(mosaic, grid, nls))
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
