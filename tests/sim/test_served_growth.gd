extends GutTest

# Issue #180 (D-085): immigrants only count the free room of the served houses, the ones with every good of the
# class's growth.served_categories within reach (bread for the workers). With no served house free nobody arrives
# and nothing is kept for later; losing the bread evicts nobody. population.growth.served_capacity_only = false is
# the rule of before.

const WIDTH: int = 24
const SERVED_ONLY: StringName = &"population.growth.served_capacity_only"
# The 8x8 has no streets, so every house counts as served and the rule changes nothing there.
const PARITY_SCENARIO: String = "res://tests/scenarios/both_chains.json"

var _catalog: DataCatalog
var _context: EconomyContext
var _initial: EconomyState
var _radius: int
var _capacity: int


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = RoadTestMap.street(_catalog, WIDTH)
	# In street steps: the radius is in metres since issue #186 (D-086), a step is one street piece.
	_radius = int(_params().get_value(&"building.bakery.service_radius_m")) / RoadSystem.metres(_params(), _context, 1)
	_capacity = int(_params().get_value(&"building.housing.capacity"))
	_initial = EconomyState.new()
	_initial.money = 100000
	_initial.satisfaction = 90.0
	_initial.stocks.assign({&"wheat": 0, &"flour": 0, &"bread": 1000, &"tea": 1000})


# The housing bonus is off, so each house holds its base capacity and the counts below are exact.
func _params(served_only: bool = true) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"needs.housing_bonus_per_category", &"set", 0))
	if not served_only:
		role.modifiers.append(Modifier.new(SERVED_ONLY, &"set", 0))
	return Params.new(_catalog, role)


# A bakery at the first street cell and houses at the given steps from it.
func _sim(house_steps: Array[int], population: int, served_only: bool = true) -> Simulation:
	_initial.population = population
	var sim: Simulation = Simulation.new(_params(served_only), _initial, 7, _context)
	sim.apply_command(BuildCommand.new(_context, &"bakery", RoadTestMap.land(1)))
	for steps: int in house_steps:
		sim.apply_command(BuildCommand.new(_context, &"housing",
			RoadTestMap.on_street(_context.buildings[&"housing"].footprint, steps)))
	sim.tick()
	return sim


func _ticks(sim: Simulation, count: int) -> Dictionary:
	for index: int in range(count):
		sim.tick()
	return sim.snapshot()["economy"]


func _seconds_per_arrival() -> int:
	return ceili(60.0 / float(_params().get_value(&"population.growth.immigration_per_minute")))


# Assert the real RoadSystem-derived service state for the worker class.
# A failed preparation stops the case before diagnostic assertions or array access.
func _assert_worker_service_preconditions(sim: Simulation, expected_total_capacity: int,
		expected_served_capacity: int, expected_total_houses: int, expected_served_houses: int) -> bool:
	assert_true(sim._context.classes.has(&"worker"), "precondition: context has worker class")
	var rooms: Dictionary = sim._state.service_rooms.get(&"worker", {})
	assert_true(rooms.has(RoadSystem.TOTAL), "precondition: worker TOTAL service room recorded")
	assert_true(rooms.has(RoadSystem.SERVED), "precondition: worker SERVED service room recorded")
	assert_true(rooms.has(&"bread"), "precondition: worker bread service room recorded")
	if not sim._context.classes.has(&"worker") or not rooms.has(RoadSystem.TOTAL) \
			or not rooms.has(RoadSystem.SERVED) or not rooms.has(&"bread"):
		return false
	assert_eq(rooms[RoadSystem.TOTAL], Vector2(expected_total_capacity, expected_total_houses), "total worker rooms")
	assert_eq(rooms[RoadSystem.SERVED], Vector2(expected_served_capacity, expected_served_houses), "served worker rooms")
	assert_eq(rooms[&"bread"], Vector2(expected_served_capacity, expected_served_houses), "worker bread rooms")
	var worker_houses: int = 0
	var served_houses: int = 0
	for hs: Dictionary in sim._state.house_service:
		if hs.get("class_id") == &"worker":
			worker_houses += 1
			if hs.get("connected", false) and hs.get("served", {}).get(&"bread", false):
				served_houses += 1
	assert_eq(worker_houses, expected_total_houses, "worker house_service entries")
	assert_eq(served_houses, expected_served_houses, "worker served houses in house_service")
	return rooms[RoadSystem.TOTAL] == Vector2(expected_total_capacity, expected_total_houses) \
		and rooms[RoadSystem.SERVED] == Vector2(expected_served_capacity, expected_served_houses) \
		and rooms[&"bread"] == Vector2(expected_served_capacity, expected_served_houses) \
		and worker_houses == expected_total_houses and served_houses == expected_served_houses


