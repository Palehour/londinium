extends GutTest

# Maps drawn as rows of cell types (issue #61, task 2; D-086, D-091, D-092, D-093). The fixture is a small map of
# the same format as the full one: river to the north, a street of whole 2x2 pieces, stairs and a dock basin.

const GRID: String = "maps/grid_test.json"
const GRID_ID: StringName = &"grid_test"
const FLOOR_KEY: String = "min_riverside_buildable"
# Buildable cells of the fixture with a side on the river: row 1 without its stairs.
const RIVERSIDE: int = 7

var _documents: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps", "eras/victorian"]:
		var dir: DirAccess = DirAccess.open("res://data/" + folder)
		for file_name: String in dir.get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				_documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))
	_documents["economy/map.json"][FLOOR_KEY] = RIVERSIDE
	_documents[GRID] = {
		"id": String(GRID_ID), "size": [8, 6], "cell_size_m": _documents["economy/map.json"]["cell_size_m"],
		"cells": ["~~~~~~~~", "....s...", "########", "########", "..DD....", "..DD...."],
		"districts": [{"id": "whitechapel", "name": "Whitechapel", "symbol": "W"}],
		"district_by_cell": ["WWWWWWWW", "WWWWWWWW", "WWWWWWWW", "WWWWWWWW", "WWWWWWWW", "WWWWWWWW"],
		"zones": [{"id": "all", "cells": [[0, 1], [1, 1]]}],
	}


func _load() -> DataLoadResult:
	return DataLoader.new().load_documents(_documents)


func _map() -> MapDef:
	var result: DataLoadResult = _load()
	assert_true(result.is_ok(), str(result.errors))
	return result.catalog.maps.get(GRID_ID) if result.is_ok() else null


func _assert_invalid(message: String) -> void:
	var result: DataLoadResult = _load()
	assert_false(result.is_ok(), "expected: " + message)
	assert_string_contains("\n".join(result.errors), message)


func _set_cell(field: String, cell: Vector2i, symbol: String) -> void:
	var rows: Array = _documents[GRID][field]
	var row: String = rows[cell.y]
	rows[cell.y] = row.substr(0, cell.x) + symbol + row.substr(cell.x + 1)


func test_types_fill_the_map_layers() -> void:
	var map: MapDef = _map()
	if map == null:
		return
	assert_eq([map.width, map.height], [8, 6])
	assert_eq(map.river_cells.size(), 8)
	assert_eq(map.stairs_cells, [Vector2i(4, 1)] as Array[Vector2i])
	assert_eq(map.dock_cells.size(), 4)
	assert_eq(map.road_cells.size(), 16)
	assert_true(map.existing_cells.is_empty())
	assert_eq(map.district_by_cell.size(), 48)
	assert_eq(map.district_by_cell[Vector2i(0, 1)], &"whitechapel")
	assert_eq(map.district_names, {&"whitechapel": "Whitechapel"} as Dictionary[StringName, String])
	assert_eq(map.zones[&"all"], [Vector2i(0, 1), Vector2i(1, 1)])


# Until task 4 every district without a source drinks the neutral water (D-088).
func test_a_district_without_water_source_is_neutral() -> void:
	var map: MapDef = _map()
	if map == null:
		return
	assert_eq(map.district_water_sources[&"whitechapel"], MapDef.DEFAULT_WATER_SOURCE)


func test_a_water_source_must_be_a_source_of_the_events_data() -> void:
	_documents[GRID]["districts"][0]["water_source"] = "old_ford"
	assert_eq(_map().district_water_sources[&"whitechapel"], &"old_ford")
	_documents[GRID]["districts"][0]["water_source"] = "nowhere"
	_assert_invalid("maps/grid_test.json.districts: whitechapel has an unknown water_source nowhere")


