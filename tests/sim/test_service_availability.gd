extends GutTest

# Issue #87, task 1 (D-118, after D-054): each service building has an availability that consume() spends and that
# comes back at recovery_per_min up to availability_max. A house is worth the best availability among the services of
# one kind that cover it (0 when none does), and a district's attribute is the mean of its houses. The map is the
# street of RoadTestMap: every building on the land row touches it, and the steps between two are the pieces walked.

const WIDTH: int = 24
const FIRE: StringName = &"fire_station"
const HEALTH_POST: StringName = &"health_post"
const POLICE: StringName = &"police_station"
const HOUSE: StringName = &"housing"
const WEST: StringName = &"west"
const EAST: StringName = &"east"
const EMPTY: StringName = &"empty"
const SEED: int = 7

var _catalog: DataCatalog
var _context: EconomyContext


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog


func before_each() -> void:
	_context = RoadTestMap.street(_catalog, WIDTH)


func _params() -> Params:
	return Params.new(_catalog, _catalog.roles[&"neutral_administrator"])


func _value(key: String) -> float:
	return float(_params().get_value(StringName(key)))


func _max(service: StringName = FIRE) -> float:
	return _value("service.%s.availability_max" % service)


func _recovery_per_minute(service: StringName = FIRE) -> float:
	return _value("service.%s.recovery_per_min" % service)


# Builds each [id, steps] on the land row and ticks once, so the coverage is evaluated.
func _sim(builds: Array) -> Simulation:
	var initial: EconomyState = EconomyState.new()
	initial.money = 100000
	var sim: Simulation = Simulation.new(_params(), initial, SEED, _context)
	for build: Array in builds:
		sim.apply_command(BuildCommand.new(_context, build[0], RoadTestMap.land(build[1])))
	sim.tick()
	return sim


func _cell(steps: int) -> Array:
	var cell: Vector2i = RoadTestMap.land(steps)
	return [cell.x, cell.y]


func _service(sim: Simulation, steps: int) -> Dictionary:
	for service: Dictionary in sim.snapshot()["services"]["buildings"]:
		if service["cell"] == _cell(steps):
			return service
	return {}


func _house(sim: Simulation, steps: int, attribute: StringName = ServiceSystem.SAFETY) -> float:
	for house: Dictionary in sim.snapshot()["services"]["houses"]:
		if house["cell"] == _cell(steps):
			return float(house["values"][attribute])
	return -1.0


func _district(sim: Simulation, attribute: StringName = ServiceSystem.SAFETY,
		district: StringName = WaterSystem.DEFAULT_DISTRICT) -> float:
	return float(sim.snapshot()["services"]["districts"][district][attribute])


func _consume(sim: Simulation, steps: int, amount: float) -> bool:
	return sim.consume_service(RoadTestMap.land(steps), amount)


func _ticks(sim: Simulation, count: int) -> void:
	for i: int in range(count):
		sim.tick()


func test_a_service_starts_at_its_maximum() -> void:
	var sim: Simulation = _sim([[FIRE, 1]])
	assert_eq(float(_service(sim, 1)["availability"]), _max())
	assert_eq(float(_service(sim, 1)["availability_max"]), _max())
	assert_eq(StringName(_service(sim, 1)["attribute"]), ServiceSystem.SAFETY)


func test_a_house_outside_every_radius_gives_0_and_one_within_gives_100() -> void:
	var outside: Simulation = _sim([[FIRE, 1], [HOUSE, WIDTH]])
	var within: Simulation = _sim([[FIRE, 1], [HOUSE, 2]])
	assert_eq(_district(outside), 0.0)
	assert_eq(_max(), 100.0, "the acceptance criterion reads 100 for a service at its maximum")
	assert_eq(_district(within), 100.0)


func test_consume_lowers_the_attribute_in_proportion() -> void:
	var sim: Simulation = _sim([[FIRE, 1], [HOUSE, 2]])
	assert_true(_consume(sim, 1, 50.0))
	assert_eq(float(_service(sim, 1)["availability"]), _max() - 50.0)
	assert_eq(_house(sim, 2), _max() - 50.0)
	assert_eq(_district(sim), _max() - 50.0)


func test_availability_comes_back_at_recovery_per_min_up_to_its_maximum() -> void:
	var sim: Simulation = _sim([[FIRE, 1], [HOUSE, 2]])
	_consume(sim, 1, 50.0)
	_ticks(sim, SimTime.TICKS_PER_MINUTE)
	assert_almost_eq(float(_service(sim, 1)["availability"]), _max() - 50.0 + _recovery_per_minute(), 0.0001)
	assert_almost_eq(_district(sim), _max() - 50.0 + _recovery_per_minute(), 0.0001)
	var minutes_left: int = ceili((50.0 - _recovery_per_minute()) / _recovery_per_minute())
	_ticks(sim, minutes_left * SimTime.TICKS_PER_MINUTE + SimTime.TICKS_PER_MINUTE)
	assert_eq(float(_service(sim, 1)["availability"]), _max(), "it stops at the maximum")
	assert_eq(_district(sim), _max())


