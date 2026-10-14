extends GutTest

# Issue #50: barley and the split of the wharf's unloading capacity between wheat, barley and the imported
# flour (the tea is exempt). Prices are frozen unless the test is about the price walk, so every number
# here is one the test chose.

var _catalog: DataCatalog
var _context: EconomyContext


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])


# Plenty of bread keeps the city from a hunger riot; both markets stay at the price the test sets and
# nothing spoils unless asked.
func _params(modifiers: Array[Modifier] = [], frozen: bool = true, decay: bool = false) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign(modifiers)
	role.modifiers.append(Modifier.new(&"population.initial_bread", &"set", 1000000))
	if frozen:
		role.modifiers.append(Modifier.new(&"market.wheat.price_update_seconds", &"set", 100000))
		role.modifiers.append(Modifier.new(&"market.barley.price_update_seconds", &"set", 100000))
	if not decay:
		role.modifiers.append(Modifier.new(&"market.wheat.decay_fraction_per_minute", &"set", 0.0))
		role.modifiers.append(Modifier.new(&"market.barley.decay_fraction_per_minute", &"set", 0.0))
	return Params.new(_catalog, role)


# `wharves` fully staffed wharves; barley_percent is the player's split.
func _state(barley_percent: int, wharves: int = 1, extra: Array[StringName] = []) -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.population = 40
	state.money = 100000
	state.wheat_price = 2
	state.barley_price = 2
	state.wheat_reserve_minutes = 0
	state.unloading_barley_percent = barley_percent
	for index: int in range(wharves):
		state.buildings.append({"definition_id": &"wharf", "cell": [index, 7]})
	for id: StringName in extra:
		state.buildings.append({"definition_id": id, "cell": [0, 0]})
	return state


func _sim(state: EconomyState, params: Params = _params()) -> Simulation:
	return Simulation.create_new(params, state, 42, _context)


func _run(sim: Simulation, ticks: int) -> void:
	for index: int in range(ticks):
		sim.tick()


func _stock(sim: Simulation, good: StringName) -> int:
	return int(sim.snapshot()["economy"]["stocks"].get(good, 0))


# --- Barley in the state ---------------------------------------------------------------------

func test_barley_survives_to_dict_and_from_dict() -> void:
	var state: EconomyState = _state(40)
	state.stocks[&"barley"] = 7
	state.barley_price = 3
	state.barley_previous_price = 2
	state.barley_decay_fraction = 0.25
	state.flour_unloading_debt = 4.5
	var copy: EconomyState = EconomyState.from_dict(state.to_dict())
	assert_eq(copy.stocks[&"barley"], 7)
	assert_eq(copy.barley_price, 3)
	assert_eq(copy.barley_previous_price, 2)
	assert_eq(copy.barley_decay_fraction, 0.25)
	assert_eq(copy.unloading_barley_percent, 40)
	assert_eq(copy.flour_unloading_debt, 4.5)


func test_an_old_save_without_barley_loads_with_neutral_values() -> void:
	var values: Dictionary = _state(0).to_dict()
	for key: String in ["barley_price", "barley_previous_price", "barley_decay_fraction",
			"unloading_barley_percent", "flour_unloading_debt"]:
		values.erase(key)
	var copy: EconomyState = EconomyState.from_dict(values)
	assert_eq(copy.barley_price, -1, "the simulation loads the price from data")
	assert_eq(copy.unloading_barley_percent, -1, "the simulation loads the split from data")
	assert_eq(copy.flour_unloading_debt, 0.0)


func test_barley_is_a_good_and_the_split_defaults_to_all_wheat_from_data() -> void:
	assert_true(_catalog.goods.has(&"barley"))
	var sim: Simulation = _sim(EconomyState.new())
	var barley: Dictionary = sim.snapshot()["market"]["barley"]
	assert_eq(barley["barley_percent"], 0)
	assert_eq(barley["wheat_percent"], 100)
	assert_eq(barley["price"], 2, "the base price of data")
	assert_eq(barley["capacity"], 80)


# --- The split ---------------------------------------------------------------------------------

