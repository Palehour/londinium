extends GutTest

# The four 1870 houses of the strip, empty dense housing from the start (issue #180, D-085).
const PERIOD_HOUSES: Array[Dictionary] = [{"definition_id": &"dense_housing", "cell": [4, 3]},
	{"definition_id": &"dense_housing", "cell": [3, 4]}, {"definition_id": &"dense_housing", "cell": [5, 4]},
	{"definition_id": &"dense_housing", "cell": [5, 5]}]

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


func test_only_demo_enables_victory_and_restart_resets_its_progress() -> void:
	assert_true(_session.get_snapshot()["victory"]["enabled"])
	_session.simulation.tick()
	assert_eq(_session.get_snapshot()["economy"]["victory"]["elapsed_seconds"], 1)
	_session.restart()
	assert_eq(_session.get_snapshot()["economy"]["victory"]["elapsed_seconds"], 0)
	assert_false(_session.get_snapshot()["victory"]["won"])
	var no_objectives: GameSession = GameSession.new(_catalog,
		Params.new(_catalog, _catalog.roles[&"neutral_administrator"]), &"no_objectives")
	assert_false(no_objectives.get_snapshot()["victory"]["enabled"])


func _tick() -> void:
	_session.simulation.tick()
	_session.publish_tick()


func test_provisional_startup_uses_params_and_existing_initial_bread() -> void:
	var state: Dictionary = _session.get_snapshot()["economy"]
	var params: Params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	assert_eq(state["money"], params.get_value(&"startup.money"))
	assert_eq(state["population"], 20)
	assert_eq(state["stocks"][&"bread"], 40)
	# Only the anchors of the strip with a use: the dense housing of Pier Head (issue #154, D-075) and Oliver's Wharf
	# (issue #152), and the 1870 houses (issue #180, D-085).
	assert_eq(state["buildings"], [{"definition_id": &"dense_housing", "cell": [8, 6]}] + PERIOD_HOUSES
		+ [{"definition_id": &"wharf", "cell": [10, 8]}])
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
	# Plus the two anchors with a use the strip starts with (issues #154 and #152) and the 1870 houses (#180).
	var start: int = 2 + PERIOD_HOUSES.size()
	assert_eq(_session.get_snapshot()["economy"]["buildings"].size(), start + 1)
	assert_eq(before["economy"]["buildings"].size(), start)
	var snapshot: Dictionary = _session.get_snapshot()
	snapshot["economy"]["buildings"].clear()
	assert_eq(_session.get_snapshot()["economy"]["buildings"].size(), start + 1)
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
		assert_eq(Strings.command_result(false, expected[index]), Strings.reason(expected[index]))
	assert_eq(Strings.command_result(false, &"future_reason"), "future_reason")
	assert_eq(Strings.command_result(true, &""), Strings.text(Strings.SUCCESS))


func test_occupied_demolition_and_insufficient_money() -> void:
	_session.submit_command(BuildCommand.new(_session.context, &"mill", Vector2i(1, 1)))
	_session.submit_command(BuildCommand.new(_session.context, &"bakery", Vector2i(1, 1)))
	_session.submit_command(DemolishCommand.new(Vector2i(1, 1)))
	_session.submit_command(DemolishCommand.new(Vector2i(1, 1)))
	_tick()
	assert_eq(_results[1]["reason"], &"occupied_cell")
	assert_true(_results[2]["accepted"])
	assert_eq(_results[3]["reason"], &"no_building")
	# Only the two anchors of the strip with a use and the 1870 houses are left (issues #154, #152 and #180).
	assert_eq(_session.get_snapshot()["economy"]["buildings"].size(), 2 + PERIOD_HOUSES.size())
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


func test_the_demo_is_played_on_the_riverside_strip() -> void:
	assert_eq(_session.context.map.id, &"riverside_strip")
	assert_eq(Vector2i(_session.context.map.width, _session.context.map.height), Vector2i(16, 12))
	var other: GameSession = GameSession.new(_catalog,
		Params.new(_catalog, _catalog.roles[&"neutral_administrator"]), &"no_objectives")
	assert_eq(other.context.map.id, &"whitechapel_1850s", "A scenario without a map keeps the 8x8 map")


# Issue #154 (D-075): the demo starts with its one dense housing, and a restart puts it back. Issue #152 (option A of
# Cristian, 2026-10-18): Oliver's Wharf stands too, and neither anchor is demolished, so the restart is tested after a
# street of the player instead of after demolishing the house.
func test_the_demo_starts_with_its_anchors_and_a_restart_puts_them_back() -> void:
	var start: Array = _session.get_snapshot()["economy"]["buildings"]
	assert_eq(start.size(), 2 + PERIOD_HOUSES.size(), "The anchors and the 1870 houses (issue #180, D-085)")
	if start.is_empty():
		return
	var ids: Array[StringName] = []
	for building: Dictionary in start:
		ids.append(StringName(building["definition_id"]))
	assert_eq(ids, [&"dense_housing", &"dense_housing", &"dense_housing", &"dense_housing", &"dense_housing",
		&"wharf"] as Array[StringName])
	_session.submit_command(DemolishCommand.new(Vector2i(start[0]["cell"][0], start[0]["cell"][1])))
	_tick()
	assert_eq(_results, [{"accepted": false, "reason": &"historic_anchor"}], "The starting house is not demolished")
	_session.submit_command(BuildRoadCommand.new(_session.context, Vector2i(6, 5)))
	_tick()
	assert_false(_session.get_snapshot()["economy"]["player_roads"].is_empty())
	_session.restart()
	assert_eq(_session.get_snapshot()["economy"]["buildings"], start)
	assert_true(_session.get_snapshot()["economy"]["player_roads"].is_empty())
