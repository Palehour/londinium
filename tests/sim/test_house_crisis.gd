extends GutTest

# Issue #222 (D-104 to D-108): during a health crisis a house with sick people is never demolished (D-106), its
# exposed neighbours wait out a preventive quarantine (D-107), and a sick house within the health post's radius can be
# disinfected for a price (D-104). Nothing makes a house sick yet (#87, D-054): the tests use the hooks
# Simulation.mark_house_sick() and Simulation.cure_house(). Ticks are game seconds.

const HOUSE: StringName = &"housing"
const POST: StringName = &"health_post"
const SHAPE_KEY: StringName = &"crisis.health.exposure_diamond"
const TILES_KEY: StringName = &"crisis.health.exposure_tiles"
const RADIUS_KEY: StringName = &"crisis.health.post_radius_m"
# A 3x3 block of 2x2 houses whose middle one falls sick; ORIGIN is its north-west corner.
const ORIGIN: Vector2i = Vector2i(2, 2)
const CENTRE: Vector2i = ORIGIN + Vector2i(2, 2)
# The middle house of the block's east column, and a house one empty column east of it: two tiles apart.
const EAST: Vector2i = ORIGIN + Vector2i(4, 2)
const BEYOND: Vector2i = ORIGIN + Vector2i(7, 2)

var _catalog: DataCatalog
var _context: EconomyContext
var _initial: EconomyState


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	_initial = EconomyState.new()
	_initial.money = 10000
	_initial.stocks.assign({&"wheat": 0, &"flour": 0, &"bread": 0})


func _sim(modifiers: Array[Modifier] = []) -> Simulation:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign(modifiers)
	return Simulation.new(SimTestParams.isolated_params(_catalog, role), _initial, 7, _context)


func _params(modifiers: Array[Modifier] = []) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign(modifiers)
	return SimTestParams.isolated_params(_catalog, role)


func _place(id: StringName, cell: Vector2i) -> void:
	_initial.buildings.append({"definition_id": id, "cell": [cell.x, cell.y]})


func _block() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(3):
		for x: int in range(3):
			cells.append(ORIGIN + Vector2i(x, y) * 2)
	return cells


func _place_block() -> void:
	for cell: Vector2i in _block():
		_place(HOUSE, cell)
	_place(HOUSE, BEYOND)


func _ticks(sim: Simulation, count: int) -> void:
	for index: int in range(count):
		sim.tick()


func _minutes(params: Params, key: StringName) -> int:
	return SimTime.minutes_to_ticks(float(params.get_value(key)))


# The lock of each house in a crisis, by its cell, from the snapshot the map reads.
func _locks(sim: Simulation) -> Dictionary[Vector2i, StringName]:
	var found: Dictionary[Vector2i, StringName] = {}
	for house: Dictionary in sim.snapshot()["crisis"]["houses"]:
		found[Vector2i(int(house["cell"][0]), int(house["cell"][1]))] = StringName(house["lock"])
	return found


func _demolish(sim: Simulation, cell: Vector2i) -> DemolishCommand:
	var command: DemolishCommand = DemolishCommand.new(cell)
	sim.apply_command(command)
	sim.tick()
	return command


func _disinfect(sim: Simulation, cell: Vector2i) -> DisinfectCommand:
	var command: DisinfectCommand = DisinfectCommand.new(cell)
	sim.apply_command(command)
	sim.tick()
	return command


func _money(sim: Simulation) -> int:
	return sim.snapshot()["economy"]["money"]


func test_the_data_starts_with_a_square_of_one_tile_and_a_shorter_quarantine_by_the_post() -> void:
	var params: Params = _params()
	assert_false(params.get_value(SHAPE_KEY))
	assert_eq(params.get_value(TILES_KEY), 1)
	assert_lt(float(params.get_value(&"crisis.health.quarantine_post_min")),
		float(params.get_value(&"crisis.health.quarantine_min")))
	assert_true(CrisisSystem.POST_TAG in _catalog.buildings[POST].tags)
	assert_null(_catalog.buildings[POST].recipe)


func test_a_square_at_one_tile_exposes_the_eight_houses_around_a_sick_one() -> void:
	_place_block()
	var sim: Simulation = _sim()
	assert_true(sim.mark_house_sick(CENTRE))
	var locks: Dictionary[Vector2i, StringName] = _locks(sim)
	assert_eq(locks.size(), 9, str(locks))
	assert_eq(locks[CENTRE], CrisisSystem.HOUSE_SICK)
	for cell: Vector2i in _block():
		if cell != CENTRE:
			assert_eq(locks.get(cell), CrisisSystem.HOUSE_QUARANTINE, str(cell))
	assert_false(locks.has(BEYOND))


