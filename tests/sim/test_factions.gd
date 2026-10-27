extends GutTest

# Issue #84: factions and legitimacy (D-115, D-116, D-139, D-140) with the values of D-141. The unit tests run the
# rules on a bare state with the strip's context; R there is the head tax of the workers of one mill.

const STRIP: StringName = &"riverside_strip"
const WORKERS: int = 10
const RATEPAYERS: StringName = &"ratepayers"
const REFORMERS: StringName = &"reformers"
const VESTRYMEN: StringName = &"vestrymen"
const EPSILON: float = 0.000001

var _catalog: DataCatalog
var _strip: EconomyContext
var _params: Params


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_strip = EconomyContext.new(_catalog, _catalog.maps[STRIP])


func before_each() -> void:
	_params = _with({})


func _with(overrides: Dictionary[StringName, float]) -> Params:
	var role: RoleDef = RoleDef.new()
	for key: StringName in overrides:
		role.modifiers.append(Modifier.new(key, &"set", overrides[key]))
	return Params.new(_catalog, role)


func _value(key: StringName) -> float:
	return float(_params.get_value(key))


func _state(workers: int = WORKERS) -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.tax_rate = _value(&"population.tax.rate")
	state.buildings.append({"definition_id": &"mill", "cell": [0, 0], "workers": workers})
	return state


func _r() -> float:
	return WORKERS * _value(&"population.tax.rate") * _value(&"population.tax.base_per_employed_worker_per_minute")


# A state with its factions and its reserve started, as a new game has them.
func _started(state: EconomyState) -> EconomyState:
	FactionSystem.initialize(state, _params, _strip)
	return state


func _faction(id: StringName) -> FactionDef:
	return _strip.factions[id]


func _target(state: EconomyState, id: StringName) -> float:
	return FactionSystem.target(state, _params, _strip, _faction(id))


func _ticks(state: EconomyState, count: int) -> void:
	for index: int in range(count):
		state.reset_flows()
		FactionSystem.tick(state, _params, _strip)


# A house at `cell` that the services of `attributes` reach.
func _house(state: EconomyState, cell: Vector2i, attributes: Array[StringName]) -> void:
	state.buildings.append({"definition_id": &"housing", "cell": [cell.x, cell.y]})
	var cover: Dictionary = {}
	for attribute: StringName in attributes:
		cover[attribute] = [Vector2i(-1, -1)]
	state.service_cover[cell] = cover


func test_the_values_are_those_of_d_140_and_d_141() -> void:
	var expected: Dictionary[StringName, float] = {&"factions.legitimacy_fill_per_min": 2,
		&"factions.legitimacy_start": 50, &"factions.support_drift_per_min": 5,
		&"factions.legitimacy_drain_multiplier": 2, &"factions.ratio_income_floor": 1,
		&"factions.decree_legitimacy_cost": 15, &"factions.low_legitimacy_threshold": 30,
		&"factions.low_legitimacy_cost_multiplier": 1.5,
		&"factions.ratepayers.target_base": 80, &"factions.ratepayers.target_scale": 100,
		&"factions.reformers.target_base": 20, &"factions.reformers.target_scale": 60,
		&"factions.vestrymen.target_base": 30, &"factions.vestrymen.target_scale": 50}
	for key: StringName in expected:
		assert_almost_eq(_value(key), expected[key], EPSILON, str(key))


func test_the_three_factions_of_d_139_have_fixed_engines() -> void:
	assert_eq(_strip.factions.keys(), [RATEPAYERS, REFORMERS, VESTRYMEN])
	assert_eq(_faction(RATEPAYERS).engine, FactionDef.RATES_RATIO)
	assert_eq(_faction(REFORMERS).engine, FactionDef.SERVICE_COVERAGE)
	assert_eq(_faction(VESTRYMEN).engine, FactionDef.STABILITY)


