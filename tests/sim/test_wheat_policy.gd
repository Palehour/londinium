extends GutTest

# Issue #41: the wharf's purchase policy, the warehouse limits and the loss of stock. The wheat price
# is set on the state and the random walk is frozen, so every price here is the one the test chose.

var _catalog: DataCatalog
var _context: EconomyContext


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])


# Plenty of bread keeps the city from falling to a hunger riot, which would freeze long runs.
func _params(modifiers: Array[Modifier] = [], decay: bool = false) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign(modifiers)
	role.modifiers.append(Modifier.new(&"population.initial_bread", &"set", 1000000))
	role.modifiers.append(Modifier.new(&"market.wheat.price_update_seconds", &"set", 100000))
	if not decay:
		role.modifiers.append(Modifier.new(&"market.wheat.decay_fraction_per_minute", &"set", 0.0))
	return Params.new(_catalog, role)


# One fully staffed wharf; `policy` is [accumulate_price, max_price, target_stock, reserve_minutes] and the
# reserve defaults to 0, the behaviour before it existed. `chain` adds a mill and a bakery.
func _state(price: int, policy: Array = [0, 0, 0], stock: int = 0, chain: bool = false) -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.population = 20
	state.money = 10000
	state.wheat_price = price
	state.wheat_accumulate_price = policy[0]
	state.wheat_max_price = policy[1]
	state.wheat_target_stock = policy[2]
	state.wheat_reserve_minutes = policy[3] if policy.size() > 3 else 0
	state.buildings.append({"definition_id": &"wharf", "cell": [0, 7]})
	if chain:
		state.buildings.append({"definition_id": &"mill", "cell": [1, 7]})
		state.buildings.append({"definition_id": &"bakery", "cell": [2, 7]})
	if stock > 0:
		state.stocks[&"wheat"] = stock
	return state


func _sim(state: EconomyState, params: Params = _params()) -> Simulation:
	return Simulation.create_new(params, state, 42, _context)


func _run(sim: Simulation, ticks: int) -> void:
	for index: int in range(ticks):
		sim.tick()


func _wheat(sim: Simulation) -> int:
	return int(sim.snapshot()["economy"]["stocks"].get(&"wheat", 0))


func test_default_policy_buys_the_staffed_capacity_as_before() -> void:
	var sim: Simulation = _sim(_state(2))
	_run(sim, 60)
	assert_eq(_wheat(sim), 10, "the recipe's 10 a minute, no more")
	assert_eq(sim.snapshot()["stats"]["wheat_spent_per_minute"], 20.0)


func test_defaults_come_from_data_and_mean_no_policy() -> void:
	var sim: Simulation = _sim(EconomyState.new())
	var wheat: Dictionary = sim.snapshot()["market"]["wheat"]
	assert_eq(wheat["accumulate_price"], 0)
	assert_eq(wheat["max_price"], 0, "0 is no limit")
	assert_eq(wheat["target_stock"], 0)
	assert_eq(wheat["reserve_minutes"], 2, "the default reserve only matters once a maximum price is set")
	assert_eq(wheat["capacity"], 100)


func test_accumulating_buys_double_until_the_target_then_goes_back_to_normal() -> void:
	var sim: Simulation = _sim(_state(1, [1, 0, 60]))
	_run(sim, 60)
	assert_eq(_wheat(sim), 20, "accumulate_factor doubles the capacity")
	_run(sim, 120)
	assert_eq(_wheat(sim), 60, "stops exactly at the target")
	_run(sim, 60)
	assert_eq(_wheat(sim), 70, "past the target it buys the normal capacity again")


func test_a_price_above_the_accumulate_price_buys_normally() -> void:
	var sim: Simulation = _sim(_state(2, [1, 0, 60]))
	_run(sim, 60)
	assert_eq(_wheat(sim), 10)


func test_a_price_above_the_maximum_stops_the_wharf_without_banking_capacity() -> void:
	var sim: Simulation = _sim(_state(3, [0, 2, 0], 5))
	_run(sim, 120)
	assert_eq(_wheat(sim), 5)
	assert_eq(sim.snapshot()["stats"]["wheat_spent_per_minute"], 0.0)
	assert_true(sim.snapshot()["market"]["wheat"]["blocked_by_price"])
	sim.apply_command(SetWheatPolicyCommand.new(0, 0, 0, 0))
	_run(sim, 6)
	assert_eq(_wheat(sim), 6, "one unit in six ticks: the blocked minutes were not saved up")


