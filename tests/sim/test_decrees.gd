extends GutTest

# Issue #71: revocable decrees paid from the legitimacy reserve (D-124, D-125, D-126). Costs come from
# FactionSystem.weights and Params, never from a hardcoded weight. The fixture upkeep is a test number only.

const STRIP: StringName = &"riverside_strip"
const DECREE: StringName = &"fixture_decree"
const UPKEEP_KEY: StringName = &"decree.fixture_decree.upkeep_per_min"
const RATEPAYERS: StringName = &"ratepayers"
const REFORMERS: StringName = &"reformers"
const EFFECT_TEXT: String = "El mantenimiento sale de las tasas y baja el apoyo de los contribuyentes."
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
	_strip.decrees.clear()
	_strip.decree_competencies.clear()


func _with(overrides: Dictionary[StringName, float]) -> Params:
	var role: RoleDef = RoleDef.new()
	for key: StringName in overrides:
		role.modifiers.append(Modifier.new(key, &"set", overrides[key]))
	return Params.new(_catalog, role)


func _value(key: StringName) -> float:
	return float(_params.get_value(key))


func _state(workers: int = 10) -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.tax_rate = _value(&"population.tax.rate")
	state.money = 500
	state.buildings.append({"definition_id": &"mill", "cell": [0, 0], "workers": workers})
	return state


func _started(state: EconomyState) -> EconomyState:
	FactionSystem.initialize(state, _params, _strip)
	return state


func _make(id: StringName, supporters: Array[StringName], opponents: Array[StringName]) -> DecreeDef:
	var decree: DecreeDef = DecreeDef.new()
	decree.use_id(id)
	decree.for_factions = supporters
	decree.against_factions = opponents
	decree.name_key = &"ui.decree.fixture"
	return decree


func _put(decree: DecreeDef, competent: bool = true, context: EconomyContext = null) -> void:
	var target: EconomyContext = _strip if context == null else context
	target.decrees[decree.id] = decree
	if competent and decree.id not in target.decree_competencies:
		target.decree_competencies.append(decree.id)


func _run(command: SimulationCommand, state: EconomyState, context: EconomyContext = null) -> void:
	command.use_context(_strip if context == null else context)
	command.execute(state, _params, RandomNumberGenerator.new())
	command.release_context()


func _weight_of(state: EconomyState, ids: Array[StringName], context: EconomyContext = null) -> float:
	var target: EconomyContext = _strip if context == null else context
	var weights: Dictionary[StringName, float] = FactionSystem.weights(state, _params, target)
	var total: float = 0.0
	for id: StringName in ids:
		total += weights.get(id, 0.0)
	return total


func _expected(state: EconomyState, ids: Array[StringName], context: EconomyContext = null) -> float:
	var target: EconomyContext = _strip if context == null else context
	return FactionSystem.cost(state, _params, _value(&"factions.decree_legitimacy_cost") * _weight_of(state, ids, target))


# Writes a fixture upkeep into the catalog, builds Params, then restores the catalog. The number never ships.
func _params_with(amount: int, overrides: Dictionary[StringName, float] = {}) -> Params:
	var previous: Variant = _catalog.base_values.get(UPKEEP_KEY, null)
	var had_money: bool = UPKEEP_KEY in _catalog.money_keys
	var had_integer: bool = UPKEEP_KEY in _catalog.integer_keys
	_catalog.base_values[UPKEEP_KEY] = amount
	if not had_money:
		_catalog.money_keys.append(UPKEEP_KEY)
	if not had_integer:
		_catalog.integer_keys.append(UPKEEP_KEY)
	var params: Params = _with(overrides)
	if previous == null:
		_catalog.base_values.erase(UPKEEP_KEY)
	else:
		_catalog.base_values[UPKEEP_KEY] = previous
	if not had_money:
		_catalog.money_keys.erase(UPKEEP_KEY)
	if not had_integer:
		_catalog.integer_keys.erase(UPKEEP_KEY)
	return params


