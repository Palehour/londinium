extends GutTest

# Issue #176 (D-083, task 1 of Mason's breakdown of #171): the free land of the Wapping strip is drawn as 1870 lots,
# four 1870 houses stand on the north-west street stub (4,4)-(4,5) as plain dense housing that is never demolished,
# and one damaged wharf waits on the river. The houses start empty (Cristian, 2026-10-18): the people of the startup
# do not change. Repairing the wharf is #177.

const STRIP: StringName = &"riverside_strip"
const HOUSES: Array[Vector2i] = [Vector2i(4, 3), Vector2i(3, 4), Vector2i(5, 4), Vector2i(5, 5)]
const DAMAGED_WHARF: Vector2i = Vector2i(14, 7)
# The count of #152, which D-083 keeps: free cells in total and without the corner with no sheet (VII.77).
const FREE_TOTAL: int = 65
const FREE_WITHOUT_CORNER: int = 47
const NO_SHEET_CORNER: Rect2i = Rect2i(0, 0, 6, 4)

var _catalog: DataCatalog
var _strip: EconomyContext
var _raw: Dictionary


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_strip = EconomyContext.new(_catalog, _catalog.maps[STRIP])
	_raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/riverside_strip.json"))


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


# Mason's count of #152: an anchor with a use counts as free, like any other cell nothing blocks.
func _free_cells(map: MapDef, outside: Rect2i = Rect2i()) -> int:
	var count: int = 0
	for y: int in range(map.height):
		for x: int in range(map.width):
			var cell: Vector2i = Vector2i(x, y)
			if outside.has_point(cell):
				continue
			if map.anchors.get(cell, &"") != &"":
				count += 1
			elif cell not in map.river_cells and cell not in map.dock_cells and cell not in map.road_cells \
					and cell not in map.existing_cells:
				count += 1
	return count


func test_the_strip_lists_four_invented_period_houses_beside_a_street() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	assert_eq(map.period_houses, HOUSES)
	for cell: Vector2i in HOUSES:
		assert_true(cell in map.existing_cells, "%s is a standing building" % cell)
		assert_true(map.beside_road(cell), "%s has a street on one side (D-079)" % cell)
		assert_eq(map.anchors.get(cell), Simulation.DENSE_HOUSING, "%s carries the anchor mark (D-084)" % cell)
	assert_eq(_raw["period_houses"].size(), HOUSES.size())
	for entry: Dictionary in _raw["period_houses"]:
		assert_string_starts_with(str(entry["history"]), "[INVENTED]", str(entry["cell"]))
		assert_false(entry.has("building"), "Always dense housing: the field would be a second source")


func test_period_houses_stand_empty_at_the_start_as_plain_dense_housing() -> void:
	var params: Params = SimTestParams.isolated_params(_catalog)
	var sim: Simulation = _new_game(params)
	var pier_head: Dictionary = _building_at(sim, Vector2i(8, 6))
	for cell: Vector2i in HOUSES:
		var house: Dictionary = _building_at(sim, cell)
		assert_eq(StringName(house.get("definition_id", &"")), Simulation.DENSE_HOUSING, str(cell))
		assert_false(house.has("built_at"), "Established: no correction window (D-029) %s" % cell)
		assert_eq(house.keys(), pier_head.keys(), "No field of its own, such as a level %s" % cell)
	assert_eq(sim.snapshot()["economy"]["population"], int(params.get_value(&"startup.population")),
		"They start empty: the people of the startup do not change")


func test_period_houses_are_never_demolished_and_pay_nothing() -> void:
	for cell: Vector2i in HOUSES:
		var sim: Simulation = _new_game(SimTestParams.isolated_params(_catalog))
		var kept: Simulation = _new_game(SimTestParams.isolated_params(_catalog))
		var command: DemolishCommand = DemolishCommand.new(cell)
		sim.apply_command(command)
		sim.tick()
		kept.tick()
		assert_false(command.accepted, str(cell))
		assert_eq(command.reason, &"historic_anchor", str(cell))
		assert_eq(StringName(_building_at(sim, cell).get("definition_id", &"")), Simulation.DENSE_HOUSING, str(cell))
		assert_eq(sim.snapshot()["economy"]["money"], kept.snapshot()["economy"]["money"], "No refund %s" % cell)


func test_the_damaged_wharf_is_an_invented_river_cell_with_its_repair_ratio() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	assert_eq(map.damaged_wharves.keys(), [DAMAGED_WHARF])
	assert_true(DAMAGED_WHARF in map.river_cells, "Water, like the cell of a wharf")
	assert_true(map.beside_road(DAMAGED_WHARF), "A wharf works only beside a street")
	assert_false(map.anchors.has(DAMAGED_WHARF), "Nothing stands there yet")
	var entry: Dictionary = _raw["damaged_wharves"][0]
	assert_eq(map.damaged_wharves[DAMAGED_WHARF], float(entry["repair_cost_ratio"]), "Read from the map's data")
	assert_string_starts_with(str(entry["history"]), "[INVENTED]")


func test_every_free_cell_has_one_lot_style_and_nothing_else_has_one() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	for y: int in range(map.height):
		for x: int in range(map.width):
			var cell: Vector2i = Vector2i(x, y)
			var free: bool = cell not in map.river_cells and cell not in map.dock_cells \
					and cell not in map.road_cells and cell not in map.existing_cells
			assert_eq(map.lot_styles.has(cell), free, str(cell))
	assert_eq(map.lot_styles.size(), _raw["lot_styles"].values().reduce(
		func(total: int, cells: Array) -> int: return total + cells.size(), 0), "Each cell listed once")
	assert_string_contains("\n".join(_raw["history_notes"]), "[INVENTED] Lot styles")


func test_the_free_cell_count_is_the_same_as_in_152() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	assert_eq(_free_cells(map), FREE_TOTAL, "Total")
	assert_eq(_free_cells(map, NO_SHEET_CORNER), FREE_WITHOUT_CORNER, "Without the north-west corner")
