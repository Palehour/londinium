extends GutTest

const FIXTURE: String = "res://tests/tools/fixtures/map_import"
const SOURCES: String = "res://data/maps/sources"


# A grid of `width`×`height` cells of 10 m whose north-west corner is at easting 0, northing 10 × height.
func _config(width: int, height: int, samples: int = 5) -> Dictionary:
	return {"id": "fixture", "width": width, "height": height, "origin": [0, 10 * height], "cell_metres": 10,
		"samples_per_axis": samples, "priority": ["river", "dock", "marsh", "existing", "land"]}


# Grid coordinates (x right, y down) to a GeoJSON ring in metres (easting, northing).
func _rect(config: Dictionary, x0: float, y0: float, x1: float, y1: float) -> Array:
	var top: float = float(config["origin"][1])
	return [[x0 * 10, top - y0 * 10], [x1 * 10, top - y0 * 10], [x1 * 10, top - y1 * 10],
		[x0 * 10, top - y1 * 10], [x0 * 10, top - y0 * 10]]


func _polygons(rings: Array) -> Dictionary:
	var features: Array = []
	for polygon: Variant in rings:
		features.append({"type": "Feature", "properties": {}, "geometry": {"type": "Polygon", "coordinates": polygon}})
	return {"type": "FeatureCollection", "features": features}


func _line(config: Dictionary, points: Array) -> Dictionary:
	var top: float = float(config["origin"][1])
	var coordinates: Array = []
	for point: Variant in points:
		coordinates.append([point[0] * 10, top - point[1] * 10])
	return {"type": "FeatureCollection", "features": [
		{"type": "Feature", "properties": {}, "geometry": {"type": "LineString", "coordinates": coordinates}}]}


