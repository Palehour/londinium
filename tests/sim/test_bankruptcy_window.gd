extends GutTest

# Issue #280: bankruptcy without a loan is a threshold in head-tax minutes plus a window (D-131, D-133), building
# is blocked while the window runs (D-133) and a building with upkeep needs a delta of 0 or more (D-134). The unit
# tests run on a bare state whose R is the head tax of WORKERS employed workers of the base class.

const WORKERS: int = 10
const MAP_SIZE: Vector2i = Vector2i(8, 6)
const STREET_ROW: int = 3
const BASICS: Array[StringName] = [&"housing", &"dense_housing", &"wheat_field", &"mill", &"bakery", &"well"]

var _catalog: DataCatalog
var _params: Params
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	for id: StringName in _catalog.buildings:
		_catalog.buildings[id].footprint = Vector2i.ONE
	_catalog.buildings[&"dense_housing"].buildable = true
	_catalog.road_footprint = Vector2i.ONE
	_params = _with({&"defeat.grace_seconds": 0})


func _with(overrides: Dictionary[StringName, float]) -> Params:
	var role: RoleDef = RoleDef.new()
	for key: StringName in overrides:
		role.modifiers.append(Modifier.new(key, &"set", overrides[key]))
	return Params.new(_catalog, role)


func _value(key: StringName) -> float:
	return float(_params.get_value(key))


# A state with one mill staffed by `workers`, so R = workers x rate x base.
func _state(money: int, workers: int = WORKERS) -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.money = money
	state.population = 100
	state.tax_rate = _value(&"population.tax.rate")
	state.buildings.append({"definition_id": &"mill", "cell": [0, 0], "workers": workers})
	return state


func _r(workers: int = WORKERS) -> float:
	return workers * _value(&"population.tax.rate") * _value(&"population.tax.base_per_employed_worker_per_minute")


func _jobs(id: StringName) -> int:
	return int(_value(StringName("building.%s.jobs" % id)))


func _threshold(workers: int = WORKERS) -> int:
	return roundi(_value(&"defeat.bankruptcy.threshold_tax_minutes") * _r(workers))


func _ticks(system: DefeatSystem, state: EconomyState, count: int) -> void:
	for index: int in range(count):
		system.tick(state, _params)


func _context() -> EconomyContext:
	var roads: Array[Vector2i] = []
	for x: int in range(MAP_SIZE.x):
		roads.append(Vector2i(x, STREET_ROW))
	return RoadTestMap.custom(_catalog, MAP_SIZE, roads)


func _build(state: EconomyState, context: EconomyContext, id: StringName, cell: Vector2i) -> BuildCommand:
	var command: BuildCommand = BuildCommand.new(context, id, cell)
	command.execute(state, _params, _rng)
	return command


func _open_window(state: EconomyState) -> void:
	state.money = _threshold() - 1
	var system: DefeatSystem = DefeatSystem.new()
	_ticks(system, state, 1)
	assert_true(DefeatSystem.bankruptcy_window_running(state), "The window is open")


func test_entering_and_leaving_the_window_resets_it() -> void:
	var system: DefeatSystem = DefeatSystem.new()
	var state: EconomyState = _state(_threshold() - 1)
	_ticks(system, state, 40)
	assert_eq(state.bankruptcy.status, &"warning")
	assert_eq(state.bankruptcy.elapsed_seconds, 40)
	assert_true(DefeatSystem.bankruptcy_window_running(state))
	# At the threshold exactly it is not "below": the window closes and starts over.
	state.money = _threshold()
	_ticks(system, state, 1)
	assert_eq(state.bankruptcy.status, &"ok")
	assert_eq(state.bankruptcy.elapsed_seconds, 0)
	assert_false(DefeatSystem.bankruptcy_window_running(state))
	state.money = _threshold() - 1
	_ticks(system, state, 1)
	assert_eq(state.bankruptcy.elapsed_seconds, 1, "A new window, not the old one resumed")
	assert_true(state.defeat_causes.is_empty())


func test_defeat_when_the_window_runs_out() -> void:
	var system: DefeatSystem = DefeatSystem.new()
	var state: EconomyState = _state(_threshold() - 1)
	var window: int = int(_value(&"defeat.bankruptcy.duration_seconds"))
	_ticks(system, state, window - 1)
	assert_eq(state.bankruptcy.status, &"warning")
	assert_true(state.defeat_causes.is_empty())
	_ticks(system, state, 1)
	assert_eq(state.bankruptcy.status, &"defeat")
	assert_eq(state.defeat_causes, [&"bankruptcy"])


