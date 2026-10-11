extends GutTest

# Issue #7: the tea (D-025) and the imported flour (D-026). Numbers come from data/ through Params;
# the wheat price is frozen so nothing here depends on the random walk.

var _catalog: DataCatalog
var _context: EconomyContext


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])


# Plenty of bread so a long run is not cut short by a hunger riot; no wheat repricing.
func _params(modifiers: Array[Modifier] = []) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign(modifiers)
	role.modifiers.append(Modifier.new(&"population.initial_bread", &"set", 1000000))
	role.modifiers.append(Modifier.new(&"market.wheat.price_update_seconds", &"set", 100000))
	return Params.new(_catalog, role)


func _state(buildings: Array[StringName], population: int = 20, money: int = 100000) -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.population = population
	state.money = money
	state.wheat_price = 2
	for id: StringName in buildings:
		state.buildings.append({"definition_id": id, "cell": [0, 0]})
	return state


func _run(state: EconomyState, ticks: int, params: Params = _params()) -> Simulation:
	var sim: Simulation = Simulation.create_new(params, state, 42, _context)
	for index: int in range(ticks):
		sim.tick()
	return sim


func _consume(state: EconomyState, ticks: int, params: Params = _params()) -> void:
	for index: int in range(ticks):
		ConsumptionSystem.new().tick(state, params)


# --- Tea: consumption -------------------------------------------------------------------------

func test_tea_is_eaten_at_a_fifth_of_a_unit_per_person_per_minute() -> void:
	var state: EconomyState = _state([], 60)
	state.stocks[&"tea"] = 20
	_consume(state, 60)
	# 60 people x 0.2 per minute = 12 units in a minute.
	assert_almost_eq(float(state.stocks[&"tea"]) + state.tea_fraction, 8.0, 0.0001)
	assert_eq(state.tea_coverage, 1.0)


func test_tea_coverage_is_the_share_of_the_demand_the_store_covers() -> void:
	var state: EconomyState = _state([], 600)
	state.stocks[&"tea"] = 1
	_consume(state, 1)
	# 600 people x 0.2 / 60 = 2 units per second against 1 in store.
	assert_eq(state.tea_demand, 2.0)
	assert_eq(state.tea_coverage, 0.5)
	assert_eq(state.stocks[&"tea"], 0)


func test_no_tea_is_no_coverage_and_never_negative_stock() -> void:
	var state: EconomyState = _state([], 100)
	_consume(state, 10)
	assert_eq(state.tea_coverage, 0.0)
	assert_eq(state.stocks.get(&"tea", 0), 0)


# --- Tea: satisfaction ------------------------------------------------------------------------

func _target(coverage: float, tax: float = 0.75) -> float:
	var state: EconomyState = _state([], 0)
	state.tax_rate = tax
	state.tea_coverage = coverage
	SatisfactionSystem.new().update_target(state, _params(), _context)
	return state.satisfaction_target


func test_full_tea_coverage_adds_the_bonus_to_the_target() -> void:
	var bonus: float = float(_params().get_value(&"population.tea.satisfaction_bonus"))
	assert_eq(_target(1.0), _target(0.0) + bonus)


func test_partial_tea_coverage_adds_a_proportional_bonus() -> void:
	var bonus: float = float(_params().get_value(&"population.tea.satisfaction_bonus"))
	assert_almost_eq(_target(0.5), _target(0.0) + bonus * 0.5, 0.0001)


func test_tea_is_shown_in_the_satisfaction_breakdown() -> void:
	var state: EconomyState = _state([], 0)
	state.tax_rate = 0.25
	state.tea_coverage = 1.0
	SatisfactionSystem.new().update_target(state, _params(), _context)
	assert_eq(state.satisfaction_breakdown["tea"], 15.0)


func test_the_target_never_goes_over_100_with_tea() -> void:
	assert_eq(_target(1.0, 0.0), 100.0)


# --- Tea: buying ------------------------------------------------------------------------------

