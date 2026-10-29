extends GutTest

# Issue #88, T2 (D-148, D-150, D-151): draining a marsh makes it firm ground for terrain.drain_cost, and firm ground
# beside water becomes riverbank for drain_cost × terrain.riverbank_cost_mult. A command is refused, charging nothing,
# without the money, on a taken cell (any cell of a building's footprint, D-152) or, for riverbank, away from water.
#
# A map of its own keeps the cells readable:
#   x = 0 is the river and (5, 0) a dock basin; (1, 1) and (5, 5) are marsh; (1, 3) is riverbank; (6, 4) is a standing
#   building of the map (D-075) and (1, 7) Thames stairs; the rest is firm.

const DRAIN_KEY: StringName = &"terrain.drain_cost"
const MULT_KEY: StringName = &"terrain.riverbank_cost_mult"
const MONEY: int = 10000
const MARSH_BY_RIVER: Vector2i = Vector2i(1, 1)
const MARSH_INLAND: Vector2i = Vector2i(5, 5)
const RIVERBANK: Vector2i = Vector2i(1, 3)
const FIRM_BY_RIVER: Vector2i = Vector2i(1, 6)
const FIRM_BY_DOCK: Vector2i = Vector2i(5, 1)
const FIRM_INLAND: Vector2i = Vector2i(4, 3)
const FIRM_DIAGONAL_TO_DOCK: Vector2i = Vector2i(6, 1)
const EXISTING: Vector2i = Vector2i(6, 4)
const STAIRS: Vector2i = Vector2i(1, 7)

var _catalog: DataCatalog
var _context: EconomyContext


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	var map: MapDef = MapDef.new()
	map.id = &"terrain_test"
	map.width = 8
	map.height = 8
	for y: int in range(map.height):
		map.river_cells.append(Vector2i(0, y))
	map.dock_cells.append(Vector2i(5, 0))
	map.terrain[MARSH_BY_RIVER] = &"marsh"
	map.terrain[MARSH_INLAND] = &"marsh"
	map.terrain[RIVERBANK] = &"riverbank"
	map.existing_cells.append(EXISTING)
	map.stairs_cells.append(STAIRS)
	_context = EconomyContext.new(_catalog, map)


func _params(modifiers: Array[Modifier] = []) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign(modifiers)
	return SimTestParams.isolated_params(_catalog, role)


func _sim(money: int = MONEY, modifiers: Array[Modifier] = [], buildings: Array[Dictionary] = []) -> Simulation:
	var state: EconomyState = EconomyState.new()
	state.money = money
	state.buildings.assign(buildings)
	return Simulation.new(_params(modifiers), state, 7, _context)


func _run(sim: Simulation, command: SimulationCommand) -> SimulationCommand:
	sim.apply_command(command)
	sim.tick()
	return command


func _drain_cost() -> int:
	return int(_params().get_value(DRAIN_KEY))


func _assert_refused(sim: Simulation, cell: Vector2i, target: StringName, expected: StringName) -> void:
	var money: int = sim.treasury()
	var terrain: StringName = sim.terrain_at(cell)
	var command: SimulationCommand = _run(sim, TransformTerrainCommand.new(cell, target))
	assert_false(command.accepted, "%s → %s" % [cell, target])
	assert_eq(command.reason, expected, "%s → %s" % [cell, target])
	assert_eq(sim.treasury(), money, "A refused transformation charges nothing")
	assert_eq(sim.terrain_at(cell), terrain, "A refused transformation leaves the cell as it was")


func test_the_costs_come_from_data() -> void:
	assert_eq(_params().get_value(DRAIN_KEY), 60, "D-151")
	assert_eq(float(_params().get_value(MULT_KEY)), 2.0, "D-150")


func test_draining_a_marsh_charges_drain_cost_and_leaves_firm_ground() -> void:
	var sim: Simulation = _sim()
	assert_eq(sim.terrain_at(MARSH_INLAND), &"marsh")
	var command: SimulationCommand = _run(sim, TransformTerrainCommand.new(MARSH_INLAND, &"firm"))
	assert_true(command.accepted, str(command.reason))
	assert_eq(sim.terrain_at(MARSH_INLAND), &"firm")
	assert_eq(MONEY - sim.treasury(), _drain_cost())


func test_firm_ground_beside_the_river_becomes_riverbank_for_twice_the_drain_cost() -> void:
	var sim: Simulation = _sim()
	var command: SimulationCommand = _run(sim, TransformTerrainCommand.new(FIRM_BY_RIVER, &"riverbank"))
	assert_true(command.accepted, str(command.reason))
	assert_eq(sim.terrain_at(FIRM_BY_RIVER), &"riverbank")
	assert_eq(MONEY - sim.treasury(), _drain_cost() * 2)


func test_a_dock_basin_is_water_too() -> void:
	var sim: Simulation = _sim()
	assert_true(_run(sim, TransformTerrainCommand.new(FIRM_BY_DOCK, &"riverbank")).accepted)
	assert_eq(sim.terrain_at(FIRM_BY_DOCK), &"riverbank")