func _import(config: Dictionary, layers: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var importer: MapImporter = MapImporter.new()
	var map: Dictionary = importer.import_documents(config, layers, overrides)
	assert_eq(importer.errors, [] as Array[String])
	return map


func _cells(raw: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Variant in raw:
		cells.append(Vector2i(int(cell[0]), int(cell[1])))
	return cells


func test_each_cell_takes_the_class_covering_most_of_it() -> void:
	var config: Dictionary = _config(3, 1)
	# Cell 0 is fully river, cell 1 is 60 % river and cell 2 is 40 % river.
	var layers: Dictionary = {"river": _polygons([[_rect(config, 0, 0, 1.6, 1)], [_rect(config, 2, 0, 2.4, 1)]])}
	var map: Dictionary = _import(config, layers)
	assert_eq(_cells(map["river_cells"]), [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i])


func test_ties_break_by_the_configured_priority() -> void:
	var config: Dictionary = _config(1, 1, 2)
	var layers: Dictionary = {"river": _polygons([[_rect(config, 0, 0, 0.5, 1)]]),
		"docks": _polygons([[_rect(config, 0.5, 0, 1, 1)]])}
	assert_eq(_cells(_import(config, layers)["river_cells"]), [Vector2i(0, 0)] as Array[Vector2i])
	config["priority"] = ["dock", "river", "marsh", "existing", "land"]
	var map: Dictionary = _import(config, layers)
	assert_eq(_cells(map["dock_cells"]), [Vector2i(0, 0)] as Array[Vector2i])
	assert_true(map["river_cells"].is_empty())


func test_a_hole_in_a_polygon_is_not_part_of_it() -> void:
	var config: Dictionary = _config(3, 3)
	var layers: Dictionary = {"docks": _polygons([[_rect(config, 0, 0, 3, 3), _rect(config, 1, 1, 2, 2)]])}
	var docks: Array[Vector2i] = _cells(_import(config, layers)["dock_cells"])
	assert_eq(docks.size(), 8)
	assert_false(Vector2i(1, 1) in docks)


func test_a_diagonal_street_becomes_a_staircase_joined_side_by_side() -> void:
	var config: Dictionary = _config(5, 5)
	var roads: Array[Vector2i] = _cells(_import(config, {"roads": _line(config, [[0.3, 0.6], [4.6, 4.2]])})["road_cells"])
	assert_true(Vector2i(0, 0) in roads and Vector2i(4, 4) in roads, str(roads))
	# #67 joins road cells through their four sides, so a diagonal must not hop corner to corner.
	var reached: Array[Vector2i] = [roads[0]]
	var index: int = 0
	while index < reached.size():
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = reached[index] + step
			if next in roads and next not in reached:
				reached.append(next)
		index += 1
	assert_eq(reached.size(), roads.size(), str(roads))
	assert_lt(roads.size(), 10, "A staircase, not a band: %s" % str(roads))


func test_overrides_replace_what_the_sources_say() -> void:
	var config: Dictionary = _config(3, 1)
	var layers: Dictionary = {"river": _polygons([[_rect(config, 0, 0, 3, 1)]])}
	var overrides: Dictionary = {"areas": [{"class": "land", "rects": [[2, 0, 1, 1]]},
		{"class": "existing", "rects": [[1, 0, 1, 1]]}], "roads": {"add": [[2, 0]], "remove": []}}
	var map: Dictionary = _import(config, layers, overrides)
	assert_eq(_cells(map["river_cells"]), [Vector2i(0, 0)] as Array[Vector2i])
	assert_eq(_cells(map["existing_cells"]), [Vector2i(1, 0)] as Array[Vector2i])
	assert_eq(_cells(map["road_cells"]), [Vector2i(2, 0)] as Array[Vector2i])
	var removed: Dictionary = _import(config, {"roads": _line(config, [[0.5, 0.5], [2.5, 0.5]])},
		{"areas": [], "roads": {"add": [], "remove": [[1, 0]]}})
	assert_eq(_cells(removed["road_cells"]), [Vector2i(0, 0), Vector2i(2, 0)] as Array[Vector2i])


# Issue #154 (D-079): the cells where dense housing starts are listed by hand and travel to the map unchanged.
func test_overrides_list_the_dense_housing_start_cells() -> void:
	var config: Dictionary = _config(3, 2)
	var overrides: Dictionary = {"areas": [{"class": "existing", "rects": [[0, 0, 2, 1]]}],
		"roads": {"add": [[0, 1]], "remove": []}, "dense_housing_cells": [[0, 0]]}
	var importer: MapImporter = MapImporter.new()
	var map: Dictionary = importer.import_documents(config, {}, overrides)
	assert_eq(importer.errors, [] as Array[String])
	assert_eq(_cells(map["dense_housing_cells"]), [Vector2i(0, 0)] as Array[Vector2i])
	var parsed: Dictionary = JSON.parse_string(importer.to_text(map))
	assert_eq(_cells(parsed["dense_housing_cells"]), [Vector2i(0, 0)] as Array[Vector2i])
	assert_false(JSON.parse_string(importer.to_text(_import(config, {}))).has("dense_housing_cells"),
		"A map without them writes no field")
	var outside: MapImporter = MapImporter.new()
	outside.import_documents(config, {}, {"areas": [], "dense_housing_cells": [[5, 0]]})
	assert_false(outside.errors.is_empty(), "A start cell outside the grid is an error")


func test_land_beside_water_is_riverbank_and_marsh_is_kept() -> void:
	var config: Dictionary = _config(4, 3)
	var layers: Dictionary = {"river": _polygons([[_rect(config, 0, 2, 4, 3)]]),
		"docks": _polygons([[_rect(config, 3, 0, 4, 1)]]), "marsh": _polygons([[_rect(config, 0, 1, 1, 2)]])}
	var terrain: Dictionary = _import(config, layers)["terrain"]
	assert_eq(_cells(terrain["marsh"]), [Vector2i(0, 1)] as Array[Vector2i])
	assert_eq(_cells(terrain["riverbank"]),
		[Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)] as Array[Vector2i])


func test_the_same_sources_always_give_the_same_text() -> void:
	var config: Dictionary = _config(5, 5)
	var layers: Dictionary = {"roads": _line(config, [[4.5, 0.5], [0.5, 3.5]]),
		"river": _polygons([[_rect(config, 0, 4, 5, 5)]])}
	var importer: MapImporter = MapImporter.new()
	var first: String = importer.to_text(importer.import_documents(config, layers, {}))
	var second: String = importer.to_text(importer.import_documents(config, layers, {}))
	assert_eq(first, second)
	var parsed: Dictionary = JSON.parse_string(first)
	var roads: Array[Vector2i] = _cells(parsed["road_cells"])
	var sorted: Array[Vector2i] = roads.duplicate()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	assert_eq(roads, sorted, "Cells are written row by row")


func test_a_folder_of_geojson_files_is_imported() -> void:
	var importer: MapImporter = MapImporter.new()
	var map: Dictionary = importer.import_folder(FIXTURE)
	assert_eq(importer.errors, [] as Array[String])
	assert_eq(map["id"], "fixture")
	assert_eq(_cells(map["river_cells"]), [Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)] as Array[Vector2i])
	assert_eq(_cells(map["dock_cells"]), [Vector2i(3, 0)] as Array[Vector2i])
	assert_eq(_cells(map["road_cells"]), [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2)] as Array[Vector2i])
	assert_eq(_cells(map["existing_cells"]), [Vector2i(1, 2)] as Array[Vector2i])


