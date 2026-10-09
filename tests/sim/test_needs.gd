extends GutTest

var _params: Params
var _state: EconomyState


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
	_state = EconomyState.new()
	_state.tax_rate = 0.25


func test_one_person_eats_continuously_without_integer_stock_hunger() -> void:
	_state.population = 1
	_state.stocks[&"bread"] = 1
	var loaded: DataLoadResult = DataLoader.new().load_all()
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"population.bread_decay_fraction_per_minute", &"set", 0))
	_params = Params.new(loaded.catalog, role)
	for index: int in range(60):
		ConsumptionSystem.new().tick(_state, _params)
		assert_almost_eq(_state.bread_coverage, 1.0, 0.00000001)
	assert_eq(_state.stocks[&"bread"], 0)
	assert_almost_eq(_state.bread_fraction, 0.0, 0.00000001)


func test_partial_bread_coverage_uses_this_tick_demand() -> void:
	_state.population = 120
	_state.stocks[&"bread"] = 1
	ConsumptionSystem.new().tick(_state, _params)
	assert_eq(_state.bread_demand, 2.0)
	assert_eq(_state.bread_consumed, 1.0)
	assert_eq(_state.bread_coverage, 0.5)
	ConsumptionSystem.new().tick(_state, _params)
	assert_eq(_state.bread_coverage, 0.0)


func test_empty_population_has_full_coverage_and_exact_minute_decay() -> void:
	_state.stocks[&"bread"] = 100
	for index: int in range(60):
		ConsumptionSystem.new().tick(_state, _params)
	assert_eq(_state.bread_coverage, 1.0)
	assert_almost_eq(float(_state.stocks[&"bread"]) + _state.bread_fraction, 95.0, 0.00000001)
	assert_typeof(_state.stocks[&"bread"], TYPE_INT)


func test_decay_only_applies_to_surplus_after_consumption() -> void:
	_state.population = 60
	_state.stocks[&"bread"] = 2
	ConsumptionSystem.new().tick(_state, _params)
	assert_eq(_state.bread_consumed, 1.0)
	assert_almost_eq(float(_state.stocks[&"bread"]) + _state.bread_fraction,
		pow(0.95, 1.0 / 60.0), 0.00000001)


func test_production_in_progress_is_not_edible() -> void:
	_state.population = 1
	_state.buildings.append({"definition_id": &"bakery", "output_fraction": 0.9})
	ConsumptionSystem.new().tick(_state, _params)
	assert_eq(_state.bread_consumed, 0.0)
	assert_eq(_state.bread_coverage, 0.0)


func test_satisfaction_breakdown_and_overcrowding_are_bounded() -> void:
	_state.population = 40
	_state.bread_coverage = 0.8
	_state.buildings.append({"definition_id": &"housing"})
	SatisfactionSystem.new().tick(_state, _params)
	assert_eq(_state.housing_capacity, 20)
	assert_eq(_state.overcrowding, 0.5)
	assert_eq(_state.satisfaction_breakdown, {"bread": 80.0, "tea": 0.0,
		"tax": 10.0, "overcrowding": 15.0})
	assert_eq(_state.satisfaction, 55.0)
	_state.buildings.clear()
	_state.bread_coverage = 0.0
	SatisfactionSystem.new().tick(_state, _params)
	assert_eq(_state.overcrowding, 1.0)
	assert_eq(_state.satisfaction, 0.0)
	_state.population = 0
	_state.bread_coverage = 1.0
	SatisfactionSystem.new().tick(_state, _params)
	assert_eq(_state.overcrowding, 0.0)
	assert_eq(_state.satisfaction, 90.0)


func test_role_modifiers_apply_to_consumption_capacity_and_weights() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(&"population.bread_per_person_per_minute", &"set", 2),
		Modifier.new(&"building.housing.capacity", &"set", 10),
		Modifier.new(&"population.satisfaction.tax_weight", &"set", 20)])
	_params = Params.new(loaded.catalog, role)
	_state.population = 60
	_state.stocks[&"bread"] = 2
	_state.buildings.append({"definition_id": &"housing"})
	ConsumptionSystem.new().tick(_state, _params)
	SatisfactionSystem.new().tick(_state, _params)
	assert_eq(_state.bread_demand, 2.0)
	assert_eq(_state.housing_capacity, 10)
	assert_eq(_state.satisfaction_breakdown["tax"], 5.0)


func test_satisfaction_is_capped_at_100_with_modified_weights() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"population.satisfaction.bread_weight", &"set", 200))
	_params = Params.new(loaded.catalog, role)
	SatisfactionSystem.new().tick(_state, _params)
	assert_eq(_state.satisfaction, 100.0)
	assert_eq(_state.satisfaction_breakdown["bread"], 200.0)
