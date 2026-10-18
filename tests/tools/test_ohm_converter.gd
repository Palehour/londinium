extends GutTest

# Issue #152: the streets of the riverside strip come from an OpenHistoricalMap export (CC0) and only those standing
# in the year of the map are kept.

const YEAR: int = 1870
const SOURCES: String = "res://data/maps/sources"


func _way(id: int, tags: Dictionary, points: Array) -> Dictionary:
	var geometry: Array = []
	for point: Variant in points:
		geometry.append({"lat": point[0], "lon": point[1]})
	return {"type": "way", "id": id, "tags": tags, "geometry": geometry}


func _export(ways: Array) -> Dictionary:
	return {"version": 0.6, "elements": ways}


func _street(id: int, name: String, start: String, end: String = "") -> Dictionary:
	var tags: Dictionary = {"highway": "unclassified", "name": name, "start_date": start}
	if not end.is_empty():
		tags["end_date"] = end
	return _way(id, tags, [[51.505, -0.065], [51.505, -0.064]])


func _names(collection: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for feature: Dictionary in collection["features"]:
		names.append(feature["properties"]["name"])
	return names


func test_only_streets_standing_in_the_year_are_kept() -> void:
	var converter: OhmConverter = OhmConverter.new()
	var roads: Dictionary = converter.roads(_export([
		_street(1, "Old Gravel Lane", "1746"),
		_street(2, "Pell Street", "1896"),
		_street(3, "Cox's Yard", "1746", "1804"),
		_street(4, "Thames Tunnel", "1843", "1865"),
		_street(5, "Neptune Street", "1690", "1938"),
		_street(6, "Ensign Street", "1870-03-01"),
		_street(7, "Closed in 1870", "1700", "1870-06-01"),
	]), YEAR)
	assert_eq(converter.errors, [] as Array[String])
	assert_eq(_names(roads), ["Old Gravel Lane", "Neptune Street", "Ensign Street"] as Array[String])


func test_ways_without_a_street_tag_or_a_start_date_are_left_out() -> void:
	var dock: Dictionary = _way(1, {"waterway": "dock", "start_date": "1805"}, [[51.505, -0.065], [51.506, -0.065]])
	var undated: Dictionary = _way(2, {"highway": "footway", "name": "Undated"}, [[51.505, -0.065], [51.506, -0.065]])
	var roads: Dictionary = OhmConverter.new().roads(_export([dock, undated, _street(3, "Burr Street", "1746")]), YEAR)
	assert_eq(_names(roads), ["Burr Street"] as Array[String])


func test_streets_come_out_as_lines_in_british_national_grid_metres() -> void:
	var roads: Dictionary = OhmConverter.new().roads(_export([_street(1, "Burr Street", "1746")]), YEAR)
	var feature: Dictionary = roads["features"][0]
	assert_eq(feature["geometry"]["type"], "LineString")
	var first: Array = feature["geometry"]["coordinates"][0]
	var expected: PackedFloat64Array = OsgbProjection.wgs84_to_bng(PackedFloat64Array([51.505, -0.065]))
	assert_almost_eq(float(first[0]), expected[0], 0.01)
	assert_almost_eq(float(first[1]), expected[1], 0.01)


func test_the_same_export_always_gives_the_same_text() -> void:
	var ways: Array = [_street(9, "Wapping Dock Street", "1746"), _street(2, "Burr Street", "1746")]
	var converter: OhmConverter = OhmConverter.new()
	var first: String = converter.to_text(converter.roads(_export(ways), YEAR))
	ways.reverse()
	var second: String = converter.to_text(converter.roads(_export(ways), YEAR))
	assert_eq(first, second, "Ordered by OHM id, not by the order of the export")
	var parsed: Variant = JSON.parse_string(first)
	assert_true(parsed is Dictionary and parsed["type"] == "FeatureCollection")
	assert_eq(_names(parsed), ["Burr Street", "Wapping Dock Street"] as Array[String])


func test_a_broken_export_is_reported() -> void:
	var converter: OhmConverter = OhmConverter.new()
	converter.roads({"version": 0.6}, YEAR)
	assert_false(converter.errors.is_empty())


# Bailey's review requirement: the generated layers are exactly what the committed raw sources give.
func test_every_committed_street_layer_is_what_its_ohm_export_gives() -> void:
	var checked: int = 0
	for folder: String in DirAccess.get_directories_at(SOURCES):
		var path: String = SOURCES.path_join(folder)
		if not FileAccess.file_exists(path.path_join("sources.json")):
			continue
		var sources: MapSourceConverter = MapSourceConverter.new()
		var layers: Dictionary[String, String] = sources.generate_folder(path)
		assert_eq(sources.errors, [] as Array[String], folder)
		for layer: String in layers:
			assert_eq(layers[layer], FileAccess.get_file_as_string(path.path_join(layer)),
				"%s/%s is out of date: run tools/map_sources" % [folder, layer])
		checked += 1
	assert_gt(checked, 0, "The riverside strip has its sources.json")
