extends GutTest

# Issue #88, task 1: the terrain data. What draining a marsh costs and how much more turning firm ground into riverbank
# costs (D-150, values [INVENTED]), and the terrain each building may stand on (D-149): the wharf on the riverbank, the
# mill and the malthouse on either, everything else on firm ground.

const BUILDINGS: String = "economy/buildings.json"
const TERRAIN: String = "economy/terrain.json"
const RIVERBANK_BUILDINGS: Array[StringName] = [&"wharf", &"mill", &"malthouse"]

var _documents: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "services"]:
		for name: String in DirAccess.open("res://data/" + folder).get_files():
			if name.ends_with(".json"):
				var path: String = folder.path_join(name)
				_documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))


func _load() -> DataLoadResult:
	var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(loaded.is_ok(), str(loaded.errors))
	return loaded


func _assert_invalid(message: String) -> void:
	var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_false(loaded.is_ok())
	assert_string_contains("\n".join(loaded.errors), message)


func test_terrain_costs_exist_with_their_first_values() -> void:
	var loaded: DataLoadResult = _load()
	if not loaded.is_ok():
		return
	var params: Params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
	assert_eq(params.get_value(&"terrain.drain_cost"), 60)
	assert_eq(float(params.get_value(&"terrain.riverbank_cost_mult")), 2.0)


func test_terrain_costs_are_required_and_validated() -> void:
	_documents[TERRAIN].erase("drain_cost")
	_assert_invalid("%s.drain_cost: missing field" % TERRAIN)
	before_each()
	_documents[TERRAIN]["drain_cost"] = -5
	_assert_invalid("%s.drain_cost: invalid money value" % TERRAIN)
	before_each()
	_documents[TERRAIN]["drain_cost"] = 1.5
	_assert_invalid("%s.drain_cost: invalid money value" % TERRAIN)
	before_each()
	_documents[TERRAIN]["riverbank_cost_mult"] = 0
	_assert_invalid("%s.riverbank_cost_mult: invalid positive value" % TERRAIN)
	before_each()
	_documents.erase(TERRAIN)
	_assert_invalid("%s: missing file" % TERRAIN)


func test_buildings_allowed_terrain_follows_d149() -> void:
	var loaded: DataLoadResult = _load()
	if not loaded.is_ok():
		return
	var buildings: Dictionary = loaded.catalog.buildings
	assert_eq(buildings[&"wharf"].allowed_terrain, [&"riverbank"] as Array[StringName])
	for id: StringName in [&"mill", &"malthouse"]:
		assert_eq(buildings[id].allowed_terrain, [&"firm", &"riverbank"] as Array[StringName], id)
	for id: StringName in buildings:
		if id not in RIVERBANK_BUILDINGS:
			assert_eq(buildings[id].allowed_terrain, [&"firm"] as Array[StringName], id)


# Every building of data/ names its terrain, so the list reads without knowing the default.
func test_every_building_of_the_data_names_its_terrain() -> void:
	for id: String in _documents[BUILDINGS]:
		assert_true(_documents[BUILDINGS][id].has("terrain"), id)


func test_allowed_terrain_rejects_bad_labels() -> void:
	var cases: Dictionary[String, Variant] = {
		"expected an array": "firm",
		"expected at least one terrain": [],
		"unknown terrain swamp": ["swamp"],
		"duplicate terrain firm": ["firm", "firm"],
		# Nothing is built on a marsh until it is drained (D-136).
		"nothing is built on marsh": ["marsh"],
	}
	for message: String in cases:
		before_each()
		_documents[BUILDINGS]["bakery"]["terrain"] = cases[message]
		_assert_invalid("%s.bakery.terrain: %s" % [BUILDINGS, message])


func test_allowed_terrain_defaults_to_firm() -> void:
	_documents[BUILDINGS]["bakery"].erase("terrain")
	var loaded: DataLoadResult = _load()
	if loaded.is_ok():
		assert_eq(loaded.catalog.buildings[&"bakery"].allowed_terrain, [&"firm"] as Array[StringName])


# Task 3 (D-152): each cell of the wharf's footprint names its own terrain, row by row from the north-west corner.
func test_the_wharf_mask_puts_the_riverbank_north_and_the_river_south() -> void:
	var loaded: DataLoadResult = _load()
	if not loaded.is_ok():
		return
	var wharf: BuildingDef = loaded.catalog.buildings[&"wharf"]
	assert_eq(wharf.terrain_mask, [&"riverbank", &"riverbank", &"river", &"river"] as Array[StringName])
	for id: StringName in loaded.catalog.buildings:
		if id != &"wharf":
			assert_true(loaded.catalog.buildings[id].terrain_mask.is_empty(), id)


func test_terrain_mask_follows_the_footprint_and_the_building_terrains() -> void:
	var cases: Dictionary[String, Variant] = {
		"expected 2 rows of 2 cells": [["riverbank", "riverbank"]],
		"firm is neither the river nor a terrain of the building": [["firm", "riverbank"], ["river", "river"]],
		"marsh is neither the river nor a terrain of the building": [["marsh", "riverbank"], ["river", "river"]],
	}
	for message: String in cases:
		before_each()
		_documents[BUILDINGS]["wharf"]["terrain_mask"] = cases[message]
		_assert_invalid("%s.wharf.terrain_mask: %s" % [BUILDINGS, message])


# A map drawn as rows of text marks the riverbank with "r": buildable land with its label.
func test_the_full_map_has_riverbank_beside_the_river() -> void:
	var loaded: DataLoadResult = _load()
	if not loaded.is_ok():
		return
	var map: MapDef = loaded.catalog.maps[&"whitechapel_full"]
	var riverbank: Array[Vector2i] = []
	for cell: Vector2i in map.terrain:
		if map.terrain[cell] == &"riverbank":
			riverbank.append(cell)
	assert_false(riverbank.is_empty())
	for cell: Vector2i in riverbank:
		assert_false(cell in map.river_cells or cell in map.dock_cells or cell in map.road_cells, str(cell))
	var context: EconomyContext = EconomyContext.new(loaded.catalog, map)
	assert_eq(context.building_unavailable_reason(&"wharf"), &"")