# Issue #209: a district drinks from neutral, old_ford or lea_bridge; another section with a source_risk, like the
# well's, is no district source.
func test_a_district_may_drink_from_lea_bridge_but_not_from_a_well() -> void:
	_documents[GRID]["districts"][0]["water_source"] = "lea_bridge"
	assert_eq(_map().district_water_sources[&"whitechapel"], &"lea_bridge")
	_documents[GRID]["districts"][0]["water_source"] = "well"
	_assert_invalid("maps/grid_test.json.districts: whitechapel has an unknown water_source well")


func test_buildable_land_touching_a_street_loads() -> void:
	assert_true(_load().is_ok(), str(_load().errors))


# No buildable land without street access (D-079): the right half of row 1 and the south-east block are cut off.
func test_a_buildable_island_without_a_street_is_rejected() -> void:
	_documents[GRID]["cells"][2] = "####DDDD"
	_documents[GRID]["cells"][3] = "####DDDD"
	_assert_invalid("maps/grid_test.json.cells: buildable land at [5, 1] has no street on any side")
	_assert_invalid("maps/grid_test.json.cells: buildable land at [4, 4] has no street on any side")


# Stairs touch the street but are no street for the access (issue #61, approved 2026-10-23).
func test_stairs_give_no_street_access() -> void:
	_documents[GRID]["cells"][2] = "####DsDD"
	_documents[GRID]["cells"][3] = "####DDDD"
	_assert_invalid("maps/grid_test.json.cells: buildable land at [5, 1] has no street on any side")


func test_too_little_riverside_buildable_land_is_rejected() -> void:
	_documents["economy/map.json"][FLOOR_KEY] = RIVERSIDE + 1
	_assert_invalid("maps/grid_test.json.cells: %d buildable cells beside the river, map.%s is %d"
		% [RIVERSIDE, FLOOR_KEY, RIVERSIDE + 1])


# Only a side on a river cell counts: neither stairs nor dock basins are the river (approved 2026-10-23).
func test_land_beside_a_dock_is_not_riverside() -> void:
	_documents[GRID]["cells"][0] = "~~~~DDDD"
	_documents["economy/map.json"][FLOOR_KEY] = 4
	assert_true(_load().is_ok(), str(_load().errors))
	_documents["economy/map.json"][FLOOR_KEY] = 5
	_assert_invalid("maps/grid_test.json.cells: 4 buildable cells beside the river")


func test_a_buildable_cell_without_district_is_rejected() -> void:
	_set_cell("cells", Vector2i(0, 0), ".")
	_set_cell("district_by_cell", Vector2i(0, 0), MapDef.NO_DISTRICT)
	_assert_invalid("maps/grid_test.json.district_by_cell: buildable cell [0, 0] has no district")


func test_water_may_have_no_district() -> void:
	_set_cell("district_by_cell", Vector2i(0, 0), MapDef.NO_DISTRICT)
	assert_true(_load().is_ok(), str(_load().errors))


func test_an_unknown_district_symbol_is_rejected() -> void:
	_set_cell("district_by_cell", Vector2i(3, 3), "X")
	_assert_invalid("maps/grid_test.json.district_by_cell: [3, 3] has unknown district X")


func test_districts_need_an_id_a_name_and_one_symbol() -> void:
	_documents[GRID]["districts"].append({"id": "whitechapel", "name": "Again", "symbol": "A"})
	_assert_invalid("maps/grid_test.json.districts: duplicate district whitechapel")
	before_each()
	_documents[GRID]["districts"][0]["name"] = ""
	_assert_invalid("maps/grid_test.json.districts: expected id, name and a one-character symbol")
	before_each()
	_documents[GRID]["districts"][0]["symbol"] = MapDef.NO_DISTRICT
	_assert_invalid("maps/grid_test.json.districts: expected id, name and a one-character symbol")


func test_a_malformed_size_is_rejected() -> void:
	for size: Variant in [[8], [8, 0], [8.5, 6], "8x6", [8, 6, 1]]:
		before_each()
		_documents[GRID]["size"] = size
		_assert_invalid("maps/grid_test.json.size: expected [width, height] of positive whole numbers")


