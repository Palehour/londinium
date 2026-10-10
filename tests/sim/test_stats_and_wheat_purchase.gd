extends GutTest

var _catalog: DataCatalog
var _context: EconomyContext


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])


func _params(modifiers: Array[Modifier] = []) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign(modifiers)
	return Params.new(_catalog, role)


func _sim(state: EconomyState, params: Params = _params()) -> Simulation:
	return Simulation.create_new(params, state, 42, _context)


func _state(population: int, money: int) -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.population = population
	state.money = money
	return state


func _flows(state: EconomyState, values: Array[int]) -> void:
	state.bread_produced_tick = values[0]
	state.bread_consumed_tick = float(values[1])
	state.bread_demand_tick = float(values[2])
	state.taxes_tick = values[3]
	state.wages_tick = values[4]
	state.upkeep_tick = values[5]
	state.wheat_spent_tick = values[6]
	state.construction_spent_tick = values[7]


func test_stats_window_rolls_over_ticks_and_balance_excludes_construction() -> void:
	var stats: Stats = Stats.new(2)
	var state: EconomyState = EconomyState.new()
	_flows(state, [2, 1, 2, 10, 3, 2, 1, 20])
	stats.record(state)
	var first: Dictionary = stats.snapshot()
	assert_false(first["complete"])
	assert_eq(first["window_seconds"], 1)
	assert_eq(first["bread_produced_per_minute"], 120.0)
	# 10 taxes - 3 wages - 2 upkeep - 1 wheat = 4 per second.
	assert_eq(first["operating_balance_per_minute"], 240.0)
	assert_eq(first["construction_spent_per_minute"], 1200.0)
	_flows(state, [0, 1, 1, 0, 1, 0, 0, 0])
	stats.record(state)
	var complete: Dictionary = stats.snapshot()
	assert_true(complete["complete"])
	assert_eq(complete["bread_produced_per_minute"], 60.0)
	assert_eq(complete["bread_demand_per_minute"], 90.0)
	assert_eq(complete["operating_balance_per_minute"], 90.0)
	_flows(state, [0, 0, 0, 0, 0, 0, 0, 0])
	stats.record(state)
	var rolled: Dictionary = stats.snapshot()
	assert_eq(rolled["window_seconds"], 2, "the oldest tick leaves the window")
	assert_eq(rolled["bread_produced_per_minute"], 0.0)
	assert_eq(rolled["operating_balance_per_minute"], -30.0)
	assert_eq(rolled["construction_spent_per_minute"], 0.0)


func test_window_size_comes_from_data_through_params() -> void:
	var default_sim: Simulation = _sim(_state(20, 10000))
	assert_eq(default_sim.snapshot()["stats"]["window_size"], 60)
	var sim: Simulation = _sim(_state(20, 10000), _params([Modifier.new(&"population.stats_window_seconds", &"set", 5)]))
	for index: int in range(12):
		sim.tick()
	var stats: Dictionary = sim.snapshot()["stats"]
	assert_eq(stats["window_size"], 5)
	assert_eq(stats["window_seconds"], 5)
	assert_true(stats["complete"])
	assert_eq(stats["window"].size(), 5, "the snapshot carries the whole window")
	assert_eq(stats["window"][0].keys().size(), Stats.KEYS.size())


func test_fractional_window_modifier_is_rejected_not_truncated() -> void:
	var key: StringName = &"population.stats_window_seconds"
	for value: float in [1.5, 59.9, 0.5]:
		assert_null(_params([Modifier.new(key, &"set", value)]).get_value(key), str(value))
		assert_push_error("Params: invalid range for '%s'" % key)
	assert_null(_params([Modifier.new(key, &"mul", 1.01)]).get_value(key))
	assert_push_error("Params: invalid range for '%s'" % key)
	assert_eq(_params([Modifier.new(key, &"set", 5)]).get_value(key), 5.0)
	assert_eq(_params([Modifier.new(key, &"mul", 0.5)]).get_value(key), 30.0)


func test_bread_rates_are_measured_flows_not_stock_differences() -> void:
	var sim: Simulation = _sim(_state(20, 10000))
	for index: int in range(60):
		sim.tick()
	var snapshot: Dictionary = sim.snapshot()
	# Stock fell (eaten and stale), yet nothing was produced: production must stay zero.
	assert_lt(snapshot["economy"]["stocks"][&"bread"], 40)
	assert_eq(snapshot["stats"]["bread_produced_per_minute"], 0.0)
	assert_gt(snapshot["stats"]["bread_consumed_per_minute"], 0.0)
	assert_almost_eq(snapshot["stats"]["bread_demand_per_minute"], 20.0, 0.5)
	var state: EconomyState = _state(20, 10000)
	state.stocks[&"flour"] = 100
	state.buildings.append({"definition_id": &"bakery", "cell": [1, 1]})
	var bakery: Simulation = _sim(state)
	for index: int in range(60):
		bakery.tick()
	# A fully staffed bakery turns 10 flour into 20 bread per minute.
	assert_almost_eq(bakery.snapshot()["stats"]["bread_produced_per_minute"], 20.0, 1.0)


