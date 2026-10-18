class_name OhmConverter
extends RefCounted

# Streets of an OpenHistoricalMap export (Overpass JSON with `out geom`, CC0) to the roads.geojson that
# tools/map_import reads, in British National Grid metres (issue #152). Only the ways standing in the map's year are
# kept. Deterministic: features go by OHM id and coordinates are rounded to the centimetre, so the same export
# always gives the same text.

const STREET_TAG: String = "highway"
const COORDINATE_FORMAT: String = "[%.2f, %.2f]"
const FEATURE_FORMAT: String = ('    {"type": "Feature", "properties": {"name": %s, "ohm_id": %d}, '
	+ '"geometry": {"type": "LineString", "coordinates": [%s]}}')

var errors: Array[String] = []


# A FeatureCollection of LineStrings, one per standing street, with its OHM name and id.
func roads(export: Variant, year: int) -> Dictionary:
	errors.clear()
	var features: Array = []
	for way: Dictionary in _ways(export):
		var tags: Dictionary = way.get("tags", {})
		if not tags.has(STREET_TAG) or not is_standing(tags, year):
			continue
		var line: Array = _line(way)
		if line.size() >= 2:
			features.append({"type": "Feature", "properties": {"name": str(tags.get("name", "")), "ohm_id": way["id"]},
				"geometry": {"type": "LineString", "coordinates": line}})
	return {"type": "FeatureCollection", "features": features}


# Standing in `year`: built in or before it and not gone by then. OHM dates start with the year ("1746",
# "1869-12-07"); a way without a start date is not dated, so it is left out rather than guessed.
static func is_standing(tags: Dictionary, year: int) -> bool:
	var start: int = _year(tags.get("start_date", ""))
	var end: int = _year(tags.get("end_date", ""))
	return start != 0 and start <= year and (end == 0 or end > year)


# One feature per line, so a new export only changes the lines of the streets that changed.
func to_text(collection: Dictionary) -> String:
	var lines: Array[String] = []
	for feature: Dictionary in collection["features"]:
		var points: Array[String] = []
		for point: Array in feature["geometry"]["coordinates"]:
			points.append(COORDINATE_FORMAT % [point[0], point[1]])
		lines.append(FEATURE_FORMAT % [JSON.stringify(feature["properties"]["name"]), feature["properties"]["ohm_id"],
			", ".join(points)])
	return '{\n  "type": "FeatureCollection",\n  "features": [\n%s\n  ]\n}\n' % ",\n".join(lines)


static func _year(date: Variant) -> int:
	var text: String = str(date)
	return int(text.substr(0, 4)) if text.length() >= 4 and text.substr(0, 4).is_valid_int() else 0


func _ways(export: Variant) -> Array[Dictionary]:
	var ways: Array[Dictionary] = []
	if export is not Dictionary or export.get("elements") is not Array:
		errors.append("OHM export: expected an Overpass JSON object with elements")
		return ways
	for element: Variant in export["elements"]:
		if element is Dictionary and element.get("type") == "way" and element.get("geometry") is Array:
			ways.append(element)
	ways.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return ways


func _line(way: Dictionary) -> Array:
	var points: Array = []
	for node: Variant in way["geometry"]:
		if node is not Dictionary or typeof(node.get("lat")) != TYPE_FLOAT or typeof(node.get("lon")) != TYPE_FLOAT:
			errors.append("OHM way %s: invalid node %s" % [str(way["id"]), str(node)])
			return []
		var en: PackedFloat64Array = OsgbProjection.wgs84_to_bng(PackedFloat64Array([node["lat"], node["lon"]]))
		points.append([snappedf(en[0], 0.01), snappedf(en[1], 0.01)])
	return points
