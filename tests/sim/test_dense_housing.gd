extends GutTest

# Issue #154: the standing buildings of the riverside strip. D-075: one full dense housing at the start, the rest of
# existing_cells is a block. D-076: a saved building on a blocked cell stays and works. D-079: the starting house
# stands beside a historical street. Issue #152 (option A of Cristian, 2026-10-18): on the traced strip the starting
# house is the Pier Head anchor, which is never demolished.
# Issue #186 (D-086): the cells below are the corners (2x, 2y) of the 2x2 blocks of the old cells of 50 m.

const STRIP: StringName = &"riverside_strip"
const SMALL: StringName = &"whitechapel_1850s"
const DENSE: StringName = &"dense_housing"
# Pier Head (issue #152): its own cell (6,6) has no street on any side, so it stands on the nearest lot beside one,
# Green Bank.
const START_CELL: Vector2i = Vector2i(16, 12)
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
# Base capacity of a dense housing (D-075). Since issue #180 (D-085) the four empty 1870 houses add theirs too.
const DENSE_CAPACITY: int = 20

var _catalog: DataCatalog
var _strip: EconomyContext


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_strip = EconomyContext.new(_catalog, _catalog.maps[STRIP])


func _params(modifiers: Array[Modifier] = []) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign(modifiers)
	return Params.new(_catalog, role)


func _startup_state(params: Params) -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.money = int(params.get_value(&"startup.money"))
	state.population = int(params.get_value(&"startup.population"))
	return state


func _new_game(params: Params, context: EconomyContext = _strip) -> Simulation:
	return Simulation.create_new(params, _startup_state(params), 42, context)


