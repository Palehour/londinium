extends GutTest

var _catalog: DataCatalog
var _params: Params
var _context: EconomyContext


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])


func _with(overrides: Dictionary[StringName, float]) -> Params:
	var role: RoleDef = RoleDef.new()
	for key: StringName in overrides:
		role.modifiers.append(Modifier.new(key, &"set", overrides[key]))
	return Params.new(_catalog, role)


func _ticks(sim: Simulation, count: int) -> Dictionary:
	for index: int in range(count):
		sim.tick()
	return sim.snapshot()["economy"]


func _new_city(state: EconomyState, params: Params = null) -> Simulation:
	return Simulation.create_new(params if params != null else _params, state, 42, _context)


func test_empty_city_loses_at_480_with_no_historical_peak() -> void:
	var sim: Simulation = Simulation.new(_params, EconomyState.new(), 42, _context)
	assert_eq(sim.snapshot()["economy"]["depopulation"]["status"], &"ok")
	assert_eq(sim.snapshot()["economy"]["depopulation"]["elapsed_seconds"], 0)
	var state: Dictionary = _ticks(sim, 300)
	assert_eq(state["depopulation"]["status"], &"ok")
	assert_eq(state["depopulation"]["elapsed_seconds"], 0)
	state = _ticks(sim, 1)
	assert_eq(state["depopulation"]["status"], &"warning")
	assert_eq(state["depopulation"]["elapsed_seconds"], 1)
	state = _ticks(sim, 178)
	assert_true(state["defeat_causes"].is_empty())
	assert_eq(state["depopulation"]["elapsed_seconds"], 179)
	state = _ticks(sim, 1)
	assert_eq(state["defeat_causes"], [&"depopulation"])
	assert_eq(state["population_peak"], 0.0)
	assert_false(state["depopulation_active"])


func test_small_peak_empty_city_recovers_and_restarts_full_timer() -> void:
	var state: EconomyState = EconomyState.new()
	state.population = 9
	# Isolate the empty-city timer from peak decay.
	var params: Params = _with({&"defeat.grace_seconds": 0,
		&"defeat.depopulation.peak_decay_per_minute": 0})
	var system: DefeatSystem = DefeatSystem.new()
	system.initialize(state, params)
	state.population = 0
	for index: int in range(179):
		system.tick(state, params)
	assert_eq(state.depopulation.elapsed_seconds, 179)
	assert_eq(state.depopulation.status, &"warning")
	state.population = 1
	system.tick(state, params)
	assert_eq(state.depopulation.elapsed_seconds, 0)
	assert_eq(state.depopulation.status, &"ok")
	state.population = 0
	for index: int in range(179):
		system.tick(state, params)
	assert_true(state.defeat_causes.is_empty())
	system.tick(state, params)
	assert_eq(state.defeat_causes, [&"depopulation"])
	assert_eq(state.population_peak, 9.0)


func test_bankruptcy_earliest_defeat_remains_480() -> void:
	var state: EconomyState = EconomyState.new()
	state.money = -1
	var system: DefeatSystem = DefeatSystem.new()
	for index: int in range(479):
		system.tick(state, _params)
	assert_true(state.defeat_causes.is_empty())
	system.tick(state, _params)
	assert_eq(state.defeat_causes, [&"bankruptcy", &"depopulation"])


func test_hunger_overrides_high_and_neutral_satisfaction_and_immigration() -> void:
	for happiness: float in [100.0, 50.0]:
		var state: EconomyState = EconomyState.new()
		state.population = 20
		state.housing_capacity = 100
		state.satisfaction = happiness
		state.bread_coverage = 0.0
		state.hunger_smoothed_coverage = 0.49
		state.immigration_fraction = 0.99
		for index: int in range(60):
			GrowthSystem.new().tick(state, _params)
		assert_eq(state.population, 12)
		assert_eq(state.immigration_fraction, 0.0)