func test_threshold_scales_with_tax_income() -> void:
	var poor: EconomyState = _state(0, WORKERS)
	var rich: EconomyState = _state(0, 2 * WORKERS)
	var multiple: float = _value(&"defeat.bankruptcy.threshold_tax_minutes")
	assert_eq(DefeatSystem.bankruptcy_threshold(poor, _params, null), roundi(multiple * _r(WORKERS)))
	assert_eq(DefeatSystem.bankruptcy_threshold(rich, _params, null), roundi(multiple * _r(2 * WORKERS)))
	assert_lt(DefeatSystem.bankruptcy_threshold(rich, _params, null), DefeatSystem.bankruptcy_threshold(poor, _params, null))
	# The same treasury is a crisis for the small city and not for the big one.
	var money: int = int((DefeatSystem.bankruptcy_threshold(poor, _params, null) + DefeatSystem.bankruptcy_threshold(rich, _params, null)) / 2.0)
	poor.money = money
	rich.money = money
	var system: DefeatSystem = DefeatSystem.new()
	_ticks(system, poor, 1)
	_ticks(system, rich, 1)
	assert_eq(poor.bankruptcy.status, &"warning")
	assert_eq(rich.bankruptcy.status, &"ok")
	# With no tax at all R is 0 and the threshold is 0: any debt opens the window.
	assert_eq(DefeatSystem.bankruptcy_threshold(_state(0, 0), _params, null), 0)


func test_unpaid_loan_skips_the_window_and_uses_the_receiver() -> void:
	var system: DefeatSystem = DefeatSystem.new()
	var state: EconomyState = _state(0)
	var request: RequestLoanCommand = RequestLoanCommand.new(100)
	request.execute(state, _params, _rng)
	assert_true(request.accepted, str(request.reason))
	state.money = 2 * _threshold()
	for index: int in range(900 + 1500 - 1):
		state.reset_flows()
		LoanSystem.tick(state, _params)
		system.tick(state, _params)
		assert_eq(state.bankruptcy.elapsed_seconds, 0, "The window never runs with a loan")
		assert_false(DefeatSystem.bankruptcy_window_running(state))
	assert_true(state.defeat_causes.is_empty())
	state.reset_flows()
	LoanSystem.tick(state, _params)
	system.tick(state, _params)
	assert_eq(state.defeat_causes, [LoanSystem.DEFEAT_CAUSE], "Only the receiver of D-128 ends it")


func test_build_and_road_blocked_during_window_even_basics() -> void:
	var context: EconomyContext = _context()
	var state: EconomyState = _state(100000)
	assert_true(_build(state, context, &"housing", Vector2i(0, 2)).accepted, "Housing builds without the window")
	var road_before: BuildRoadCommand = BuildRoadCommand.new(context, Vector2i(6, 0))
	road_before.execute(state, _params, _rng)
	assert_true(road_before.accepted, "A street builds without the window: %s" % road_before.reason)
	_open_window(state)
	state.money = 100000
	var count: int = state.buildings.size()
	var roads: int = state.player_roads.size()
	for id: StringName in BASICS:
		var command: BuildCommand = _build(state, context, id, Vector2i(2, 0))
		assert_false(command.accepted, str(id))
		assert_eq(command.reason, &"bankruptcy_window", str(id))
	var road: BuildRoadCommand = BuildRoadCommand.new(context, Vector2i(4, 0))
	road.execute(state, _params, _rng)
	assert_false(road.accepted)
	assert_eq(road.reason, &"bankruptcy_window")
	assert_eq(state.buildings.size(), count)
	assert_eq(state.player_roads.size(), roads)
	# Demolishing stays allowed: it is the way out.
	var demolish: DemolishCommand = DemolishCommand.new(Vector2i(0, 2))
	demolish.execute(state, _params, _rng)
	assert_true(demolish.accepted, str(demolish.reason))


func test_build_blocked_when_projected_delta_negative() -> void:
	var context: EconomyContext = _context()
	var state: EconomyState = _state(100000, 0)
	state.tax_rate = 0.0
	var blocked: BuildCommand = _build(state, context, &"malthouse", Vector2i(2, 0))
	assert_false(blocked.accepted)
	assert_eq(blocked.reason, &"negative_balance")
	# With income that covers the upkeep (administration included) the same building goes up.
	var funded: EconomyState = _state(100000)
	assert_gt(MoneySystem.projected_delta_per_minute(funded, _params, context, &"malthouse"), 0.0)
	assert_true(_build(funded, context, &"malthouse", Vector2i(2, 0)).accepted)
	# Money first: a building that is too dear reports it before the delta.
	var broke: EconomyState = _state(0, 0)
	assert_eq(_build(broke, context, &"malthouse", Vector2i(2, 0)).reason, &"insufficient_money")