func test_a_price_at_the_maximum_still_buys() -> void:
	var sim: Simulation = _sim(_state(2, [0, 2, 0]))
	_run(sim, 60)
	assert_eq(_wheat(sim), 10)


func test_the_storage_capacity_is_a_hard_limit_that_roles_can_change() -> void:
	var small: Simulation = _sim(_state(2), _params([Modifier.new(&"market.wheat.storage_capacity", &"set", 15)]))
	_run(small, 200)
	assert_eq(_wheat(small), 15)
	assert_eq(small.snapshot()["market"]["wheat"]["capacity"], 15)
	var big: Simulation = _sim(_state(2), _params([Modifier.new(&"market.wheat.storage_capacity", &"mul", 2.0)]))
	assert_eq(big.snapshot()["market"]["wheat"]["capacity"], 200)


func test_buying_never_goes_beyond_what_the_treasury_pays() -> void:
	var state: EconomyState = _state(3, [3, 0, 60])
	state.money = 7
	var sim: Simulation = _sim(state)
	_run(sim, 5)
	assert_lte(_wheat(sim), 2, "7 pence at 3 each is two units")
	assert_gte(int(sim.snapshot()["economy"]["money"]), 0)


func test_wheat_decays_slowly_and_in_whole_units() -> void:
	var state: EconomyState = _state(2, [0, 0, 0], 50)
	state.buildings.clear()
	var sim: Simulation = _sim(state, _params([], true))
	_run(sim, 600)
	assert_between(_wheat(sim), 44, 46, "about 1 % a minute for ten minutes")
	var tiny: EconomyState = _state(2, [0, 0, 0], 1)
	tiny.buildings.clear()
	var small: Simulation = _sim(tiny, _params([], true))
	_run(small, 60)
	assert_eq(_wheat(small), 1, "a single unit is not erased by rounding on every tick")


func test_decay_goes_on_when_purchases_are_off() -> void:
	var state: EconomyState = _state(2, [0, 0, 0], 50)
	state.buildings.clear()
	state.wheat_purchases_enabled = false
	var sim: Simulation = _sim(state, _params([], true))
	_run(sim, 1200)
	assert_lt(_wheat(sim), 43)


func test_pausing_purchases_keeps_the_policy_and_the_mill_lives_on_the_stock() -> void:
	var state: EconomyState = _state(1, [1, 2, 40], 30, true)
	state.wheat_purchases_enabled = false
	var sim: Simulation = _sim(state)
	_run(sim, 120)
	assert_lt(_wheat(sim), 30, "the mill ground some of it")
	assert_gt(_wheat(sim), 0)
	assert_eq(sim.snapshot()["stats"]["wheat_spent_per_minute"], 0.0)
	var economy: Dictionary = sim.snapshot()["economy"]
	assert_eq([economy["wheat_accumulate_price"], economy["wheat_max_price"], economy["wheat_target_stock"]], [1, 2, 40])


func test_the_command_sets_a_valid_policy() -> void:
	var sim: Simulation = _sim(_state(2))
	var command: SetWheatPolicyCommand = SetWheatPolicyCommand.new(1, 2, 60, 3)
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted)
	var wheat: Dictionary = sim.snapshot()["market"]["wheat"]
	assert_eq([wheat["accumulate_price"], wheat["max_price"], wheat["target_stock"], wheat["reserve_minutes"]], [1, 2, 60, 3])


func test_the_command_rejects_what_the_market_cannot_honour() -> void:
	var cases: Array[Array] = [
		[-1, 0, 0, 0], [0, -1, 0, 0], [0, 0, -1, 0], [0, 0, 0, -1],
		[4, 0, 0, 0], [0, 4, 0, 0], [3, 2, 0, 0], [0, 0, 101, 0], [0, 0, 0, 11],
	]
	for values: Array in cases:
		var sim: Simulation = _sim(_state(2, [1, 2, 30, 2]))
		var command: SetWheatPolicyCommand = SetWheatPolicyCommand.new(values[0], values[1], values[2], values[3])
		sim.apply_command(command)
		sim.tick()
		assert_false(command.accepted, str(values))
		assert_eq(command.reason, &"invalid_wheat_policy", str(values))
		var wheat: Dictionary = sim.snapshot()["market"]["wheat"]
		assert_eq([wheat["accumulate_price"], wheat["max_price"], wheat["target_stock"], wheat["reserve_minutes"]], [1, 2, 30, 2],
			"unchanged: %s" % str(values))