func test_a_diamond_at_one_tile_exposes_only_the_four_houses_sharing_a_side() -> void:
	_place_block()
	var sim: Simulation = _sim([Modifier.new(SHAPE_KEY, &"set", 1)])
	sim.mark_house_sick(CENTRE)
	var locks: Dictionary[Vector2i, StringName] = _locks(sim)
	assert_eq(locks.size(), 5, str(locks))
	for offset: Vector2i in [Vector2i(0, -2), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(2, 0)]:
		assert_eq(locks.get(CENTRE + offset), CrisisSystem.HOUSE_QUARANTINE, str(offset))


func test_one_tile_stops_at_the_gap_and_two_tiles_reach_beyond_it() -> void:
	_place_block()
	var sim: Simulation = _sim()
	sim.mark_house_sick(EAST)
	assert_false(_locks(sim).has(BEYOND))
	sim = _sim([Modifier.new(TILES_KEY, &"set", 2)])
	sim.mark_house_sick(EAST)
	assert_eq(_locks(sim).get(BEYOND), CrisisSystem.HOUSE_QUARANTINE)


func test_a_sick_house_is_never_demolished_outside_the_post_radius() -> void:
	_place(HOUSE, CENTRE)
	var sim: Simulation = _sim()
	sim.mark_house_sick(CENTRE)
	var params: Params = _params()
	# Long after any quarantine or disinfection would have ended, the crisis still holds it.
	_ticks(sim, _minutes(params, &"crisis.health.quarantine_min") * 3)
	var command: DemolishCommand = _demolish(sim, CENTRE + Vector2i.ONE)
	assert_false(command.accepted)
	assert_eq(command.reason, CrisisSystem.HOUSE_SICK)
	assert_eq(_disinfect(sim, CENTRE).reason, CrisisSystem.OUTSIDE_POST)
	assert_eq(sim.snapshot()["economy"]["buildings"].size(), 1)


func test_the_quarantine_is_shorter_within_the_post_radius() -> void:
	var params: Params = _params([Modifier.new(RADIUS_KEY, &"set", 50)])
	# Centres two cells apart are 50 m on 25 m cells: the post covers the west neighbour, not the east one.
	var sick: Vector2i = Vector2i(8, 4)
	var west: Vector2i = sick - Vector2i(2, 0)
	var east: Vector2i = sick + Vector2i(2, 0)
	_place(HOUSE, sick)
	_place(HOUSE, west)
	_place(HOUSE, east)
	_place(POST, west - Vector2i(2, 0))
	var sim: Simulation = _sim([Modifier.new(RADIUS_KEY, &"set", 50)])
	sim.mark_house_sick(sick)
	var short: int = _minutes(params, &"crisis.health.quarantine_post_min")
	var full: int = _minutes(params, &"crisis.health.quarantine_min")
	_ticks(sim, short)
	assert_true(_demolish(sim, west).accepted, "The covered house waits only the shorter term")
	var command: DemolishCommand = _demolish(sim, east)
	assert_eq(command.reason, CrisisSystem.HOUSE_QUARANTINE)
	_ticks(sim, full - short - 2)
	assert_true(_demolish(sim, east).accepted)


func test_an_exposed_house_that_falls_sick_stays_locked_until_the_crisis_ends() -> void:
	_place_block()
	var neighbour: Vector2i = CENTRE + Vector2i(2, 0)
	var sim: Simulation = _sim()
	sim.mark_house_sick(CENTRE)
	sim.mark_house_sick(neighbour)
	assert_eq(_locks(sim)[neighbour], CrisisSystem.HOUSE_SICK)
	_ticks(sim, _minutes(_params(), &"crisis.health.quarantine_min") + 1)
	assert_eq(_demolish(sim, neighbour).reason, CrisisSystem.HOUSE_SICK, "D-106 beats the quarantine")
	sim.cure_house(CENTRE)
	assert_eq(_demolish(sim, neighbour).reason, CrisisSystem.HOUSE_SICK, "The crisis goes on while one is sick")
	sim.cure_house(neighbour)
	assert_true(_demolish(sim, neighbour).accepted)


func test_a_new_case_does_not_restart_a_running_quarantine() -> void:
	_place_block()
	var params: Params = _params()
	var full: int = _minutes(params, &"crisis.health.quarantine_min")
	var corner: Vector2i = ORIGIN
	var sim: Simulation = _sim()
	sim.mark_house_sick(CENTRE)
	_ticks(sim, full / 2)
	# The corner's other neighbour falls sick halfway through; its term still ends when it was due.
	sim.mark_house_sick(ORIGIN + Vector2i(2, 0))
	_ticks(sim, full - full / 2)
	assert_true(_demolish(sim, corner).accepted)