func test_a_drained_marsh_beside_water_can_then_become_riverbank() -> void:
	var sim: Simulation = _sim()
	assert_true(_run(sim, TransformTerrainCommand.new(MARSH_BY_RIVER, &"firm")).accepted)
	assert_true(_run(sim, TransformTerrainCommand.new(MARSH_BY_RIVER, &"riverbank")).accepted)
	assert_eq(sim.terrain_at(MARSH_BY_RIVER), &"riverbank")
	assert_eq(MONEY - sim.treasury(), _drain_cost() * 3)


func test_the_costs_follow_params() -> void:
	var sim: Simulation = _sim(MONEY, [Modifier.new(DRAIN_KEY, &"set", 45), Modifier.new(MULT_KEY, &"set", 3)])
	assert_true(_run(sim, TransformTerrainCommand.new(MARSH_INLAND, &"firm")).accepted)
	assert_eq(MONEY - sim.treasury(), 45)
	assert_true(_run(sim, TransformTerrainCommand.new(FIRM_BY_RIVER, &"riverbank")).accepted)
	assert_eq(MONEY - sim.treasury(), 45 + 135)


func test_the_riverbank_cost_is_rounded_down_to_whole_pence() -> void:
	# 45 × 1.5 = 67.5: rounding to the nearest would charge 68.
	var sim: Simulation = _sim(MONEY, [Modifier.new(DRAIN_KEY, &"set", 45), Modifier.new(MULT_KEY, &"set", 1.5)])
	assert_true(_run(sim, TransformTerrainCommand.new(FIRM_BY_RIVER, &"riverbank")).accepted)
	assert_eq(MONEY - sim.treasury(), 67)


func test_refused_without_the_money() -> void:
	_assert_refused(_sim(_drain_cost() - 1), MARSH_INLAND, &"firm", &"insufficient_money")
	_assert_refused(_sim(_drain_cost() * 2 - 1), FIRM_BY_RIVER, &"riverbank", &"insufficient_money")


func test_exactly_the_money_is_enough() -> void:
	var sim: Simulation = _sim(_drain_cost())
	assert_true(_run(sim, TransformTerrainCommand.new(MARSH_INLAND, &"firm")).accepted)
	assert_eq(sim.treasury(), 0)


func test_riverbank_is_refused_away_from_water() -> void:
	_assert_refused(_sim(), FIRM_INLAND, &"riverbank", &"no_water_nearby")


func test_water_only_counts_on_the_four_sides() -> void:
	_assert_refused(_sim(), FIRM_DIAGONAL_TO_DOCK, &"riverbank", &"no_water_nearby")


func test_refused_on_any_cell_of_a_building_footprint() -> void:
	# A 2x2 bakery from (3, 4) covers (3, 4), (4, 4), (3, 5) and (4, 5); the marsh at (5, 5) is just outside it.
	var footprint: Vector2i = _context.buildings[&"bakery"].footprint
	var corner: Vector2i = MARSH_INLAND - footprint
	var bakery: Dictionary = {"definition_id": &"bakery", "cell": [corner.x, corner.y], "built_at": 0, "paid": 0}
	var covered: Vector2i = corner + footprint - Vector2i.ONE
	var taken: Array[Dictionary] = [bakery]
	_assert_refused(_sim(MONEY, [], taken), covered, &"firm", &"occupied_cell")
	var sim: Simulation = _sim(MONEY, [], taken)
	assert_true(_run(sim, TransformTerrainCommand.new(MARSH_INLAND, &"firm")).accepted, "Outside the footprint")


func test_a_taken_marsh_is_refused() -> void:
	var house: Dictionary = {"definition_id": &"housing", "cell": [MARSH_INLAND.x, MARSH_INLAND.y], "built_at": 0,
		"paid": 0}
	var taken: Array[Dictionary] = [house]
	_assert_refused(_sim(MONEY, [], taken), MARSH_INLAND, &"firm", &"occupied_cell")


func test_standing_buildings_and_stairs_of_the_map_take_their_cell() -> void:
	_assert_refused(_sim(), EXISTING, &"riverbank", &"occupied_cell")
	_assert_refused(_sim(), STAIRS, &"riverbank", &"occupied_cell")


func test_only_marsh_to_firm_and_firm_to_riverbank() -> void:
	_assert_refused(_sim(), FIRM_INLAND, &"firm", &"invalid_transformation")
	_assert_refused(_sim(), MARSH_BY_RIVER, &"riverbank", &"invalid_transformation")
	_assert_refused(_sim(), RIVERBANK, &"riverbank", &"invalid_transformation")
	_assert_refused(_sim(), RIVERBANK, &"firm", &"invalid_transformation")
	_assert_refused(_sim(), FIRM_INLAND, &"marsh", &"invalid_transformation")


func test_water_and_cells_off_the_map_are_refused() -> void:
	_assert_refused(_sim(), Vector2i(0, 3), &"riverbank", &"water_cell")
	_assert_refused(_sim(), Vector2i(5, 0), &"firm", &"water_cell")
	var sim: Simulation = _sim()
	var command: SimulationCommand = _run(sim, TransformTerrainCommand.new(Vector2i(8, 3), &"firm"))
	assert_eq(command.reason, &"outside_map")
	assert_eq(sim.treasury(), MONEY)