func test_the_reformers_are_named_after_toynbee_hall_from_1884() -> void:
	assert_eq(_faction(REFORMERS).name_key(1855), &"ui.faction.sanitary_reformers")
	assert_eq(_faction(REFORMERS).name_key(1883), &"ui.faction.sanitary_reformers")
	assert_eq(_faction(REFORMERS).name_key(1884), &"ui.faction.toynbee_hall")
	assert_eq(_faction(RATEPAYERS).name_key(1888), &"ui.faction.ratepayers")
	assert_eq(_faction(VESTRYMEN).name_key(1855), &"ui.faction.vestrymen")


func test_every_faction_name_is_a_translated_key() -> void:
	for faction: FactionDef in _strip.factions.values():
		for entry: Dictionary in faction.names:
			assert_true(Strings.all_keys().has(entry["key"]), str(entry["key"]))


# D-139, point 4, and D-140: ratio = gasto_tasas / max(R, 1); target 80 - 100 x ratio.
func test_the_ratepayers_target_falls_with_the_rates_spending_over_the_income() -> void:
	var state: EconomyState = _state()
	assert_almost_eq(FactionSystem.rates_ratio(state, _params, _strip), 0.0, EPSILON, "No loan, no spending")
	assert_almost_eq(_target(state, RATEPAYERS), 80.0, EPSILON)
	LoanSystem.open(state, _params, 1000, 0.0)
	# 10 installments of 100 every 300 s: 20 a minute.
	var spending: float = 100.0 * 60.0 / _value(&"loan.installment_interval_s")
	assert_almost_eq(FactionSystem.rates_ratio(state, _params, _strip), spending / _r(), EPSILON)
	assert_almost_eq(_target(state, RATEPAYERS), clampf(80.0 - 100.0 * spending / _r(), 0.0, 100.0), EPSILON)


func test_the_receiver_takes_every_tax_so_the_ratepayers_target_bottoms_out() -> void:
	var state: EconomyState = _state()
	LoanSystem.open(state, _params, 1000, 0.0)
	state.loan.receiver = true
	assert_almost_eq(FactionSystem.rates_ratio(state, _params, _strip), 1.0, EPSILON)
	assert_almost_eq(_target(state, RATEPAYERS), 0.0, EPSILON, "80 - 100 clipped to 0")


# D-140: with R = 0 the floor of 1 a minute applies, so there is no division by zero and the ratio is finite.
func test_with_no_rates_income_the_floor_of_one_a_minute_applies() -> void:
	var state: EconomyState = _state(0)
	assert_almost_eq(MoneySystem.tax_per_minute(state, _params, _strip), 0.0, EPSILON, "R = 0")
	assert_almost_eq(FactionSystem.rates_ratio(state, _params, _strip), 0.0, EPSILON, "Nothing spent over the floor")
	assert_almost_eq(_target(state, RATEPAYERS), 80.0, EPSILON)
	LoanSystem.open(state, _params, 50, 0.0)
	var ratio: float = FactionSystem.rates_ratio(state, _params, _strip)
	assert_true(is_finite(ratio), "Finite with R = 0")
	# 5 every 300 s is 1 a minute, over the floor of 1.
	assert_almost_eq(ratio, 1.0, EPSILON)
	assert_almost_eq(_target(state, RATEPAYERS), 0.0, EPSILON)


func test_the_floor_only_matters_below_it() -> void:
	var state: EconomyState = _state()
	LoanSystem.open(state, _params, 1000, 0.0)
	var with_floor: float = FactionSystem.rates_ratio(state, _with({&"factions.ratio_income_floor": _r() / 2}), _strip)
	assert_almost_eq(with_floor, FactionSystem.rates_ratio(state, _params, _strip), EPSILON, "R is above the floor")
	var high: float = FactionSystem.rates_ratio(state, _with({&"factions.ratio_income_floor": _r() * 2}), _strip)
	assert_almost_eq(high, 20.0 / (_r() * 2), EPSILON, "The floor is above R")