func test_the_command_limits_follow_the_roles_storage() -> void:
	var roomy: Params = _params([Modifier.new(&"market.wheat.storage_capacity", &"set", 200)])
	var command: SetWheatPolicyCommand = SetWheatPolicyCommand.new(0, 0, 150, 0)
	var sim: Simulation = _sim(_state(2), roomy)
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted)


func test_the_command_is_refused_after_defeat() -> void:
	var params: Params = _params([Modifier.new(&"defeat.grace_seconds", &"set", 2),
		Modifier.new(&"defeat.bankruptcy.duration_seconds", &"set", 5)])
	var state: EconomyState = _state(2)
	state.money = -100
	state.stocks[&"bread"] = 1000
	var sim: Simulation = _sim(state, params)
	_run(sim, 10)
	assert_eq(sim.snapshot()["defeat"]["causes"], [&"bankruptcy"])
	var late: SetWheatPolicyCommand = SetWheatPolicyCommand.new(1, 2, 60, 0)
	sim.apply_command(late)
	assert_false(late.accepted)
	assert_eq(late.reason, &"simulation_defeated")


func test_the_policy_survives_saving_and_loading() -> void:
	var state: EconomyState = _state(2, [1, 2, 60, 4])
	state.wheat_previous_price = 3
	state.wheat_decay_fraction = 0.25
	var loaded: EconomyState = EconomyState.from_dict(state.to_dict())
	assert_eq([loaded.wheat_accumulate_price, loaded.wheat_max_price, loaded.wheat_target_stock, loaded.wheat_reserve_minutes],
		[1, 2, 60, 4])
	assert_eq(loaded.wheat_previous_price, 3)
	assert_eq(loaded.wheat_decay_fraction, 0.25)
	assert_eq(EconomyState.from_dict({"stocks": {}, "money": 0, "population": 0, "buildings": []}).wheat_accumulate_price, -1,
		"older saves load with the defaults pending")


func test_the_snapshot_says_how_many_minutes_of_mill_the_stock_covers() -> void:
	var sim: Simulation = _sim(_state(2, [0, 0, 0], 30, true))
	sim.tick()
	var wheat: Dictionary = sim.snapshot()["market"]["wheat"]
	assert_almost_eq(float(wheat["consumption_per_minute"]), 10.0, 0.001)
	assert_almost_eq(float(wheat["minutes_covered"]), float(wheat["stock"]) / 10.0, 0.001)
	var no_mill: Simulation = _sim(_state(2, [0, 0, 0], 30))
	no_mill.tick()
	assert_eq(no_mill.snapshot()["market"]["wheat"]["minutes_covered"], -1.0, "no mill, nothing to divide by")


func test_the_snapshot_trend_remembers_the_last_price() -> void:
	var sim: Simulation = _sim(_state(2))
	var wheat: Dictionary = sim.snapshot()["market"]["wheat"]
	assert_eq(wheat["previous_price"], wheat["price"], "no repricing yet: flat")
	var changing: Simulation = _sim(_state(2), Params.new(_catalog, RoleDef.new()))
	_run(changing, 60)
	var after: Dictionary = changing.snapshot()["market"]["wheat"]
	assert_eq(after["previous_price"], 2, "the price before the first update")


func test_the_market_snapshot_is_an_isolated_copy() -> void:
	var sim: Simulation = _sim(_state(2))
	sim.tick()
	var snapshot: Dictionary = sim.snapshot()
	var expected: Dictionary = sim.snapshot().duplicate(true)
	snapshot["market"]["wheat"]["stock"] = 999
	snapshot["market"]["wheat"].clear()
	assert_eq(sim.snapshot(), expected)


