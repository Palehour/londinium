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


func test_gdd_depopulation_records_key_contract_elements() -> void:
	var text: String = FileAccess.get_file_as_string("res://docs/GDD.md").to_lower()
	var lines: PackedStringArray = text.split("\n")
	var row_index: int = -1
	for index: int in range(lines.size()):
		if lines[index].begins_with("| despoblación |"):
			assert_eq(row_index, -1, "The depopulation row must be unique")
			row_index = index
	assert_gte(row_index, 0, "The depopulation contract must exist")
	if row_index < 0:
		return
	var cells: PackedStringArray = lines[row_index].split("|")
	assert_eq(cells.size(), 5, "The defeat table must retain its three columns")
	if cells.size() != 5:
		return
	_assert_gdd_contract(cells[2], "50\\s*%[^.;|]*pico", "Warning uses 50 % of the peak")
	var defeat: String = cells[3]
	_assert_gdd_contract(defeat, "25\\s*%[^.;|]*pico", "Relative defeat uses 25 % of the peak")
	_assert_gdd_contract(defeat, "%d\\s*(s\\b|segundos)" % int(
		_params().get_value(&"defeat.depopulation.duration_seconds")), "Duration remains data-backed")
	_assert_gdd_contract(defeat, "10\\s+habitantes[^.;|]*(no\\s+(est[aá]|es)\\s+estable|inestable)",
		"The absolute minimum only applies to an unstable city")
	_assert_gdd_contract(defeat, "\\b0\\s+habitantes[^.;|]*siempre[^.;|]*(terminada|despu[eé]s de|tras)[^.;|]*gracia",
		"An empty city always counts after grace")
	var paragraph: String = ""
	for index: int in range(row_index + 1, lines.size()):
		if lines[index].strip_edges().is_empty():
			if not paragraph.is_empty():
				break
			continue
		paragraph += " " + lines[index].strip_edges()
	_assert_gdd_contract(paragraph, "ciudad[^.;]*estable", "The stability definition follows the table")
	_assert_gdd_contract(paragraph, "no\\s+(hay\\s+)?emigraci[oó]n\\s+por\\s+hambre",
		"Stability requires no hunger emigration")
	_assert_gdd_contract(paragraph, "cobertura[^.;]*pan[^.;]*suavizada[^.;]*0\\s*[,\\.]\\s*6[^.;]*(o\\s+m[aá]s|como\\s+m[ií]nimo)",
		"Stability requires smoothed bread coverage at least 0.6")
	_assert_gdd_contract(paragraph, "satisfacci[oó]n[^.;]*no[^.;]*por\\s+debajo[^.;]*umbral[^.;]*emigraci[oó]n",
		"Stability requires satisfaction at least the emigration threshold")
	_assert_gdd_contract(paragraph, "mientras[^.;]*estable[^.;]*pico[^.;]*baja[^.;]*poblaci[oó]n\\s+actual",
		"The peak decays toward current population while stable")
	_assert_gdd_contract(paragraph, "durante[^.;]*gracia[^.;]*no[^.;]*avisos[^.;]*despoblaci[oó]n",
		"Grace suppresses depopulation warnings")


func _assert_gdd_contract(text: String, pattern: String, message: String) -> void:
	var expression: RegEx = RegEx.new()
	assert_eq(expression.compile(pattern), OK)
	assert_not_null(expression.search(text), message)


func test_departure_age_boundary_and_role_window_control_stability() -> void:
	for window: int in [60, 90]:
		var params: Params = _params() if window == 60 else _params({
			&"defeat.depopulation.stability_window_seconds": window})
		assert_eq(int(params.get_value(&"defeat.depopulation.stability_window_seconds")), window)
		for age: int in [window - 1, window, window + 1]:
			var stable: bool = age >= window
			var state: EconomyState = _state()
			state.satisfaction_departure_age_seconds = age
			assert_eq(_system.is_city_stable(state, params), stable)
			_ticks(state, params, 1)
			assert_almost_eq(state.population_peak, 100.0 * pow(0.97, 1.0 / 60.0) if stable else 100.0, 0.00000001)
			var small: EconomyState = _state(9)
			small.population_peak = 10.0
			small.satisfaction_departure_age_seconds = age
			_ticks(small, params, 1)
			assert_eq(small.depopulation.status, &"ok" if stable else &"warning")
			assert_eq(small.depopulation.cause, &"" if stable else &"depopulation")
			assert_eq(small.depopulation.elapsed_seconds, 0 if stable else 1)