func test_hunger_equality_recovery_and_threshold_modifier() -> void:
	var state: EconomyState = EconomyState.new()
	state.population = 20
	state.satisfaction = 50.0
	state.bread_coverage = 0.0
	state.hunger_smoothed_coverage = 0.6
	for index: int in range(60):
		GrowthSystem.new().tick(state, _params)
	assert_eq(state.population, 20)
	state.hunger_smoothed_coverage = 0.599
	GrowthSystem.new().tick(state, _params)
	assert_gt(state.emigration_fraction, 0.0)
	state.hunger_smoothed_coverage = 0.75
	GrowthSystem.new().tick(state, _params)
	assert_eq(state.emigration_fraction, 0.0)
	var params: Params = _with({&"population.growth.hunger_emigration_threshold": 0.75})
	state.hunger_smoothed_coverage = 0.6
	for index: int in range(60):
		GrowthSystem.new().tick(state, params)
	assert_eq(state.population, 12)


func test_smoothed_coverage_updates_once_before_growth_and_restores() -> void:
	var state: EconomyState = EconomyState.new()
	state.population = 20
	state.satisfaction = 100.0
	state.hunger_smoothed_coverage = 0.65
	state.defeat_initialized = true
	state.buildings.append({"definition_id": &"housing", "cell": [1, 1]})
	var params: Params = _with({&"defeat.hunger.smoothing": 0.1})
	var sim: Simulation = Simulation.new(params, state, 42, _context)
	sim.tick()
	var snapshot: Dictionary = sim.snapshot()["economy"]
	assert_almost_eq(snapshot["hunger_smoothed_coverage"], 0.585, 0.00000001)
	assert_gt(snapshot["emigration_fraction"], 0.0, "Growth uses this tick's smoothed coverage")
	assert_eq(snapshot["hunger"]["status"], &"ok")
	assert_eq(snapshot["immigration_fraction"], 0.0)
	var restored: Simulation = Simulation.new(params, EconomyState.from_dict(snapshot), 42, _context)
	sim.tick()
	restored.tick()
	assert_eq(sim.snapshot()["economy"], restored.snapshot()["economy"])
	assert_almost_eq(sim.snapshot()["economy"]["hunger_smoothed_coverage"], 0.5265, 0.00000001)


func test_new_city_has_bread_and_target_satisfaction_without_advancing_time() -> void:
	var state: EconomyState = EconomyState.new()
	state.population = 10
	state.buildings.append({"definition_id": &"housing", "cell": [1, 1]})
	var before: Dictionary = state.to_dict()
	var sim: Simulation = _new_city(state)
	if sim == null:
		return
	var snapshot: Dictionary = sim.snapshot()
	var economy: Dictionary = snapshot["economy"]
	assert_eq(snapshot["tick_count"], 0)
	assert_eq(economy["defeat_elapsed_seconds"], 0)
	assert_eq(economy["stocks"][&"bread"], 40)
	assert_eq(economy["bread_fraction"], 0.0)
	assert_eq(economy["bread_consumed"], 0.0)
	assert_eq(economy["bread_coverage"], 1.0)
	assert_eq(economy["hunger_smoothed_coverage"], 1.0)
	assert_eq(economy["satisfaction"], 90.0)
	assert_eq(economy["satisfaction_target"], 90.0)
	assert_eq(economy["satisfaction_breakdown"]["smoothed"], 90.0)
	assert_eq(state.to_dict(), before)
	state.stocks[&"bread"] = 99
	assert_eq(sim.snapshot()["economy"]["stocks"][&"bread"], 40)
	sim.apply_command(SetTaxCommand.new(0.5))
	sim.tick()
	assert_almost_eq(sim.snapshot()["economy"]["satisfaction"], 89.0, 0.00000001)


func test_new_city_uses_params_and_previews_coverage_without_consumption() -> void:
	var state: EconomyState = EconomyState.new()
	state.population = 120
	state.stocks[&"bread"] = 100
	state.bread_fraction = 0.75
	state.buildings.append({"definition_id": &"housing", "cell": [1, 1]})
	var params: Params = _with({&"population.initial_bread": 1,
		&"population.tax.rate": 0.5, &"population.satisfaction.overcrowding_weight": 0})
	var sim: Simulation = _new_city(state, params)
	if sim == null:
		return
	var snapshot: Dictionary = sim.snapshot()["economy"]
	assert_eq(snapshot["stocks"][&"bread"], 1)
	assert_eq(snapshot["bread_fraction"], 0.0)
	assert_eq(snapshot["bread_coverage"], 0.5)
	assert_eq(snapshot["hunger_smoothed_coverage"], 0.5)
	assert_eq(snapshot["satisfaction"], 30.0)
	assert_eq(snapshot["bread_consumed"], 0.0)
	assert_eq(snapshot["housing_capacity"], 20)


