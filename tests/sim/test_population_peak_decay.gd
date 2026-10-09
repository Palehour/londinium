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
	state.satisfaction = float(_params().get_value(&"population.growth.emigration_threshold"))
	_system.initialize(state, _params())
	state.population = population
	return state


func _ticks(state: EconomyState, params: Params, count: int) -> void:
	for index: int in range(count):
		_system.tick(state, params, false)


func test_compound_decay_is_fractional_and_exactly_three_percent_per_minute() -> void:
	var state: EconomyState = _state()
	var params: Params = _params()
	_ticks(state, params, 1)
	assert_almost_eq(float(state.population_peak), 100.0 * pow(0.97, 1.0 / 60.0), 0.00000001)
	_ticks(state, params, 59)
	assert_almost_eq(float(state.population_peak), 97.0, 0.00000001)
	_ticks(state, params, 60)
	assert_almost_eq(float(state.population_peak), 94.09, 0.00000001)


func test_stability_uses_shared_coverage_threshold_and_active_emigration() -> void:
	for threshold: float in [0.6, 0.55]:
		var params: Params = _params({&"population.growth.hunger_emigration_threshold": threshold,
			&"population.growth.hunger_emigration_recovery": 0.9})
		for coverage: float in [threshold - 0.001, threshold, threshold + 0.001, 1.0]:
			for active: bool in [false, true]:
				var state: EconomyState = _state()
				state.bread_coverage = 0.0 if coverage >= threshold else 1.0
				state.hunger_smoothed_coverage = coverage
				state.hunger_emigration_active = active
				_ticks(state, params, 60)
				var stable: bool = not active and coverage >= threshold
				assert_almost_eq(float(state.population_peak), 97.0 if stable else 100.0, 0.00000001)
				assert_eq(state.hunger_emigration_active, active)
				# Same predicate controls the absolute minimum, independently of relative limits.
				var small: EconomyState = _state(9)
				small.population_peak = 10.0
				small.bread_coverage = state.bread_coverage
				small.hunger_smoothed_coverage = coverage
				small.hunger_emigration_active = active
				_ticks(small, params, 60)
				assert_eq(small.depopulation.status, &"ok" if stable else &"warning")
				assert_eq(small.depopulation.elapsed_seconds, 0 if stable else 60)


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
	falling.hunger_emigration_active = true
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


func test_stable_minimum_recovers_and_instability_preserves_terminal_state() -> void:
	var state: EconomyState = _state(9)
	var params: Params = _params({&"defeat.depopulation.peak_decay_per_minute": 1,
		&"defeat.depopulation.duration_seconds": 2})
	_ticks(state, params, 1)
	assert_eq(float(state.population_peak), 9.0)
	assert_true(state.depopulation_active)
	assert_eq(state.depopulation.status, &"ok")
	assert_eq(state.depopulation.elapsed_seconds, 0)
	state.hunger_emigration_active = true
	_ticks(state, params, 1)
	assert_eq(float(state.population_peak), 9.0)
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
	assert_almost_eq(float(state.population_peak), 97.0, 0.00000001)
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
	assert_almost_eq(float(snapshot["population_peak"]), 100.0 * pow(0.97, 17.0 / 60.0), 0.00000001)
	var restored: Simulation = Simulation.new(params, EconomyState.from_dict(snapshot), 42, context)
	assert_eq(restored.snapshot()["economy"], snapshot)
	for index: int in range(60):
		sim.tick()
		restored.tick()
		assert_eq(restored.snapshot()["economy"], sim.snapshot()["economy"])


func test_stability_recovery_resets_absolute_minimum_duration() -> void:
	var state: EconomyState = _state(9)
	state.population_peak = 10.0
	state.hunger_emigration_active = true
	var params: Params = _params()
	_ticks(state, params, 179)
	assert_eq(state.depopulation.status, &"warning")
	assert_eq(state.depopulation.elapsed_seconds, 179)
	state.hunger_emigration_active = false
	state.hunger_smoothed_coverage = 0.6
	_ticks(state, params, 1)
	assert_eq(state.depopulation.status, &"ok")
	assert_eq(state.depopulation.cause, &"")
	assert_eq(state.depopulation.elapsed_seconds, 0)
	state.hunger_emigration_active = true
	_ticks(state, params, 179)
	assert_true(state.defeat_causes.is_empty())
	assert_eq(state.depopulation.elapsed_seconds, 179)
	_ticks(state, params, 1)
	assert_eq(state.defeat_causes, [&"depopulation"])


func test_fed_empty_city_always_counts_after_grace_with_or_without_history() -> void:
	var params: Params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	for historical_peak: float in [0.0, 9.0, 60.0]:
		var state: EconomyState = EconomyState.new()
		state.population_peak = historical_peak
		_system.initialize(state, params)
		assert_false(state.hunger_emigration_active)
		assert_eq(state.hunger_smoothed_coverage, 1.0)
		_ticks(state, params, 300)
		assert_eq(state.depopulation.status, &"ok")
		assert_eq(state.depopulation.elapsed_seconds, 0)
		_ticks(state, params, 1)
		assert_eq(state.depopulation.status, &"warning")
		assert_eq(state.depopulation.elapsed_seconds, 1)
		_ticks(state, params, 178)
		assert_true(state.defeat_causes.is_empty())
		assert_eq(state.depopulation.elapsed_seconds, 179)
		_ticks(state, params, 1)
		assert_eq(state.defeat_causes, [&"depopulation"])
		assert_eq(state.depopulation.elapsed_seconds, 180)