func test_decrees_spend_the_existing_reserve() -> void:
	var state: EconomyState = _started(_state())
	var opponents: Array[StringName] = [RATEPAYERS]
	_put(_make(DECREE, [] as Array[StringName], opponents))
	var before: float = state.legitimacy
	var expected: float = _expected(state, opponents)
	var economy: Dictionary = state.to_dict()
	var command: EnactDecreeCommand = EnactDecreeCommand.new(DECREE)
	_run(command, state)
	assert_true(command.accepted, str(command.reason))
	assert_almost_eq(state.legitimacy, before - expected, EPSILON)
	assert_lt(state.legitimacy, before)
	assert_false(state.to_dict().has("legitimacy"), "The reserve stays off the economy dict")
	assert_eq(state.to_dict(), economy, "Spending it adds no second legitimacy field")


func test_enact_costs_the_weight_of_the_factions_against() -> void:
	var state: EconomyState = _started(_state())
	var opponents: Array[StringName] = [RATEPAYERS, REFORMERS]
	var decree: DecreeDef = _make(DECREE, [] as Array[StringName], opponents)
	_put(decree)
	var expected: float = _expected(state, opponents)
	assert_gt(expected, 0.0)
	assert_almost_eq(DecreeSystem.enact_cost(state, _params, _strip, decree), expected, EPSILON)
	var before: float = state.legitimacy
	var command: EnactDecreeCommand = EnactDecreeCommand.new(DECREE)
	_run(command, state)
	assert_true(command.accepted, str(command.reason))
	assert_almost_eq(state.legitimacy, before - expected, EPSILON)


func test_nobody_against_enacts_for_free() -> void:
	var state: EconomyState = _started(_state())
	var decree: DecreeDef = _make(DECREE, [RATEPAYERS] as Array[StringName], [] as Array[StringName])
	_put(decree)
	assert_almost_eq(DecreeSystem.enact_cost(state, _params, _strip, decree), 0.0, EPSILON)
	var before: float = state.legitimacy
	var command: EnactDecreeCommand = EnactDecreeCommand.new(DECREE)
	_run(command, state)
	assert_true(command.accepted, str(command.reason))
	assert_almost_eq(state.legitimacy, before, EPSILON)
	assert_true(DECREE in state.active_decrees)


func test_revoke_costs_the_weight_of_the_factions_in_favor_and_refuses_when_short() -> void:
	var state: EconomyState = _started(_state())
	var supporters: Array[StringName] = [RATEPAYERS, REFORMERS]
	var decree: DecreeDef = _make(DECREE, supporters, [] as Array[StringName])
	_put(decree)
	var enact: EnactDecreeCommand = EnactDecreeCommand.new(DECREE)
	_run(enact, state)
	assert_true(enact.accepted, str(enact.reason))
	var at_full: float = DecreeSystem.revoke_cost(state, _params, _strip, decree)
	assert_almost_eq(at_full, _expected(state, supporters), EPSILON)
	assert_gt(at_full, 0.0)
	var short: float = 1.0
	state.legitimacy = short
	var cost: float = DecreeSystem.revoke_cost(state, _params, _strip, decree)
	assert_gt(cost, short, "Below 30 the revoke still costs more than the reserve")
	assert_almost_eq(cost, _expected(state, supporters), EPSILON)
	var active: Array[StringName] = state.active_decrees.duplicate()
	var command: RevokeDecreeCommand = RevokeDecreeCommand.new(DECREE)
	_run(command, state)
	assert_false(command.accepted)
	assert_eq(command.reason, FactionSystem.NOT_ENOUGH_LEGITIMACY)
	assert_eq(state.active_decrees, active, "A short reserve does not revoke")
	assert_almost_eq(state.legitimacy, short, EPSILON)