func test_projected_delta_counts_the_tax_of_new_jobs() -> void:
	var context: EconomyContext = _context()
	# Tick 0: nobody employed, 100 unemployed residents. The wharf's jobs pay for its upkeep (D-134, option A).
	var state: EconomyState = EconomyState.new()
	state.money = 100000
	state.population = 100
	state.tax_rate = _value(&"population.tax.rate")
	var jobs: int = _jobs(&"wharf")
	var expected: float = _r(jobs) - _value(&"building.wharf.upkeep_per_minute") \
		* BuildingCosts.administration_multiplier(_params, 1)
	assert_gt(jobs, 0)
	assert_almost_eq(MoneySystem.projected_delta_per_minute(state, _params, context, &"wharf"), expected, 0.0001)
	assert_gte(expected, 0.0, "The wharf pays for itself, so it may be built")
	# This map has no riverbank, so the wharf's own placement rule refuses it: what matters is that the delta does not.
	assert_ne(_build(state, context, &"wharf", Vector2i(2, 2)).reason, &"negative_balance")
	assert_true(_build(state, context, &"brewery", Vector2i(2, 0)).accepted, "A building with upkeep and jobs at tick 0")


func test_new_jobs_capped_by_unemployed() -> void:
	var context: EconomyContext = _context()
	# Everyone who looks for work already has a post: the new building adds no income, only upkeep.
	var full: EconomyState = _state(100000)
	full.population = WORKERS
	var upkeep: float = _value(&"building.wharf.upkeep_per_minute") + 0.0
	assert_almost_eq(MoneySystem.projected_delta_per_minute(full, _params, context, &"wharf"),
		_r() - upkeep * BuildingCosts.administration_multiplier(_params, 2), 0.0001)
	# Two unemployed take two of the wharf's jobs, no more.
	var some: EconomyState = _state(100000)
	some.population = WORKERS + 2
	assert_almost_eq(MoneySystem.projected_delta_per_minute(some, _params, context, &"wharf"),
		_r() + _r(2) - upkeep * BuildingCosts.administration_multiplier(_params, 2), 0.0001)
	# With no jobs in a quiet city and no tax the building is still refused.
	full.tax_rate = 0.0
	assert_eq(_build(full, context, &"brewery", Vector2i(2, 0)).reason, &"negative_balance")


func test_basics_never_blocked_by_delta() -> void:
	var context: EconomyContext = _context()
	for id: StringName in BASICS:
		var state: EconomyState = _state(100000, 0)
		state.tax_rate = 0.0
		assert_eq(float(_params.get_value(StringName("building.%s.upkeep_per_minute" % id))), 0.0, str(id))
		var command: BuildCommand = _build(state, context, id, Vector2i(2, 0))
		# The wheat field needs cultivable land and the well the historic events, which this map does not offer.
		assert_ne(command.reason, &"negative_balance", str(id))
		if id not in [&"wheat_field", &"well"]:
			assert_true(command.accepted, "%s: %s" % [id, command.reason])
	var sim_state: EconomyState = _state(100000, 0)
	sim_state.tax_rate = 0.0
	var simulation: Simulation = Simulation.new(_params, sim_state, 7, context)
	for id: StringName in BASICS:
		assert_ne(simulation.get_building_unavailable_reason(id), &"negative_balance", str(id))


func test_projected_delta_matches_formula() -> void:
	var context: EconomyContext = _context()
	var state: EconomyState = _state(100000)
	state.buildings.append({"definition_id": &"wharf", "cell": [1, 0]})
	state.buildings.append({"definition_id": &"brewery", "cell": [2, 0]})
	var upkeep: float = _value(&"building.wharf.upkeep_per_minute") + _value(&"building.brewery.upkeep_per_minute") \
		+ _value(&"building.malthouse.upkeep_per_minute")
	var multiplier: float = BuildingCosts.administration_multiplier(_params, 4)
	# 90 of the 100 residents are unemployed, so the malthouse's jobs are all filled and pay their tax.
	var income: float = _r() + _r(_jobs(&"malthouse"))
	assert_almost_eq(MoneySystem.projected_delta_per_minute(state, _params, context, &"malthouse"),
		income - upkeep * multiplier, 0.0001)
	var simulation: Simulation = Simulation.new(_params, state, 7, context)
	assert_almost_eq(simulation.get_projected_delta_per_minute(&"malthouse"), income - upkeep * multiplier, 0.0001)
	assert_false(simulation.is_bankruptcy_window_running())
	# A tax of 0 leaves nothing but the upkeep, and the simulation says why the building is unavailable.
	state.tax_rate = 0.0
	simulation = Simulation.new(_params, state, 7, context)
	assert_almost_eq(simulation.get_projected_delta_per_minute(&"malthouse"), -upkeep * multiplier, 0.0001)
	assert_eq(simulation.get_building_unavailable_reason(&"malthouse"), &"negative_balance")
	_open_window(state)
	simulation = Simulation.new(_params, state, 7, context)
	assert_true(simulation.is_bankruptcy_window_running())
	assert_eq(simulation.get_building_unavailable_reason(&"housing"), &"bankruptcy_window")