func test_tea_is_bought_at_the_wharf_at_a_fixed_price_and_covers_the_city() -> void:
	var state: EconomyState = _state([&"wharf"])
	state.tea_imports_enabled = true
	var sim: Simulation = _run(state, 120)
	var economy: Dictionary = sim.snapshot()["economy"]
	var price: int = int(_params().get_value(&"market.tea.price"))
	assert_eq(sim.snapshot()["imports"]["tea"]["coverage"], 1.0)
	assert_gt(sim.snapshot()["stats"]["imports_spent_per_minute"], 0.0)
	assert_eq(economy["satisfaction_breakdown"]["tea"], 15.0)
	assert_typeof(economy["money"], TYPE_INT)
	assert_eq(int(sim.snapshot()["stats"]["imports_spent_per_minute"]) % price, 0)


func test_tea_is_optional_nothing_is_bought_while_the_switch_is_off() -> void:
	var sim: Simulation = _run(_state([&"wharf"]), 120)
	assert_eq(sim.snapshot()["stats"]["imports_spent_per_minute"], 0.0)
	assert_eq(sim.snapshot()["economy"]["stocks"].get(&"tea", 0), 0)
	assert_eq(sim.snapshot()["imports"]["tea"]["reason"], &"tea_imports_disabled")


func test_tea_needs_a_staffed_wharf() -> void:
	var state: EconomyState = _state([])
	state.tea_imports_enabled = true
	var sim: Simulation = _run(state, 60)
	assert_eq(sim.snapshot()["economy"]["stocks"].get(&"tea", 0), 0)
	assert_eq(sim.snapshot()["imports"]["tea"]["reason"], &"no_wharf_for_imports")


func test_tea_is_not_bought_without_money() -> void:
	var state: EconomyState = _state([&"wharf"], 20, 0)
	state.tea_imports_enabled = true
	var sim: Simulation = _run(state, 5)
	assert_eq(sim.snapshot()["economy"]["stocks"].get(&"tea", 0), 0)
	assert_eq(sim.snapshot()["imports"]["tea"]["reason"], &"no_money_for_imports")


func test_a_role_can_make_the_tea_free() -> void:
	var state: EconomyState = _state([&"wharf"])
	state.tea_imports_enabled = true
	var free: Array[Modifier] = [Modifier.new(&"market.tea.price", &"set", 0)]
	var sim: Simulation = _run(state, 60, _params(free))
	assert_eq(sim.snapshot()["stats"]["imports_spent_per_minute"], 0.0)
	assert_eq(sim.snapshot()["imports"]["tea"]["coverage"], 1.0)


func test_tea_import_spending_is_part_of_the_operating_balance() -> void:
	var state: EconomyState = _state([&"wharf"])
	state.tea_imports_enabled = true
	var stats: Dictionary = _run(state, 60).snapshot()["stats"]
	assert_almost_eq(stats["operating_balance_per_minute"], stats["taxes_per_minute"] - stats["wages_per_minute"]
		- stats["upkeep_per_minute"] - stats["wheat_spent_per_minute"] - stats["imports_spent_per_minute"], 0.0001)


# --- Imported flour ---------------------------------------------------------------------------

func test_imported_flour_feeds_the_bakery_with_no_mill_at_all() -> void:
	var state: EconomyState = _state([&"wharf", &"bakery"])
	state.stocks[&"bread"] = 0
	state.flour_imports_enabled = true
	var sim: Simulation = _run(state, 180)
	assert_gt(sim.snapshot()["stats"]["bread_produced_per_minute"], 0.0)
	assert_gt(sim.snapshot()["stats"]["imports_spent_per_minute"], 0.0)


func test_without_the_import_a_bakery_with_no_mill_makes_no_bread() -> void:
	var sim: Simulation = _run(_state([&"wharf", &"bakery"]), 180)
	assert_eq(sim.snapshot()["stats"]["bread_produced_per_minute"], 0.0)
	assert_eq(sim.snapshot()["economy"]["stocks"].get(&"flour", 0), 0)


@warning_ignore("integer_division")
func test_flour_is_paid_by_the_lot_in_whole_pence() -> void:
	var state: EconomyState = _state([&"wharf", &"bakery"])
	state.flour_imports_enabled = true
	var params: Params = _params()
	var lot_price: int = int(params.get_value(&"market.imported_flour.price_per_lot"))
	var lot: int = int(params.get_value(&"market.imported_flour.lot_size"))
	var sim: Simulation = Simulation.create_new(params, state, 42, _context)
	var spent: int = 0
	var bought: int = 0
	for index: int in range(240):
		sim.tick()
		var tick_spent: int = sim.snapshot()["stats"]["window"][-1][&"imports"]
		assert_eq(tick_spent % lot_price, 0)
		spent += tick_spent
		bought += (tick_spent / lot_price) * lot
	assert_gt(spent, 0)
	# Every unit that was bought is either in store or was baked: nothing is paid for and lost.
	var left: int = int(sim.snapshot()["economy"]["stocks"].get(&"flour", 0))
	assert_lte(left, bought)