func test_diagnostics_blame_the_price_only_when_the_warehouse_is_empty() -> void:
	var wharf: Dictionary = {"definition_id": &"wharf", "cell": [0, 7], "workers": 1}
	var state: EconomyState = _state(3, [0, 2, 0])
	assert_eq(BreadDiagnostics.building_reason(state, _context, wharf, _params()), &"wheat_price_above_max")
	state.stocks[&"wheat"] = 5
	assert_eq(BreadDiagnostics.building_reason(state, _context, wharf, _params()), &"ok", "the mills still have wheat")
	state.stocks[&"wheat"] = 0
	state.wheat_purchases_enabled = false
	assert_eq(BreadDiagnostics.building_reason(state, _context, wharf, _params()), &"wheat_purchases_disabled")
	state.wheat_purchases_enabled = true
	wharf["workers"] = 0
	assert_eq(BreadDiagnostics.building_reason(state, _context, wharf, _params()), &"no_workers")
	wharf["workers"] = 1
	state.wheat_price = 2
	assert_eq(BreadDiagnostics.building_reason(state, _context, wharf, _params()), &"ok", "at the maximum it buys")


# Mill: 10 wheat a minute fully staffed, so a reserve of 2 minutes is 20 units.
func test_over_the_maximum_the_wharf_waits_while_the_stock_covers_the_reserve() -> void:
	var sim: Simulation = _sim(_state(3, [0, 2, 0, 2], 40, true))
	_run(sim, 60)
	assert_eq(sim.snapshot()["stats"]["wheat_spent_per_minute"], 0.0, "stock 40 down to 30 stays over the 20 units of reserve")
	assert_true(sim.snapshot()["market"]["wheat"]["blocked_by_price"])


func test_under_the_reserve_the_wharf_buys_at_any_price_but_only_what_the_mill_consumes() -> void:
	var sim: Simulation = _sim(_state(3, [0, 2, 0, 2], 10, true))
	_run(sim, 120)
	var wheat: Dictionary = sim.snapshot()["market"]["wheat"]
	assert_gt(sim.snapshot()["stats"]["wheat_spent_per_minute"], 0.0, "it paid 3 although the maximum is 2")
	assert_lte(sim.snapshot()["stats"]["wheat_spent_per_minute"], 30.0, "no more than the mill grinds, 10 units at 3")
	assert_gt(_wheat(sim), 0, "the mill is not left waiting")
	assert_false(wheat["blocked_by_price"], "it is buying, so the maximum is not what stops it")


# Wharves staffed 3 of 4 and 1 of 4 can together buy the mill's 10 units a minute; sharing the limit
# equally between them (5 and 5, the second one unable to use its share) would leave the mill short.
func test_the_reserve_buying_limit_is_shared_by_capacity_not_split_equally() -> void:
	var state: EconomyState = _state(3, [0, 2, 0, 2], 10, true)
	state.population = 10
	state.buildings.insert(1, {"definition_id": &"wharf", "cell": [3, 7]})
	var sim: Simulation = _sim(state)
	_run(sim, 61)
	var workers: Array[int] = []
	for building: Dictionary in sim.snapshot()["economy"]["buildings"]:
		if building["definition_id"] == &"wharf":
			workers.append(int(building["workers"]))
	assert_eq(workers, [3, 1], "the fixture: wharves staffed 3 and 1")
	assert_gte(sim.snapshot()["stats"]["wheat_spent_per_minute"], 27.0, "about 10 units at 3 pence")
	assert_lte(sim.snapshot()["stats"]["wheat_spent_per_minute"], 30.0, "and never more than the mill grinds")


func test_pausing_purchases_is_not_reported_as_the_price_stopping_the_wharf() -> void:
	var state: EconomyState = _state(3, [0, 2, 0, 0], 0, true)
	state.wheat_purchases_enabled = false
	var sim: Simulation = _sim(state)
	_run(sim, 5)
	assert_false(sim.snapshot()["market"]["wheat"]["blocked_by_price"], "the toggle is the cause")
	sim.apply_command(SetWheatPurchasesCommand.new(true))
	_run(sim, 2)
	assert_true(sim.snapshot()["market"]["wheat"]["blocked_by_price"], "with purchases on, it is the price")


func test_without_a_reserve_the_maximum_applies_in_full() -> void:
	var sim: Simulation = _sim(_state(3, [0, 2, 0, 0], 0, true))
	_run(sim, 60)
	assert_eq(sim.snapshot()["stats"]["wheat_spent_per_minute"], 0.0)
	assert_true(sim.snapshot()["market"]["wheat"]["blocked_by_price"])


