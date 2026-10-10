extends GutTest


class SupplyCommand extends SimulationCommand:
	func execute(state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
		state.stocks[&"wheat"] += 1
		state.money += 100


class PopulationCommand extends SimulationCommand:
	var _population: int


	func _init(population: int) -> void:
		_population = population


	func execute(state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
		state.population = _population


var _catalog: DataCatalog
var _params: Params
var _context: EconomyContext
var _initial: EconomyState


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_params = SimTestParams.isolated_params(_catalog)
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	_initial = EconomyState.new()
	_initial.satisfaction = float(_params.get_value(&"population.satisfaction.bread_weight"))
	_initial.stocks.assign({&"wheat": 0, &"flour": 0, &"bread": 0})
	_initial.money = 10000
	_initial.population = 10


func _add(id: StringName, cell: Array[int] = [1, 1]) -> void:
	_initial.buildings.append({"definition_id": id, "cell": cell})


func _sim(seed_value: int = 123) -> Simulation:
	return Simulation.new(_params, _initial, seed_value, _context)


func _ticks(sim: Simulation, count: int) -> Dictionary:
	for index: int in range(count):
		sim.tick()
	return sim.snapshot()["economy"]


func test_mill_converts_ten_wheat_to_ten_flour_per_minute() -> void:
	_add(&"mill")
	_initial.stocks[&"wheat"] = 10
	var state: Dictionary = _ticks(_sim(), 60)
	assert_eq(state["stocks"][&"wheat"], 0)
	assert_eq(state["stocks"][&"flour"], 10)
	assert_almost_eq(state["buildings"][0]["reserved_input"], 0.0, 0.000001)


func test_bakery_converts_ten_flour_to_twenty_bread_per_minute() -> void:
	_add(&"bakery")
	_initial.stocks[&"flour"] = 10
	var state: Dictionary = _ticks(_sim(), 60)
	assert_eq(state["stocks"][&"flour"], 0)
	assert_eq(state["stocks"][&"bread"], 20)
	assert_typeof(state["stocks"][&"bread"], TYPE_INT)


func test_missing_inputs_produce_nothing_and_accumulate_no_capacity() -> void:
	_add(&"mill")
	_add(&"bakery", [2, 1])
	var state: Dictionary = _ticks(_sim(), 120)
	assert_eq(state["stocks"], _initial.stocks)
	for building: Dictionary in state["buildings"]:
		assert_eq(building["reserved_input"], 0.0)
		assert_eq(building["output_fraction"], 0.0)


func test_one_input_is_reserved_once_and_production_stops_after_exhaustion() -> void:
	for id: StringName in [&"mill", &"bakery"]:
		_initial.buildings.clear()
		_add(id)
		var input: StringName = &"wheat" if id == &"mill" else &"flour"
		var output: StringName = &"flour" if id == &"mill" else &"bread"
		_initial.stocks.assign({&"wheat": 0, &"flour": 0, &"bread": 0})
		_initial.stocks[input] = 1
		var sim: Simulation = _sim()
		var first: Dictionary = _ticks(sim, 1)
		assert_eq(first["stocks"][input], 0)
		assert_gt(first["buildings"][0]["reserved_input"], 0.0)
		var done: Dictionary = _ticks(sim, 119)
		assert_eq(done["stocks"][input], 0)
		assert_eq(done["stocks"][output], 1 if id == &"mill" else 2)
		assert_eq(done["buildings"][0]["reserved_input"], 0.0)


func test_partial_staffing_reduces_both_converters_proportionally() -> void:
	for id: StringName in [&"mill", &"bakery"]:
		_initial.buildings.clear()
		_add(id)
		_initial.population = 1
		_initial.stocks.assign({&"wheat": 30, &"flour": 30, &"bread": 0})
		var state: Dictionary = _ticks(_sim(), 180)
		assert_eq(state["stocks"][&"flour"], 40 if id == &"mill" else 20)
		assert_eq(state["stocks"][&"bread"], 0 if id == &"mill" else 20)
		assert_eq(state["buildings"][0]["workers"], 1)


func test_fraction_accumulates_until_one_whole_output() -> void:
	_add(&"bakery")
	_initial.stocks[&"flour"] = 1
	var sim: Simulation = _sim()
	var state: Dictionary = _ticks(sim, 2)
	assert_eq(state["stocks"][&"bread"], 0)
	assert_almost_eq(state["buildings"][0]["output_fraction"], 2.0 / 3.0, 0.000001)
	state = _ticks(sim, 1)
	assert_eq(state["stocks"][&"bread"], 1)
	state = _ticks(sim, 3)
	assert_eq(state["stocks"][&"bread"], 2)
	assert_eq(state["stocks"][&"flour"], 0)


func test_zero_workers_do_not_reserve_inputs_or_buy_wheat() -> void:
	_add(&"wharf", [0, 7])
	_add(&"mill")
	_add(&"bakery", [2, 1])
	_initial.population = 0
	_initial.stocks[&"wheat"] = 10
	_initial.stocks[&"flour"] = 10
	var state: Dictionary = _ticks(_sim(), 120)
	assert_eq(state["stocks"], _initial.stocks)
	assert_eq(state["money"], _initial.money)
	for building: Dictionary in state["buildings"]:
		assert_eq(building["workers"], 0)
		assert_eq(building.get("reserved_input", 0.0), 0.0)


func test_workers_staff_chain_first_then_prioritize_bakery_mill_wharf() -> void:
	_add(&"wharf", [0, 7])
	_add(&"mill")
	_add(&"bakery", [2, 1])
	var expected: Dictionary[int, Array] = {2: [1, 1, 0], 4: [1, 1, 2], 7: [1, 3, 3]}
	for population: int in [2, 4, 7]:
		_initial.population = population
		var state: Dictionary = _ticks(_sim(), 1)
		var buildings: Array[Dictionary] = state["buildings"]
		assert_eq(buildings[0]["workers"], expected[population][0])
		assert_eq(buildings[1]["workers"], expected[population][1])
		assert_eq(buildings[2]["workers"], expected[population][2])


func test_same_type_workers_follow_construction_order_without_duplication() -> void:
	_add(&"bakery")
	_add(&"bakery", [2, 1])
	_initial.population = 4
	var state: Dictionary = _ticks(_sim(), 1)
	assert_eq(state["buildings"][0]["workers"], 3)
	assert_eq(state["buildings"][1]["workers"], 1)


func test_wharf_buys_wheat_and_spends_integer_pence_at_current_price() -> void:
	_add(&"wharf", [0, 7])
	var state: Dictionary = _ticks(_sim(), 54)
	assert_eq(state["stocks"][&"wheat"], 9)
	assert_eq(state["money"], _initial.money - 9 * int(_params.get_value(&"market.wheat.base_price")))
	assert_typeof(state["money"], TYPE_INT)


func test_partial_wharf_staffing_reduces_purchase_capacity() -> void:
	_add(&"wharf", [0, 7])
	_initial.population = 1
	var state: Dictionary = _ticks(_sim(), 48)
	assert_eq(state["stocks"][&"wheat"], 2)
	assert_eq(state["money"], _initial.money - 4)


func test_wharf_cannot_buy_unaffordable_units_or_create_debt() -> void:
	_add(&"wharf", [0, 7])
	_initial.money = 3
	var state: Dictionary = _ticks(_sim(), 54)
	assert_eq(state["stocks"][&"wheat"], 1)
	assert_eq(state["money"], 1)
	assert_lt(state["buildings"][0]["output_fraction"], 1.0)


func test_unfunded_wharf_does_not_bank_missed_purchases() -> void:
	_add(&"wharf", [0, 7])
	_initial.money = 0
	var sim: Simulation = _sim()
	_ticks(sim, 54)
	# Resume from a copied state with funds, preserving the fractional capacity.
	var resumed: EconomyState = EconomyState.from_dict(sim.snapshot()["economy"])
	resumed.money = 100
	var state: Dictionary = _ticks(Simulation.new(_params, resumed, 123, _context), 1)
	assert_eq(state["stocks"][&"wheat"], 0)
	assert_eq(state["money"], 100)


func test_price_starts_at_base_and_only_changes_on_market_interval() -> void:
	var sim: Simulation = _sim()
	var start: Dictionary = sim.snapshot()
	assert_eq(start["economy"]["wheat_price"], _params.get_value(&"market.wheat.base_price"))
	_ticks(sim, 59)
	assert_eq(sim.snapshot()["rng_state"], start["rng_state"])
	assert_eq(sim.snapshot()["economy"]["wheat_price"], start["economy"]["wheat_price"])
	sim.tick()
	assert_ne(sim.snapshot()["rng_state"], start["rng_state"])
	var after: Dictionary = sim.snapshot()
	_ticks(sim, 59)
	assert_eq(sim.snapshot()["rng_state"], after["rng_state"])


func test_fluctuating_price_stays_in_range_and_replay_matches_for_900_ticks() -> void:
	_add(&"wharf", [0, 7])
	_add(&"mill")
	_add(&"bakery", [2, 1])
	var first: Simulation = _sim()
	var second: Simulation = _sim()
	var seen: Dictionary[int, bool] = {}
	for index: int in range(900):
		first.tick()
		second.tick()
		var price: int = first.snapshot()["economy"]["wheat_price"]
		seen[price] = true
		assert_between(price, int(_params.get_value(&"market.wheat.min_price")),
			int(_params.get_value(&"market.wheat.max_price")))
	assert_gt(seen.size(), 1)
	assert_eq(first.snapshot(), second.snapshot())
	assert_gt(first.snapshot()["economy"]["stocks"][&"bread"], 0)
	assert_eq(first.snapshot()["economy"]["population"], _initial.population)


func test_multiple_wharves_use_one_current_price() -> void:
	_add(&"wharf", [0, 7])
	_add(&"wharf", [1, 7])
	var sim: Simulation = _sim()
	_ticks(sim, 59)
	var before: Dictionary = sim.snapshot()["economy"]
	var after: Dictionary = _ticks(sim, 1)
	assert_eq(after["stocks"][&"wheat"] - before["stocks"][&"wheat"], 2)
	assert_eq(before["money"] - after["money"], 2 * int(after["wheat_price"]))


func test_snapshot_and_round_trip_preserve_reserved_input_and_fractions() -> void:
	_add(&"bakery")
	_initial.stocks[&"flour"] = 2
	var sim: Simulation = _sim()
	_ticks(sim, 1)
	var snapshot: Dictionary = sim.snapshot()
	var restored: EconomyState = EconomyState.from_dict(snapshot["economy"])
	assert_eq(restored.to_dict(), snapshot["economy"])
	restored.buildings[0]["reserved_input"] = 0.0
	restored.buildings[0]["output_fraction"] = 0.0
	restored.wheat_price = 99
	assert_eq(sim.snapshot(), snapshot)
	assert_eq(_initial.buildings[0].keys().size(), 2)


func test_role_modifiers_control_production_staffing_and_market_interval() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([
		Modifier.new(&"building.bakery.recipe.seconds", &"set", 30),
		Modifier.new(&"building.bakery.jobs", &"set", 1),
		Modifier.new(&"building.bakery.recipe.inputs.flour", &"set", 5),
		Modifier.new(&"building.bakery.recipe.outputs.bread", &"set", 15),
		Modifier.new(&"market.wheat.price_update_seconds", &"set", 7),
		Modifier.new(&"market.wheat.min_price", &"set", 5),
		Modifier.new(&"market.wheat.max_price", &"set", 5),
		Modifier.new(&"market.wheat.base_price", &"set", 4.5),
	])
	_params = SimTestParams.isolated_params(_catalog, role)
	_add(&"bakery")
	_initial.population = 1
	_initial.stocks[&"flour"] = 5
	var sim: Simulation = _sim()
	var rng_before: int = sim.get_rng_state()
	_ticks(sim, 6)
	assert_eq(sim.get_rng_state(), rng_before)
	_ticks(sim, 1)
	assert_ne(sim.get_rng_state(), rng_before)
	var state: Dictionary = _ticks(sim, 23)
	assert_eq(state["stocks"][&"flour"], 0)
	assert_eq(state["stocks"][&"bread"], 15)
	assert_eq(state["wheat_price"], 5)


func test_wheat_field_and_housing_do_not_run_extra_economic_systems() -> void:
	_add(&"wheat_field")
	_add(&"housing", [2, 1])
	var state: Dictionary = _ticks(_sim(), 900)
	assert_eq(state["stocks"], _initial.stocks)
	assert_eq(state["population"], _initial.population)
	assert_eq(state["money"], _initial.money)


func test_small_fraction_does_not_round_up_before_a_unit_is_complete() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(&"building.mill.recipe.seconds", &"set", 1),
		Modifier.new(&"building.mill.recipe.inputs.wheat", &"set", 1),
		Modifier.new(&"building.mill.recipe.outputs.flour", &"set", 0.999999)])
	_params = SimTestParams.isolated_params(_catalog, role)
	_add(&"mill")
	_initial.stocks[&"wheat"] = 2
	var sim: Simulation = _sim()
	var state: Dictionary = _ticks(sim, 1)
	assert_eq(state["stocks"][&"flour"], 0)
	state = _ticks(sim, 1)
	assert_eq(state["stocks"][&"flour"], 1)
	assert_almost_eq(state["buildings"][0]["output_fraction"], 0.999998, 0.00000001)


