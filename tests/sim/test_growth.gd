extends GutTest

var _params: Params
var _context: EconomyContext
var _state: EconomyState


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
	_context = EconomyContext.new(loaded.catalog, loaded.catalog.maps[&"whitechapel_1850s"])
	_state = EconomyState.new()
	_state.population = 10
	_state.buildings.append({"definition_id": &"housing", "cell": [1, 1]})


func _ticks(sim: Simulation, count: int) -> Dictionary:
	for index: int in range(count):
		sim.tick()
	return sim.snapshot()["economy"]


func test_starving_town_shrinks_twice_as_fast_as_fed_unhappy_town() -> void:
	var starving: Simulation = Simulation.new(_params, _state, 42, _context)
	assert_eq(_ticks(starving, 60)["population"], 2)
	_state.satisfaction = 0.0
	_state.bread_coverage = 1.0
	_state.housing_capacity = 20
	for index: int in range(60):
		GrowthSystem.new().tick(_state, _params)
	assert_eq(_state.population, 6)


func test_fed_town_grows_with_free_housing_and_stops_at_capacity() -> void:
	_state.stocks[&"bread"] = 1000
	var sim: Simulation = Simulation.new(_params, _state, 42, _context)
	assert_eq(_ticks(sim, 60)["population"], 12)
	assert_eq(_ticks(sim, 600)["population"], 20)
	assert_eq(sim.snapshot()["economy"]["immigration_fraction"], 0.0)


func test_exact_thresholds_and_neutral_interval() -> void:
	_state.housing_capacity = 20
	_state.satisfaction = 70.0
	for index: int in range(30):
		GrowthSystem.new().tick(_state, _params)
	assert_eq(_state.population, 11)
	_state.satisfaction = 30.0
	for index: int in range(60):
		GrowthSystem.new().tick(_state, _params)
	assert_eq(_state.population, 11)
	_state.satisfaction = 29.999
	_state.bread_coverage = 1.0
	for index: int in range(15):
		GrowthSystem.new().tick(_state, _params)
	assert_eq(_state.population, 10)


func test_hunger_does_not_emigrate_above_threshold_and_scales_partial_shortage() -> void:
	_state.housing_capacity = 20
	_state.satisfaction = 40.0
	_state.bread_coverage = 0.5
	for index: int in range(60):
		GrowthSystem.new().tick(_state, _params)
	assert_eq(_state.population, 10)
	_state.satisfaction = 20.0
	for index: int in range(60):
		GrowthSystem.new().tick(_state, _params)
	assert_eq(_state.population, 4)


func test_blocked_and_reversed_growth_discard_pending_fractions() -> void:
	_state.satisfaction = 90.0
	_state.housing_capacity = 20
	for index: int in range(29):
		GrowthSystem.new().tick(_state, _params)
	assert_gt(_state.immigration_fraction, 0.0)
	_state.housing_capacity = 10
	GrowthSystem.new().tick(_state, _params)
	assert_eq(_state.immigration_fraction, 0.0)
	_state.housing_capacity = 20
	GrowthSystem.new().tick(_state, _params)
	assert_eq(_state.population, 10)
	_state.satisfaction = 0.0
	GrowthSystem.new().tick(_state, _params)
	assert_eq(_state.immigration_fraction, 0.0)
	assert_gt(_state.emigration_fraction, 0.0)
	_state.satisfaction = 50.0
	GrowthSystem.new().tick(_state, _params)
	assert_eq(_state.emigration_fraction, 0.0)


func test_empty_town_can_repopulate_without_emigration_debt() -> void:
	_state.population = 1
	var sim: Simulation = Simulation.new(_params, _state, 42, _context)
	var empty: Dictionary = _ticks(sim, 8)
	assert_eq(empty["population"], 0)
	assert_eq(empty["emigration_fraction"], 0.0)
	assert_eq(_ticks(sim, 30)["population"], 1)


func test_unemployed_leave_first_then_jobs_in_reverse_priority_and_order() -> void:
	_state.population = 14
	_state.buildings.assign([
		{"definition_id": &"wharf", "workers": 4},
		{"definition_id": &"bakery", "workers": 3},
		{"definition_id": &"mill", "workers": 3},
		{"definition_id": &"bakery", "workers": 3}])
	WorkersSystem.trim_to_population(_state)
	assert_eq(_state.employed, 13)
	assert_eq(_state.unemployed, 1)
	_state.population = 13
	WorkersSystem.trim_to_population(_state)
	assert_eq(_state.buildings[0]["workers"], 4)
	_state.population = 5
	WorkersSystem.trim_to_population(_state)
	assert_eq(_state.buildings[0]["workers"], 0)
	assert_eq(_state.buildings[2]["workers"], 0)
	assert_eq(_state.buildings[1]["workers"], 3)
	assert_eq(_state.buildings[3]["workers"], 2)
	assert_eq(_state.employed, 5)
	assert_eq(_state.unemployed, 0)


func test_demolishing_housing_causes_overcrowding_without_immediate_eviction() -> void:
	_state.stocks[&"bread"] = 100
	var sim: Simulation = Simulation.new(_params, _state, 42, _context)
	sim.apply_command(DemolishCommand.new(Vector2i(1, 1)))
	var snapshot: Dictionary = _ticks(sim, 1)
	assert_eq(snapshot["population"], 10)
	assert_eq(snapshot["housing_capacity"], 0)
	assert_eq(snapshot["overcrowding"], 1.0)
	assert_eq(_ticks(sim, 60)["population"], 10)


func test_role_modifier_controls_hunger_speed() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"population.growth.hunger_emigration_multiplier", &"set", 1))
	_params = Params.new(loaded.catalog, role)
	var sim: Simulation = Simulation.new(_params, _state, 42, _context)
	assert_eq(_ticks(sim, 60)["population"], 6)