func test_the_reserve_buying_is_limited_by_space_and_by_the_treasury() -> void:
	var tight: Simulation = _sim(_state(3, [0, 2, 0, 2], 10, true),
		_params([Modifier.new(&"market.wheat.storage_capacity", &"set", 10)]))
	_run(tight, 120)
	assert_lte(_wheat(tight), 10, "a full warehouse buys nothing")
	var poor_state: EconomyState = _state(3, [0, 2, 0, 2], 0, true)
	poor_state.money = 4
	var poor: Simulation = _sim(poor_state)
	_run(poor, 30)
	assert_gte(int(poor.snapshot()["economy"]["money"]), 0)


func test_the_reason_appears_only_when_the_maximum_really_stops_the_wharf() -> void:
	var state: EconomyState = _state(3, [0, 2, 0, 0], 0, true)
	for building: Dictionary in state.buildings:
		building["workers"] = 3
	var wharf: Dictionary = state.buildings[0]
	assert_eq(BreadDiagnostics.building_reason(state, _context, wharf, _params()), &"wheat_price_above_max",
		"reserve 0: the maximum stops it")
	state.wheat_reserve_minutes = 2
	assert_eq(BreadDiagnostics.building_reason(state, _context, wharf, _params()), &"ok", "under the reserve it buys")


func test_roles_cannot_make_the_policy_defaults_impossible() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"policy.wheat.default_max_price", &"set", 9))
	assert_null(Params.new(_catalog, role).get_value(&"policy.wheat.default_max_price"))
	assert_push_error("Params: maximum price must be 0 (no limit) or inside the market's price range after role modifiers")
	var fractional: RoleDef = RoleDef.new()
	fractional.modifiers.append(Modifier.new(&"market.wheat.storage_capacity", &"mul", 1.001))
	assert_null(Params.new(_catalog, fractional).get_value(&"market.wheat.storage_capacity"))
	assert_push_error("Params: invalid range for 'market.wheat.storage_capacity'")
	var reserve: RoleDef = RoleDef.new()
	reserve.modifiers.append(Modifier.new(&"policy.wheat.default_reserve_minutes", &"set", 11))
	assert_null(Params.new(_catalog, reserve).get_value(&"policy.wheat.default_reserve_minutes"))
	assert_push_error("Params: invalid range for 'policy.wheat.default_reserve_minutes'")
	var deeper: RoleDef = RoleDef.new()
	deeper.modifiers.append(Modifier.new(&"policy.wheat.default_reserve_minutes", &"add", 3))
	assert_eq(Params.new(_catalog, deeper).get_value(&"policy.wheat.default_reserve_minutes"), 5.0, "a role may deepen the reserve")
	var fractional_reserve: RoleDef = RoleDef.new()
	fractional_reserve.modifiers.append(Modifier.new(&"policy.wheat.default_reserve_minutes", &"mul", 1.25))
	assert_null(Params.new(_catalog, fractional_reserve).get_value(&"policy.wheat.default_reserve_minutes"))
	assert_push_error("Params: invalid range for 'policy.wheat.default_reserve_minutes'")


func _documents() -> Dictionary[String, Dictionary]:
	var documents: Dictionary[String, Dictionary] = {}
	for folder: String in ["economy", "roles", "maps"]:
		for file_name: String in DirAccess.open("res://data/" + folder).get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))
	return documents


func test_data_rejects_an_impossible_policy_or_a_missing_file() -> void:
	var documents: Dictionary[String, Dictionary] = _documents()
	documents["economy/policy.json"]["wheat"]["default_max_price"] = 9
	assert_eq(DataLoader.new().load_documents(documents).errors,
		["economy/policy.json: maximum price must be 0 (no limit) or inside the market's price range"])
	documents = _documents()
	documents["economy/policy.json"]["wheat"]["default_target_stock"] = 101
	assert_eq(DataLoader.new().load_documents(documents).errors,
		["economy/policy.json: target stock cannot exceed the storage capacity"])
	documents = _documents()
	documents["economy/policy.json"]["wheat"]["default_reserve_minutes"] = 11
	assert_false(DataLoader.new().load_documents(documents).is_ok(), "reserve above 10 minutes")
	documents = _documents()
	documents.erase("economy/policy.json")
	assert_eq(DataLoader.new().load_documents(documents).errors, ["economy/policy.json: missing file"])
	documents = _documents()
	documents["economy/market.json"]["wheat"]["decay_fraction_per_minute"] = 1
	assert_false(DataLoader.new().load_documents(documents).is_ok(), "a loss of 100 % a minute is not a loss, it is a wipe")