func test_imported_flour_costs_between_20_and_30_percent_more_than_milling_wheat_at_2() -> void:
	var params: Params = _params()
	var unit: float = float(params.get_value(&"market.imported_flour.price_per_lot")) \
		/ float(params.get_value(&"market.imported_flour.lot_size"))
	var milled: float = float(params.get_value(&"market.wheat.base_price"))
	assert_gte(unit / milled, 1.2)
	assert_lte(unit / milled, 1.3)


func test_a_working_mill_is_never_undercut_by_the_import() -> void:
	var state: EconomyState = _state([&"wharf", &"mill", &"bakery"], 20, 100000)
	state.stocks[&"wheat"] = 1000
	state.wheat_purchases_enabled = false
	state.flour_imports_enabled = true
	var sim: Simulation = _run(state, 120)
	assert_eq(sim.snapshot()["stats"]["imports_spent_per_minute"], 0.0)
	assert_eq(sim.snapshot()["imports"]["flour"]["reason"], &"mill_covers_flour")


func test_the_import_covers_the_mill_when_it_has_no_wheat() -> void:
	var state: EconomyState = _state([&"wharf", &"mill", &"bakery"])
	state.wheat_purchases_enabled = false
	state.flour_imports_enabled = true
	var sim: Simulation = _run(state, 180)
	assert_gt(sim.snapshot()["stats"]["imports_spent_per_minute"], 0.0)
	assert_gt(sim.snapshot()["stats"]["bread_produced_per_minute"], 0.0)


func test_flour_import_needs_a_staffed_wharf_and_the_switch() -> void:
	var off: EconomyState = _state([&"wharf", &"bakery"])
	assert_eq(_run(off, 60).snapshot()["imports"]["flour"]["reason"], &"flour_imports_disabled")
	var no_wharf: EconomyState = _state([&"bakery"])
	no_wharf.flour_imports_enabled = true
	var sim: Simulation = _run(no_wharf, 60)
	assert_eq(sim.snapshot()["imports"]["flour"]["reason"], &"no_wharf_for_imports")
	assert_eq(sim.snapshot()["stats"]["imports_spent_per_minute"], 0.0)


func test_no_flour_is_bought_without_money() -> void:
	var state: EconomyState = _state([&"wharf", &"bakery"], 20, 0)
	state.flour_imports_enabled = true
	var sim: Simulation = _run(state, 5)
	assert_eq(sim.snapshot()["economy"]["stocks"].get(&"flour", 0), 0)
	assert_eq(sim.snapshot()["imports"]["flour"]["reason"], &"no_money_for_imports")


func test_skipping_the_mill_leaves_its_jobs_to_the_other_buildings() -> void:
	var with_mill: Simulation = _run(_state([&"wharf", &"mill", &"bakery"], 7), 1)
	var without: Simulation = _run(_state([&"wharf", &"bakery"], 7), 1)
	var jobs: Dictionary = {}
	for entry: Dictionary in with_mill.snapshot()["diagnostics"]["buildings"]:
		jobs[entry["definition_id"]] = entry["workers"]
	var freed: Dictionary = {}
	for entry: Dictionary in without.snapshot()["diagnostics"]["buildings"]:
		freed[entry["definition_id"]] = entry["workers"]
	var mill_jobs: int = int(_params().get_value(&"building.mill.jobs"))
	assert_eq(jobs[&"mill"], mill_jobs)
	assert_false(freed.has(&"mill"))
	assert_eq(freed[&"bakery"], int(_params().get_value(&"building.bakery.jobs")))
	assert_eq(with_mill.snapshot()["economy"]["employed"], without.snapshot()["economy"]["employed"])


# --- State, commands, determinism, ranges -----------------------------------------------------

