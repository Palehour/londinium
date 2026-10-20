extends GutTest

# Issue #152, option A of Cristian (2026-10-18): on the traced strip of Wapping the water, the streets and the historic
# anchors are fixed. Pier Head is the starting dense housing (D-079) and Oliver's Wharf a working wharf; St John's,
# St Peter's and the Town of Ramsgate stand with no use; the Thames Police station and Wapping Old Stairs are named
# sites with no building. No anchor is ever demolished.
# Issue #186 (D-086): cells of 25 m. Each old cell (x, y) is its block from (2x, 2y), an anchor with a use covers the
# footprint of its building and the floor of free land is 176 cells of 25 m (44 of 50 m).

const STRIP: StringName = &"riverside_strip"
const PIER_HEAD: Vector2i = Vector2i(16, 12)
# The warehouse is at (16,14), but no street reaches the river there: the wharf stands on the nearest river cell beside
# one, Well Alley, the rule Cristian set for Pier Head (2026-10-18).
const OLIVERS_WHARF: Vector2i = Vector2i(20, 16)
const ST_JOHNS: Vector2i = Vector2i(18, 10)
const THAMES_POLICE: Vector2i = Vector2i(24, 14)
# The corner of sheet VII.77, which has no 1862-74 edition (option A of 2026-10-18), as Mason counted it.
const NO_SHEET_CORNER: Rect2i = Rect2i(0, 0, 12, 8)
# Criterion approved by Cristian (2026-10-18): at least this many free cells, counting the anchors with a use. D-086
# writes it as a surface: 176 cells of 25 m, the 44 of 50 m.
const FREE_FLOOR: int = 176

var _catalog: DataCatalog
var _strip: EconomyContext


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_strip = EconomyContext.new(_catalog, _catalog.maps[STRIP])


func _new_game(params: Params) -> Simulation:
	var state: EconomyState = EconomyState.new()
	state.money = int(params.get_value(&"startup.money"))
	state.population = int(params.get_value(&"startup.population"))
	return Simulation.create_new(params, state, 42, _strip)


func _building_at(sim: Simulation, cell: Vector2i) -> Dictionary:
	for building: Dictionary in sim.snapshot()["economy"]["buildings"]:
		if building["cell"] == [cell.x, cell.y]:
			return building
	return {}


func _free_cells(map: MapDef, outside: Rect2i = Rect2i()) -> int:
	var used: Array[Vector2i] = []
	for anchor: Vector2i in map.anchors:
		if map.anchors[anchor] != &"":
			used.append_array(EconomyContext.cells_of(Rect2i(anchor, _catalog.buildings[map.anchors[anchor]].footprint)))
	var count: int = 0
	for y: int in range(map.height):
		for x: int in range(map.width):
			var cell: Vector2i = Vector2i(x, y)
			if outside.has_point(cell):
				continue
			if cell in used:
				count += 1
			elif cell not in map.river_cells and cell not in map.dock_cells and cell not in map.road_cells \
					and cell not in map.existing_cells:
				count += 1
	return count


func test_the_strip_lists_its_anchors_and_named_sites_with_their_source() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	assert_eq(map.anchors.get(PIER_HEAD), &"dense_housing")
	assert_eq(map.anchors.get(OLIVERS_WHARF), &"wharf")
	assert_eq(map.anchors.values().count(&""), 3, "St John's, St Peter's and the Town of Ramsgate have no use")
	assert_eq(map.named_sites.size(), 2)
	assert_eq(map.named_sites.get(THAMES_POLICE), "Thames Police Station")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/riverside_strip.json"))
	var entries: Array = raw["anchors"] + raw["named_sites"]
	for entry: Dictionary in entries:
		assert_false(str(entry["name"]).is_empty())
		assert_string_contains(str(entry["source"]), "NLS", entry["name"])
		assert_true(MapDef.is_history_note(entry["history"]), "%s has Chronicler's tag" % entry["name"])
	var notes: String = "\n".join(raw["history_notes"])
	assert_string_contains(notes, "[DEBATED] The Thames", "The OHM river has no date")
	assert_string_contains(notes, "[INVENTED] The Wapping lock", "The basin stays closed at this scale")


func test_there_are_enough_free_cells_with_and_without_the_corner_with_no_sheet() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	assert_gte(_free_cells(map), FREE_FLOOR, "Total")
	assert_gte(_free_cells(map, NO_SHEET_CORNER), FREE_FLOOR, "Without the north-west corner")


func test_olivers_wharf_stands_established_and_working_at_the_start() -> void:
	var sim: Simulation = _new_game(SimTestParams.isolated_params(_catalog))
	var wharf: Dictionary = _building_at(sim, OLIVERS_WHARF)
	assert_eq(StringName(wharf.get("definition_id", &"")), &"wharf")
	assert_false(wharf.has("built_at"), "Established: no correction window (D-029)")
	assert_eq(StringName(_building_at(sim, PIER_HEAD).get("definition_id", &"")), &"dense_housing")
	for _second: int in range(120):
		sim.tick()
	assert_gt(int(_building_at(sim, OLIVERS_WHARF).get("workers", 0)), 0, "It hires like any wharf")


# Mason's criterion for D-084: every anchor the map lists, with or without a use, refuses a demolish and pays nothing.
func test_every_anchor_of_the_map_is_never_demolished() -> void:
	var anchors: Dictionary[Vector2i, StringName] = _catalog.maps[STRIP].anchors
	assert_eq(anchors.size(), 5, "Pier Head, Oliver's Wharf, St John's, St Peter's and the Town of Ramsgate")
	for cell: Vector2i in anchors:
		var sim: Simulation = _new_game(SimTestParams.isolated_params(_catalog))
		var kept: Simulation = _new_game(SimTestParams.isolated_params(_catalog))
		var command: DemolishCommand = DemolishCommand.new(cell)
		sim.apply_command(command)
		sim.tick()
		kept.tick()
		assert_false(command.accepted, str(cell))
		assert_eq(command.reason, &"historic_anchor", str(cell))
		assert_eq(StringName(_building_at(sim, cell).get("definition_id", &"")), anchors[cell], str(cell))
		assert_eq(sim.snapshot()["economy"]["money"], kept.snapshot()["economy"]["money"], "No refund %s" % cell)


func test_an_anchor_with_no_use_is_neither_demolished_nor_built_over() -> void:
	var sim: Simulation = _new_game(SimTestParams.isolated_params(_catalog))
	var demolish: DemolishCommand = DemolishCommand.new(ST_JOHNS)
	sim.apply_command(demolish)
	sim.tick()
	assert_false(demolish.accepted)
	assert_eq(demolish.reason, &"historic_anchor")
	var build: BuildCommand = BuildCommand.new(_strip, &"housing", ST_JOHNS)
	sim.apply_command(build)
	sim.tick()
	assert_false(build.accepted)
	assert_eq(build.reason, &"existing_building")


func test_a_named_site_does_not_block_building() -> void:
	assert_eq(_strip.terrain_placement_reason(&"housing", THAMES_POLICE), &"")