func _buildings_of(sim: Simulation, id: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for building: Dictionary in sim.snapshot()["economy"]["buildings"]:
		if StringName(building["definition_id"]) == id:
			found.append(building)
	return found


# The dense housing of startup.dense_housing_occupied (D-075), without the 1870 houses of D-085.
func _start_houses(sim: Simulation) -> Array[Dictionary]:
	return _buildings_of(sim, DENSE).filter(func(building: Dictionary) -> bool:
		return _cell_of(building) not in _catalog.maps[STRIP].period_houses)


func _cell_of(building: Dictionary) -> Vector2i:
	return Vector2i(int(building["cell"][0]), int(building["cell"][1]))


func _build(sim: Simulation, context: EconomyContext, id: StringName, cell: Vector2i) -> BuildCommand:
	var command: BuildCommand = BuildCommand.new(context, id, cell)
	sim.apply_command(command)
	sim.tick()
	return command


func test_new_game_on_the_strip_starts_with_one_full_dense_housing() -> void:
	var sim: Simulation = _new_game(_params())
	var houses: Array[Dictionary] = _start_houses(sim)
	var period_houses: int = _catalog.maps[STRIP].period_houses.size()
	assert_eq(houses.size(), 1)
	assert_eq(sim.snapshot()["economy"]["buildings"].size(), 2 + period_houses,
		"Only the anchors and the 1870 houses (D-085) stand at the start")
	assert_eq(_buildings_of(sim, &"wharf").size(), 1, "Oliver's Wharf, the other anchor with a use (#152)")
	if houses.is_empty():
		return
	assert_eq(_cell_of(houses[0]), START_CELL)
	sim.tick()
	var economy: Dictionary = sim.snapshot()["economy"]
	assert_eq(economy["population"], 20)
	assert_eq(economy["housing_capacity"], DENSE_CAPACITY * (1 + period_houses),
		"Pier Head full with the 20 people of startup.json; the 1870 houses empty (D-085)")
	assert_eq(economy["overcrowding"], 0.0)


func test_the_start_cell_is_a_standing_building_beside_a_historical_street() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	assert_false(map.dense_housing_cells.is_empty())
	for cell: Vector2i in map.dense_housing_cells:
		assert_true(cell in map.existing_cells, str(cell))
		var beside_street: bool = false
		for side: Vector2i in SIDES:
			beside_street = beside_street or (cell + side) in map.road_cells
		assert_true(beside_street, "%s has a street on one side (D-079)" % cell)


func test_the_occupied_knob_sets_how_many_houses_start() -> void:
	assert_eq(_params().get_value(&"startup.dense_housing_occupied"), 1)
	var none: Simulation = _new_game(_params([Modifier.new(&"startup.dense_housing_occupied", &"set", 0)]))
	assert_true(_start_houses(none).is_empty())
	var more: Simulation = _new_game(_params([Modifier.new(&"startup.dense_housing_occupied", &"set", 5)]))
	assert_eq(_start_houses(more).size(), _catalog.maps[STRIP].dense_housing_cells.size(),
		"Never more houses than the map lists")


func test_the_small_map_starts_empty() -> void:
	var small: EconomyContext = EconomyContext.new(_catalog, _catalog.maps[SMALL])
	assert_true(_new_game(_params(), small).snapshot()["economy"]["buildings"].is_empty(), "Parity of the 8x8 (D-074)")


func test_the_rest_of_the_standing_buildings_block_building() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	var taken: Array = _new_game(_params()).snapshot()["economy"]["buildings"]
	for cell: Vector2i in map.existing_cells:
		# A footprint that would cover a building of the start is refused for that first (D-086).
		if taken.any(func(building: Dictionary) -> bool:
				return _strip.area_of(building).intersects(Rect2i(cell, _strip.buildings[&"housing"].footprint))):
			continue
		for id: StringName in [&"housing", &"bakery", &"mill"]:
			var sim: Simulation = _new_game(_params())
			var command: BuildCommand = _build(sim, _strip, id, cell)
			assert_false(command.accepted, "%s %s" % [id, cell])
			assert_eq(command.reason, &"existing_building", "%s %s" % [id, cell])


func test_dense_housing_is_not_built_by_the_player() -> void:
	var sim: Simulation = _new_game(_params())
	var command: BuildCommand = _build(sim, _strip, DENSE, Vector2i(2, 2))
	assert_false(command.accepted)
	assert_eq(command.reason, &"not_buildable")
	assert_eq(_strip.building_unavailable_reason(DENSE), &"not_buildable")


# Issue #152 (option A of Cristian, 2026-10-18): no anchor is demolished, so the starting house of Pier Head refunds
# nothing; until #152 it refunded half its cost (D-029, D-075).
func test_the_dense_housing_of_pier_head_is_not_demolished() -> void:
	# Without taxes, wages or upkeep, a refund would be the only money that differs from a game that keeps the house.
	var params: Params = SimTestParams.isolated_params(_catalog)
	var kept: Simulation = _new_game(params)
	var sim: Simulation = _new_game(params)
	var command: DemolishCommand = DemolishCommand.new(START_CELL)
	sim.apply_command(command)
	sim.tick()
	kept.tick()
	assert_false(command.accepted)
	assert_eq(command.reason, &"historic_anchor")
	assert_eq(_start_houses(sim).size(), 1)
	assert_eq(sim.snapshot()["economy"]["money"], kept.snapshot()["economy"]["money"], "No refund")
	var over: BuildCommand = _build(sim, _strip, &"housing", START_CELL)
	assert_false(over.accepted)
	assert_eq(over.reason, &"occupied_cell", "The house is still there")


# Mason's required test (D-076): a game saved with a building on a cell that is now blocked keeps it, working; the
# blocked cell only stops something new from being built there, even after the old building is demolished.
# Both cells have a street beside them, the access every building needs on the strip (D-080, D-079).
func test_a_saved_building_on_a_blocked_cell_stays_and_works() -> void:
	var params: Params = SimTestParams.isolated_params(_catalog)
	# St Peter's and St John's (issue #152): the standing buildings beside a street that are not the starting house.
	var bakery_cell: Vector2i = Vector2i(26, 0)
	var housing_cell: Vector2i = Vector2i(18, 10)
	var saved: Dictionary = _new_game(params).to_save()
	var state: EconomyState = EconomyState.from_dict(saved["economy"])
	state.buildings.append({"definition_id": &"bakery", "cell": [bakery_cell.x, bakery_cell.y]})
	state.buildings.append({"definition_id": &"housing", "cell": [housing_cell.x, housing_cell.y]})
	state.stocks[&"flour"] = 100
	saved["economy"] = state.to_dict()
	var sim: Simulation = Simulation.from_save(params, _strip, [], bytes_to_var(var_to_bytes(saved)))
	var bread_before: int = sim.snapshot()["economy"]["stocks"][&"bread"]
	for _second: int in range(120):
		sim.tick()
	var economy: Dictionary = sim.snapshot()["economy"]
	assert_eq(_buildings_of(sim, &"bakery").size(), 1, "The saved bakery is still there")
	assert_gt(economy["stocks"][&"bread"], bread_before, "and still bakes")
	assert_eq(economy["housing_capacity"], 40 + DENSE_CAPACITY * _catalog.maps[STRIP].period_houses.size(),
		"The saved housing still counts: 20 dense + 20, beside the 1870 houses (D-085)")
	var occupied: BuildCommand = _build(sim, _strip, &"mill", bakery_cell)
	assert_false(occupied.accepted)
	sim.apply_command(DemolishCommand.new(bakery_cell))
	sim.tick()
	var blocked: BuildCommand = _build(sim, _strip, &"mill", bakery_cell)
	assert_false(blocked.accepted)
	assert_eq(blocked.reason, &"existing_building")


# Issue #180 (D-085): the four 1870 houses of D-083 stand from the start as dense housing, empty, and like the anchors
# of D-084 they are never demolished nor refunded.
func test_the_period_houses_stand_empty_and_are_never_demolished() -> void:
	var params: Params = SimTestParams.isolated_params(_catalog)
	var map: MapDef = _catalog.maps[STRIP]
	assert_eq(map.period_houses.size(), 4)
	var kept: Simulation = _new_game(params)
	var sim: Simulation = _new_game(params)
	for cell: Vector2i in map.period_houses:
		var houses: Array[Dictionary] = _buildings_of(sim, DENSE).filter(
			func(building: Dictionary) -> bool: return _cell_of(building) == cell)
		assert_eq(houses.size(), 1, "A dense housing stands on %s" % cell)
		var command: DemolishCommand = DemolishCommand.new(cell)
		sim.apply_command(command)
		sim.tick()
		kept.tick()
		assert_false(command.accepted, str(cell))
		assert_eq(command.reason, &"historic_anchor", "The same reason as the anchors (%s)" % cell)
	var economy: Dictionary = sim.snapshot()["economy"]
	assert_eq(_buildings_of(sim, DENSE).size(), 1 + map.period_houses.size(), "Pier Head and the four houses")
	assert_eq(economy["money"], kept.snapshot()["economy"]["money"], "No refund")
	assert_eq(economy["population"], int(params.get_value(&"startup.population")),
		"The houses start with nobody: the people are the ones of startup.json, all in Pier Head")
