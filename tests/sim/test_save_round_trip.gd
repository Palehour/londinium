extends GutTest

# Issue #57 (D-037): a game saved at minute N and loaded again plays on to minute M exactly as if it had never
# stopped. The save goes through var_to_bytes, the way the file stores it, and covers the Hito 2 chain: barley,
# malt, beer and artisans who arrive and rise.

const SAVE_TICK: int = 600
const END_TICK: int = 1500
# A command after the load, so the restored generators and queue are exercised too.
const LATE_COMMAND_TICK: int = 900

var _catalog: DataCatalog
var _context: EconomyContext
var _stages: Array[Dictionary] = []


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	_stages.assign(_catalog.scenarios[&"victorian_demo"]["stages"])


func _params(preset_id: StringName = DataLayers.NORMAL) -> Params:
	var layers: DataLayers = DataLayers.resolve(_catalog, preset_id)
	return Params.new(_catalog, _catalog.roles[&"neutral_administrator"], layers.modifiers)


func _new_game(params: Params) -> Simulation:
	var state: EconomyState = EconomyState.new()
	state.money = 1000000
	state.population = 30
	var sim: Simulation = Simulation.create_new(params, state, 7, _context, _stages)
	var builds: Array[Array] = [[&"wharf", Vector2i(2, 7)], [&"wharf", Vector2i(4, 7)], [&"mill", Vector2i(2, 5)],
		[&"bakery", Vector2i(3, 5)], [&"housing", Vector2i(5, 3)], [&"housing", Vector2i(5, 4)],
		[&"malthouse", Vector2i(2, 3)], [&"brewery", Vector2i(3, 3)], [&"artisan_housing", Vector2i(6, 3)]]
	for build: Array in builds:
		sim.apply_command(BuildCommand.new(_context, build[0], build[1]))
	sim.apply_command(SetUnloadingSplitCommand.new(15))
	sim.apply_command(SetFlourImportsCommand.new(true))
	sim.apply_command(SetTeaImportsCommand.new(true))
	sim.apply_command(SetWheatPolicyCommand.new(1, 3, 80, 2))
	return sim


func _play(sim: Simulation, from_tick: int, to_tick: int) -> void:
	for tick: int in range(from_tick, to_tick):
		if tick == LATE_COMMAND_TICK:
			sim.apply_command(SetTaxCommand.new(0.45))
		sim.tick()


func _through_bytes(saved: Dictionary) -> Dictionary:
	return bytes_to_var(var_to_bytes(saved))


func _round_trip(preset_id: StringName) -> void:
	var params: Params = _params(preset_id)
	var uninterrupted: Simulation = _new_game(params)
	_play(uninterrupted, 0, END_TICK)
	var first: Simulation = _new_game(params)
	_play(first, 0, SAVE_TICK)
	var loaded: Simulation = Simulation.from_save(params, _context, _stages, _through_bytes(first.to_save()))
	_play(loaded, SAVE_TICK, END_TICK)
	assert_eq(loaded.snapshot(), uninterrupted.snapshot(), "Same state at minute M (%s)" % preset_id)
	assert_eq(loaded.stats_history_to_dict(), uninterrupted.stats_history_to_dict(), "Same saved history")


func test_save_at_minute_n_resume_to_m_matches_uninterrupted_run() -> void:
	_round_trip(DataLayers.NORMAL)


func test_round_trip_holds_on_another_difficulty() -> void:
	_round_trip(&"hard")


func test_restores_tick_rng_buildings_and_policies() -> void:
	var sim: Simulation = _new_game(_params())
	_play(sim, 0, SAVE_TICK)
	var loaded: Simulation = Simulation.from_save(_params(), _context, _stages, _through_bytes(sim.to_save()))
	var snapshot: Dictionary = loaded.snapshot()
	assert_eq(snapshot["tick_count"], SAVE_TICK)
	assert_eq(snapshot["seed"], 7)
	assert_eq(loaded.get_rng_state(), sim.get_rng_state())
	assert_eq(loaded.get_barley_rng_state(), sim.get_barley_rng_state())
	assert_eq(snapshot["economy"]["buildings"], sim.snapshot()["economy"]["buildings"])
	assert_eq(snapshot["economy"]["unloading_barley_percent"], 15)
	assert_eq(snapshot["economy"]["wheat_max_price"], 3)
	assert_eq(snapshot["economy"]["wheat_target_stock"], 80)
	assert_true(snapshot["economy"]["flour_imports_enabled"])


func test_hito_2_goods_and_classes_travel_in_the_save() -> void:
	var sim: Simulation = _new_game(_params())
	_play(sim, 0, END_TICK)
	var economy: Dictionary = sim.snapshot()["economy"]
	assert_gt(int(economy["class_states"][&"artisan"]["population"]), 0, "Artisans arrived before the save")
	assert_gt(int(economy["stocks"][&"barley"]) + int(economy["stocks"][&"malt"]), 0, "The beer chain ran")
	var loaded: Simulation = Simulation.from_save(_params(), _context, _stages, _through_bytes(sim.to_save()))
	assert_eq(loaded.snapshot()["economy"], economy)


func test_save_without_history_still_loads_with_an_empty_one() -> void:
	var sim: Simulation = _new_game(_params())
	_play(sim, 0, SAVE_TICK)
	var saved: Dictionary = sim.to_save()
	saved.erase("stats_history")
	var loaded: Simulation = Simulation.from_save(_params(), _context, _stages, saved)
	assert_eq(loaded.snapshot()["economy"], sim.snapshot()["economy"])
	assert_true(loaded.stats_events().is_empty())