func test_money_change_equals_operating_balance_minus_construction() -> void:
	var state: EconomyState = _state(20, 10000)
	state.buildings.append({"definition_id": &"wharf", "cell": [0, 7]})
	state.buildings.append({"definition_id": &"housing", "cell": [1, 1]})
	var sim: Simulation = _sim(state)
	for index: int in range(30):
		sim.tick()
	var before: int = sim.snapshot()["economy"]["money"]
	sim.apply_command(BuildCommand.new(_context, &"mill", Vector2i(2, 2)))
	for index: int in range(60):
		sim.tick()
	var stats: Dictionary = sim.snapshot()["stats"]
	assert_true(stats["complete"])
	assert_gt(stats["wheat_spent_per_minute"], 0.0)
	assert_eq(stats["construction_spent_per_minute"], float(_params().get_value(&"building.mill.cost")))
	assert_eq(stats["operating_balance_per_minute"], stats["taxes_per_minute"] - stats["wages_per_minute"]
		- stats["upkeep_per_minute"] - stats["wheat_spent_per_minute"])
	var after: int = sim.snapshot()["economy"]["money"]
	assert_eq(float(after - before), stats["operating_balance_per_minute"] - stats["construction_spent_per_minute"])


func _window_after(ticks: int, params: Params) -> Dictionary:
	var sim: Simulation = _sim(_chain_state(20, 10000), params)
	for index: int in range(ticks):
		sim.tick()
	return sim.snapshot()


func test_stats_window_round_trips_through_the_snapshot() -> void:
	var params: Params = _params()
	var saved: Dictionary = _window_after(75, params)
	var expected: Dictionary = saved["stats"].duplicate(true)
	var window: Array = saved["stats"]["window"]
	assert_eq(window.size(), 60)
	var loaded: Simulation = Simulation.new(params, EconomyState.from_dict(saved["economy"]), saved["seed"], _context, window)
	assert_eq(loaded.snapshot()["stats"], expected, "rates and window match before and after loading")
	window[0][&"taxes"] = 999.0
	window.clear()
	assert_eq(loaded.snapshot()["stats"]["window"], expected["window"], "the loaded window is a copy")
	loaded.tick()
	var after: Array = loaded.snapshot()["stats"]["window"]
	assert_eq(after.size(), 60)
	assert_eq(after.slice(0, 59), expected["window"].slice(1), "the restored window keeps rolling")
	var fresh: Simulation = Simulation.new(params, EconomyState.from_dict(saved["economy"]), saved["seed"], _context)
	assert_eq(fresh.snapshot()["stats"]["window_seconds"], 0, "no window means an empty one")


func test_restored_window_fits_the_current_size_and_rejects_bad_samples() -> void:
	var saved: Dictionary = _window_after(75, _params())
	var small: Params = _params([Modifier.new(&"population.stats_window_seconds", &"set", 5)])
	var loaded: Simulation = Simulation.new(small, EconomyState.from_dict(saved["economy"]), saved["seed"], _context, saved["stats"]["window"])
	assert_eq(loaded.snapshot()["stats"]["window"], saved["stats"]["window"].slice(55), "keeps the newest samples")
	var broken: Array = saved["stats"]["window"].duplicate(true)
	broken[30].erase(&"wages")
	var rejected: Simulation = Simulation.new(_params(), EconomyState.from_dict(saved["economy"]), saved["seed"], _context, broken)
	assert_push_error("Stats: malformed window sample; starting an empty window")
	assert_eq(rejected.snapshot()["stats"]["window_seconds"], 0)


func test_restore_rejects_nonfinite_or_negative_samples() -> void:
	var saved: Dictionary = _window_after(75, _params())
	for value: float in [NAN, INF, -INF, -1.0]:
		var broken: Array = saved["stats"]["window"].duplicate(true)
		broken[10][&"taxes"] = value
		var stats: Stats = Stats.new(60)
		stats.restore(broken)
		assert_push_error("Stats: malformed window sample; starting an empty window")
		assert_eq(stats.snapshot()["window_seconds"], 0, str(value))
	var zero: Array = saved["stats"]["window"].duplicate(true)
	zero[10][&"taxes"] = 0.0
	var accepted: Stats = Stats.new(60)
	accepted.restore(zero)
	assert_eq(accepted.snapshot()["window_seconds"], 60, "zero is a valid flow")


