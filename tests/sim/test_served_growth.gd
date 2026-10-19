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
	_radius = int(_params().get_value(&"building.bakery.service_radius"))
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
		sim.apply_command(BuildCommand.new(_context, &"housing", RoadTestMap.land(steps)))
	sim.tick()
	return sim


func _ticks(sim: Simulation, count: int) -> Dictionary:
	for index: int in range(count):
		sim.tick()
	return sim.snapshot()["economy"]


func _seconds_per_arrival() -> int:
	return ceili(60.0 / float(_params().get_value(&"population.growth.immigration_per_minute")))


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