func test_satisfaction_recovery_resets_absolute_minimum_full_duration() -> void:
	var params: Params = _params()
	var window: int = int(params.get_value(&"defeat.depopulation.stability_window_seconds"))
	var state: EconomyState = _state(9)
	state.population_peak = 10.0
	state.satisfaction_departure_age_seconds = 0
	_ticks(state, params, 179)
	assert_eq(state.population_peak, 10.0)
	assert_eq(state.depopulation.status, &"warning")
	assert_eq(state.depopulation.elapsed_seconds, 179)
	assert_true(state.defeat_causes.is_empty())
	# Nobody left for a whole window: the city is stable again and the timer resets.
	state.satisfaction_departure_age_seconds = window
	_ticks(state, params, 1)
	assert_eq(state.depopulation.status, &"ok")
	assert_eq(state.depopulation.cause, &"")
	assert_eq(state.depopulation.elapsed_seconds, 0)
	var recovered_peak: float = state.population_peak
	state.satisfaction_departure_age_seconds = 0
	_ticks(state, params, 179)
	assert_eq(state.population_peak, recovered_peak)
	assert_eq(state.depopulation.status, &"warning")
	assert_eq(state.depopulation.elapsed_seconds, 179)
	assert_true(state.defeat_causes.is_empty())
	_ticks(state, params, 1)
	assert_eq(state.depopulation.elapsed_seconds, 180)
	assert_eq(state.defeat_causes, [&"depopulation"])