func test_wheat_purchase_command_stops_buying_but_not_price_fluctuation() -> void:
	# Plenty of bread keeps the wharf staffed for the whole run.
	var fed: Params = _params([Modifier.new(&"population.initial_bread", &"set", 100000)])
	var enabled: Simulation = _sim(_state(20, 10000), fed)
	var disabled: Simulation = _sim(_state(20, 10000), fed)
	for sim: Simulation in [enabled, disabled]:
		sim.apply_command(BuildCommand.new(_context, &"wharf", Vector2i(0, 7)))
	var command: SetWheatPurchasesCommand = SetWheatPurchasesCommand.new(false)
	disabled.apply_command(command)
	var prices: Array[int] = []
	for index: int in range(300):
		enabled.tick()
		disabled.tick()
		assert_eq(disabled.snapshot()["economy"]["wheat_price"], enabled.snapshot()["economy"]["wheat_price"])
		if prices.is_empty() or prices.back() != enabled.snapshot()["economy"]["wheat_price"]:
			prices.append(enabled.snapshot()["economy"]["wheat_price"])
	assert_true(command.accepted)
	assert_false(disabled.snapshot()["economy"]["wheat_purchases_enabled"])
	assert_gt(prices.size(), 1, "the price must keep fluctuating")
	assert_eq(disabled.snapshot()["economy"]["stocks"].get(&"wheat", 0), 0)
	assert_eq(disabled.snapshot()["stats"]["wheat_spent_per_minute"], 0.0)
	assert_gt(enabled.snapshot()["economy"]["stocks"].get(&"wheat", 0), 0)
	disabled.apply_command(SetWheatPurchasesCommand.new(true))
	for index: int in range(10):
		disabled.tick()
	assert_true(disabled.snapshot()["economy"]["wheat_purchases_enabled"])
	assert_gt(disabled.snapshot()["economy"]["stocks"].get(&"wheat", 0), 0)


func test_startup_wheat_purchase_flag_is_a_boolean_in_data_params_and_state() -> void:
	assert_typeof(_catalog.base_values[&"startup.wheat_purchases_enabled"], TYPE_BOOL)
	var key: StringName = &"startup.wheat_purchases_enabled"
	assert_typeof(_params().get_value(key), TYPE_BOOL)
	assert_eq(_params([Modifier.new(key, &"set", 0)]).get_value(key), false)
	assert_eq(_params([Modifier.new(key, &"set", 1)]).get_value(key), true)
	for modifier: Modifier in [Modifier.new(key, &"set", 2), Modifier.new(key, &"add", 1), Modifier.new(key, &"mul", 0)]:
		assert_null(_params([modifier]).get_value(key))
		assert_push_error("Params: boolean '%s' only accepts set 0 or 1" % key)
	var session: GameSession = GameSession.new(_catalog, _params([Modifier.new(key, &"set", 0)]))
	assert_typeof(session.get_snapshot()["economy"]["wheat_purchases_enabled"], TYPE_BOOL)
	assert_false(session.get_snapshot()["economy"]["wheat_purchases_enabled"])
	assert_true(GameSession.new(_catalog, _params()).get_snapshot()["economy"]["wheat_purchases_enabled"])


func test_data_rejects_a_numeric_wheat_purchase_switch() -> void:
	var documents: Dictionary[String, Dictionary] = {}
	for folder: String in ["economy", "roles", "maps"]:
		for file_name: String in DirAccess.open("res://data/" + folder).get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))
	for value: Variant in [1, 0, "true"]:
		documents["economy/startup.json"]["wheat_purchases_enabled"] = value
		var result: DataLoadResult = DataLoader.new().load_documents(documents)
		assert_eq(result.errors, ["economy/startup.json.wheat_purchases_enabled: expected a boolean"], str(value))


func _diagnostics(state: EconomyState, starving: bool = true) -> Dictionary:
	# create_new grants the startup bread; starving fixtures remove it to expose the shortage.
	var initial_bread: int = 0 if starving else 500
	var sim: Simulation = _sim(state, _params([Modifier.new(&"population.initial_bread", &"set", initial_bread)]))
	sim.tick()
	return sim.snapshot()["diagnostics"]


func _reason(diagnostics: Dictionary, id: StringName) -> StringName:
	for building: Dictionary in diagnostics["buildings"]:
		if building["definition_id"] == id:
			return building["reason"]
	return &""


