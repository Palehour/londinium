class_name MapSourceConverter
extends RefCounted

# Turns the raw downloads kept in data/maps/sources/<id>/ (listed in its sources.json) into the GeoJSON layers that
# tools/map_import rasterizes (issue #152). Nothing here goes online: the downloads are committed with their date.

const MANIFEST: String = "sources.json"
const ROADS: String = "roads.geojson"

var errors: Array[String] = []


# Each generated layer's file name and text, or {} with `errors` filled.
func generate_folder(folder: String) -> Dictionary[String, String]:
	errors.clear()
	var layers: Dictionary[String, String] = {}
	var manifest: Variant = _read_json(folder.path_join(MANIFEST))
	if manifest is not Dictionary or typeof(manifest.get("year")) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s: expected an object with the map's year" % MANIFEST)
		return layers
	var ohm: Variant = manifest.get("ohm")
	if ohm is Dictionary and ohm.get("export") is String:
		var converter: OhmConverter = OhmConverter.new()
		var collection: Dictionary = converter.roads(_read_json(folder.path_join(ohm["export"])), int(manifest["year"]))
		errors.append_array(converter.errors)
		layers[ROADS] = converter.to_text(collection)
	if not errors.is_empty():
		layers.clear()
	return layers


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s: missing file" % path)
		return null
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
