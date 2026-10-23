extends GutTest

# Issue #63, task 1 (D-090): the generic mission system. A mission is active until its duration ends, when its goal
# is checked once (completed or failed), or until the player abandons it. While a mission whose `defeat_pause` key is
# true is active, the depopulation timer stands still. The missions below exist only in these tests.

const MISSIONS: String = "eras/victorian/missions/"
const PAUSE_KEY: String = "events.cholera.defeat_pause"
# Each outcome pays a different reward, so the money says which effects ran and how many times.
const COMPLETED_PENCE: int = 300
const FAILED_PENCE: int = 200
const ABANDONED_PENCE: int = 100
const START_MONEY: int = 1000

var _documents: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps", "eras/victorian"]:
		for name: String in DirAccess.open("res://data/" + folder).get_files():
			if name.ends_with(".json"):
				var path: String = folder.path_join(name)
				_documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))
	# The population goal of `easy` is met by any city, the one of `census` by none of the empty cities below.
	_documents[MISSIONS + "easy.json"] = _mission(0)
	_documents[MISSIONS + "census.json"] = _mission(1)
	var paused: Dictionary = _mission(0)
	paused["defeat_pause"] = PAUSE_KEY
	_documents[MISSIONS + "paused.json"] = paused


static func _mission(at_least: int) -> Dictionary:
	return {
		"duration_min": 6.5,
		"goal": {"metric": "population", "at_least": at_least},
		"on_completed": [{"type": "money", "pence": COMPLETED_PENCE}],
		"on_failed": [{"type": "money", "pence": FAILED_PENCE}],
		"on_abandoned": [{"type": "money", "pence": ABANDONED_PENCE}],
	}


func _catalog() -> DataCatalog:
	var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(loaded.is_ok(), str(loaded.errors))
	return loaded.catalog


func _params(catalog: DataCatalog) -> Params:
	return Params.new(catalog, catalog.roles[&"neutral_administrator"])


# An empty city with money and nothing that earns or spends it.
func _empty_city(catalog: DataCatalog) -> Simulation:
	var state: EconomyState = EconomyState.new()
	state.money = START_MONEY
	var context: EconomyContext = EconomyContext.new(catalog, catalog.maps[&"whitechapel_1850s"])
	return Simulation.new(_params(catalog), state, 7, context)


func _duration_ticks(catalog: DataCatalog, id: String) -> int:
	return SimTime.minutes_to_ticks(float(_params(catalog).get_value(StringName("mission.%s.duration_min" % id))))


static func _ticks(sim: Simulation, count: int) -> void:
	for index: int in range(count):
		sim.tick()


static func _status(sim: Simulation, id: StringName) -> StringName:
	return StringName(sim.snapshot()["economy"]["missions"][id]["status"])


func test_minutes_become_ticks_in_one_place() -> void:
	assert_eq(SimTime.minutes_to_ticks(6.5), 390)
	assert_eq(SimTime.minutes_to_ticks(1.0), 60)


func test_start_sets_the_mission_active_for_its_duration() -> void:
	var catalog: DataCatalog = _catalog()
	var sim: Simulation = _empty_city(catalog)
	var command: MissionCommand = MissionCommand.new(&"start", &"easy")
	sim.apply_command(command)
	_ticks(sim, _duration_ticks(catalog, "easy") - 1)
	assert_true(command.accepted, str(command.reason))
	assert_eq(_status(sim, &"easy"), &"active", "Active until its last tick")
	assert_eq(sim.treasury(), START_MONEY, "No effect while active")


func test_goal_met_at_close_completes_and_applies_completed_effects() -> void:
	var catalog: DataCatalog = _catalog()
	var sim: Simulation = _empty_city(catalog)
	sim.apply_command(MissionCommand.new(&"start", &"easy"))
	_ticks(sim, _duration_ticks(catalog, "easy"))
	assert_eq(_status(sim, &"easy"), &"completed")
	assert_eq(sim.treasury(), START_MONEY + COMPLETED_PENCE)


func test_goal_missed_at_close_fails_and_applies_failed_effects() -> void:
	var catalog: DataCatalog = _catalog()
	var sim: Simulation = _empty_city(catalog)
	sim.apply_command(MissionCommand.new(&"start", &"census"))
	_ticks(sim, _duration_ticks(catalog, "census"))
	assert_eq(_status(sim, &"census"), &"failed")
	assert_eq(sim.treasury(), START_MONEY + FAILED_PENCE)


func test_abandon_closes_early_and_the_goal_is_never_checked() -> void:
	var catalog: DataCatalog = _catalog()
	var sim: Simulation = _empty_city(catalog)
	sim.apply_command(MissionCommand.new(&"start", &"easy"))
	_ticks(sim, 10)
	var abandon: MissionCommand = MissionCommand.new(&"abandon", &"easy")
	sim.apply_command(abandon)
	_ticks(sim, _duration_ticks(catalog, "easy"))
	assert_true(abandon.accepted, str(abandon.reason))
	assert_eq(_status(sim, &"easy"), &"abandoned")
	assert_eq(sim.treasury(), START_MONEY + ABANDONED_PENCE, "Only the abandon effects, once")