func test_wheat_and_barley_never_exceed_the_capacity_whatever_the_split() -> void:
	for percent: int in [0, 50, 100]:
		var sim: Simulation = _sim(_state(percent))
		_run(sim, 60)
		var wheat: int = _stock(sim, &"wheat")
		var barley: int = _stock(sim, &"barley")
		assert_eq(wheat, (100 - percent) / 10, "wheat at %d %% barley" % percent)
		assert_eq(barley, percent / 10, "barley at %d %% barley" % percent)
		assert_lte(wheat + barley, 10, "a wharf unloads 10 a minute between the two")
		_run(sim, 240)
		assert_eq(_stock(sim, &"wheat") + _stock(sim, &"barley"), 50, "still 10 a minute after five minutes")


func test_the_capacity_is_the_sum_of_the_wharves_and_the_split_applies_to_all() -> void:
	var sim: Simulation = _sim(_state(50, 2))
	_run(sim, 60)
	assert_eq(_stock(sim, &"wheat"), 10)
	assert_eq(_stock(sim, &"barley"), 10)


func test_a_partly_staffed_wharf_unloads_less_for_both_goods() -> void:
	var state: EconomyState = _state(50)
	state.population = 2
	var sim: Simulation = _sim(state)
	_run(sim, 120)
	var total: int = _stock(sim, &"wheat") + _stock(sim, &"barley")
	assert_lt(total, 20, "fewer hands than jobs: less than the full 10 a minute")
	assert_gt(total, 0)


func test_the_default_split_is_all_wheat_and_barley_stays_out_of_it() -> void:
	var sim: Simulation = _sim(_state(0))
	_run(sim, 600)
	assert_eq(_stock(sim, &"wheat"), 100)
	assert_eq(_stock(sim, &"barley"), 0)
	assert_eq(sim.snapshot()["stats"]["barley_spent_per_minute"], 0.0)


func test_the_barley_walk_does_not_move_the_wheat_series() -> void:
	# The wheat price of a game is the walk of an rng seeded with the game's seed, whatever barley does.
	var sim: Simulation = _sim(_state(100), _params([], false))
	var expected: RandomNumberGenerator = RandomNumberGenerator.new()
	expected.seed = 42
	var params: Params = _params([], false)
	var price: int = 2
	for minute: int in range(1, 11):
		_run(sim, 60)
		price = MarketSystem.next_price(price, params, expected)
		assert_eq(sim.snapshot()["economy"]["wheat_price"], price, "minute %d" % minute)


func test_the_barley_price_walks_on_its_own_generator_within_its_range() -> void:
	var sim: Simulation = _sim(_state(0), _params([], false))
	var expected: RandomNumberGenerator = RandomNumberGenerator.new()
	expected.seed = 42 ^ Simulation.BARLEY_SEED_SALT
	var params: Params = _params([], false)
	var price: int = 2
	for minute: int in range(1, 11):
		_run(sim, 60)
		price = MarketSystem.next_barley_price(price, params, expected)
		var shown: int = sim.snapshot()["market"]["barley"]["price"]
		assert_eq(shown, price, "minute %d" % minute)
		assert_between(shown, 1, 3)


func test_the_snapshot_shows_the_barley_generator_and_it_moves_only_with_the_barley_walk() -> void:
	var sim: Simulation = _sim(_state(0), _params([], false))
	var start: Dictionary = sim.snapshot()
	assert_true(start.has("barley_rng_state"))
	var expected: RandomNumberGenerator = RandomNumberGenerator.new()
	expected.seed = 42 ^ Simulation.BARLEY_SEED_SALT
	assert_eq(start["barley_rng_state"], expected.state, "seeded from the game's seed")
	_run(sim, 59)
	assert_eq(sim.snapshot()["barley_rng_state"], start["barley_rng_state"], "no repricing yet")
	_run(sim, 1)
	assert_ne(sim.snapshot()["barley_rng_state"], start["barley_rng_state"], "the first repricing draws")
	assert_eq(sim.get_barley_rng_state(), sim.snapshot()["barley_rng_state"])
	var frozen: Simulation = _sim(_state(0))
	_run(frozen, 120)
	assert_eq(frozen.snapshot()["barley_rng_state"], start["barley_rng_state"], "a frozen walk draws nothing")


