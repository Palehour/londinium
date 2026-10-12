extends GutTest

var _catalog: DataCatalog
var _params: Params
var _growth: GrowthSystem
var _defeat: DefeatSystem


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	_growth = GrowthSystem.new()
	_defeat = DefeatSystem.new()


func _window(params: Params) -> int:
	return int(params.get_value(&"defeat.depopulation.stability_window_seconds"))


# A fed city whose residents are about to leave for low satisfaction: the next tick makes one depart.
func _leaving_state() -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.population = 100
	state.satisfaction = 0.0
	state.satisfaction_target = 0.0
	state.emigration_fraction = 0.99
	return state


func _calm(state: EconomyState) -> void:
	state.satisfaction = 50.0
	state.satisfaction_target = 50.0


func test_new_state_has_never_lost_anyone_and_old_snapshots_default_to_it() -> void:
	var state: EconomyState = EconomyState.new()
	assert_eq(state.satisfaction_departure_age_seconds, -1)
	assert_true(_defeat.is_city_stable(state, _params))
	var values: Dictionary = state.to_dict()
	assert_true(values.has("satisfaction_departure_age_seconds"))
	values.erase("satisfaction_departure_age_seconds")
	assert_eq(EconomyState.from_dict(values).satisfaction_departure_age_seconds, -1)


func test_window_comes_from_data() -> void:
	assert_eq(_window(_params), 60)


func test_window_edge_59_60_61_seconds_after_the_last_departure() -> void:
	var state: EconomyState = _leaving_state()
	_growth.tick(state, _params)
	assert_eq(state.population, 99)
	assert_eq(state.satisfaction_departure_age_seconds, 0)
	assert_false(_defeat.is_city_stable(state, _params))
	_calm(state)
	for second: int in range(1, 62):
		_growth.tick(state, _params)
		assert_eq(state.satisfaction_departure_age_seconds, second)
		assert_eq(_defeat.is_city_stable(state, _params), second >= 60, "second %d" % second)
	assert_eq(state.population, 99, "Nobody else left while the city was calm")


func test_new_departure_reopens_the_window() -> void:
	var state: EconomyState = _leaving_state()
	_growth.tick(state, _params)
	_calm(state)
	for second: int in range(60):
		_growth.tick(state, _params)
	assert_true(_defeat.is_city_stable(state, _params))
	state.satisfaction = 0.0
	state.satisfaction_target = 0.0
	state.emigration_fraction = 0.99
	_growth.tick(state, _params)
	assert_eq(state.population, 98)
	assert_eq(state.satisfaction_departure_age_seconds, 0)
	assert_false(_defeat.is_city_stable(state, _params))


func test_fraction_without_a_whole_departure_is_not_a_departure() -> void:
	var state: EconomyState = EconomyState.new()
	state.population = 100
	_growth.tick(state, _params)
	assert_eq(state.population, 100)
	assert_gt(state.emigration_fraction, 0.0)
	assert_eq(state.satisfaction_departure_age_seconds, -1)
	assert_true(_defeat.is_city_stable(state, _params))


func test_target_recovery_stops_departures_and_the_window_runs() -> void:
	var state: EconomyState = _leaving_state()
	_growth.tick(state, _params)
	# Smoothed satisfaction is still low, but the target recovered: nobody leaves, the age grows.
	state.satisfaction_target = 60.0
	state.emigration_fraction = 0.99
	_growth.tick(state, _params)
	assert_eq(state.population, 99)
	assert_eq(state.satisfaction_departure_age_seconds, 1)


func test_departure_during_hunger_counts_when_satisfaction_emigration_is_active() -> void:
	var state: EconomyState = _leaving_state()
	state.hunger_smoothed_coverage = 0.0
	state.bread_coverage = 0.0
	_growth.tick(state, _params)
	assert_true(state.hunger_emigration_active)
	assert_lt(state.population, 100)
	assert_eq(state.satisfaction_departure_age_seconds, 0)


func test_hunger_only_departure_does_not_count_as_satisfaction_departure() -> void:
	var state: EconomyState = _leaving_state()
	_calm(state)
	state.hunger_smoothed_coverage = 0.0
	state.bread_coverage = 0.0
	_growth.tick(state, _params)
	assert_lt(state.population, 100)
	assert_eq(state.satisfaction_departure_age_seconds, -1)
	assert_false(_defeat.is_city_stable(state, _params), "Hunger emigration still blocks stability")


func test_hunger_conditions_keep_blocking_stability_after_a_quiet_window() -> void:
	var state: EconomyState = EconomyState.new()
	state.satisfaction_departure_age_seconds = 500
	assert_true(_defeat.is_city_stable(state, _params))
	state.hunger_emigration_active = true
	assert_false(_defeat.is_city_stable(state, _params))
	state.hunger_emigration_active = false
	state.hunger_smoothed_coverage = float(_params.get_value(&"population.growth.hunger_emigration_threshold")) - 0.001
	assert_false(_defeat.is_city_stable(state, _params))


func test_role_modifier_moves_the_window_edge() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"defeat.depopulation.stability_window_seconds", &"set", 90))
	var params: Params = Params.new(_catalog, role)
	var state: EconomyState = EconomyState.new()
	for age: int in [59, 60, 89, 90, 91]:
		state.satisfaction_departure_age_seconds = age
		assert_eq(_defeat.is_city_stable(state, params), age >= 90, "age %d" % age)


func test_age_round_trips_through_snapshot_and_continues_identically() -> void:
	var context: EconomyContext = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	var state: EconomyState = EconomyState.new()
	state.population = 100
	state.money = 10000
	state.stocks[&"bread"] = 1000
	state.satisfaction = 50.0
	state.satisfaction_departure_age_seconds = 30
	var sim: Simulation = Simulation.new(_params, state, 42, context)
	for index: int in range(10):
		sim.tick()
	var snapshot: Dictionary = sim.snapshot()["economy"]
	assert_eq(snapshot["satisfaction_departure_age_seconds"], 40)
	var restored: Simulation = Simulation.new(_params, EconomyState.from_dict(snapshot), 42, context)
	assert_eq(restored.snapshot()["economy"]["satisfaction_departure_age_seconds"], 40)
	for index: int in range(25):
		sim.tick()
		restored.tick()
		var current: Dictionary = sim.snapshot()["economy"]
		assert_eq(restored.snapshot()["economy"]["satisfaction_departure_age_seconds"],
			current["satisfaction_departure_age_seconds"])
	assert_eq(sim.snapshot()["economy"]["satisfaction_departure_age_seconds"], 65)
	assert_true(_defeat.is_city_stable(EconomyState.from_dict(sim.snapshot()["economy"]), _params))