func test_real_rate_city_60_to_27_exits_warning_at_stable_tick_208() -> void:
	var params: Params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	assert_eq(params.get_value(&"defeat.depopulation.peak_decay_per_minute"), 0.03)
	var state: EconomyState = EconomyState.new()
	state.population = 27
	state.population_peak = 60.0
	state.depopulation_active = true
	state.defeat_initialized = true
	state.defeat_elapsed_seconds = 300
	state.money = 10000
	state.stocks[&"bread"] = 1000
	# Full coverage with no housing keeps satisfaction between migration thresholds.
	state.satisfaction = 60.0
	var context: EconomyContext = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	var sim: Simulation = Simulation.new(params, state, 42, context)
	for index: int in range(207):
		sim.tick()
		var snapshot: Dictionary = sim.snapshot()["economy"]
		assert_eq(snapshot["population"], 27)
		assert_false(snapshot["hunger_emigration_active"])
		assert_eq(snapshot["hunger_smoothed_coverage"], 1.0)
		assert_eq(snapshot["depopulation"]["status"], &"warning")
		assert_eq(snapshot["depopulation"]["elapsed_seconds"], 0)
		assert_true(snapshot["defeat_causes"].is_empty())
	sim.tick()
	var recovered: Dictionary = sim.snapshot()["economy"]
	assert_eq(sim.snapshot()["tick_count"], 208)
	assert_eq(recovered["population"], 27)
	assert_almost_eq(float(recovered["population_peak"]), 60.0 * pow(0.97, 208.0 / 60.0), 0.00000001)
	assert_eq(recovered["depopulation"]["status"], &"ok")
	assert_eq(recovered["depopulation"]["cause"], &"")
	assert_eq(recovered["depopulation"]["elapsed_seconds"], 0)
	assert_true(recovered["defeat_causes"].is_empty())


func test_gdd_depopulation_text_matches_issue_30_and_duration() -> void:
	var text: String = FileAccess.get_file_as_string("res://docs/GDD.md")
	var expected_row: String = "| Despoblación | La población cae por debajo del 50 % de su pico | La población se mantiene 180 s seguidos por debajo del 25 % de su pico, o por debajo de 10 habitantes mientras la ciudad no está estable. Con 0 habitantes cuenta siempre, una vez terminada la gracia |"
	var expected_paragraph: String = "Una ciudad es estable cuando nadie se está yendo: no hay emigración por hambre, la cobertura de pan suavizada es de 0,6 o más y la satisfacción no está por debajo del umbral de emigración. Mientras la ciudad está estable, su pico de población baja despacio hasta alcanzar la población actual. Durante la gracia no se muestran avisos de despoblación."
	var row: String = ""
	for line: String in text.split("\n"):
		if line.begins_with("| Despoblación |"):
			row = line
	assert_eq(row, expected_row)
	assert_false(row.contains("su máximo"))
	assert_string_contains(row, "%d s seguidos" % int(_params().get_value(&"defeat.depopulation.duration_seconds")))
	assert_eq(text.count(expected_row), 1)
	assert_eq(text.count(expected_paragraph), 1)
	assert_string_contains(text, expected_row + "\n\n" + expected_paragraph)


func test_smoothed_satisfaction_boundary_and_role_threshold_control_stability() -> void:
	for threshold: float in [30.0, 45.0]:
		var params: Params = _params() if threshold == 30.0 else _params({
			&"population.growth.emigration_threshold": threshold})
		assert_eq(float(params.get_value(&"population.growth.emigration_threshold")), threshold)
		for satisfaction: float in [threshold - 0.001, threshold, threshold + 0.001]:
			var stable: bool = satisfaction >= threshold
			var state: EconomyState = _state()
			state.satisfaction = satisfaction
			state.satisfaction_target = 0.0 if stable else 100.0
			_ticks(state, params, 60)
			assert_almost_eq(state.population_peak, 97.0 if stable else 100.0, 0.00000001)
			var small: EconomyState = _state(9)
			small.population_peak = 10.0
			small.satisfaction = satisfaction
			small.satisfaction_target = state.satisfaction_target
			_ticks(small, params, 60)
			assert_eq(small.depopulation.status, &"ok" if stable else &"warning")
			assert_eq(small.depopulation.cause, &"" if stable else &"depopulation")
			assert_eq(small.depopulation.elapsed_seconds, 0 if stable else 60)


func test_satisfaction_recovery_resets_absolute_minimum_full_duration() -> void:
	var params: Params = _params()
	var threshold: float = float(params.get_value(&"population.growth.emigration_threshold"))
	var state: EconomyState = _state(9)
	state.population_peak = 10.0
	state.satisfaction = threshold - 0.001
	_ticks(state, params, 179)
	assert_eq(state.population_peak, 10.0)
	assert_eq(state.depopulation.status, &"warning")
	assert_eq(state.depopulation.elapsed_seconds, 179)
	assert_true(state.defeat_causes.is_empty())
	state.satisfaction = threshold
	_ticks(state, params, 1)
	assert_eq(state.depopulation.status, &"ok")
	assert_eq(state.depopulation.cause, &"")
	assert_eq(state.depopulation.elapsed_seconds, 0)
	var recovered_peak: float = state.population_peak
	state.satisfaction = threshold - 0.001
	_ticks(state, params, 179)
	assert_eq(state.population_peak, recovered_peak)
	assert_eq(state.depopulation.status, &"warning")
	assert_eq(state.depopulation.elapsed_seconds, 179)
	assert_true(state.defeat_causes.is_empty())
	_ticks(state, params, 1)
	assert_eq(state.depopulation.elapsed_seconds, 180)
	assert_eq(state.defeat_causes, [&"depopulation"])
