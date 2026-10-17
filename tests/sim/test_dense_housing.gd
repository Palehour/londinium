extends GutTest

# Issue #154: the standing buildings of the riverside strip. D-075: one full dense housing at the start, the rest of
# existing_cells is a block until the tracing of #152. D-076: a saved building on a blocked cell stays and works.
# D-079: the starting house stands beside a historical street.

const STRIP: StringName = &"riverside_strip"
const SMALL: StringName = &"whitechapel_1850s"
const DENSE: StringName = &"dense_housing"
const START_CELL: Vector2i = Vector2i(4, 5)
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

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


func _cell_of(building: Dictionary) -> Vector2i:
	return Vector2i(int(building["cell"][0]), int(building["cell"][1]))


func _build(sim: Simulation, context: EconomyContext, id: StringName, cell: Vector2i) -> BuildCommand:
	var command: BuildCommand = BuildCommand.new(context, id, cell)
	sim.apply_command(command)
	sim.tick()
	return command


func test_new_game_on_the_strip_starts_with_one_full_dense_housing() -> void:
	var sim: Simulation = _new_game(_params())
	var houses: Array[Dictionary] = _buildings_of(sim, DENSE)
	assert_eq(houses.size(), 1)
	assert_eq(sim.snapshot()["economy"]["buildings"].size(), 1, "Nothing else stands at the start")
	if houses.is_empty():
		return
	assert_eq(_cell_of(houses[0]), START_CELL)
	sim.tick()
	var economy: Dictionary = sim.snapshot()["economy"]
	assert_eq(economy["population"], 20)
	assert_eq(economy["housing_capacity"], 20, "Full with the 20 people of startup.json")
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
	assert_true(_buildings_of(none, DENSE).is_empty())
	var more: Simulation = _new_game(_params([Modifier.new(&"startup.dense_housing_occupied", &"set", 5)]))
	assert_eq(_buildings_of(more, DENSE).size(), _catalog.maps[STRIP].dense_housing_cells.size(),
		"Never more houses than the map lists")


func test_the_small_map_starts_empty() -> void:
	var small: EconomyContext = EconomyContext.new(_catalog, _catalog.maps[SMALL])
	assert_true(_new_game(_params(), small).snapshot()["economy"]["buildings"].is_empty(), "Parity of the 8x8 (D-074)")


func test_the_rest_of_the_standing_buildings_block_building() -> void:
	var map: MapDef = _catalog.maps[STRIP]
	for cell: Vector2i in map.existing_cells:
		if cell in map.dense_housing_cells:
			continue
		for id: StringName in [&"housing", &"bakery", &"mill"]:
			var sim: Simulation = _new_game(_params())
			var command: BuildCommand = _build(sim, _strip, id, cell)
			assert_false(command.accepted, "%s %s" % [id, cell])
			assert_eq(command.reason, &"existing_building", "%s %s" % [id, cell])


func test_dense_housing_is_not_built_by_the_player() -> void:
	var sim: Simulation = _new_game(_params())
	var command: BuildCommand = _build(sim, _strip, DENSE, Vector2i(1, 1))
	assert_false(command.accepted)
	assert_eq(command.reason, &"not_buildable")
	assert_eq(_strip.building_unavailable_reason(DENSE), &"not_buildable")


func test_demolishing_the_dense_housing_refunds_half_its_cost() -> void:
	# Without taxes, wages or upkeep, the refund is the only money that differs from a game that keeps the house.
	var params: Params = SimTestParams.isolated_params(_catalog)
	var kept: Simulation = _new_game(params)
	var sim: Simulation = _new_game(params)
	sim.apply_command(DemolishCommand.new(START_CELL))
	sim.tick()
	kept.tick()
	assert_true(_buildings_of(sim, DENSE).is_empty())
	var cost: int = int(params.get_value(&"building.dense_housing.cost"))
	var ratio: float = float(params.get_value(&"demolish.no_jobs_refund_ratio"))
	var refund: int = sim.snapshot()["economy"]["money"] - kept.snapshot()["economy"]["money"]
	assert_eq(refund, roundi(cost * ratio), "D-029: 50 % of 60")
	# Every standing-building cell stays a block until the tracing of #152 (D-075), its own included.
	var rebuilt: BuildCommand = _build(sim, _strip, &"housing", START_CELL)
	assert_eq(rebuilt.reason, &"existing_building")


# Mason's required test (D-076): a game saved with a building on a cell that is now blocked keeps it, working; the
# blocked cell only stops something new from being built there, even after the old building is demolished.
# Both cells have a street beside them, the access every building needs on the strip (D-080, D-079).
func test_a_saved_building_on_a_blocked_cell_stays_and_works() -> void:
	var params: Params = SimTestParams.isolated_params(_catalog)
	var bakery_cell: Vector2i = Vector2i(10, 5)
	var housing_cell: Vector2i = Vector2i(11, 5)
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
	assert_eq(economy["housing_capacity"], 40, "The saved housing still counts: 20 dense + 20")
	var occupied: BuildCommand = _build(sim, _strip, &"mill", bakery_cell)
	assert_false(occupied.accepted)
	sim.apply_command(DemolishCommand.new(bakery_cell))
	sim.tick()
	var blocked: BuildCommand = _build(sim, _strip, &"mill", bakery_cell)
	assert_false(blocked.accepted)
	assert_eq(blocked.reason, &"existing_building")
