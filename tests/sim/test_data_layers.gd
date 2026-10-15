extends GutTest

# Difficulty layers (issue #70, D-065): base → preset → knobs → role, resolved by DataLayers.

const GAME_TICKS: int = 900

var _catalog: DataCatalog


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog


func _params(preset_id: StringName, knobs: Dictionary[StringName, Variant] = {}, role: RoleDef = null) -> Params:
	var layers: DataLayers = DataLayers.resolve(_catalog, preset_id, knobs)
	assert_true(layers.is_ok(), str(layers.errors))
	return Params.new(_catalog, role if role != null else RoleDef.new(), layers.modifiers)


func _assert_values(params: Params, expected: Dictionary[StringName, Variant]) -> void:
	for key: StringName in expected:
		if typeof(expected[key]) == TYPE_FLOAT:
			assert_almost_eq(float(params.get_value(key)), float(expected[key]), 0.0000001, str(key))
		else:
			assert_eq(params.get_value(key), expected[key], str(key))


func test_easy_preset_values() -> void:
	_assert_values(_params(&"easy"), {&"startup.money": 1470, &"defeat.grace_seconds": 600.0,
		&"defeat.bankruptcy.duration_seconds": 300, &"defeat.hunger.duration_seconds": 300,
		&"defeat.depopulation.duration_seconds": 300, &"demolish.refund_ratio": 0.75,
		&"market.wheat.max_price": 3, &"market.wheat.reversion": 0.5})


func test_hard_preset_values() -> void:
	_assert_values(_params(&"hard"), {&"startup.money": 800, &"defeat.grace_seconds": 180.0,
		&"defeat.bankruptcy.duration_seconds": 120, &"defeat.hunger.duration_seconds": 120,
		&"defeat.depopulation.duration_seconds": 120, &"market.wheat.max_price": 4,
		&"market.wheat.reversion": 0.35, &"market.barley.reversion": 0.25, &"demolish.refund_ratio": 0.25})


func test_normal_equals_no_layers() -> void:
	assert_true(DataLayers.resolve(_catalog, DataLayers.NORMAL).modifiers.is_empty())


func test_preset_is_relative_to_the_values_below_it() -> void:
	# Stands in for a mod that lowered the starting money: Easy multiplies what it finds, not a fixed 1470.
	_catalog.base_values[&"startup.money"] = 1000
	_assert_values(_params(&"easy"), {&"startup.money": 1400})


func test_knob_overrides_preset() -> void:
	_assert_values(_params(&"hard", {&"starting_money": 2000, &"grace_seconds": 0, &"refund_ratio": 1.0}),
		{&"startup.money": 2000, &"defeat.grace_seconds": 0.0, &"demolish.refund_ratio": 1.0,
		&"defeat.hunger.duration_seconds": 120})


func test_reaction_knob_sets_the_three_durations() -> void:
	_assert_values(_params(&"easy", {&"reaction_seconds": 90}), {&"defeat.bankruptcy.duration_seconds": 90,
		&"defeat.hunger.duration_seconds": 90, &"defeat.depopulation.duration_seconds": 90})


func test_volatility_scales_both_grains() -> void:
	# Base 2, max 3, step 1 for both grains in data/; 1.5 widens the room to 2 pence and the step to 2.
	_assert_values(_params(&"normal", {&"price_volatility": 1.5}), {&"market.wheat.max_price": 4,
		&"market.wheat.max_step": 2, &"market.barley.max_price": 4, &"market.barley.max_step": 2})
	# Hard already took wheat to 4; 0.5 halves its room (2 → 1) and keeps the step at one penny.
	_assert_values(_params(&"hard", {&"price_volatility": 0.5}), {&"market.wheat.max_price": 3,
		&"market.wheat.max_step": 1, &"market.barley.max_price": 3, &"market.barley.max_step": 1})


func test_defeats_knob_turns_the_switch_off() -> void:
	_assert_values(_params(&"normal", {&"defeats_enabled": false}), {&"defeat.enabled": false})


func test_role_applies_after_layers() -> void:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"startup.money", &"add", 100))
	_assert_values(_params(&"hard", {}, role), {&"startup.money": 900})


func test_knob_outside_range_or_step_is_rejected_with_a_clear_error() -> void:
	var cases: Dictionary[StringName, Variant] = {&"reaction_seconds": 45, &"grace_seconds": 30,
		&"starting_money": 3100, &"price_volatility": 0.55, &"refund_ratio": 0.3, &"defeats_enabled": 1}
	for knob_id: StringName in cases:
		var knobs: Dictionary[StringName, Variant] = {knob_id: cases[knob_id]}
		var layers: DataLayers = DataLayers.resolve(_catalog, &"normal", knobs)
		assert_false(layers.is_ok(), str(knob_id))
		assert_true(layers.modifiers.is_empty())
		assert_string_contains("\n".join(layers.errors), "knob '%s'" % knob_id)
	var reaction: DataLayers = DataLayers.resolve(_catalog, &"normal", {&"reaction_seconds": 45})
	assert_eq(reaction.errors, ["difficulty: knob 'reaction_seconds': 45 is outside 60..600 step 30"])


func test_unknown_preset_or_knob_is_rejected() -> void:
	assert_eq(DataLayers.resolve(_catalog, &"nightmare").errors, ["difficulty: unknown preset 'nightmare'"])
	assert_eq(DataLayers.resolve(_catalog, &"easy", {&"events": 1}).errors, ["difficulty: unknown knob 'events'"])


func test_disabled_defeats_never_end_the_game() -> void:
	var params: Params = _params(&"normal", {&"defeats_enabled": false, &"grace_seconds": 0})
	var state: EconomyState = EconomyState.new()
	state.population = 0
	state.money = -1000
	var simulation: Simulation = Simulation.create_new(params, state, 1, EconomyContext.new(_catalog,
		_catalog.maps[&"whitechapel_1850s"]))
	for tick: int in range(GAME_TICKS):
		simulation.tick()
	var defeat: Dictionary = simulation.snapshot()["defeat"]
	assert_true(defeat["causes"].is_empty(), "An empty, bankrupt city must not lose with defeats off")
	for condition: StringName in [&"bankruptcy", &"hunger", &"depopulation"]:
		assert_eq(defeat[condition]["status"], &"ok", str(condition))


func test_same_preset_and_seed_give_the_same_game() -> void:
	var runs: Array[Array] = []
	for run: int in range(2):
		var session: GameSession = GameSession.new(_catalog, _params(&"hard", {&"price_volatility": 1.5}), &"victorian_demo", &"hard")
		var snapshots: Array = []
		for tick: int in range(GAME_TICKS):
			session.simulation.tick()
			if tick % 60 == 59:
				snapshots.append(session.get_snapshot())
		runs.append(snapshots)
	assert_eq(runs[0], runs[1])


func test_session_restart_with_another_preset_uses_its_values() -> void:
	var session: GameSession = GameSession.new(_catalog, _params(&"normal"))
	assert_eq(session.difficulty, DataLayers.NORMAL)
	session.restart_with(_params(&"easy"), &"easy")
	assert_eq(session.difficulty, &"easy")
	assert_eq(session.get_snapshot()["economy"]["money"], 1470)
	session.restart()
	assert_eq(session.get_snapshot()["economy"]["money"], 1470, "A plain restart keeps the difficulty")