func test_outcome_is_final_and_its_effects_run_once() -> void:
	var catalog: DataCatalog = _catalog()
	var sim: Simulation = _empty_city(catalog)
	sim.apply_command(MissionCommand.new(&"start", &"easy"))
	_ticks(sim, _duration_ticks(catalog, "easy") + 30)
	var restart: MissionCommand = MissionCommand.new(&"start", &"easy")
	var abandon: MissionCommand = MissionCommand.new(&"abandon", &"easy")
	sim.apply_command(restart)
	sim.apply_command(abandon)
	_ticks(sim, 1)
	assert_false(restart.accepted, "A mission runs once")
	assert_false(abandon.accepted, "Only an active mission can be abandoned")
	assert_eq(_status(sim, &"easy"), &"completed")
	assert_eq(sim.treasury(), START_MONEY + COMPLETED_PENCE)


func test_unknown_mission_is_refused() -> void:
	var sim: Simulation = _empty_city(_catalog())
	var command: MissionCommand = MissionCommand.new(&"start", &"nowhere")
	sim.apply_command(command)
	_ticks(sim, 1)
	assert_false(command.accepted)
	assert_eq(command.reason, &"unknown_mission")


func test_save_mid_mission_resumes_to_the_same_outcome() -> void:
	var catalog: DataCatalog = _catalog()
	var context: EconomyContext = EconomyContext.new(catalog, catalog.maps[&"whitechapel_1850s"])
	var end: int = _duration_ticks(catalog, "census") + 60
	var uninterrupted: Simulation = _empty_city(catalog)
	uninterrupted.apply_command(MissionCommand.new(&"start", &"census"))
	_ticks(uninterrupted, end)
	var first: Simulation = _empty_city(catalog)
	first.apply_command(MissionCommand.new(&"start", &"census"))
	_ticks(first, 200)
	var saved: Dictionary = bytes_to_var(var_to_bytes(first.to_save()))
	var loaded: Simulation = Simulation.from_save(_params(catalog), context, [], saved)
	assert_eq(_status(loaded, &"census"), &"active", "Loaded in the middle of the mission")
	_ticks(loaded, end - 200)
	assert_eq(_status(loaded, &"census"), &"failed")
	assert_eq(loaded.snapshot(), uninterrupted.snapshot())


# A game that never started a mission saves as before the missions, and such a save loads with none.
func test_save_without_missions_is_unchanged_and_loads_with_none() -> void:
	var catalog: DataCatalog = _catalog()
	var context: EconomyContext = EconomyContext.new(catalog, catalog.maps[&"whitechapel_1850s"])
	var saved: Dictionary = _empty_city(catalog).to_save()
	assert_false(saved["economy"].has("missions"))
	var loaded: Simulation = Simulation.from_save(_params(catalog), context, [], saved)
	var start: MissionCommand = MissionCommand.new(&"start", &"easy")
	loaded.apply_command(start)
	_ticks(loaded, 1)
	assert_true(start.accepted, "No mission had started")


func test_defeat_pause_freezes_the_depopulation_timer_while_active() -> void:
	var catalog: DataCatalog = _catalog()
	var params: Params = _params(catalog)
	var depopulation: int = int(params.get_value(&"defeat.depopulation.duration_seconds"))
	var counting_from: int = int(params.get_value(&"defeat.grace_seconds")) + 1
	var sim: Simulation = _empty_city(catalog)
	# The empty city's timer runs for half its time before the mission starts.
	_ticks(sim, counting_from + depopulation / 2)
	var before: int = int(sim.snapshot()["economy"]["depopulation"]["elapsed_seconds"])
	assert_gt(before, 0, "The timer was running")
	sim.apply_command(MissionCommand.new(&"start", &"paused"))
	_ticks(sim, _duration_ticks(catalog, "paused") - 1)
	assert_eq(sim.snapshot()["defeat"]["causes"], [], "No depopulation defeat while the mission is active")
	assert_eq(int(sim.snapshot()["economy"]["depopulation"]["elapsed_seconds"]), before, "Frozen, not reset")
	_ticks(sim, 1 + depopulation - before)
	assert_eq(sim.snapshot()["defeat"]["causes"], [&"depopulation"], "The timer goes on from where it stopped")


func test_without_the_pause_the_depopulation_defeat_comes_as_always() -> void:
	_documents["economy/events.json"]["cholera"]["defeat_pause"] = false
	var catalog: DataCatalog = _catalog()
	var params: Params = _params(catalog)
	var sim: Simulation = _empty_city(catalog)
	# Started when the timer starts counting, so the mission is still running when the timer runs out.
	_ticks(sim, int(params.get_value(&"defeat.grace_seconds")))
	sim.apply_command(MissionCommand.new(&"start", &"paused"))
	_ticks(sim, int(params.get_value(&"defeat.depopulation.duration_seconds")) + 1)
	assert_eq(sim.snapshot()["defeat"]["causes"], [&"depopulation"])
	assert_eq(_status(sim, &"paused"), &"active", "The mission was still running")


# The missions loaded but never started change nothing: with none in data/, the game plays as before them.
func test_missions_never_started_leave_the_game_unchanged() -> void:
	var with_missions: Simulation = _empty_city(_catalog())
	for path: String in _documents.keys():
		if path.begins_with(MISSIONS):
			_documents.erase(path)
	var without: Simulation = _empty_city(_catalog())
	_ticks(with_missions, 900)
	_ticks(without, 900)
	assert_eq(with_missions.snapshot(), without.snapshot())