func test_barley_is_paid_at_its_own_price_and_stops_at_the_warehouse_or_the_treasury() -> void:
	var state: EconomyState = _state(100)
	state.barley_price = 3
	var sim: Simulation = _sim(state)
	_run(sim, 60)
	assert_eq(_stock(sim, &"barley"), 10)
	assert_eq(sim.snapshot()["stats"]["barley_spent_per_minute"], 30.0)
	var small: Simulation = _sim(_state(100), _params([Modifier.new(&"market.barley.storage_capacity", &"set", 15)]))
	_run(small, 200)
	assert_eq(_stock(small, &"barley"), 15)
	# The market alone, so wages and taxes do not move the treasury.
	var poor: EconomyState = _state(100)
	poor.money = 5
	poor.buildings.clear()
	poor.buildings.append({"definition_id": &"wharf", "cell": [0, 7], "workers": 4})
	var market: MarketSystem = MarketSystem.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for tick_count: int in range(1, 121):
		market.tick(poor, _params(), rng, tick_count)
	assert_eq(poor.stocks[&"barley"], 2, "5 pence at 2 each is two units")
	assert_eq(poor.money, 1)


func test_barley_spoils_in_whole_units_like_wheat() -> void:
	var state: EconomyState = _state(0)
	state.stocks[&"barley"] = 100
	var sim: Simulation = _sim(state, _params([], true, true))
	_run(sim, 60)
	assert_eq(_stock(sim, &"barley"), 99, "1 % a minute of 100 units")


# --- The command -----------------------------------------------------------------------------

func test_the_command_sets_the_split_and_rejects_what_is_not_a_percentage() -> void:
	var sim: Simulation = _sim(_state(0))
	var good: SetUnloadingSplitCommand = SetUnloadingSplitCommand.new(30)
	sim.apply_command(good)
	sim.tick()
	assert_true(good.accepted)
	assert_eq(sim.snapshot()["market"]["barley"]["barley_percent"], 30)
	for invalid: int in [-1, 101]:
		var bad: SetUnloadingSplitCommand = SetUnloadingSplitCommand.new(invalid)
		sim.apply_command(bad)
		sim.tick()
		assert_false(bad.accepted)
		assert_eq(bad.reason, &"invalid_unloading_split")
		assert_eq(sim.snapshot()["market"]["barley"]["barley_percent"], 30, "a refused split changes nothing")
	for edge: int in [0, 100]:
		var accepted: SetUnloadingSplitCommand = SetUnloadingSplitCommand.new(edge)
		sim.apply_command(accepted)
		sim.tick()
		assert_true(accepted.accepted, "%d %% is a valid split" % edge)


func test_the_command_is_refused_after_defeat() -> void:
	var state: EconomyState = _state(0)
	state.defeat_causes.append(&"bankruptcy")
	var sim: Simulation = _sim(state)
	var command: SetUnloadingSplitCommand = SetUnloadingSplitCommand.new(50)
	sim.apply_command(command)
	assert_false(command.accepted)
	assert_eq(command.reason, &"simulation_defeated")


func test_the_split_can_be_set_from_a_scenario() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	var scenario: Dictionary = {
		"id": "barley_split", "description": "x", "notes": "x", "seed": 42, "duration_ticks": 60,
		"commands": [
			{"tick": 0, "cmd": "build", "building": "wharf", "cell": [2, 7]},
			{"tick": 0, "cmd": "set_unloading_split", "barley_percent": 50}],
	}
	assert_eq(runner.validate(scenario), [])
	scenario["commands"][1]["barley_percent"] = 101
	assert_false(runner.validate(scenario).is_empty(), "a split above 100 % is not a scenario")


# --- The imported flour shares the capacity ------------------------------------------------

func _flour_state(barley_percent: int) -> EconomyState:
	var state: EconomyState = _state(barley_percent, 1, [&"bakery"])
	state.flour_imports_enabled = true
	return state


func test_a_lot_of_imported_flour_takes_the_capacity_the_barley_does_not_reserve_before_the_wheat() -> void:
	# Issue #116: the barley keeps its 50 % of the wharf (5 a minute); the flour has the other half.
	var sim: Simulation = _sim(_flour_state(50))
	_run(sim, 30)
	assert_gt(_stock(sim, &"flour") + int(sim.snapshot()["economy"]["bread_fraction"]), 0, "a lot was bought")
	assert_eq(_stock(sim, &"wheat"), 0, "the wharf is still unloading the flour")
	assert_gt(_stock(sim, &"barley"), 0, "the flour does not touch the reserved barley")
	assert_gt(sim.snapshot()["market"]["barley"]["flour_unloading_debt"], 0.0)
	# The bakery would keep asking for flour and the flour would keep its half; with the imports off the
	# lot is paid at 5 a minute (at most 5 minutes for 25 units) and the wheat gets its half again.
	sim.apply_command(SetFlourImportsCommand.new(false))
	_run(sim, 300)
	assert_gt(_stock(sim, &"wheat"), 0, "once the lot is unloaded the wheat gets what is left of its half")
	assert_gt(_stock(sim, &"barley"), 0)
	assert_eq(sim.snapshot()["market"]["barley"]["flour_unloading_debt"], 0.0)