func test_empty_new_city_coverage_uses_existing_reserve_lookahead() -> void:
	var state: EconomyState = EconomyState.new()
	for reserve: int in [0, 1, 2, 40]:
		# Two immigrants a minute need two loaves of reserve; pinned so it does not follow data/.
		var sim: Simulation = _new_city(state, _with({&"population.initial_bread": reserve,
			&"population.growth.immigration_per_minute": 2.0}))
		if sim == null:
			return
		var snapshot: Dictionary = sim.snapshot()["economy"]
		assert_eq(snapshot["bread_coverage"], 1.0 if reserve >= 2 else 0.0)
		assert_eq(snapshot["satisfaction"], 90.0 if reserve >= 2 else 0.0)
		assert_eq(snapshot["stocks"][&"bread"], reserve)


func test_explicit_constructor_and_restore_preserve_bread_and_happiness() -> void:
	var state: EconomyState = EconomyState.new()
	state.population = 10
	state.stocks[&"bread"] = 3
	state.satisfaction = 17.0
	var sim: Simulation = Simulation.new(_params, state, 42, _context)
	var snapshot: Dictionary = sim.snapshot()["economy"]
	assert_eq(snapshot["stocks"][&"bread"], 3)
	assert_eq(snapshot["satisfaction"], 17.0)
	var restored: Simulation = Simulation.new(_params, EconomyState.from_dict(snapshot), 42, _context)
	assert_eq(restored.snapshot()["economy"], snapshot)


func test_authorized_docs_record_depopulation_duration_from_data() -> void:
	var duration: int = int(_params.get_value(&"defeat.depopulation.duration_seconds"))
	for path: String in ["res://docs/GDD.md", "res://docs/DECISIONS.md"]:
		var text: String = FileAccess.get_file_as_string(path)
		var row: String = ""
		for line: String in text.split("\n"):
			if line.begins_with("| Despoblación |") or line.begins_with("| D-013 |"):
				row = line
		assert_ne(row, "")
		assert_string_contains(row, "%d s" % duration)


func test_hunger_hysteresis_persists_until_recovery_and_reactivates() -> void:
	var state: EconomyState = EconomyState.new()
	state.population = 20
	state.housing_capacity = 100
	state.satisfaction = 100.0
	state.bread_coverage = 1.0
	var coverages: Array[float] = [0.6, 0.599, 0.6, 0.749, 0.75, 0.599]
	var expected: Array[bool] = [false, true, true, true, false, true]
	for index: int in range(coverages.size()):
		state.hunger_smoothed_coverage = coverages[index]
		GrowthSystem.new().tick(state, _params)
		var active: bool = expected[index]
		assert_eq(state.to_dict().get("hunger_emigration_active"), active)
		if active:
			assert_gt(state.emigration_fraction, 0.0)
			assert_eq(state.immigration_fraction, 0.0)
		else:
			assert_eq(state.emigration_fraction, 0.0)
			assert_gt(state.immigration_fraction, 0.0)


func test_hysteresis_round_trip_preserves_active_and_inactive_mid_band() -> void:
	for active: bool in [false, true]:
		var state: EconomyState = EconomyState.new()
		state.population = 20
		state.satisfaction = 50.0
		state.bread_coverage = 1.0
		state.hunger_smoothed_coverage = 0.599 if active else 0.7
		GrowthSystem.new().tick(state, _params)
		state.hunger_smoothed_coverage = 0.7
		var snapshot: Dictionary = state.to_dict()
		assert_eq(snapshot.get("hunger_emigration_active"), active)
		var restored: EconomyState = EconomyState.from_dict(snapshot)
		assert_eq(restored.to_dict(), snapshot)
		for index: int in range(30):
			GrowthSystem.new().tick(state, _params)
			GrowthSystem.new().tick(restored, _params)
		assert_eq(restored.to_dict(), state.to_dict())
		assert_eq(state.to_dict().get("hunger_emigration_active"), active)
		snapshot.erase("hunger_emigration_active")
		assert_eq(EconomyState.from_dict(snapshot).to_dict().get("hunger_emigration_active"), false)


