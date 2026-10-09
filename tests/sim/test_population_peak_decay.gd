extends GutTest

var _catalog: DataCatalog
var _system: DefeatSystem


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_system = DefeatSystem.new()


func _params(overrides: Dictionary[StringName, float] = {}) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"defeat.grace_seconds", &"set", 0))
	for key: StringName in overrides:
		role.modifiers.append(Modifier.new(key, &"set", overrides[key]))
	return Params.new(_catalog, role)


func _state(population: int = 60) -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.population = 100
	_system.initialize(state, _params())
	state.population = population
	return state


func _ticks(state: EconomyState, params: Params, count: int) -> void:
	for index: int in range(count):
		_system.tick(state, params, false)


func test_compound_decay_is_fractional_and_exactly_one_percent_per_minute() -> void:
	var state: EconomyState = _state()
	var params: Params = _params()
	_ticks(state, params, 1)
	assert_almost_eq(float(state.population_peak), 100.0 * pow(0.99, 1.0 / 60.0), 0.00000001)
	_ticks(state, params, 59)
	assert_almost_eq(float(state.population_peak), 99.0, 0.00000001)
	_ticks(state, params, 60)
	assert_almost_eq(float(state.population_peak), 98.01, 0.00000001)


func test_decay_uses_shared_smoothed_coverage_and_modified_recovery() -> void:
	var state: EconomyState = _state()
	var params: Params = _params({&"population.growth.hunger_emigration_recovery": 0.9})
	state.bread_coverage = 1.0
	state.hunger_smoothed_coverage = 0.899
	_ticks(state, params, 60)
	assert_eq(float(state.population_peak), 100.0)
	state.bread_coverage = 0.0
	state.hunger_smoothed_coverage = 0.9
	_ticks(state, params, 60)
	assert_almost_eq(float(state.population_peak), 99.0, 0.00000001)
	state.hunger_smoothed_coverage = 0.75
	_ticks(state, _params(), 60)
	assert_almost_eq(float(state.population_peak), 98.01, 0.00000001)
	state.hunger_smoothed_coverage = 0.749
	_ticks(state, _params(), 60)
	assert_almost_eq(float(state.population_peak), 98.01, 0.00000001)


func test_rate_modifiers_boundaries_population_floor_and_new_peak() -> void:
	var state: EconomyState = _state()
	_ticks(state, _params({&"defeat.depopulation.peak_decay_per_minute": 0}), 60)
	assert_eq(float(state.population_peak), 100.0)
	_ticks(state, _params({&"defeat.depopulation.peak_decay_per_minute": 0.1}), 60)
	assert_almost_eq(float(state.population_peak), 90.0, 0.00000001)
	_ticks(state, _params({&"defeat.depopulation.peak_decay_per_minute": 1}), 1)
	assert_eq(float(state.population_peak), 60.0)
	state.population = 120
	_ticks(state, _params(), 1)
	assert_eq(float(state.population_peak), 120.0)
	assert_true(state.depopulation_active)


func test_stable_city_recovers_warning_but_continuing_decline_does_not() -> void:
	var stable: EconomyState = _state(49)
	var falling: EconomyState = _state(49)
	var params: Params = _params()
	_ticks(stable, params, 1)
	_ticks(falling, params, 1)
	assert_eq(stable.depopulation.status, &"warning")
	assert_eq(falling.depopulation.status, &"warning")
	for minute: int in range(3):
		falling.population -= 1
		_ticks(stable, params, 60)
		_ticks(falling, params, 60)
	assert_eq(stable.depopulation.status, &"ok")
	assert_eq(stable.depopulation.cause, &"")
	assert_eq(falling.depopulation.status, &"warning")
	assert_eq(falling.depopulation.elapsed_seconds, 0)