func test_900_tick_chain_conserves_inputs_and_never_creates_negative_stocks() -> void:
	_add(&"wharf", [0, 7])
	_add(&"mill")
	_add(&"bakery", [2, 1])
	var sim: Simulation = _sim()
	var total_bought: int = 0
	for index: int in range(900):
		var before: Dictionary = sim.snapshot()["economy"]
		var state: Dictionary = _ticks(sim, 1)
		@warning_ignore("integer_division")
		var bought: int = (int(before["money"]) - int(state["money"])) / int(state["wheat_price"])
		total_bought += bought
		for stock: int in state["stocks"].values():
			assert_gte(stock, 0)
		var mill: Dictionary = state["buildings"][1]
		var bakery: Dictionary = state["buildings"][2]
		var wheat_equivalent: float = float(state["stocks"][&"wheat"]) \
			+ float(mill["reserved_input"]) + float(mill["output_fraction"]) \
			+ float(state["stocks"][&"flour"]) + float(bakery["reserved_input"]) \
			+ (float(state["stocks"][&"bread"]) + float(bakery["output_fraction"])) / 2.0
		assert_almost_eq(wheat_equivalent, float(total_bought), 0.00000001)


func test_tick_order_uses_new_wharf_wheat_and_mill_flour_in_same_tick() -> void:
	var role: RoleDef = RoleDef.new()
	for id: StringName in [&"wharf", &"mill", &"bakery"]:
		role.modifiers.append(Modifier.new(StringName("building.%s.recipe.seconds" % id), &"set", 1))
	_params = SimTestParams.isolated_params(_catalog, role)
	_add(&"wharf", [0, 7])
	_add(&"mill")
	_add(&"bakery", [2, 1])
	var state: Dictionary = _ticks(_sim(), 1)
	assert_eq(state["stocks"][&"wheat"], 0)
	assert_eq(state["stocks"][&"flour"], 0)
	assert_eq(state["stocks"][&"bread"], 20)
	assert_eq(state["money"], _initial.money - 20)