func test_real_satisfaction_crisis_and_recovery_control_stability_in_simulation() -> void:
	# Hunger is switched off so that only low satisfaction can make people leave in this scenario.
	var role: RoleDef = RoleDef.new()
	for key: StringName in [&"population.growth.hunger_emigration_threshold",
			&"population.growth.hunger_emigration_recovery", &"defeat.hunger.threshold"]:
		role.modifiers.append(Modifier.new(key, &"set", 0))
	var params: Params = Params.new(_catalog, role)
	var threshold: float = float(params.get_value(&"population.growth.emigration_threshold"))
	var window: int = int(params.get_value(&"defeat.depopulation.stability_window_seconds"))
	var minimum: int = int(params.get_value(&"defeat.depopulation.minimum_population"))
	var decay: float = float(params.get_value(&"defeat.depopulation.peak_decay_per_minute"))
	var initial: EconomyState = EconomyState.new()
	initial.population = 9
	initial.population_peak = 10.0
	initial.satisfaction = 60.0
	initial.tax_rate = 1.0
	initial.money = 10000
	initial.stocks.assign({&"bread": 10, &"flour": 100})
	initial.defeat_elapsed_seconds = int(params.get_value(&"defeat.grace_seconds"))
	var context: EconomyContext = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	var sim: Simulation = Simulation.new(params, initial, 42, context)
	var previous: Dictionary = sim.snapshot()["economy"]
	# The oracle counts seconds since the last real departure from population drops (no housing, so
	# nobody arrives), never from the counter under test; -1 means nobody has left yet.
	var seconds_since_departure: int = -1
	var unstable_ticks: int = 0
	var stable_ticks: int = 0
	var recovery_requested: bool = false
	var recovered: bool = false
	var bakery: BuildCommand
	var lower_tax: SetTaxCommand
	# Full bread minus maximum tax and overcrowding targets exactly 30, not below.
	# Depleting real reserves lowers that target before smoothed coverage reaches zero.
	for index: int in range(900):
		sim.tick()
		var current: Dictionary = sim.snapshot()["economy"]
		assert_false(current["hunger_emigration_active"])
		assert_true(current["defeat_causes"].is_empty())
		assert_eq(current["housing_capacity"], 0)
		assert_true(current["depopulation_active"])
		assert_gt(float(current["population"]), float(current["population_peak"])
			* float(params.get_value(&"defeat.depopulation.warning_fraction")),
			"Only the absolute minimum can cause this warning")
		var departed: bool = current["population"] < previous["population"]
		assert_false(current["population"] > previous["population"], "Nobody arrives without housing")
		if departed:
			seconds_since_departure = 0
			# Both values must be below the threshold for anyone to leave.
			assert_lt(float(current["satisfaction"]), threshold)
			assert_lt(float(current["satisfaction_target"]), threshold)
		elif seconds_since_departure >= 0:
			seconds_since_departure += 1
		var in_window: bool = seconds_since_departure >= 0 and seconds_since_departure < window
		var city: EconomyState = EconomyState.from_dict(current)
		assert_eq(_system.is_city_stable(city, params), not in_window)
		if in_window:
			unstable_ticks += 1
			assert_eq(current["population_peak"], previous["population_peak"])
			assert_eq(current["depopulation"]["status"], &"warning")
			assert_eq(current["depopulation"]["cause"], &"depopulation")
			assert_eq(current["depopulation"]["elapsed_seconds"], unstable_ticks)
			assert_lt(current["population"], minimum)
			if not recovery_requested and unstable_ticks >= 3:
				var land: Vector2i = Vector2i.ZERO
				while land in context.map.river_cells:
					land.x += 1
				bakery = BuildCommand.new(context, &"bakery", land)
				lower_tax = SetTaxCommand.new(0.0)
				sim.apply_command(bakery)
				sim.apply_command(lower_tax)
				recovery_requested = true
		elif seconds_since_departure < 0:
			stable_ticks += 1
			assert_almost_eq(float(current["population_peak"]),
				float(previous["population_peak"]) * pow(1.0 - decay, 1.0 / 60.0), 0.00000001)
			assert_eq(current["depopulation"]["status"], &"ok")
			assert_eq(current["depopulation"]["elapsed_seconds"], 0)
			assert_almost_eq(float(current["satisfaction_target"]),
				clampf(float(current["hunger_smoothed_coverage"]) * 100.0 - 70.0, 0.0, 100.0), 0.00000001)
		else:
			# A whole window passed without anyone leaving: the city is stable again.
			assert_true(recovery_requested, "The crisis must have been answered with real commands")
			assert_true(bakery.accepted)
			assert_true(lower_tax.accepted)
			assert_eq(current["tax_rate"], 0.0)
			assert_gt(float(current["satisfaction_target"]), threshold, "Recovery comes from real bread and tax")
			assert_eq(seconds_since_departure, window)
			assert_eq(current["depopulation"]["status"], &"ok")
			assert_eq(current["depopulation"]["cause"], &"")
			assert_eq(current["depopulation"]["elapsed_seconds"], 0)
			assert_almost_eq(float(current["population_peak"]), maxf(float(current["population"]),
				float(previous["population_peak"]) * pow(1.0 - decay, 1.0 / 60.0)), 0.00000001)
			assert_lt(float(current["population_peak"]), float(previous["population_peak"]), "The peak decays again")
			recovered = true
			break
		previous = current
	assert_gt(stable_ticks, 1, "Exercise real smoothing and decay before the crisis")
	assert_gte(unstable_ticks, window, "The minimum must count from the first departure through a full quiet window")
	assert_true(recovery_requested)
	assert_true(recovered, "Real production and tax commands must restore stability within the tick limit")

	# Recovery holds: nobody else leaves, the warning stays away and the peak keeps decaying.
	var recovered_state: Dictionary = sim.snapshot()["economy"]
	var held: Dictionary = recovered_state
	for index: int in range(60):
		sim.tick()
		var current: Dictionary = sim.snapshot()["economy"]
		assert_eq(current["population"], held["population"])
		assert_true(_system.is_city_stable(EconomyState.from_dict(current), params))
		assert_eq(current["depopulation"]["status"], &"ok")
		assert_eq(current["depopulation"]["elapsed_seconds"], 0)
		assert_almost_eq(float(current["population_peak"]), maxf(float(current["population"]),
			float(held["population_peak"]) * pow(1.0 - decay, 1.0 / 60.0)), 0.00000001)
		held = current
	assert_eq(held["bread_coverage"], 1.0, "The accepted bakery supplies real bread")
	assert_true(held["defeat_causes"].is_empty())