func test_consume_never_goes_below_zero() -> void:
	var sim: Simulation = _sim([[FIRE, 1], [HOUSE, 2]])
	assert_true(_consume(sim, 1, _max() * 3.0))
	assert_eq(float(_service(sim, 1)["availability"]), 0.0)
	assert_eq(_district(sim), 0.0)


func test_consume_is_only_for_a_service_and_a_positive_amount() -> void:
	var sim: Simulation = _sim([[FIRE, 1], [HOUSE, 2]])
	assert_false(_consume(sim, 2, 10.0), "a house is not a service")
	assert_false(_consume(sim, 5, 10.0), "nothing stands there")
	assert_false(_consume(sim, 1, -10.0), "a negative spend would refill it")
	assert_eq(float(_service(sim, 1)["availability"]), _max())


func test_any_cell_of_the_footprint_names_the_service() -> void:
	var sim: Simulation = _sim([[FIRE, 1], [HOUSE, 2]])
	assert_true(sim.consume_service(RoadTestMap.land(1) + Vector2i.ONE, 10.0))
	assert_eq(float(_service(sim, 1)["availability"]), _max() - 10.0)


func test_two_overlapping_services_count_the_one_with_more_availability() -> void:
	var sim: Simulation = _sim([[FIRE, 1], [FIRE, 3], [HOUSE, 2]])
	_consume(sim, 1, 80.0)
	assert_eq(_house(sim, 2), _max(), "the untouched one covers it")
	_consume(sim, 3, 30.0)
	assert_eq(_house(sim, 2), _max() - 30.0, "the best of the two")


func test_each_service_covers_its_own_attribute() -> void:
	var health: Simulation = _sim([[HEALTH_POST, 1], [HOUSE, 2]])
	assert_eq(_district(health, ServiceSystem.HEALTH), _max(HEALTH_POST))
	assert_eq(_district(health, ServiceSystem.SAFETY), 0.0)
	assert_eq(_district(health, ServiceSystem.ORDER), 0.0)
	var police: Simulation = _sim([[POLICE, 1], [HOUSE, 2]])
	assert_eq(_district(police, ServiceSystem.ORDER), _max(POLICE))
	assert_eq(_district(police, ServiceSystem.HEALTH), 0.0)


# The street split in two parishes at the middle and a third one without land: West has a covered house and one
# beyond the radius, East a house with no service, and the empty one no houses.
func test_the_attribute_is_the_mean_of_each_district_houses() -> void:
	var map: MapDef = _context.map
	for x: int in range(map.width):
		for y: int in range(map.height):
			map.district_by_cell[Vector2i(x, y)] = WEST if x < map.width / 2 else EAST
	map.district_names[WEST] = "West"
	map.district_names[EAST] = "East"
	map.district_names[EMPTY] = "Empty"
	var sim: Simulation = _sim([[FIRE, 1], [HOUSE, 2], [HOUSE, WIDTH / 2], [HOUSE, WIDTH]])
	assert_eq(_house(sim, WIDTH / 2), 0.0, "the second West house is beyond the radius")
	assert_eq(_district(sim, ServiceSystem.SAFETY, WEST), _max() / 2.0)
	assert_eq(_district(sim, ServiceSystem.SAFETY, EAST), 0.0)
	assert_eq(_district(sim, ServiceSystem.SAFETY, EMPTY), 0.0)
	_consume(sim, 1, 50.0)
	assert_eq(_district(sim, ServiceSystem.SAFETY, WEST), (_max() - 50.0) / 2.0)


func test_the_same_seed_and_state_give_the_same_result() -> void:
	var runs: Array[Dictionary] = []
	for run: int in range(2):
		var sim: Simulation = _sim([[FIRE, 1], [FIRE, 3], [HOUSE, 2], [HOUSE, 8]])
		_consume(sim, 1, 70.0)
		_ticks(sim, 30)
		_consume(sim, 3, 25.0)
		_ticks(sim, 45)
		runs.append({"services": sim.snapshot()["services"], "save": sim.to_save()})
	assert_eq(runs[0], runs[1])


func test_the_availability_is_saved_with_the_building() -> void:
	var sim: Simulation = _sim([[FIRE, 1], [HOUSE, 2]])
	_consume(sim, 1, 50.0)
	_ticks(sim, 10)
	var loaded: Simulation = Simulation.from_save(_params(), _context, [], sim.to_save())
	assert_eq(loaded.snapshot()["services"], sim.snapshot()["services"])
	_ticks(sim, 30)
	_ticks(loaded, 30)
	assert_eq(loaded.snapshot()["services"], sim.snapshot()["services"])


# D-109's rule for D-118: consume() waits for the incidents of task 2, so a city left alone never spends availability.
func test_nothing_in_the_game_spends_availability() -> void:
	var sim: Simulation = _sim([[FIRE, 1], [HEALTH_POST, 3], [POLICE, 5], [HOUSE, 2]])
	_ticks(sim, 900)
	for steps: int in [1, 3, 5]:
		assert_eq(float(_service(sim, steps)["availability"]), float(_service(sim, steps)["availability_max"]))