# D-141: 20 + 60 x the share of houses with every service within reach.
func test_the_reformers_target_rises_with_the_houses_every_service_reaches() -> void:
	var state: EconomyState = _state()
	assert_almost_eq(_target(state, REFORMERS), 20.0, EPSILON, "No houses")
	var all: Array[StringName] = [ServiceSystem.HEALTH, ServiceSystem.SAFETY, ServiceSystem.ORDER]
	_house(state, Vector2i(2, 0), all)
	_house(state, Vector2i(4, 0), [ServiceSystem.HEALTH, ServiceSystem.SAFETY] as Array[StringName])
	_house(state, Vector2i(6, 0), [] as Array[StringName])
	_house(state, Vector2i(8, 0), all)
	assert_almost_eq(FactionSystem.coverage(state, _strip, _faction(REFORMERS).coverage), 0.5, EPSILON)
	assert_almost_eq(_target(state, REFORMERS), 50.0, EPSILON)
	for cell: Vector2i in state.service_cover:
		_house(state, cell, all)
	assert_almost_eq(_target(state, REFORMERS), 80.0, EPSILON, "Never 100")


# D-141: 30 + 50 x the mean satisfaction over 100, every class weighed by its people.
func test_the_vestrymen_target_rises_with_the_mean_satisfaction() -> void:
	var state: EconomyState = _state()
	state.satisfaction = 50.0
	assert_almost_eq(_target(state, VESTRYMEN), 55.0, EPSILON, "An empty city: the base class")
	state.population = 40
	var artisans: ClassState = ClassState.new()
	artisans.population = 10
	artisans.satisfaction = 100.0
	state.class_states[&"artisan"] = artisans
	# 30 workers at 50 and 10 artisans at 100: 62.5.
	assert_almost_eq(FactionSystem.stability(state, _strip), 0.625, EPSILON)
	assert_almost_eq(_target(state, VESTRYMEN), 30.0 + 50.0 * 0.625, EPSILON)
	state.satisfaction = 100.0
	assert_almost_eq(_target(state, VESTRYMEN), 80.0, EPSILON, "Never 100")


func test_a_new_state_starts_its_supports_at_their_targets_and_the_reserve_at_50() -> void:
	var state: EconomyState = _started(_state())
	assert_almost_eq(state.legitimacy, 50.0, EPSILON)
	for id: StringName in _strip.factions:
		assert_almost_eq(state.faction_support[id], _target(state, id), EPSILON, str(id))


func test_the_support_drifts_to_its_target_at_5_a_minute_without_overshooting() -> void:
	var state: EconomyState = _started(_state())
	state.faction_support[RATEPAYERS] = 60.0
	_ticks(state, 60)
	assert_almost_eq(state.faction_support[RATEPAYERS], 65.0, 0.0001, "One minute up")
	state.faction_support[RATEPAYERS] = 95.0
	_ticks(state, 60)
	assert_almost_eq(state.faction_support[RATEPAYERS], 90.0, 0.0001, "One minute down")
	_ticks(state, 60 * 3)
	assert_almost_eq(state.faction_support[RATEPAYERS], 80.0, EPSILON, "Stops at the target")


func test_spending_on_the_rates_moves_the_ratepayers_support_down() -> void:
	var state: EconomyState = _started(_state())
	LoanSystem.open(state, _params, 1000, 0.0)
	var target: float = _target(state, RATEPAYERS)
	assert_lt(target, 80.0)
	_ticks(state, 60)
	assert_almost_eq(state.faction_support[RATEPAYERS], maxf(target, 75.0), 0.0001)


# D-116: w_f = sum of pop_c x affinity_c,f / pop_total, each class's affinities taken as shares.
func test_the_weights_follow_each_class_population_and_affinity() -> void:
	var state: EconomyState = _state()
	var equal: Dictionary[StringName, float] = FactionSystem.weights(state, _params, _strip)
	for id: StringName in equal:
		assert_almost_eq(equal[id], 1.0 / 3.0, EPSILON, "Equal affinities: %s" % id)
	var params: Params = _with({&"factions.affinity.worker.ratepayers": 0, &"factions.affinity.worker.reformers": 1,
		&"factions.affinity.worker.vestrymen": 1, &"factions.affinity.artisan.ratepayers": 3,
		&"factions.affinity.artisan.reformers": 1, &"factions.affinity.artisan.vestrymen": 0})
	state.population = 100
	var artisans: ClassState = ClassState.new()
	artisans.population = 25
	state.class_states[&"artisan"] = artisans
	var weights: Dictionary[StringName, float] = FactionSystem.weights(state, params, _strip)
	assert_almost_eq(weights[RATEPAYERS], 0.25 * 0.75, EPSILON)
	assert_almost_eq(weights[REFORMERS], 0.75 * 0.5 + 0.25 * 0.25, EPSILON)
	assert_almost_eq(weights[VESTRYMEN], 0.75 * 0.5, EPSILON)
	assert_almost_eq(weights.values().reduce(func(a: float, b: float) -> float: return a + b), 1.0, EPSILON)