func test_input_shortage_does_not_bank_idle_production_time() -> void:
	_add(&"mill")
	var sim: Simulation = _sim()
	_ticks(sim, 120)
	sim.apply_command(SupplyCommand.new())
	var state: Dictionary = _ticks(sim, 1)
	assert_eq(state["stocks"][&"flour"], 0)
	assert_gt(state["buildings"][0]["reserved_input"], 0.0)
	state = _ticks(sim, 5)
	assert_eq(state["stocks"][&"flour"], 1)


func test_reserved_work_pauses_without_workers_and_resumes_without_double_consumption() -> void:
	_add(&"bakery")
	_initial.stocks[&"flour"] = 1
	var sim: Simulation = _sim()
	var working: Dictionary = _ticks(sim, 2)
	sim.apply_command(PopulationCommand.new(0))
	var paused: Dictionary = _ticks(sim, 120)
	assert_eq(paused["stocks"], working["stocks"])
	assert_eq(paused["buildings"][0]["reserved_input"], working["buildings"][0]["reserved_input"])
	assert_eq(paused["buildings"][0]["output_fraction"], working["buildings"][0]["output_fraction"])
	sim.apply_command(PopulationCommand.new(3))
	var done: Dictionary = _ticks(sim, 4)
	assert_eq(done["stocks"][&"flour"], 0)
	assert_eq(done["stocks"][&"bread"], 2)