func test_import_commands_switch_each_import() -> void:
	var sim: Simulation = Simulation.create_new(_params(), _state([&"wharf"]), 42, _context)
	var tea: SetTeaImportsCommand = SetTeaImportsCommand.new(true)
	var flour: SetFlourImportsCommand = SetFlourImportsCommand.new(true)
	sim.apply_command(tea)
	sim.apply_command(flour)
	sim.tick()
	assert_true(tea.accepted)
	assert_true(flour.accepted)
	var economy: Dictionary = sim.snapshot()["economy"]
	assert_true(economy["tea_imports_enabled"])
	assert_true(economy["flour_imports_enabled"])


func test_imports_start_off() -> void:
	assert_false(_catalog.base_values[&"startup.tea_imports_enabled"])
	assert_false(_catalog.base_values[&"startup.flour_imports_enabled"])


func test_state_round_trips_and_old_saves_default_to_no_imports() -> void:
	var state: EconomyState = _state([])
	state.tea_imports_enabled = true
	state.tea_fraction = 0.25
	state.tea_coverage = 0.5
	var copy: EconomyState = EconomyState.from_dict(state.to_dict())
	assert_true(copy.tea_imports_enabled)
	assert_eq(copy.tea_fraction, 0.25)
	assert_eq(copy.tea_coverage, 0.5)
	var old: Dictionary = state.to_dict()
	for key: String in ["tea_imports_enabled", "flour_imports_enabled", "tea_fraction", "tea_demand",
			"tea_consumed", "tea_coverage"]:
		old.erase(key)
	var loaded: EconomyState = EconomyState.from_dict(old)
	assert_false(loaded.tea_imports_enabled)
	assert_false(loaded.flour_imports_enabled)
	assert_eq(loaded.tea_coverage, 0.0)


func test_same_seed_gives_the_same_imports() -> void:
	var first: EconomyState = _state([&"wharf", &"bakery"])
	first.tea_imports_enabled = true
	first.flour_imports_enabled = true
	var second: EconomyState = EconomyState.from_dict(first.to_dict())
	assert_eq(_run(first, 200).snapshot()["economy"], _run(second, 200).snapshot()["economy"])


func test_stats_window_saved_before_imports_loads_as_zero_imports() -> void:
	var stats: Stats = Stats.new(2)
	stats.record(EconomyState.new())
	var window: Array = stats.snapshot()["window"]
	for sample: Dictionary in window:
		sample.erase(&"imports")
	var restored: Stats = Stats.new(2)
	restored.restore(window)
	assert_eq(restored.snapshot()["window_seconds"], 1)
	assert_eq(restored.snapshot()["imports_spent_per_minute"], 0.0)


func test_every_new_key_has_a_range_and_rejects_values_out_of_it() -> void:
	var invalid: Dictionary[StringName, Array] = {
		&"market.imported_flour.price_per_lot": [-1.0],
		&"market.imported_flour.lot_size": [0.0, -1.0, 2.5, 10001.0],
		&"market.tea.price": [-1.0],
		&"market.tea.buffer_seconds": [-1.0, 3601.0],
		&"population.tea.per_person_per_minute": [0.0, -0.1],
		&"population.tea.satisfaction_bonus": [-1.0, 100.5],
	}
	for key: StringName in invalid:
		assert_true(ParameterRanges.BY_KEY.has(key), str(key))
		assert_true(_catalog.base_values.has(key), str(key))
		for value: float in invalid[key]:
			assert_false(ParameterRanges.is_valid(key, value), "%s = %s" % [key, value])
	for key: StringName in invalid:
		assert_true(ParameterRanges.is_valid(key, float(_catalog.base_values[key])), str(key))


func test_a_role_that_breaks_a_new_range_is_refused() -> void:
	for key: StringName in [&"market.imported_flour.lot_size", &"population.tea.satisfaction_bonus"]:
		var role: RoleDef = RoleDef.new()
		role.modifiers.append(Modifier.new(key, &"set", -5))
		assert_null(Params.new(_catalog, role).get_value(key))
		assert_push_error("Params: invalid range for '%s'" % key)