func test_below_30_the_cost_is_half_as_much_again() -> void:
	var state: EconomyState = _started(_state())
	var opponents: Array[StringName] = [RATEPAYERS]
	var decree: DecreeDef = _make(DECREE, [] as Array[StringName], opponents)
	_put(decree)
	state.legitimacy = _value(&"factions.low_legitimacy_threshold")
	var at_threshold: float = DecreeSystem.enact_cost(state, _params, _strip, decree)
	assert_almost_eq(at_threshold, _expected(state, opponents), EPSILON)
	state.legitimacy = _value(&"factions.low_legitimacy_threshold") - 0.1
	var below: float = DecreeSystem.enact_cost(state, _params, _strip, decree)
	assert_almost_eq(below, at_threshold * _value(&"factions.low_legitimacy_cost_multiplier"), EPSILON)
	assert_almost_eq(below, _expected(state, opponents), EPSILON)
	var before: float = state.legitimacy
	var command: EnactDecreeCommand = EnactDecreeCommand.new(DECREE)
	_run(command, state)
	assert_true(command.accepted, str(command.reason))
	assert_almost_eq(state.legitimacy, before - below, EPSILON)


func test_a_decree_outside_the_scenario_competencies_is_refused() -> void:
	var state: EconomyState = _started(_state())
	_put(_make(DECREE, [] as Array[StringName], [RATEPAYERS] as Array[StringName]), false)
	var before: float = state.legitimacy
	var economy: Dictionary = state.to_dict()
	var unknown: EnactDecreeCommand = EnactDecreeCommand.new(&"missing")
	_run(unknown, state)
	assert_false(unknown.accepted)
	assert_eq(unknown.reason, &"unknown_decree")
	var command: EnactDecreeCommand = EnactDecreeCommand.new(DECREE)
	_run(command, state)
	assert_false(command.accepted)
	assert_eq(command.reason, &"not_in_competence")
	assert_almost_eq(state.legitimacy, before, EPSILON)
	assert_true(state.active_decrees.is_empty())
	assert_eq(state.to_dict(), economy)


func test_without_factions_decrees_are_refused() -> void:
	var decree: DecreeDef = _make(DECREE, [] as Array[StringName], [RATEPAYERS] as Array[StringName])
	var bare: EconomyContext = _strip.copy()
	bare.factions.clear()
	_put(decree, true, bare)
	var state: EconomyState = _started(_state())
	var before: float = state.legitimacy
	var command: EnactDecreeCommand = EnactDecreeCommand.new(DECREE)
	_run(command, state, bare)
	assert_false(command.accepted)
	assert_eq(command.reason, &"no_factions")
	assert_almost_eq(state.legitimacy, before, EPSILON)
	assert_true(state.active_decrees.is_empty())
	var cold: EconomyState = _state()
	assert_lt(cold.legitimacy, 0.0)
	_put(decree)
	var blocked: EnactDecreeCommand = EnactDecreeCommand.new(DECREE)
	_run(blocked, cold)
	assert_false(blocked.accepted)
	assert_eq(blocked.reason, &"no_factions")
	assert_lt(cold.legitimacy, 0.0)


func test_enacting_twice_spends_once() -> void:
	var state: EconomyState = _started(_state())
	var opponents: Array[StringName] = [RATEPAYERS]
	_put(_make(DECREE, [] as Array[StringName], opponents))
	var expected: float = _expected(state, opponents)
	var first: EnactDecreeCommand = EnactDecreeCommand.new(DECREE)
	_run(first, state)
	assert_true(first.accepted, str(first.reason))
	var after: float = state.legitimacy
	assert_almost_eq(after, _value(&"factions.legitimacy_start") - expected, EPSILON)
	var second: EnactDecreeCommand = EnactDecreeCommand.new(DECREE)
	_run(second, state)
	assert_false(second.accepted)
	assert_eq(second.reason, &"already_active")
	assert_almost_eq(state.legitimacy, after, EPSILON)
	assert_eq(state.active_decrees.size(), 1)