func test_the_end_of_the_crisis_lifts_every_quarantine() -> void:
	_place_block()
	var sim: Simulation = _sim()
	sim.mark_house_sick(CENTRE)
	sim.tick()
	assert_true(sim.snapshot()["crisis"]["active"])
	assert_true(sim.cure_house(CENTRE))
	assert_false(sim.snapshot()["crisis"]["active"])
	assert_true(_locks(sim).is_empty())
	assert_true(_demolish(sim, ORIGIN).accepted)


func test_a_disinfection_within_the_radius_frees_the_house_once_it_is_done() -> void:
	_place(HOUSE, CENTRE)
	_place(POST, CENTRE + Vector2i(2, 0))
	var params: Params = _params()
	var cost: int = int(params.get_value(&"crisis.health.response_cost"))
	var sim: Simulation = _sim()
	sim.mark_house_sick(CENTRE)
	assert_true(_disinfect(sim, CENTRE).accepted)
	assert_eq(_money(sim), _initial.money - cost)
	assert_eq(_disinfect(sim, CENTRE).reason, CrisisSystem.DISINFECTION_RUNNING)
	assert_eq(_demolish(sim, CENTRE).reason, CrisisSystem.HOUSE_SICK, "Locked while it is being disinfected")
	_ticks(sim, _minutes(params, &"crisis.health.response_min"))
	assert_true(_locks(sim).is_empty())
	assert_true(_demolish(sim, CENTRE).accepted)


func test_a_crisis_that_ends_before_the_disinfection_refunds_it() -> void:
	_place(HOUSE, CENTRE)
	_place(POST, CENTRE + Vector2i(2, 0))
	var sim: Simulation = _sim()
	sim.mark_house_sick(CENTRE)
	assert_true(_disinfect(sim, CENTRE).accepted)
	sim.cure_house(CENTRE)
	assert_eq(_money(sim), _initial.money)
	assert_true(_demolish(sim, CENTRE).accepted)


func test_without_money_the_disinfection_does_not_start_and_leaves_no_debt() -> void:
	_initial.money = int(_params().get_value(&"crisis.health.response_cost")) - 1
	_place(HOUSE, CENTRE)
	_place(POST, CENTRE + Vector2i(2, 0))
	var sim: Simulation = _sim()
	sim.mark_house_sick(CENTRE)
	var command: DisinfectCommand = _disinfect(sim, CENTRE)
	assert_false(command.accepted)
	assert_eq(command.reason, &"insufficient_money")
	assert_eq(_money(sim), _initial.money)
	assert_eq(_demolish(sim, CENTRE).reason, CrisisSystem.HOUSE_SICK, "It waits for the end of the crisis")
	sim.cure_house(CENTRE)
	assert_true(_demolish(sim, CENTRE).accepted)


func test_only_a_sick_house_can_be_disinfected() -> void:
	_place(HOUSE, CENTRE)
	_place(POST, CENTRE + Vector2i(2, 0))
	var sim: Simulation = _sim()
	assert_eq(_disinfect(sim, CENTRE).reason, CrisisSystem.NOT_SICK)
	assert_eq(_disinfect(sim, Vector2i(14, 14)).reason, &"no_building")
	assert_false(sim.mark_house_sick(CENTRE + Vector2i(2, 0)), "A post is not a house")


func test_the_snapshot_gives_the_map_the_price_the_duration_and_whether_it_can_disinfect() -> void:
	_place(HOUSE, CENTRE)
	_place(HOUSE, CENTRE + Vector2i(2, 0))
	_place(POST, CENTRE - Vector2i(2, 0))
	var params: Params = _params()
	var sim: Simulation = _sim()
	sim.mark_house_sick(CENTRE)
	var crisis: Dictionary = sim.snapshot()["crisis"]
	assert_eq(crisis["cost"], int(params.get_value(&"crisis.health.response_cost")))
	assert_eq(crisis["duration_seconds"], _minutes(params, &"crisis.health.response_min"))
	var houses: Dictionary = {}
	for house: Dictionary in crisis["houses"]:
		houses[Vector2i(int(house["cell"][0]), int(house["cell"][1]))] = house
	assert_eq(houses[CENTRE]["disinfect"], &"")
	assert_eq(houses[CENTRE + Vector2i(2, 0)]["disinfect"], CrisisSystem.NOT_SICK)
	assert_gt(int(houses[CENTRE + Vector2i(2, 0)]["seconds_left"]), 0)


func test_a_saved_game_keeps_the_locks() -> void:
	_place_block()
	var sim: Simulation = _sim()
	sim.mark_house_sick(CENTRE)
	sim.tick()
	var loaded: Simulation = Simulation.from_save(_params(), _context, [], sim.to_save())
	assert_eq(_locks(loaded), _locks(sim))
	assert_eq(_demolish(loaded, ORIGIN).reason, CrisisSystem.HOUSE_QUARANTINE)