func test_data_rejects_invalid_import_values_and_a_numeric_switch() -> void:
	var cases: Array[Array] = [
		["economy/market.json", ["imported_flour", "lot_size"], 0],
		["economy/market.json", ["imported_flour", "price_per_lot"], -1],
		["economy/market.json", ["tea", "price"], 1.5],
		["economy/population.json", ["tea", "per_person_per_minute"], 0],
		["economy/population.json", ["tea", "satisfaction_bonus"], 101],
		["economy/startup.json", ["tea_imports_enabled"], 1],
		["economy/startup.json", ["flour_imports_enabled"], "true"],
	]
	for entry: Array in cases:
		var documents: Dictionary[String, Dictionary] = {}
		for folder: String in ["economy", "roles", "maps"]:
			for file_name: String in DirAccess.open("res://data/" + folder).get_files():
				if file_name.ends_with(".json"):
					var path: String = folder.path_join(file_name)
					documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))
		var section: Dictionary = documents[entry[0]]
		var fields: Array = entry[1]
		for index: int in range(fields.size() - 1):
			section = section[fields[index]]
		section[fields[-1]] = entry[2]
		assert_false(DataLoader.new().load_documents(documents).is_ok(), str(entry))


func test_flour_is_refilled_before_the_stock_falls_short_of_the_bakeries() -> void:
	# Three staffed bakeries each want a whole unit this tick; two units left would starve the third.
	var state: EconomyState = _state([&"wharf", &"bakery", &"bakery", &"bakery"], 20)
	state.stocks[&"flour"] = 2
	state.flour_imports_enabled = true
	var params: Params = _params()
	var lot: int = int(params.get_value(&"market.imported_flour.lot_size"))
	var sim: Simulation = _run(state, 1, params)
	assert_gt(sim.snapshot()["stats"]["imports_spent_per_minute"], 0.0)
	assert_gte(int(sim.snapshot()["economy"]["stocks"][&"flour"]), 2 + lot - 3)


func test_flour_is_not_refilled_while_the_stock_serves_every_bakery() -> void:
	var state: EconomyState = _state([&"wharf", &"bakery", &"bakery", &"bakery"], 20)
	state.stocks[&"flour"] = 3
	state.flour_imports_enabled = true
	var sim: Simulation = _run(state, 1)
	assert_eq(sim.snapshot()["stats"]["imports_spent_per_minute"], 0.0)


func test_tea_spending_is_reported_apart_from_the_flour() -> void:
	var state: EconomyState = _state([&"wharf", &"bakery"])
	state.tea_imports_enabled = true
	state.flour_imports_enabled = true
	var stats: Dictionary = _run(state, 120).snapshot()["stats"]
	assert_gt(stats["tea_spent_per_minute"], 0.0)
	assert_gt(stats["imports_spent_per_minute"], stats["tea_spent_per_minute"], "the flour is the rest")
	var only_flour: EconomyState = _state([&"wharf", &"bakery"])
	only_flour.flour_imports_enabled = true
	assert_eq(_run(only_flour, 120).snapshot()["stats"]["tea_spent_per_minute"], 0.0)


func test_flour_lots_are_bought_until_every_requesting_bakery_gets_a_unit() -> void:
	var buildings: Array[StringName] = [&"wharf"]
	for index: int in range(11):
		buildings.append(&"bakery")
	var state: EconomyState = _state(buildings, 20)
	state.flour_imports_enabled = true
	var params: Params = _params()
	var price: int = int(params.get_value(&"market.imported_flour.price_per_lot"))
	var stats: Dictionary = _run(state, 1, params).snapshot()["stats"]
	# 11 bakeries against lots of 10: two lots, not one. A single tick makes the per-minute rate x60.
	assert_eq(stats["imports_spent_per_minute"], float(2 * price) * 60.0)


func test_flour_lots_are_limited_by_the_money() -> void:
	var buildings: Array[StringName] = [&"wharf"]
	for index: int in range(11):
		buildings.append(&"bakery")
	var params: Params = _params()
	var price: int = int(params.get_value(&"market.imported_flour.price_per_lot"))
	var state: EconomyState = _state(buildings, 20, price + 1)
	state.flour_imports_enabled = true
	var stats: Dictionary = _run(state, 1, params).snapshot()["stats"]
	assert_eq(stats["imports_spent_per_minute"], float(price) * 60.0)


func test_tea_with_no_buffer_is_still_bought_on_demand() -> void:
	var state: EconomyState = _state([&"wharf"])
	state.tea_imports_enabled = true
	var no_buffer: Array[Modifier] = [Modifier.new(&"market.tea.buffer_seconds", &"set", 0)]
	var sim: Simulation = _run(state, 60, _params(no_buffer))
	assert_eq(sim.snapshot()["imports"]["tea"]["coverage"], 1.0)
	assert_gt(sim.snapshot()["stats"]["tea_spent_per_minute"], 0.0)
	assert_eq(sim.snapshot()["economy"]["satisfaction_breakdown"]["tea"], 15.0)