func _chain_state(population: int, money: int) -> EconomyState:
	var state: EconomyState = _state(population, money)
	for id: StringName in [&"wharf", &"mill", &"bakery"]:
		state.buildings.append({"definition_id": id, "cell": [0, 7] if id == &"wharf" else [state.buildings.size(), 3]})
	state.buildings.append({"definition_id": &"housing", "cell": [5, 5]})
	return state


func test_diagnostics_explain_disabled_purchases_along_the_chain() -> void:
	var state: EconomyState = _chain_state(20, 10000)
	state.wheat_purchases_enabled = false
	var diagnostics: Dictionary = _diagnostics(state)
	assert_true(diagnostics["bread_short"])
	assert_eq(_reason(diagnostics, &"wharf"), &"wheat_purchases_disabled")
	assert_eq(_reason(diagnostics, &"mill"), &"no_input")
	assert_eq(_reason(diagnostics, &"bakery"), &"no_input")
	assert_eq(diagnostics["bread_causes"][0], {"definition_id": &"wharf", "reason": &"wheat_purchases_disabled"})
	assert_eq(diagnostics["bread_causes"].size(), 3)
	for building: Dictionary in diagnostics["buildings"]:
		assert_ne(building["definition_id"], &"housing", "housing has no jobs to diagnose")
		assert_eq(building["workers"], building["jobs"])


func test_diagnostics_report_missing_workers_money_and_buildings() -> void:
	var nobody: Dictionary = _diagnostics(_chain_state(0, 10000))
	for id: StringName in [&"wharf", &"mill", &"bakery"]:
		assert_eq(_reason(nobody, id), &"no_workers")
	var broke: EconomyState = _chain_state(20, 0)
	assert_eq(_reason(_diagnostics(broke), &"wharf"), &"no_money_for_wheat")
	var empty: Dictionary = _diagnostics(_state(20, 10000))
	assert_eq(empty["bread_causes"][2], {"definition_id": &"bakery", "reason": &"missing_building"})
	var fed: EconomyState = _chain_state(20, 10000)
	fed.stocks[&"wheat"] = 50
	fed.stocks[&"flour"] = 50
	var working: Dictionary = _diagnostics(fed, false)
	assert_false(working["bread_short"])
	assert_true(working["bread_causes"].is_empty())
	assert_eq(_reason(working, &"mill"), &"ok")


func test_no_money_reason_uses_the_market_affordability_rule() -> void:
	var state: EconomyState = _state(20, 5)
	state.wheat_price = 3
	assert_eq(MarketSystem.affordable_wheat(state, 10), 1)
	state.money = 2
	assert_eq(MarketSystem.affordable_wheat(state, 10), 0)
	state.money = -50
	assert_eq(MarketSystem.affordable_wheat(state, 10), 0)
	state.wheat_price = 0
	assert_eq(MarketSystem.affordable_wheat(state, 10), 10, "free wheat is never limited by money")
	var wharf: Dictionary = {"definition_id": &"wharf", "cell": [0, 7], "workers": 1}
	state.wheat_price = 3
	state.money = 2
	assert_eq(BreadDiagnostics.building_reason(state, _context, wharf, _params()), &"no_money_for_wheat", "cannot buy one unit")
	state.money = 3
	assert_eq(BreadDiagnostics.building_reason(state, _context, wharf, _params()), &"ok", "exactly one unit is affordable")
	state.money = 2
	state.wheat_price = 0
	assert_eq(BreadDiagnostics.building_reason(state, _context, wharf, _params()), &"ok", "free wheat needs no money")


func _hungry_chain(population: int) -> Dictionary:
	var state: EconomyState = _chain_state(population, 10000)
	state.stocks[&"wheat"] = 500
	state.stocks[&"flour"] = 500
	# Demand far above what one fully supplied chain can bake.
	var params: Params = _params([Modifier.new(&"population.initial_bread", &"set", 0),
		Modifier.new(&"population.bread_per_person_per_minute", &"set", 50)])
	var sim: Simulation = _sim(state, params)
	sim.tick()
	return sim.snapshot()["diagnostics"]


func test_diagnostics_explain_shortage_when_every_stage_works() -> void:
	var full: Dictionary = _hungry_chain(20)
	assert_true(full["bread_short"])
	for building: Dictionary in full["buildings"]:
		assert_eq(building["reason"], &"ok")
	assert_eq(full["bread_causes"], [{"definition_id": &"", "reason": &"insufficient_capacity"}])
	# Ten jobs, five workers: the bakery is filled first, so the mill and wharf lack hands.
	var short_handed: Dictionary = _hungry_chain(5)
	assert_true(short_handed["bread_short"])
	assert_eq(short_handed["bread_causes"], [{"definition_id": &"wharf", "reason": &"understaffed"},
		{"definition_id": &"mill", "reason": &"understaffed"}])