func test_wharf_resumes_funded_purchases_at_normal_rate() -> void:
	_add(&"wharf", [0, 7])
	_initial.money = 0
	var sim: Simulation = _sim()
	_ticks(sim, 54)
	sim.apply_command(SupplyCommand.new())
	var state: Dictionary = _ticks(sim, 1)
	assert_eq(state["stocks"][&"wheat"], 1, "Only the supplied wheat, no purchase backlog")
	assert_eq(state["money"], 100)
	state = _ticks(sim, 5)
	assert_eq(state["stocks"][&"wheat"], 2)
	assert_eq(state["money"], 100 - int(state["wheat_price"]))


func test_nonpositive_market_interval_keeps_price_and_rng_but_allows_purchases() -> void:
	_add(&"wharf", [0, 7])
	for interval: int in [0, -2]:
		var role: RoleDef = RoleDef.new()
		role.modifiers.append(Modifier.new(&"market.wheat.price_update_seconds", &"set", interval))
		_params = SimTestParams.isolated_params(_catalog, role)
		var sim: Simulation = _sim()
		var before: Dictionary = sim.snapshot()
		var state: Dictionary = _ticks(sim, 6)
		assert_eq(state["wheat_price"], before["economy"]["wheat_price"])
		assert_eq(sim.get_rng_state(), before["rng_state"])
		assert_eq(state["stocks"][&"wheat"], 1)
		assert_eq(state["money"], _initial.money - int(state["wheat_price"]))