func test_a_free_house_without_bread_in_reach_gets_no_arrivals() -> void:
	var sim: Simulation = _sim([2, _radius + 1] as Array[int], _capacity)
	var economy: Dictionary = _ticks(sim, 600)
	assert_eq(economy["housing_capacity"], 2 * _capacity, "The unserved house is still housing")
	assert_eq(economy["population"], _capacity, "Nobody moves into the house beyond the bakery's radius")


func test_a_free_house_with_bread_in_reach_fills() -> void:
	var sim: Simulation = _sim([2, 3] as Array[int], _capacity)
	assert_eq(_ticks(sim, 900)["population"], 2 * _capacity)


# The rule is what keeps them out: with it off the unserved house fills like any other.
func test_without_the_rule_the_unserved_house_fills_too() -> void:
	var sim: Simulation = _sim([2, _radius + 1] as Array[int], _capacity, false)
	assert_gt(int(_ticks(sim, 600)["population"]), _capacity)


func test_with_two_free_houses_every_arrival_goes_to_the_served_one() -> void:
	var sim: Simulation = _sim([2, _radius + 1] as Array[int], 1)
	assert_eq(_ticks(sim, 900)["population"], _capacity, "The served house fills and the other stays empty")


# No backlog: the seconds nobody could arrive are not owed when a served house opens.
func test_no_backlog_when_a_served_house_opens() -> void:
	var sim: Simulation = _sim([2, _radius + 2] as Array[int], _capacity)
	_ticks(sim, 600)
	sim.apply_command(BuildCommand.new(_context, &"bakery", RoadTestMap.land(_radius + 3)))
	var economy: Dictionary = _ticks(sim, 1)
	assert_eq(economy["population"], _capacity, "The first arrival waits for its own fraction")
	assert_eq(_ticks(sim, _seconds_per_arrival())["population"], _capacity + 1)


# Losing the bread evicts nobody: the people of a house that falls out of reach stay until hunger moves them.
func test_losing_the_bread_evicts_nobody() -> void:
	var sim: Simulation = _sim([2, 3] as Array[int], 2 * _capacity)
	sim.apply_command(DemolishCommand.new(RoadTestMap.land(1)))
	assert_eq(_ticks(sim, 1)["population"], 2 * _capacity)


