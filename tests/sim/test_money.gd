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
	_state.tax_rate = 0.25


func test_unemployed_do_not_pay_and_minute_fractional_payments_are_preserved() -> void:
	_state.population = 100
	_state.buildings.append({"definition_id": &"bakery", "workers": 3})
	_state.buildings.append({"definition_id": &"housing", "workers": 0})
	for index: int in range(60):
		MoneySystem.new().tick(_state, _params)
	assert_eq(_state.money, -3, "6 tax - 6 wages - 3 upkeep")
	assert_almost_eq(_state.tax_fraction, 0.0, 0.00000001)
	assert_almost_eq(_state.wage_fraction, 0.0, 0.00000001)
	assert_almost_eq(_state.upkeep_fraction, 0.0, 0.00000001)
	_state.buildings.clear()
	var before: int = _state.money
	for index: int in range(60):
		MoneySystem.new().tick(_state, _params)
	assert_eq(_state.money, before)
	assert_typeof(_state.money, TYPE_INT)


func test_full_wages_and_upkeep_are_paid_into_negative_treasury() -> void:
	_state.tax_rate = 0.0
	_state.buildings.append({"definition_id": &"wharf", "workers": 4})
	_state.buildings.append({"definition_id": &"housing", "workers": 0})
	for index: int in range(60):
		MoneySystem.new().tick(_state, _params)
	assert_eq(_state.money, -13)


func test_role_modifiers_control_tax_base_wages_and_upkeep() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(&"population.tax.base_per_employed_worker_per_minute", &"set", 16),
		Modifier.new(&"building.bakery.wage_per_worker_per_minute", &"set", 4),
		Modifier.new(&"building.bakery.upkeep_per_minute", &"set", 5)])
	_params = Params.new(loaded.catalog, role)
	_state.buildings.append({"definition_id": &"bakery", "workers": 3})
	for index: int in range(60):
		MoneySystem.new().tick(_state, _params)
	assert_eq(_state.money, -5, "12 tax - 12 wages - 5 upkeep")


func test_higher_taxes_give_more_money_and_less_satisfaction() -> void:
	_state.population = 3
	_state.stocks[&"bread"] = 100
	_state.buildings.assign([{"definition_id": &"bakery", "cell": [1, 1]},
		{"definition_id": &"housing", "cell": [2, 1]}])
	var low: Simulation = Simulation.new(_params, _state, 42, _context)
	var high: Simulation = Simulation.new(_params, _state, 42, _context)
	low.apply_command(SetTaxCommand.new(0.0))
	high.apply_command(SetTaxCommand.new(1.0))
	for index: int in range(15):
		low.tick()
		high.tick()
	var first: Dictionary = low.snapshot()["economy"]
	var second: Dictionary = high.snapshot()["economy"]
	assert_eq(first["population"], second["population"])
	assert_eq(second["money"] - first["money"], 6)
	assert_eq(first["satisfaction_target"] - second["satisfaction_target"], 40.0)
	assert_almost_eq(first["satisfaction"] - second["satisfaction"],
		40.0 * (1.0 - pow(0.9, 15)), 0.00000001)


func test_new_immigrant_only_works_and_eats_on_next_tick() -> void:
	_state.population = 2
	_state.satisfaction = 90.0
	_state.stocks[&"bread"] = 100
	_state.immigration_fraction = 29.0 / 30.0
	_state.buildings.assign([{"definition_id": &"bakery", "cell": [1, 1]},
		{"definition_id": &"housing", "cell": [2, 1]}])
	var sim: Simulation = Simulation.new(_params, _state, 42, _context)
	sim.tick()
	var first: Dictionary = sim.snapshot()["economy"]
	assert_eq(first["population"], 3)
	assert_eq(first["employed"], 2)
	assert_eq(first["unemployed"], 1)
	assert_almost_eq(first["bread_demand"], 2.0 / 60.0, 0.00000001)
	assert_almost_eq(first["tax_fraction"], 4.0 / 60.0, 0.00000001)
	sim.tick()
	var next: Dictionary = sim.snapshot()["economy"]
	assert_eq(next["employed"], 3)
	assert_eq(next["unemployed"], 0)
	assert_almost_eq(next["bread_demand"], 3.0 / 60.0, 0.00000001)


func test_departing_employed_worker_does_not_pay_tax_or_wages() -> void:
	_state.population = 3
	_state.emigration_fraction = 0.9
	_state.buildings.append({"definition_id": &"bakery", "cell": [1, 1]})
	var sim: Simulation = Simulation.new(_params, _state, 42, _context)
	sim.tick()
	var after: Dictionary = sim.snapshot()["economy"]
	assert_eq(after["population"], 2)
	assert_eq(after["employed"], 2)
	assert_almost_eq(after["tax_fraction"], 4.0 / 60.0, 0.00000001)
	assert_almost_eq(after["wage_fraction"], 4.0 / 60.0, 0.00000001)