func test_fractional_jobs_use_same_integer_capacity_for_assignment_and_rate() -> void:
	for id: StringName in [&"wharf", &"mill", &"bakery"]:
		for jobs: float in [2.5, 0.5, -0.5]:
			var role: RoleDef = RoleDef.new()
			role.modifiers.append(Modifier.new(StringName("building.%s.jobs" % id), &"set", jobs))
			_params = SimTestParams.isolated_params(_catalog, role)
			_initial.buildings.clear()
			_add(id)
			var output: StringName = _context.buildings[id].recipe.outputs[0]
			for population: int in [1, 10]:
				_initial.population = population
				_initial.stocks.assign({&"wheat": 20, &"flour": 20, &"bread": 0})
				var start_stock: int = _initial.stocks[output]
				var assigned: int = mini(population, maxi(0, int(jobs)))
				var state: Dictionary = _ticks(_sim(), 60)
				assert_eq(state["buildings"][0]["workers"], assigned)
				var expected_output: int = 0
				if assigned > 0:
					var output_per_minute: float = float(_params.get_value(
						StringName("building.%s.recipe.outputs.%s" % [id, output])))
					expected_output = roundi(output_per_minute * assigned / int(jobs))
				assert_eq(state["stocks"][output] - start_stock, expected_output)


func test_simulation_reconstruction_preserves_saved_market_price() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(&"market.wheat.min_price", &"set", 3),
		Modifier.new(&"market.wheat.max_price", &"set", 3)])
	_params = SimTestParams.isolated_params(_catalog, role)
	_add(&"wharf", [0, 7])
	var saved: Dictionary = _ticks(_sim(), 60)
	assert_eq(saved["wheat_price"], 3)
	assert_ne(saved["wheat_price"], _params.get_value(&"market.wheat.base_price"))
	var restored: EconomyState = EconomyState.from_dict(saved)
	var sim: Simulation = Simulation.new(_params, restored, 123, _context)
	assert_eq(sim.snapshot()["economy"], saved)
	var next: Dictionary = _ticks(sim, 6)
	assert_eq(next["wheat_price"], saved["wheat_price"])
	assert_eq(next["money"], int(saved["money"]) - 3)
	assert_eq(next["stocks"][&"wheat"], int(saved["stocks"][&"wheat"]) + 1)