# Issue #351: a free but unserved house must report unserved_housing (missing bread), not no_free_housing.
func test_unserved_free_housing_reports_unserved_housing_and_bread() -> void:
	var sim: Simulation = _sim([2, _radius + 1] as Array[int], _capacity)
	_ticks(sim, 1)
	var worker_def: ClassDef = sim._context.classes[&"worker"]
	var pop: int = ClassStates.population_of(sim._state, worker_def)
	var cap: int = ClassStates.housing_capacity_of(sim._state, worker_def)
	var served_room: int = RoadSystem.served_room(sim._state, sim._params, worker_def, cap)
	assert_eq(pop, _capacity, "precondition: served house is full")
	assert_eq(cap, 2 * _capacity, "precondition: total worker capacity")
	assert_lt(served_room, cap, "precondition: not all worker room is served")
	assert_eq(served_room, pop, "precondition: all served room is occupied")
	assert_gt(cap - pop, 0, "precondition: physical free room exists")
	if not _assert_worker_service_preconditions(sim, 2 * _capacity, _capacity, 2, 1):
		return
	if pop != _capacity or cap != 2 * _capacity or served_room != pop or cap - pop <= 0:
		return
	var needs: Dictionary = sim.snapshot()["needs"]
	var blockers: Array = needs["classes"][&"worker"].get("blockers", [])
	assert_false(blockers.is_empty(), "precondition: at least one blocker")
	if blockers.is_empty():
		return
	assert_eq(blockers[0]["reason"], &"unserved_housing", "unserved housing is the first blocker")
	assert_eq(blockers[0]["group"], &"growth")
	assert_eq(blockers[0].get("missing_goods"), [&"bread"] as Array[StringName], "unserved housing names missing bread")


# Issue #351: a served house that is full must report no_free_housing.
func test_served_full_housing_reports_no_free_housing() -> void:
	var sim: Simulation = _sim([2] as Array[int], _capacity)
	_ticks(sim, 1)
	var worker_def: ClassDef = sim._context.classes[&"worker"]
	var pop: int = ClassStates.population_of(sim._state, worker_def)
	var cap: int = ClassStates.housing_capacity_of(sim._state, worker_def)
	var served_room: int = RoadSystem.served_room(sim._state, sim._params, worker_def, cap)
	assert_eq(pop, _capacity, "precondition: house is full")
	assert_eq(cap, _capacity, "precondition: one served house capacity")
	assert_eq(served_room, cap, "precondition: all room is served")
	if not _assert_worker_service_preconditions(sim, _capacity, _capacity, 1, 1):
		return
	if pop != _capacity or cap != _capacity or served_room != cap:
		return
	var needs: Dictionary = sim.snapshot()["needs"]
	var blockers: Array = needs["classes"][&"worker"].get("blockers", [])
	assert_false(blockers.is_empty(), "precondition: at least one blocker")
	if blockers.is_empty():
		return
	# D-186: no_free_housing has no measurable gap, so it comes after every measurable growth blocker.
	# The worker's comunidad (tea) is uncovered in this map, so no_free_housing is not blockers[0].
	var reasons: Array = []
	for b: Dictionary in blockers:
		reasons.append(b.get("reason"))
	assert_eq(reasons.count(&"no_free_housing"), 1, "exactly one no_free_housing")
	assert_eq(reasons.count(&"unserved_housing"), 0, "served full housing is not unserved")
	assert_eq(reasons[reasons.size() - 1], &"no_free_housing", "housing blocker after the measurable ones")
	var previous_gap: float = INF
	for i: int in range(blockers.size() - 1):
		var b: Dictionary = blockers[i]
		assert_eq(b.get("group"), &"growth")
		assert_true(b.has("value") and b.has("threshold"), "blocker %d before housing is measurable" % i)
		if not (b.has("value") and b.has("threshold")):
			return
		var gap: float = float(b["threshold"]) - float(b["value"])
		assert_gt(gap, 0.0, "measurable blocker %d is below its threshold" % i)
		assert_true(gap <= previous_gap, "measurable gaps descend")
		previous_gap = gap
	assert_eq(blockers[blockers.size() - 1].get("group"), &"growth")


func test_the_8x8_plays_the_same_with_the_rule_on_or_off() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	assert_not_null(runner, "data/ must load")
	if runner == null:
		return
	var scenario: Dictionary = ScenarioRunner.load_file(PARITY_SCENARIO)
	var with_rule: ScenarioResult = runner.run(scenario)
	runner.use_modifiers([Modifier.new(SERVED_ONLY, &"set", 0)] as Array[Modifier])
	var without_rule: ScenarioResult = runner.run(scenario)
	assert_eq(with_rule.rows, without_rule.rows)
	assert_eq(with_rule.final_economy, without_rule.final_economy)