func test_every_committed_map_is_what_its_sources_import_to() -> void:
	var folders: PackedStringArray = DirAccess.get_directories_at(SOURCES)
	assert_gt(folders.size(), 0)
	for folder: String in folders:
		var importer: MapImporter = MapImporter.new()
		var text: String = importer.to_text(importer.import_folder(SOURCES.path_join(folder)))
		assert_eq(importer.errors, [] as Array[String], folder)
		assert_eq(text, FileAccess.get_file_as_string("res://data/maps/%s.json" % folder),
			"data/maps/%s.json is out of date: run tools/map_import" % folder)


# Issue #152 (option A of Cristian, 2026-10-18): the historic anchors and named sites are listed by hand with their
# source and travel to the map unchanged; an anchor on land is a standing building, one on the river stays water.
func test_overrides_list_the_anchors_and_named_sites() -> void:
	var config: Dictionary = _config(3, 2)
	var layers: Dictionary = {"river": _polygons([[_rect(config, 0, 1, 3, 2)]])}
	var church: Dictionary = {"name": "Church", "cell": [1, 0], "building": "", "source": "Sheet A",
		"history": "[FACT] Built 1756."}
	var wharf: Dictionary = {"name": "Wharf", "cell": [1, 1], "building": "wharf", "source": "Sheet A",
		"history": "[INVENTED] Game cell."}
	var stairs: Dictionary = {"name": "Stairs", "cell": [2, 1], "source": "Sheet B", "history": "[FACT ±1] Stairs."}
	var notes: Array = ["[DEBATED] Undated water."]
	var importer: MapImporter = MapImporter.new()
	var map: Dictionary = importer.import_documents(config, layers,
		{"areas": [], "anchors": [church, wharf], "named_sites": [stairs], "history_notes": notes})
	assert_eq(importer.errors, [] as Array[String])
	assert_eq(_cells(map["existing_cells"]), [Vector2i(1, 0)] as Array[Vector2i])
	assert_true([1, 1] in map["river_cells"], "The wharf anchor stays on the river")
	var parsed: Dictionary = JSON.parse_string(importer.to_text(map))
	# Through JSON both ways, since parsing turns the cell numbers into floats.
	assert_eq(parsed["anchors"], JSON.parse_string(JSON.stringify([church, wharf])))
	assert_eq(parsed["named_sites"], JSON.parse_string(JSON.stringify([stairs])))
	assert_eq(parsed["history_notes"], notes)
	assert_false(JSON.parse_string(importer.to_text(_import(config, {}))).has("anchors"),
		"A map without them writes no field")
	var tagged: String = "[FACT] A"
	for broken: Dictionary in [
			{"anchors": [{"name": "", "cell": [0, 0], "building": "", "source": "A", "history": tagged}]},
			{"anchors": [{"name": "Off", "cell": [5, 0], "building": "", "source": "A", "history": tagged}]},
			{"anchors": [{"name": "Unsourced", "cell": [0, 0], "building": "", "history": tagged}]},
			{"anchors": [{"name": "Untagged", "cell": [0, 0], "building": "", "source": "A", "history": "Built"}]},
			{"named_sites": [{"name": "Unsourced", "cell": [0, 0], "history": tagged}]},
			{"history_notes": ["Undated water"]}]:
		var bad: MapImporter = MapImporter.new()
		assert_eq(bad.import_documents(config, {}, broken), {}, str(broken))
		assert_false(bad.errors.is_empty(), str(broken))