func test_rows_that_do_not_match_the_size_are_rejected() -> void:
	_documents[GRID]["size"] = [9, 6]
	_assert_invalid("maps/grid_test.json.cells: expected 6 rows of 9 cells")
	_assert_invalid("maps/grid_test.json.district_by_cell: expected 6 rows of 9 cells")
	before_each()
	_documents[GRID]["size"] = [8, 7]
	_assert_invalid("maps/grid_test.json.cells: expected 7 rows of 8 cells")


func test_an_unknown_cell_type_is_rejected() -> void:
	_set_cell("cells", Vector2i(6, 5), "?")
	_assert_invalid("maps/grid_test.json.cells: [6, 5] has unknown cell type ?")


# Every map is 25 m a cell (D-086): a map cannot bring its own scale.
func test_a_cell_size_other_than_the_economy_one_is_rejected() -> void:
	_documents[GRID]["cell_size_m"] = int(_documents["economy/map.json"]["cell_size_m"]) * 2
	_assert_invalid("maps/grid_test.json.cell_size_m: must be map.cell_size_m")


func test_the_coordinate_layers_do_not_mix_with_cell_types() -> void:
	_documents[GRID]["river_cells"] = [[0, 0]]
	_assert_invalid("maps/grid_test.json.river_cells: unknown field")


func test_street_cells_are_whole_pieces() -> void:
	_set_cell("cells", Vector2i(0, 2), ".")
	_assert_invalid("maps/grid_test.json.cells: [1, 2] is not part of a whole street piece")


func test_overlapping_zones_are_rejected() -> void:
	_documents[GRID]["zones"].append({"id": "more", "cells": [[1, 1]]})
	_assert_invalid("maps/grid_test.json.zones.more: out of bounds or duplicate cell")
	before_each()
	_documents[GRID]["zones"].append({"id": "all", "cells": [[2, 1]]})
	_assert_invalid("maps/grid_test.json.zones: expected zones with a unique id and cells")


# Stairs are not buildable (issue #61, approved 2026-10-23); a wharf still needs the river.
func test_nothing_is_built_on_stairs() -> void:
	var map: MapDef = _map()
	if map == null:
		return
	var context: EconomyContext = EconomyContext.new(_load().catalog, map)
	for id: StringName in [&"housing", &"mill", &"bakery"]:
		assert_eq(context.terrain_placement_reason(id, Vector2i(4, 1)), &"requires_land", id)
	assert_eq(context.terrain_placement_reason(&"wharf", Vector2i(4, 1)), &"requires_river")
	assert_eq(context.copy().map.stairs_cells, map.stairs_cells)
	assert_eq(context.copy().map.district_by_cell, map.district_by_cell)


# The two maps the game already has keep their format and gain nothing (issue #61).
func test_the_old_maps_have_no_districts_zones_or_stairs() -> void:
	_documents.erase(GRID)
	var result: DataLoadResult = _load()
	assert_true(result.is_ok(), str(result.errors))
	if not result.is_ok():
		return
	for id: StringName in [&"riverside_strip", &"whitechapel_1850s"]:
		var map: MapDef = result.catalog.maps[id]
		assert_true(map.stairs_cells.is_empty(), id)
		assert_true(map.district_by_cell.is_empty(), id)
		assert_true(map.district_names.is_empty(), id)
		assert_true(map.zones.is_empty(), id)


func test_the_riverside_floor_and_the_open_zones_are_data() -> void:
	_documents.erase(GRID)
	_documents["economy/map.json"].erase(FLOOR_KEY)
	_assert_invalid("economy/map.json.%s: missing field" % FLOOR_KEY)
	before_each()
	_documents["economy/zones.json"]["all_unlocked"] = 1
	_assert_invalid("economy/zones.json.all_unlocked: expected a boolean")