func test_the_wharf_never_owes_more_than_two_lots_so_the_flour_cannot_skip_the_limit() -> void:
	var lot: float = float(_params().get_value(&"market.imported_flour.lot_size"))
	var sim: Simulation = _sim(_flour_state(0))
	for index: int in range(900):
		sim.tick()
		assert_lt(sim.snapshot()["market"]["barley"]["flour_unloading_debt"], 2.0 * lot)
	assert_eq(_params().get_value(&"market.imported_flour.max_debt_lots"), 2, "two lots, from data")


func test_many_bakeries_asking_at_once_cannot_push_the_debt_past_two_lots() -> void:
	var extra: Array[StringName] = []
	for index: int in range(21):
		extra.append(&"bakery")
	var state: EconomyState = _state(0, 1, extra)
	state.flour_imports_enabled = true
	state.population = 400
	var sim: Simulation = _sim(state)
	sim.tick()
	var lot: float = float(_params().get_value(&"market.imported_flour.lot_size"))
	assert_lte(sim.snapshot()["market"]["barley"]["flour_unloading_debt"], 2.0 * lot)
	assert_gt(sim.snapshot()["market"]["barley"]["flour_unloading_debt"], 0.0, "it did buy")
	# The bound is a datum: a role that allows three lots gets three.
	var wide: Simulation = _sim(_wide_state(extra),
		_params([Modifier.new(&"market.imported_flour.max_debt_lots", &"set", 3)]))
	wide.tick()
	assert_lte(wide.snapshot()["market"]["barley"]["flour_unloading_debt"], 3.0 * lot)
	assert_gt(wide.snapshot()["market"]["barley"]["flour_unloading_debt"], 2.0 * lot)


func _wide_state(extra: Array[StringName]) -> EconomyState:
	var state: EconomyState = _state(0, 1, extra)
	state.flour_imports_enabled = true
	state.population = 400
	return state


func test_the_flour_waits_for_the_wharf_when_it_is_busy() -> void:
	var state: EconomyState = _flour_state(0)
	state.flour_unloading_debt = 12.0
	state.population = 40
	var sim: Simulation = _sim(state)
	sim.tick()
	assert_eq(_stock(sim, &"flour"), 0, "a lot or more still to unload: no new lot")
	assert_eq(sim.snapshot()["imports"]["flour"]["reason"], &"wharf_unloading_busy")


# --- The barley is reserved before the flour (issue #116) -----------------------------------

func _owing_state(barley_percent: int, debt: float) -> EconomyState:
	var state: EconomyState = _state(barley_percent)
	state.flour_unloading_debt = debt
	return state


func test_the_barley_share_is_kept_while_a_lot_of_flour_is_pending() -> void:
	# 10 a minute of capacity, 3 reserved for the barley: the flour can only take the other 7.
	var sim: Simulation = _sim(_owing_state(30, 50.0))
	_run(sim, 120)
	assert_between(_stock(sim, &"barley"), 5, 6, "30 % of 10 a minute, for 2 minutes")
	assert_almost_eq(float(sim.snapshot()["market"]["barley"]["flour_unloading_debt"]), 36.0, 0.001,
		"the flour unloaded 7 a minute")
	assert_eq(_stock(sim, &"wheat"), 0, "the flour keeps what the barley leaves")


func test_a_lot_of_flour_unloads_in_parts_with_what_the_reserve_leaves() -> void:
	var sim: Simulation = _sim(_owing_state(30, 4.0))
	_run(sim, 60)
	assert_eq(sim.snapshot()["market"]["barley"]["flour_unloading_debt"], 0.0, "4 units fit in the 7 a minute")
	assert_gt(_stock(sim, &"wheat"), 0, "what the flour did not need goes to the wheat")
	assert_between(_stock(sim, &"barley"), 2, 3)