func test_simulation_reconstruction_preserves_zero_price() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(&"market.wheat.min_price", &"set", 0),
		Modifier.new(&"market.wheat.max_price", &"set", 0)])
	_params = SimTestParams.isolated_params(_catalog, role)
	_add(&"wharf", [0, 7])
	var saved: Dictionary = _ticks(_sim(), 60)
	assert_eq(saved["wheat_price"], 0)
	var restored: EconomyState = EconomyState.from_dict(saved)
	var sim: Simulation = Simulation.new(_params, restored, 123, _context)
	assert_eq(sim.snapshot()["economy"], saved)
	var next: Dictionary = _ticks(sim, 6)
	assert_eq(next["wheat_price"], 0)
	assert_eq(next["money"], saved["money"])


func test_chain_first_worker_precedes_a_second_bakery_worker() -> void:
	_add(&"bakery", [2, 1])
	_add(&"mill")
	_add(&"wharf", [0, 7])
	for population: int in range(1, 4):
		_initial.population = population
		var state: Dictionary = _ticks(_sim(), 1)
		assert_eq(state["buildings"][2]["workers"], 1)
		assert_eq(state["buildings"][1]["workers"], 1 if population >= 2 else 0)
		assert_eq(state["buildings"][0]["workers"], 1 if population >= 3 else 0)


func test_lower_population_keeps_every_chain_stage_running() -> void:
	_add(&"wharf", [0, 7])
	_add(&"mill")
	_add(&"bakery", [2, 1])
	var sim: Simulation = _sim()
	_ticks(sim, 1)
	sim.apply_command(PopulationCommand.new(3))
	var state: Dictionary = _ticks(sim, 180)
	for building: Dictionary in state["buildings"]:
		assert_eq(building["workers"], 1)
	assert_gt(state["stocks"][&"bread"], 0, "The complete chain still feeds its town")


func test_emigration_exactly_reverses_both_assignment_phases() -> void:
	_add(&"bakery")
	_add(&"wharf", [0, 7])
	_add(&"mill", [2, 1])
	_add(&"bakery", [3, 1])
	_initial.population = 13
	var fully_assigned: EconomyState = EconomyState.from_dict(_ticks(_sim(), 1))
	for population: int in range(12, -1, -1):
		fully_assigned.population = population
		WorkersSystem.trim_to_population(fully_assigned)
		var fresh: EconomyState = EconomyState.from_dict(_initial.to_dict())
		fresh.population = population
		WorkersSystem.new().tick(fresh, _params)
		for index: int in range(fresh.buildings.size()):
			assert_eq(fully_assigned.buildings[index]["workers"], fresh.buildings[index]["workers"],
				"Reverse allocation equals fresh allocation at population %d" % population)


func test_small_town_chain_remains_fed_after_population_drops() -> void:
	_add(&"wharf", [0, 7])
	_add(&"mill")
	_add(&"bakery", [2, 1])
	_add(&"housing", [3, 1])
	_initial.stocks[&"bread"] = 4
	var role: RoleDef = RoleDef.new()
	# Fix town size while exercising real consumption, decay, smoothing and finance.
	role.modifiers.append(Modifier.new(&"population.growth.immigration_per_minute", &"set", 0))
	_params = Params.new(_catalog, role)
	var sim: Simulation = _sim()
	sim.apply_command(PopulationCommand.new(3))
	for index: int in range(900):
		sim.tick()
		var state: Dictionary = sim.snapshot()["economy"]
		assert_eq(state["population"], 3)
		assert_almost_eq(state["bread_coverage"], 1.0, 0.00000001)
		for building: Dictionary in state["buildings"]:
			assert_eq(building["workers"], 0 if building["definition_id"] == &"housing" else 1)
	assert_gt(sim.snapshot()["economy"]["satisfaction"], 70.0)