func test_diagnostics_name_cost_upkeep_and_factions_without_changing_state() -> void:
	var params: Params = _params_with(60)
	var state: EconomyState = _started(_state())
	var supporters: Array[StringName] = [REFORMERS]
	var opponents: Array[StringName] = [RATEPAYERS]
	var decree: DecreeDef = _make(DECREE, supporters, opponents)
	_put(decree)
	var money: int = state.money
	var legitimacy: float = state.legitimacy
	var economy: Dictionary = state.to_dict()
	var built: Array = DecreeDiagnostics.build(state, params, _strip)
	assert_eq(built.size(), 1)
	if built.size() != 1:
		return
	var row: Dictionary = built[0]
	assert_eq(row["id"], DECREE)
	assert_eq(row["name_key"], decree.name_key)
	assert_false(row["active"])
	assert_true(row["in_competence"])
	assert_eq(row["for"], supporters)
	assert_eq(row["against"], opponents)
	assert_almost_eq(row["enact_cost"], DecreeSystem.enact_cost(state, params, _strip, decree), EPSILON)
	assert_almost_eq(row["revoke_cost"], DecreeSystem.revoke_cost(state, params, _strip, decree), EPSILON)
	assert_eq(row["upkeep_per_min"], params.get_value(UPKEEP_KEY))
	assert_eq(row["effect"], &"rates_upkeep")
	Strings.use_default_locale()
	assert_eq(Strings.text(&"ui.decree.effect.rates_upkeep"), EFFECT_TEXT)
	assert_eq(state.money, money)
	assert_almost_eq(state.legitimacy, legitimacy, EPSILON)
	assert_true(state.active_decrees.is_empty())
	assert_eq(state.decree_upkeep_fraction, 0.0)
	assert_eq(state.to_dict(), economy)


func test_active_upkeep_joins_the_rates_spending() -> void:
	var params: Params = _params_with(60)
	var state: EconomyState = _started(_state())
	var faction: FactionDef = _strip.factions[RATEPAYERS]
	var before: float = FactionSystem.target(state, params, _strip, faction)
	var income: float = MoneySystem.tax_per_minute(state, params, _strip)
	assert_almost_eq(FactionSystem.rates_spending_per_minute(state, params, income), 0.0, EPSILON)
	_put(_make(DECREE, [] as Array[StringName], [RATEPAYERS] as Array[StringName]))
	var enact: EnactDecreeCommand = EnactDecreeCommand.new(DECREE)
	_run(enact, state)
	assert_true(enact.accepted, str(enact.reason))
	var upkeep: float = float(params.get_value(UPKEEP_KEY))
	assert_almost_eq(FactionSystem.rates_spending_per_minute(state, params, income), upkeep, EPSILON)
	assert_lt(FactionSystem.target(state, params, _strip, faction), before)
	var money: int = state.money
	for _index: int in range(SimTime.TICKS_PER_MINUTE):
		DecreeSystem.tick(state, params, _strip)
	assert_eq(state.money, money - int(params.get_value(UPKEEP_KEY)))


func test_the_receiver_lapses_active_decrees_without_spending_legitimacy() -> void:
	var state: EconomyState = _started(_state())
	_put(_make(DECREE, [RATEPAYERS] as Array[StringName], [] as Array[StringName]))
	var enact: EnactDecreeCommand = EnactDecreeCommand.new(DECREE)
	_run(enact, state)
	assert_true(enact.accepted, str(enact.reason))
	assert_true(DECREE in state.active_decrees)
	var legitimacy: float = state.legitimacy
	var money: int = state.money
	state.loan = LoanState.new()
	state.loan.receiver = true
	DecreeSystem.tick(state, _params, _strip)
	assert_true(state.active_decrees.is_empty())
	assert_almost_eq(state.legitimacy, legitimacy, EPSILON)
	assert_eq(state.money, money)