func test_flour_still_comes_before_wheat_on_what_the_reserve_leaves() -> void:
	var sim: Simulation = _sim(_owing_state(30, 7.0))
	_run(sim, 60)
	assert_eq(_stock(sim, &"wheat"), 0, "7 units owed and 7 a minute: nothing left for the wheat")
	assert_almost_eq(float(sim.snapshot()["market"]["barley"]["flour_unloading_debt"]), 0.0, 0.001)


func test_with_zero_barley_the_flour_unloading_matches_the_old_split() -> void:
	var sim: Simulation = _sim(_owing_state(0, 25.0))
	_run(sim, 60)
	assert_almost_eq(float(sim.snapshot()["market"]["barley"]["flour_unloading_debt"]), 15.0, 0.001,
		"the flour takes the whole 10 a minute")
	assert_eq(_stock(sim, &"wheat"), 0)
	assert_eq(_stock(sim, &"barley"), 0)
	_run(sim, 120)
	assert_eq(sim.snapshot()["market"]["barley"]["flour_unloading_debt"], 0.0)
	assert_between(_stock(sim, &"wheat"), 4, 5, "the 5 left of the third minute and nothing else")


func test_the_panel_does_not_blame_the_price_while_the_flour_keeps_all_the_unreserved_wharf() -> void:
	var state: EconomyState = _owing_state(30, 7.0)
	state.wheat_price = 3
	state.wheat_max_price = 2
	state.stocks[&"wheat"] = 5
	var sim: Simulation = _sim(state)
	sim.tick()
	assert_false(sim.snapshot()["market"]["wheat"]["blocked_by_price"], "7 units owed, 7 a minute left for them")


func test_the_scenario_probe_respects_the_warehouse_cap_and_empties_the_eaten_part_of_a_unit() -> void:
	var state: EconomyState = _state(0)
	state.beer_fraction = 0.6
	var params: Params = _params()
	ForceStockCommand.new(&"beer", 9999).execute(state, params, RandomNumberGenerator.new())
	assert_eq(int(state.stocks[&"beer"]), int(params.get_value(&"market.beer.storage_capacity")))
	assert_eq(state.beer_fraction, 0.0)


func test_the_scenario_probe_warns_when_a_good_has_no_warehouse_cap() -> void:
	var state: EconomyState = _state(0)
	var params: Params = _params()
	assert_false(params.has_value(&"market.bread.storage_capacity"), "the bread has no cap in data/")
	ForceStockCommand.new(&"bread", 500).execute(state, params, RandomNumberGenerator.new())
	assert_push_warning("market.bread.storage_capacity")
	assert_eq(int(state.stocks[&"bread"]), 500, "without a cap the scripted amount is kept")


func test_the_tea_is_exempt_from_the_unloading_capacity() -> void:
	var state: EconomyState = _state(0)
	state.tea_imports_enabled = true
	var sim: Simulation = _sim(state)
	_run(sim, 60)
	assert_eq(_stock(sim, &"wheat"), 10, "the tea took none of the wheat capacity")
	assert_gt(_stock(sim, &"tea"), 0)
	assert_eq(sim.snapshot()["market"]["barley"]["flour_unloading_debt"], 0.0)


# --- The wheat policy (#41) inside the wheat share ----------------------------------------

func test_a_wheat_price_over_the_maximum_does_not_hand_its_share_to_barley() -> void:
	var state: EconomyState = _state(50)
	state.wheat_price = 3
	state.wheat_max_price = 2
	state.stocks[&"wheat"] = 5
	var sim: Simulation = _sim(state)
	_run(sim, 60)
	assert_eq(_stock(sim, &"wheat"), 5, "the wharf waits for the price")
	assert_eq(_stock(sim, &"barley"), 5, "barley keeps its half and no more")


func test_accumulating_stays_an_extra_of_the_wheat_only() -> void:
	var state: EconomyState = _state(50)
	state.wheat_price = 1
	state.wheat_accumulate_price = 1
	state.wheat_target_stock = 60
	var sim: Simulation = _sim(state)
	_run(sim, 60)
	assert_eq(_stock(sim, &"wheat"), 10, "half of the capacity, doubled by accumulating")
	assert_eq(_stock(sim, &"barley"), 5, "barley does not accumulate")