func test_the_ceiling_is_the_weighted_support() -> void:
	var state: EconomyState = _started(_state())
	state.faction_support[RATEPAYERS] = 90.0
	state.faction_support[REFORMERS] = 30.0
	state.faction_support[VESTRYMEN] = 60.0
	assert_almost_eq(FactionSystem.ceiling(state, _params, _strip), 60.0, EPSILON)


# D-116 and D-141: the reserve fills to P at 2 a minute and falls to it at 4 a minute.
func test_the_reserve_fills_to_the_ceiling_at_2_a_minute_and_stops_there() -> void:
	var state: EconomyState = _started(_state())
	var top: float = FactionSystem.ceiling(state, _params, _strip)
	state.legitimacy = top - 3.0
	_ticks(state, 60)
	assert_almost_eq(state.legitimacy, top - 1.0, 0.0001)
	_ticks(state, 60)
	assert_almost_eq(state.legitimacy, top, EPSILON, "Never above the ceiling")


func test_the_reserve_falls_to_a_lower_ceiling_twice_as_fast() -> void:
	var state: EconomyState = _started(_state())
	var top: float = FactionSystem.ceiling(state, _params, _strip)
	state.legitimacy = top + 6.0
	_ticks(state, 60)
	assert_almost_eq(state.legitimacy, top + 2.0, 0.0001)
	_ticks(state, 60)
	assert_almost_eq(state.legitimacy, top, EPSILON)


# D-139, point 5.
func test_spending_more_legitimacy_than_there_is_is_refused_without_changes() -> void:
	var state: EconomyState = _started(_state())
	state.legitimacy = 10.0
	var before: Dictionary = state.factions_to_dict()
	assert_false(FactionSystem.spend(state, 10.5))
	assert_eq(state.factions_to_dict(), before, "Refused without changes")
	assert_false(FactionSystem.spend(state, -1.0), "No negative costs")
	assert_true(FactionSystem.spend(state, 4.0))
	assert_almost_eq(state.legitimacy, 6.0, EPSILON)
	assert_true(FactionSystem.spend(state, 6.0), "Exactly the reserve is allowed")
	assert_almost_eq(state.legitimacy, 0.0, EPSILON, "Never negative")
	assert_false(FactionSystem.spend(state, 0.1))


func test_a_state_without_factions_spends_nothing() -> void:
	var state: EconomyState = _state()
	assert_false(FactionSystem.spend(state, 0.0))
	assert_eq(state.legitimacy, -1.0)


# D-141: a decree costs 15, and 1.5 times more below 30; the refusal still applies.
func test_a_decree_costs_15_and_half_as_much_again_below_30() -> void:
	var state: EconomyState = _started(_state())
	state.legitimacy = 30.0
	assert_almost_eq(FactionSystem.decree_cost(state, _params), 15.0, EPSILON, "At the threshold")
	state.legitimacy = 29.9
	assert_almost_eq(FactionSystem.decree_cost(state, _params), 22.5, EPSILON)
	state.legitimacy = 20.0
	assert_false(FactionSystem.spend(state, FactionSystem.decree_cost(state, _params)), "22.5 over 20")
	assert_almost_eq(state.legitimacy, 20.0, EPSILON)


# D-139, point 3: low legitimacy is no defeat and no event, the reserve only fills again.
func test_an_empty_reserve_is_no_defeat() -> void:
	var state: EconomyState = _started(_state())
	LoanSystem.open(state, _params, 100000, 0.0)
	state.loan.receiver = true
	state.legitimacy = 0.0
	_ticks(state, 600)
	assert_true(state.defeat_causes.is_empty())
	assert_gte(state.legitimacy, 0.0)
	assert_lte(state.legitimacy, FactionSystem.ceiling(state, _params, _strip) + EPSILON)