func test_snapshot_sections_are_isolated_copies() -> void:
	var sim: Simulation = _sim(_chain_state(20, 10000))
	sim.tick()
	var snapshot: Dictionary = sim.snapshot()
	var expected: Dictionary = sim.snapshot().duplicate(true)
	snapshot["stats"]["window_seconds"] = 999
	snapshot["stats"]["window"][0][&"taxes"] = 999.0
	snapshot["stats"]["window"].clear()
	snapshot["diagnostics"]["buildings"][0]["cell"][0] = 99
	snapshot["diagnostics"]["bread_causes"].clear()
	snapshot["defeat"]["causes"].append(&"hunger")
	snapshot["defeat"]["hunger"]["status"] = &"defeat"
	snapshot["economy"]["wheat_purchases_enabled"] = false
	assert_eq(sim.snapshot(), expected)


func test_defeat_snapshot_exposes_warning_timer_cause_and_metrics() -> void:
	var params: Params = _params([Modifier.new(&"defeat.grace_seconds", &"set", 2),
		Modifier.new(&"defeat.bankruptcy.duration_seconds", &"set", 5)])
	var state: EconomyState = _state(20, -100)
	state.stocks[&"bread"] = 1000
	var sim: Simulation = _sim(state, params)
	sim.tick()
	var grace: Dictionary = sim.snapshot()["defeat"]
	assert_true(grace["grace_active"])
	assert_eq(grace["grace_remaining_seconds"], 1)
	for index: int in range(3):
		sim.tick()
	var warning: Dictionary = sim.snapshot()["defeat"]
	assert_false(warning["grace_active"])
	assert_eq(warning["bankruptcy"]["status"], &"warning")
	assert_eq(warning["bankruptcy"]["cause"], &"bankruptcy")
	assert_true(warning["bankruptcy"]["timer_running"])
	assert_eq(warning["bankruptcy"]["elapsed_seconds"], 2)
	assert_eq(warning["bankruptcy"]["remaining_seconds"], 3)
	assert_eq(warning["bankruptcy"]["duration_seconds"], 5)
	assert_eq(warning["bankruptcy"]["threshold"], 0)
	assert_lt(warning["bankruptcy"]["money"], 0)
	assert_eq(warning["hunger"]["status"], &"ok")
	assert_false(warning["hunger"]["timer_running"])
	assert_eq(warning["hunger"]["threshold"], 0.5)
	assert_eq(warning["depopulation"]["population"], 20)
	for index: int in range(3):
		sim.tick()
	var lost: Dictionary = sim.snapshot()["defeat"]
	assert_eq(lost["causes"], [&"bankruptcy"])
	assert_eq(lost["bankruptcy"]["status"], &"defeat")
	assert_eq(lost["bankruptcy"]["remaining_seconds"], 0)
	var late: SetWheatPurchasesCommand = SetWheatPurchasesCommand.new(false)
	sim.apply_command(late)
	assert_false(late.accepted)
	assert_eq(late.reason, &"simulation_defeated")


func test_restart_creates_a_fresh_game_with_the_same_startup_and_seed() -> void:
	var params: Params = _params([Modifier.new(&"defeat.grace_seconds", &"set", 0),
		Modifier.new(&"defeat.bankruptcy.duration_seconds", &"set", 1),
		Modifier.new(&"defeat.bankruptcy.threshold", &"set", 20000)])
	var session: GameSession = GameSession.new(_catalog, params)
	var fresh: Dictionary = session.get_snapshot()
	session.submit_command(BuildCommand.new(session.context, &"housing", Vector2i(1, 1)))
	session.submit_command(SetWheatPurchasesCommand.new(false))
	var old: Simulation = session.simulation
	for index: int in range(5):
		session.simulation.tick()
	assert_false(session.get_snapshot()["defeat"]["causes"].is_empty())
	session.restart()
	assert_ne(session.simulation, old)
	var restarted: Dictionary = session.get_snapshot()
	assert_eq(restarted, fresh)
	assert_eq(restarted["tick_count"], 0)
	assert_true(restarted["economy"]["wheat_purchases_enabled"])
	assert_eq(restarted["stats"]["window_seconds"], 0)
	var command: SetTaxCommand = SetTaxCommand.new(0.1)
	session.submit_command(command)
	session.simulation.tick()
	assert_true(command.accepted, "commands work again after the restart")