func test_scarce_wheat_is_credited_to_one_mill_only() -> void:
	# Two staffed mills, one unit of wheat: only one mill can work, so the two bakeries still run short.
	var state: EconomyState = _state([&"wharf", &"mill", &"mill", &"bakery", &"bakery"], 20)
	state.stocks[&"wheat"] = 1
	state.wheat_purchases_enabled = false
	state.flour_imports_enabled = true
	var sim: Simulation = _run(state, 1)
	assert_gt(sim.snapshot()["stats"]["imports_spent_per_minute"], 0.0)


func _diagnostics_after_one_tick(state: EconomyState) -> Dictionary:
	var starving: Array[Modifier] = [Modifier.new(&"population.initial_bread", &"set", 0)]
	return _run(state, 1, _params(starving)).snapshot()["diagnostics"]


func test_diagnostics_do_not_ask_for_the_stages_the_imported_flour_skips() -> void:
	var state: EconomyState = _state([&"wharf", &"bakery"])
	state.wheat_purchases_enabled = false
	state.flour_imports_enabled = true
	var diagnostics: Dictionary = _diagnostics_after_one_tick(state)
	for cause: Dictionary in diagnostics["bread_causes"]:
		assert_ne(cause["definition_id"], &"mill")
		assert_ne(cause["reason"], &"wheat_purchases_disabled")
	for building: Dictionary in diagnostics["buildings"]:
		if building["definition_id"] == &"wharf":
			assert_eq(building["reason"], &"ok")


func test_diagnostics_still_ask_for_the_mill_without_the_import() -> void:
	var state: EconomyState = _state([&"wharf", &"bakery"])
	state.wheat_purchases_enabled = false
	var diagnostics: Dictionary = _diagnostics_after_one_tick(state)
	var stages: Array[StringName] = []
	for cause: Dictionary in diagnostics["bread_causes"]:
		stages.append(cause["definition_id"])
	assert_has(stages, &"mill")


func test_diagnostics_blame_the_wharf_when_the_flour_cannot_be_paid() -> void:
	var state: EconomyState = _state([&"wharf", &"bakery"], 20, 0)
	state.flour_imports_enabled = true
	var diagnostics: Dictionary = _diagnostics_after_one_tick(state)
	var reasons: Array[StringName] = []
	for cause: Dictionary in diagnostics["bread_causes"]:
		reasons.append(cause["reason"])
	assert_has(reasons, &"no_money_for_imports")


func test_flour_lots_follow_the_modified_rate_of_the_bakery() -> void:
	# Half-second recipe: one fully staffed bakery asks for 20 units of flour in a single tick.
	var fast: Array[Modifier] = [Modifier.new(&"building.bakery.recipe.seconds", &"set", 0.5)]
	var state: EconomyState = _state([&"wharf", &"bakery"], 20)
	state.flour_imports_enabled = true
	var params: Params = _params(fast)
	var price: int = int(params.get_value(&"market.imported_flour.price_per_lot"))
	var stats: Dictionary = _run(state, 1, params).snapshot()["stats"]
	assert_eq(stats["imports_spent_per_minute"], float(2 * price) * 60.0, "20 units = two lots of 10")


func test_each_wharf_is_judged_on_its_own_workers_and_money() -> void:
	# One person: the first wharf gets them (first pass runs wharf by wharf); the second has nobody.
	var state: EconomyState = _state([&"wharf", &"wharf", &"bakery"], 1)
	state.flour_imports_enabled = true
	var wharves: Array[StringName] = []
	for building: Dictionary in _diagnostics_after_one_tick(state)["buildings"]:
		if building["definition_id"] == &"wharf":
			wharves.append(building["reason"])
	assert_eq(wharves, [&"ok", &"no_workers"] as Array[StringName])
	var broke: EconomyState = _state([&"wharf", &"bakery"], 20, 0)
	broke.flour_imports_enabled = true
	for building: Dictionary in _diagnostics_after_one_tick(broke)["buildings"]:
		if building["definition_id"] == &"wharf":
			assert_eq(building["reason"], &"no_money_for_imports")