func test_the_legitimacy_gained_this_tick_joins_the_reserve() -> void:
	var state: EconomyState = _started(_state())
	var top: float = FactionSystem.ceiling(state, _params, _strip)
	state.legitimacy = top - 10.0
	state.reset_flows()
	state.legitimacy_gain_tick = 5.0
	FactionSystem.tick(state, _params, _strip)
	assert_almost_eq(state.legitimacy, top - 5.0 + 2.0 / 60.0, EPSILON)


func test_shifting_a_support_is_clipped_and_drifts_back() -> void:
	var state: EconomyState = _started(_state())
	FactionSystem.shift_support(state, VESTRYMEN, 200.0)
	assert_almost_eq(state.faction_support[VESTRYMEN], 100.0, EPSILON)
	_ticks(state, 60)
	assert_almost_eq(state.faction_support[VESTRYMEN], 95.0, 0.0001)


# Apart from the economy, so it saves and compares as before the factions (the v0.3.0 save of test_save_upgrade).
func test_the_factions_save_apart_from_the_economy() -> void:
	var state: EconomyState = _started(_state())
	assert_false(state.to_dict().has("legitimacy"))
	assert_false(state.to_dict().has("faction_support"))
	state.legitimacy = 42.5
	state.faction_support[REFORMERS] = 33.25
	var loaded: EconomyState = EconomyState.new()
	loaded.restore_factions(bytes_to_var(var_to_bytes(state.factions_to_dict())))
	assert_eq(loaded.factions_to_dict(), state.factions_to_dict())
	assert_almost_eq(loaded.legitimacy, 42.5, EPSILON)


# The game itself: the strip starts its factions and an early payoff adds its 5 points to the reserve (D-129, D-138).
func _game() -> Simulation:
	var state: EconomyState = EconomyState.new()
	state.money = 1000
	state.wheat_purchases_enabled = false
	state.population = int(_params.get_value(&"startup.population"))
	return Simulation.create_new(_params, state, 42, _strip)


func test_a_new_game_starts_with_the_reserve_at_50_and_moves_it() -> void:
	var sim: Simulation = _game()
	var factions: Dictionary = sim.snapshot()["factions"]
	assert_almost_eq(factions["legitimacy"], 50.0, EPSILON)
	assert_eq(factions["factions"].keys(), [RATEPAYERS, REFORMERS, VESTRYMEN])
	var top: float = factions["ceiling"]
	for index: int in range(60):
		sim.tick()
	var after: float = sim.snapshot()["factions"]["legitimacy"]
	assert_lte(absf(after - 50.0), 4.0 + EPSILON, "At most 4 a minute")
	assert_eq(signf(after - 50.0), signf(top - 50.0))


func test_an_early_payoff_adds_its_legitimacy_in_the_game() -> void:
	var with_payoff: Simulation = _game()
	var without: Simulation = _game()
	for sim: Simulation in [with_payoff, without]:
		sim.tick()
		sim.apply_command(RequestLoanCommand.new(1))
		sim.tick()
	with_payoff.apply_command(RepayLoanEarlyCommand.new())
	with_payoff.tick()
	without.tick()
	var gained: float = with_payoff.snapshot()["factions"]["legitimacy"] - without.snapshot()["factions"]["legitimacy"]
	assert_almost_eq(gained, 5.0, 0.2, "The 5 points of D-138, give or take the support the loan moved")


func test_a_saved_game_plays_on_the_same_factions() -> void:
	var sim: Simulation = _game()
	for index: int in range(90):
		sim.tick()
	var saved: Dictionary = sim.to_save()
	assert_true(saved.has("factions"))
	var other: Simulation = Simulation.from_save(_params, _strip, [], bytes_to_var(var_to_bytes(saved)))
	for index: int in range(120):
		sim.tick()
		other.tick()
	assert_eq(other.snapshot()["factions"], sim.snapshot()["factions"])