func test_decay_preserves_absolute_minimum_activation_and_terminal_state() -> void:
	var state: EconomyState = _state(9)
	var params: Params = _params({&"defeat.depopulation.peak_decay_per_minute": 1,
		&"defeat.depopulation.duration_seconds": 2})
	_ticks(state, params, 1)
	assert_eq(float(state.population_peak), 9.0)
	assert_true(state.depopulation_active)
	assert_eq(state.depopulation.status, &"warning")
	assert_eq(state.depopulation.elapsed_seconds, 1)
	_ticks(state, params, 1)
	assert_eq(state.defeat_causes, [&"depopulation"])
	var final_state: Dictionary = state.to_dict()
	_ticks(state, params, 60)
	assert_eq(state.to_dict(), final_state)


func test_grace_suppresses_all_depopulation_cases_until_tick_301() -> void:
	var params: Params = _params({&"defeat.grace_seconds": 300})
	for population: int in [0, 1, 9, 24, 49]:
		var state: EconomyState = _state(population)
		state.money = -1
		state.bread_coverage = 0.0
		state.hunger_smoothed_coverage = 0.0
		for index: int in range(300):
			_system.tick(state, params)
			assert_eq(state.depopulation.status, &"ok")
			assert_eq(state.depopulation.cause, &"")
			assert_eq(state.depopulation.elapsed_seconds, 0)
		assert_eq(state.bankruptcy.status, &"warning")
		assert_eq(state.bankruptcy.elapsed_seconds, 0)
		assert_eq(state.hunger.status, &"warning" if population > 0 else &"ok")
		assert_eq(state.hunger.elapsed_seconds, 0)
		_system.tick(state, params)
		assert_eq(state.depopulation.status, &"warning")
		assert_eq(state.depopulation.cause, &"depopulation")
		assert_eq(state.depopulation.elapsed_seconds, 1 if population < 25 else 0)
		assert_eq(state.bankruptcy.elapsed_seconds, 1)
		assert_eq(state.hunger.elapsed_seconds, 1 if population > 0 else 0)


func test_decay_during_grace_round_trips_without_extra_initialization_step() -> void:
	var params: Params = _params({&"defeat.grace_seconds": 75})
	var state: EconomyState = _state(24)
	_ticks(state, params, 60)
	assert_almost_eq(float(state.population_peak), 99.0, 0.00000001)
	var values: Dictionary = state.to_dict()
	var restored: EconomyState = EconomyState.from_dict(values)
	_system.initialize(restored, params)
	assert_eq(restored.to_dict(), values)
	_ticks(state, params, 15)
	_ticks(restored, params, 15)
	assert_eq(state.depopulation.status, &"ok")
	assert_eq(state.depopulation.elapsed_seconds, 0)
	_ticks(state, params, 1)
	_ticks(restored, params, 1)
	assert_eq(restored.to_dict(), state.to_dict())
	assert_eq(restored.depopulation.status, &"warning")
	assert_eq(restored.depopulation.elapsed_seconds, 1)
	values["population_peak"] = 100
	assert_eq(float(EconomyState.from_dict(values).population_peak), 100.0)


func test_simulation_snapshot_preserves_fractional_peak_and_continuation() -> void:
	var params: Params = _params({&"population.growth.immigration_per_minute": 0,
		&"population.growth.emigration_per_minute": 0,
		&"market.wheat.price_update_seconds": 100000})
	var context: EconomyContext = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	var state: EconomyState = _state()
	state.money = 10000
	state.stocks[&"bread"] = 1000
	var sim: Simulation = Simulation.new(params, state, 42, context)
	for index: int in range(17):
		sim.tick()
	var snapshot: Dictionary = sim.snapshot()["economy"]
	assert_almost_eq(float(snapshot["population_peak"]), 100.0 * pow(0.99, 17.0 / 60.0), 0.00000001)
	var restored: Simulation = Simulation.new(params, EconomyState.from_dict(snapshot), 42, context)
	assert_eq(restored.snapshot()["economy"], snapshot)
	for index: int in range(60):
		sim.tick()
		restored.tick()
		assert_eq(restored.snapshot()["economy"], sim.snapshot()["economy"])