# Issue #176 (D-083): period houses, damaged wharves and lot styles are listed by hand and travel to the map unchanged;
# a period house on land is a standing building, like an anchor, and a damaged wharf stays water.
func test_overrides_list_period_houses_damaged_wharves_and_lot_styles() -> void:
	var config: Dictionary = _config(3, 2)
	var layers: Dictionary = {"river": _polygons([[_rect(config, 0, 1, 3, 2)]])}
	var house: Dictionary = {"name": "Period house", "cell": [1, 0], "source": "No sheet",
		"history": "[INVENTED] A house."}
	var wharf: Dictionary = {"name": "Damaged wharf", "cell": [1, 1], "repair_cost_ratio": 0.5, "source": "No sheet",
		"history": "[INVENTED] Damaged."}
	var styles: Dictionary = {"yard": [[0, 0]], "garden": [[2, 0]]}
	var importer: MapImporter = MapImporter.new()
	var map: Dictionary = importer.import_documents(config, layers,
		{"areas": [], "period_houses": [house], "damaged_wharves": [wharf], "lot_styles": styles})
	assert_eq(importer.errors, [] as Array[String])
	assert_eq(_cells(map["existing_cells"]), [Vector2i(1, 0)] as Array[Vector2i])
	assert_true([1, 1] in map["river_cells"], "The damaged wharf stays on the river")
	var parsed: Dictionary = JSON.parse_string(importer.to_text(map))
	assert_eq(parsed["period_houses"], JSON.parse_string(JSON.stringify([house])))
	assert_eq(parsed["damaged_wharves"], JSON.parse_string(JSON.stringify([wharf])))
	assert_eq(parsed["lot_styles"], JSON.parse_string(JSON.stringify(styles)))
	var plain: Dictionary = JSON.parse_string(importer.to_text(_import(config, {})))
	for field: String in ["period_houses", "damaged_wharves", "lot_styles"]:
		assert_false(plain.has(field), "A map without %s writes no field" % field)
	for broken: Dictionary in [
			{"period_houses": [{"name": "Off", "cell": [5, 0], "source": "A", "history": "[INVENTED] A"}]},
			{"period_houses": [{"name": "Untagged", "cell": [1, 0], "source": "A", "history": "A house"}]},
			{"damaged_wharves": [{"name": "Unpriced", "cell": [1, 1], "source": "A", "history": "[INVENTED] A"}]},
			{"lot_styles": {"yard": [[9, 9]]}},
			{"lot_styles": [[0, 0]]}]:
		var bad: MapImporter = MapImporter.new()
		assert_eq(bad.import_documents(config, {}, broken), {}, str(broken))
		assert_false(bad.errors.is_empty(), str(broken))


func test_bad_sources_are_reported_and_give_no_map() -> void:
	var config: Dictionary = _config(2, 2)
	var cases: Dictionary = {
		"unknown layer": [{"lakes": _polygons([])}, {}],
		"unsupported geometry": [{"river": {"type": "FeatureCollection", "features": [
			{"type": "Feature", "geometry": {"type": "Point", "coordinates": [0, 0]}}]}}, {}],
		"unknown class": [{}, {"areas": [{"class": "lake", "rects": [[0, 0, 1, 1]]}]}],
		"outside the grid": [{}, {"areas": [{"class": "river", "rects": [[1, 1, 2, 1]]}]}],
		"road outside the grid": [{}, {"roads": {"add": [[2, 0]], "remove": []}}],
	}
	for name: String in cases:
		var importer: MapImporter = MapImporter.new()
		var map: Dictionary = importer.import_documents(config, cases[name][0], cases[name][1])
		assert_true(map.is_empty(), name)
		assert_false(importer.errors.is_empty(), name)
	var missing: Dictionary = config.duplicate()
	missing.erase("cell_metres")
	var importer: MapImporter = MapImporter.new()
	assert_true(importer.import_documents(missing, {}, {}).is_empty())
	assert_string_contains("\n".join(importer.errors), "cell_metres")


# Issue #67 (D-080): import.json says whether the map plays with streets and overrides.json lists the diagonal
# edges of its historic streets one by one; without them the map has none and plays without streets.
func test_roads_switch_and_diagonal_edges_come_from_the_sources() -> void:
	var config: Dictionary = _config(3, 3)
	var plain: Dictionary = _import(config, {})
	assert_false(plain["roads_enabled"])
	assert_eq(plain["road_diagonals"], [])
	config["roads_enabled"] = true
	var map: Dictionary = _import(config, {}, {"areas": [], "roads": {"add": [[0, 0], [1, 1]], "remove": [],
		"diagonals": [[0, 0, 1, 1]]}})
	assert_true(map["roads_enabled"])
	assert_eq(map["road_diagonals"], [[0, 0, 1, 1]])
	var parsed: Dictionary = JSON.parse_string(MapImporter.new().to_text(map))
	assert_true(parsed["roads_enabled"])
	assert_eq(parsed["road_diagonals"].size(), 1)


func test_a_diagonal_outside_the_grid_is_reported() -> void:
	var importer: MapImporter = MapImporter.new()
	var map: Dictionary = importer.import_documents(_config(3, 3), {}, {"roads": {"diagonals": [[2, 2, 3, 3]]}})
	assert_eq(map, {})
	assert_string_contains("\n".join(importer.errors), "overrides.json.roads.diagonals")