func test_the_safety_reserve_still_measures_against_the_mill_with_part_of_the_capacity_left() -> void:
	var state: EconomyState = _state(50, 1, [&"mill", &"bakery"])
	state.wheat_price = 3
	state.wheat_max_price = 2
	state.wheat_reserve_minutes = 2
	var sim: Simulation = _sim(state)
	_run(sim, 60)
	assert_gt(_stock(sim, &"wheat") + int(sim.snapshot()["stats"]["bread_produced_per_minute"]), 0,
		"under the reserve it buys at any price, inside its half of the wharf")
	assert_lte(_stock(sim, &"barley"), 5)


func test_the_panel_does_not_blame_the_price_when_wheat_has_no_share_of_the_wharf() -> void:
	for percent: int in [0, 100]:
		var state: EconomyState = _state(percent)
		state.wheat_price = 3
		state.wheat_max_price = 2
		state.stocks[&"wheat"] = 5
		var sim: Simulation = _sim(state)
		_run(sim, 5)
		assert_eq(sim.snapshot()["market"]["wheat"]["blocked_by_price"], percent == 0,
			"at %d %% barley the price is the cause only if wheat could buy" % percent)


func test_the_panel_does_not_blame_the_price_while_the_flour_keeps_the_whole_wharf() -> void:
	var state: EconomyState = _state(0)
	state.wheat_price = 3
	state.wheat_max_price = 2
	state.stocks[&"wheat"] = 5
	state.flour_unloading_debt = 15.0
	var sim: Simulation = _sim(state)
	sim.tick()
	assert_false(sim.snapshot()["market"]["wheat"]["blocked_by_price"], "15 units owed, 10 a minute of capacity")


# --- Data ---------------------------------------------------------------------------------

func test_the_new_values_come_from_data_with_the_approved_numbers() -> void:
	var params: Params = Params.new(_catalog, RoleDef.new())
	var expected: Dictionary[StringName, Variant] = {
		&"market.barley.base_price": 2, &"market.barley.min_price": 1, &"market.barley.max_price": 3,
		&"market.barley.max_step": 1, &"market.barley.reversion": 0.35,
		&"market.barley.storage_capacity": 80, &"market.barley.decay_fraction_per_minute": 0.01,
		&"market.barley.price_update_seconds": 60,
		&"policy.unloading.default_barley_percent": 0,
		&"policy.unloading.step_percent": 10,
	}
	for key: StringName in expected:
		assert_eq(params.get_value(key), expected[key], String(key))


func test_a_role_cannot_push_the_new_values_out_of_their_range() -> void:
	var invalid: Dictionary[StringName, Array] = {
		&"policy.unloading.default_barley_percent": [-1.0, 101.0, 50.5],
		&"market.barley.storage_capacity": [-1.0, 10001.0, 1.5],
		&"market.barley.reversion": [-0.1, 1.1],
		&"market.barley.max_step": [0.0, 1.5],
		&"market.barley.decay_fraction_per_minute": [-0.1, 1.0],
		&"market.barley.base_price": [-1.0],
		&"market.imported_flour.max_debt_lots": [0.0, 101.0, 1.5],
	}
	for key: StringName in invalid:
		for value: float in invalid[key]:
			var role: RoleDef = RoleDef.new()
			role.modifiers.append(Modifier.new(key, &"set", value))
			assert_null(Params.new(_catalog, role).get_value(key), "%s = %s" % [key, value])
			assert_push_error("Params: invalid range for '%s'" % key)
	for edge: float in [0.0, 100.0]:
		var role: RoleDef = RoleDef.new()
		role.modifiers.append(Modifier.new(&"policy.unloading.default_barley_percent", &"set", edge))
		assert_eq(Params.new(_catalog, role).get_value(&"policy.unloading.default_barley_percent"), edge)


func test_the_scenario_csv_exports_the_barley_so_the_columns_reconcile_with_the_balance() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	var scenario: Dictionary = {
		"id": "barley_csv", "description": "x", "notes": "x", "seed": 42, "duration_ticks": 180,
		"commands": [
			{"tick": 0, "cmd": "build", "building": "wharf", "cell": [2, 7]},
			{"tick": 0, "cmd": "set_unloading_split", "barley_percent": 100}],
	}
	assert_eq(runner.validate(scenario), [])
	var row: Dictionary = runner.run(scenario).final_row()
	assert_gt(row["barley_stock"], 0)
	assert_gt(row["barley_spent_pm"], 0.0)
	assert_true("barley_spent_pm" in ScenarioResult.CSV_COLUMNS)
	assert_true("barley_spent_pm" in ScenarioResult.FLOAT_COLUMNS)
