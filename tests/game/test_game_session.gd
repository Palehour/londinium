extends GutTest

var _catalog: DataCatalog
var _session: GameSession
var _results: Array[Dictionary] = []


func before_each() -> void:
	_catalog = DataLoader.new().load_all().catalog
	_session = GameSession.new(_catalog, Params.new(_catalog, _catalog.roles[&"neutral_administrator"]))
	_results.clear()
	_session.command_resolved.connect(_resolved)


func _resolved(accepted: bool, reason: StringName) -> void:
	_results.append({"accepted": accepted, "reason": reason})


func _tick() -> void:
	_session.simulation.tick()
	_session.publish_tick()


func test_provisional_startup_uses_params_and_existing_initial_bread() -> void:
	var state: Dictionary = _session.get_snapshot()["economy"]
	var params: Params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	assert_eq(state["money"], params.get_value(&"startup.money"))
	assert_eq(state["population"], 20)
	assert_eq(state["stocks"][&"bread"], 40)
	assert_true(state["buildings"].is_empty())
	assert_eq(_session.get_snapshot()["seed"], 42)
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign([Modifier.new(&"startup.money", &"set", 1234), Modifier.new(&"startup.population", &"set", 12), Modifier.new(&"population.initial_bread", &"set", 55)])
	role.modifiers.append(Modifier.new(&"startup.seed", &"set", 77))
	var session: GameSession = GameSession.new(_catalog, Params.new(_catalog, role))
	state = session.get_snapshot()["economy"]
	assert_eq(state["money"], 1234)
	assert_eq(state["population"], 12)
	assert_eq(state["stocks"][&"bread"], 55)
	assert_eq(session.get_snapshot()["seed"], 77)


func test_commands_wait_for_tick_and_publish_snapshots_without_aliases() -> void:
	watch_signals(_session)
	var before: Dictionary = _session.get_snapshot()
	var command: BuildCommand = BuildCommand.new(_session.context, &"mill", Vector2i(1, 1))
	_session.submit_command(command)
	assert_eq(command.reason, &"pending")
	assert_true(_results.is_empty())
	_tick()
	assert_eq(_results, [{"accepted": true, "reason": &""}])
	assert_signal_emitted(_session, "snapshot_changed")
	assert_eq(_session.get_snapshot()["economy"]["buildings"].size(), 1)
	assert_true(before["economy"]["buildings"].is_empty())
	var snapshot: Dictionary = _session.get_snapshot()
	snapshot["economy"]["buildings"].clear()
	assert_eq(_session.get_snapshot()["economy"]["buildings"].size(), 1)
	_session.publish_tick()
	assert_eq(_results.size(), 1)


func test_terrain_reasons_are_results_of_real_commands() -> void:
	for id: StringName in [&"mill", &"bakery"]:
		_session.submit_command(BuildCommand.new(_session.context, id, Vector2i(0, 7)))
	_session.submit_command(BuildCommand.new(_session.context, &"wharf", Vector2i(0, 0)))
	_session.submit_command(BuildCommand.new(_session.context, &"wheat_field", Vector2i(2, 2)))
	_session.submit_command(BuildCommand.new(_session.context, &"mill", Vector2i(-1, 0)))
	_tick()
	var expected: Array[StringName] = [&"requires_land", &"requires_land", &"requires_river", &"not_cultivable", &"outside_map"]
	for index: int in range(expected.size()):
		assert_false(_results[index]["accepted"])
		assert_eq(_results[index]["reason"], expected[index])
		assert_eq(Strings.command_result(false, expected[index]), Strings.REASONS[expected[index]])
	assert_eq(Strings.command_result(false, &"future_reason"), "future_reason")
	assert_eq(Strings.command_result(true, &""), Strings.SUCCESS)


func test_occupied_demolition_and_insufficient_money() -> void:
	_session.submit_command(BuildCommand.new(_session.context, &"mill", Vector2i(1, 1)))
	_session.submit_command(BuildCommand.new(_session.context, &"bakery", Vector2i(1, 1)))
	_session.submit_command(DemolishCommand.new(Vector2i(1, 1)))
	_session.submit_command(DemolishCommand.new(Vector2i(1, 1)))
	_tick()
	assert_eq(_results[1]["reason"], &"occupied_cell")
	assert_true(_results[2]["accepted"])
	assert_eq(_results[3]["reason"], &"no_building")
	assert_true(_session.get_snapshot()["economy"]["buildings"].is_empty())
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"startup.money", &"set", 0))
	var poor: GameSession = GameSession.new(_catalog, Params.new(_catalog, role))
	var command: BuildCommand = BuildCommand.new(poor.context, &"mill", Vector2i(1, 1))
	poor.submit_command(command)
	poor.simulation.tick()
	assert_eq(command.reason, &"insufficient_money")


func test_defeat_rejection_is_immediate() -> void:
	var state: EconomyState = EconomyState.new()
	state.defeat_causes.append(&"hunger")
	_session.simulation = Simulation.new(Params.new(_catalog, _catalog.roles[&"neutral_administrator"]), state, 42, _session.context)
	_session.submit_command(DemolishCommand.new(Vector2i.ZERO))
	assert_eq(_results, [{"accepted": false, "reason": &"simulation_defeated"}])