func test_idle_decrees_do_not_move_money_or_legitimacy() -> void:
	var state: EconomyState = _started(_state())
	state.money = 400
	var legitimacy: float = state.legitimacy
	DecreeSystem.tick(state, _params, _strip)
	assert_eq(state.money, 400, "No decree upkeep")
	assert_almost_eq(state.legitimacy, legitimacy, EPSILON)
	assert_eq(state.decree_upkeep_fraction, 0.0)
	var initial: EconomyState = EconomyState.new()
	initial.money = 1000
	initial.wheat_purchases_enabled = false
	initial.population = int(_params.get_value(&"startup.population"))
	var sim: Simulation = Simulation.create_new(_params, initial, 42, _strip)
	sim.tick()
	assert_false(sim.to_save().has("decrees"))


func test_an_active_decree_roundtrips_and_an_old_save_does_not() -> void:
	var params: Params = _params_with(1)
	_put(_make(DECREE, [RATEPAYERS] as Array[StringName], [] as Array[StringName]))
	var initial: EconomyState = EconomyState.new()
	initial.money = 1000
	initial.population = 10
	initial.wheat_purchases_enabled = false
	var sim: Simulation = Simulation.create_new(params, initial, 7, _strip)
	var command: EnactDecreeCommand = EnactDecreeCommand.new(DECREE)
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted, str(command.reason))
	var saved: Dictionary = sim.to_save()
	assert_true(saved.has("decrees"))
	assert_false(saved["economy"].has("decrees"))
	assert_false(saved["economy"].has("legitimacy"))
	var loaded: Simulation = Simulation.from_save(params, _strip, [], bytes_to_var(var_to_bytes(saved)))
	assert_eq(_active_ids(loaded), [DECREE])
	assert_almost_eq(float(loaded.to_save()["decrees"]["upkeep_fraction"]),
		float(saved["decrees"]["upkeep_fraction"]), EPSILON)
	# A real save writes String ids. Only the decrees block is reparsed, so the history stays intact.
	var as_strings: Dictionary = saved.duplicate(true)
	as_strings["decrees"] = JSON.parse_string(JSON.stringify(saved["decrees"]))
	var from_json: Simulation = Simulation.from_save(params, _strip, [], as_strings)
	assert_eq(_active_ids(from_json), [DECREE])
	var old: Dictionary = saved.duplicate(true)
	old.erase("decrees")
	var resumed: Simulation = Simulation.from_save(params, _strip, [], old)
	assert_false(resumed.to_save().has("decrees"))
	assert_true(_active_ids(resumed).is_empty())


func test_the_same_decree_costs_more_when_the_opposing_weight_grows() -> void:
	var state: EconomyState = _started(_state())
	state.population = 100
	var opponents: Array[StringName] = [RATEPAYERS]
	var decree: DecreeDef = _make(DECREE, [] as Array[StringName], opponents)
	_put(decree)
	var low_weight: float = _weight_of(state, opponents)
	var low: float = DecreeSystem.enact_cost(state, _params, _strip, decree)
	assert_almost_eq(low, _expected(state, opponents), EPSILON)
	var artisans: ClassState = ClassState.new()
	artisans.population = 80
	state.class_states[&"artisan"] = artisans
	assert_eq(ClassStates.population_of(state, _strip.classes[&"artisan"]), 80)
	assert_gt(_weight_of(state, opponents), low_weight)
	var high: float = DecreeSystem.enact_cost(state, _params, _strip, decree)
	assert_almost_eq(high, _expected(state, opponents), EPSILON)
	assert_gt(high, low)


func test_shipped_catalog_is_empty() -> void:
	assert_true(_catalog.decrees.is_empty())
	assert_eq(DecreeDiagnostics.build(_started(_state()), _params, _strip).size(), 0)


func test_a_role_modifier_changes_the_upkeep() -> void:
	var plain: Params = _params_with(60)
	var modified: Params = _params_with(60, {UPKEEP_KEY: 12.0})
	assert_eq(plain.get_value(UPKEEP_KEY), 60)
	assert_eq(modified.get_value(UPKEEP_KEY), 12)


func _active_ids(sim: Simulation) -> Array[StringName]:
	var ids: Array[StringName] = []
	for row: Variant in sim.snapshot()["decrees"]:
		if row["active"]:
			ids.append(row["id"])
	return ids