func test_empty_city_hysteresis_recovers_and_low_satisfaction_still_emigrates() -> void:
	var state: EconomyState = EconomyState.new()
	state.hunger_smoothed_coverage = 0.0
	GrowthSystem.new().tick(state, _params)
	assert_eq(state.to_dict().get("hunger_emigration_active"), true)
	state.hunger_smoothed_coverage = 0.75
	GrowthSystem.new().tick(state, _params)
	assert_eq(state.to_dict().get("hunger_emigration_active"), false)
	state.population = 20
	state.satisfaction = 0.0
	GrowthSystem.new().tick(state, _params)
	assert_gt(state.emigration_fraction, 0.0)


func test_empty_during_grace_restores_without_warning_and_recovers_after_grace() -> void:
	var state: EconomyState = EconomyState.new()
	state.population = 10
	var system: DefeatSystem = DefeatSystem.new()
	system.initialize(state, _params)
	state.population = 0
	for index: int in range(200):
		system.tick(state, _params)
	assert_eq(state.depopulation.status, &"ok")
	assert_eq(state.depopulation.cause, &"")
	assert_eq(state.depopulation.elapsed_seconds, 0)
	state = EconomyState.from_dict(state.to_dict())
	for index: int in range(100):
		system.tick(state, _params)
	assert_eq(state.depopulation.status, &"ok")
	system.tick(state, _params)
	assert_eq(state.depopulation.status, &"warning")
	assert_eq(state.depopulation.elapsed_seconds, 1)
	state.population = 10
	system.tick(state, _params)
	assert_eq(state.depopulation.status, &"ok")
	assert_eq(state.depopulation.elapsed_seconds, 0)
	state.population = 0
	for index: int in range(179):
		system.tick(state, _params)
	assert_true(state.defeat_causes.is_empty())
	assert_eq(state.depopulation.elapsed_seconds, 179)
	system.tick(state, _params)
	assert_eq(state.defeat_causes, [&"depopulation"])


func test_empty_zero_grace_exposes_initial_warning() -> void:
	var state: EconomyState = EconomyState.new()
	DefeatSystem.new().initialize(state, _with({&"defeat.grace_seconds": 0}))
	assert_eq(state.depopulation.status, &"warning")
	assert_eq(state.depopulation.elapsed_seconds, 0)


func test_architecture_records_shared_smoothing_before_hunger_growth() -> void:
	var text: String = FileAccess.get_file_as_string("res://docs/ARCHITECTURE.md")
	var order: String = text.split("## Tick order")[1].split("## Data example")[0]
	var consumption: int = order.find("Consumption:")
	var smoothing: int = order.find("Hunger coverage:")
	var satisfaction: int = order.find("Satisfaction")
	var growth: int = order.find("Growth:")
	assert_gt(consumption, -1)
	assert_gt(smoothing, consumption)
	assert_gt(satisfaction, smoothing)
	assert_gt(growth, satisfaction)
	assert_string_contains(order, "hunger emigration")


func test_role_modifiers_control_both_hysteresis_boundaries() -> void:
	var params: Params = _with({&"population.growth.hunger_emigration_threshold": 0.55,
		&"population.growth.hunger_emigration_recovery": 0.9})
	var state: EconomyState = EconomyState.new()
	state.population = 20
	state.satisfaction = 50.0
	for coverage: float in [0.55, 0.549, 0.75, 0.9]:
		state.hunger_smoothed_coverage = coverage
		GrowthSystem.new().tick(state, params)
		assert_eq(state.hunger_emigration_active, coverage == 0.549 or coverage == 0.75)
		assert_eq(state.immigration_fraction, 0.0)
	assert_eq(state.emigration_fraction, 0.0)


func test_simulation_constructor_preserves_mid_band_hysteresis() -> void:
	for active: bool in [false, true]:
		var state: EconomyState = EconomyState.new()
		state.population = 20
		state.defeat_initialized = true
		state.hunger_smoothed_coverage = 0.7
		state.hunger_emigration_active = active
		var sim: Simulation = Simulation.new(_params, state, 42, _context)
		var snapshot: Dictionary = sim.snapshot()["economy"]
		assert_eq(snapshot["hunger_emigration_active"], active)
		assert_eq(snapshot["hunger_smoothed_coverage"], 0.7)
		var restored: Simulation = Simulation.new(_params, EconomyState.from_dict(snapshot), 42, _context)
		assert_eq(restored.snapshot()["economy"], snapshot)
