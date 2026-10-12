extends GutTest

# Issue #51: malthouse (barley -> malt) and brewery (malt -> beer). Nothing eats beer until #52, so a full
# warehouse stops the producer instead of throwing the output away.


class StockCommand extends SimulationCommand:
	var _good: StringName
	var _amount: int


	func _init(good: StringName, amount: int) -> void:
		_good = good
		_amount = amount


	func execute(state: EconomyState, _params: Params, _rng: RandomNumberGenerator) -> void:
		state.stocks[_good] = _amount


var _catalog: DataCatalog
var _params: Params
var _context: EconomyContext
var _initial: EconomyState


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_params = _isolated()
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	_initial = EconomyState.new()
	_initial.satisfaction = float(_params.get_value(&"population.satisfaction.bread_weight"))
	_initial.stocks.assign({&"barley": 0, &"malt": 0, &"beer": 0, &"bread": 0})
	_initial.money = 10000
	_initial.population = 40


# Production rules without needs and finance; beer spoilage only when the test is about it.
func _isolated(spoils: bool = false) -> Params:
	var role: RoleDef = RoleDef.new()
	# Barley in store would spoil too, which these tests count.
	role.modifiers.append(Modifier.new(&"market.barley.decay_fraction_per_minute", &"set", 0.0))
	if not spoils:
		role.modifiers.append(Modifier.new(&"market.beer.decay_fraction_per_minute", &"set", 0.0))
	return SimTestParams.isolated_params(_catalog, role)


func _add(id: StringName, cell: Array[int] = [1, 1]) -> void:
	_initial.buildings.append({"definition_id": id, "cell": cell})


func _sim() -> Simulation:
	return Simulation.new(_params, _initial, 123, _context)


func _ticks(sim: Simulation, count: int) -> Dictionary:
	for index: int in range(count):
		sim.tick()
	return sim.snapshot()["economy"]


func _reason(sim: Simulation, id: StringName) -> StringName:
	for entry: Dictionary in sim.snapshot()["diagnostics"]["buildings"]:
		if entry["definition_id"] == id:
			return entry["reason"]
	return &"absent"


# --- Production per tick -----------------------------------------------------------------------

func test_malthouse_makes_four_malt_from_four_barley_per_minute() -> void:
	_add(&"malthouse")
	_initial.stocks[&"barley"] = 10
	var state: Dictionary = _ticks(_sim(), 60)
	assert_eq(state["stocks"][&"barley"], 6)
	assert_eq(state["stocks"][&"malt"], 4)
	assert_typeof(state["stocks"][&"malt"], TYPE_INT)


func test_brewery_makes_eight_beer_from_four_malt_per_minute() -> void:
	_add(&"brewery")
	_initial.stocks[&"malt"] = 10
	var state: Dictionary = _ticks(_sim(), 60)
	assert_eq(state["stocks"][&"malt"], 6)
	assert_eq(state["stocks"][&"beer"], 8)
	assert_typeof(state["stocks"][&"beer"], TYPE_INT)


func test_partial_staffing_scales_both_new_converters() -> void:
	for id: StringName in [&"malthouse", &"brewery"]:
		_initial.buildings.clear()
		_add(id)
		_initial.population = 1
		_initial.stocks.assign({&"barley": 30, &"malt": 30, &"beer": 0})
		var state: Dictionary = _ticks(_sim(), 180)
		# One worker of three: a third of 4 inputs per minute, over 3 minutes = 4 inputs used.
		assert_eq(state["buildings"][0]["workers"], 1)
		assert_eq(state["stocks"][&"barley"], 26 if id == &"malthouse" else 30)
		assert_eq(state["stocks"][&"malt"], 34 if id == &"malthouse" else 26)
		assert_eq(state["stocks"][&"beer"], 8 if id == &"brewery" else 0)


func test_full_chain_turns_every_barley_into_two_beers_without_rounding_loss() -> void:
	_add(&"malthouse")
	_add(&"brewery", [2, 1])
	_initial.stocks[&"barley"] = 20
	var state: Dictionary = _ticks(_sim(), 420)
	assert_eq(state["stocks"][&"barley"], 0)
	assert_eq(state["stocks"][&"malt"], 0)
	assert_eq(state["stocks"][&"beer"], 40)
	for building: Dictionary in state["buildings"]:
		assert_eq(building["reserved_input"], 0.0)
		assert_almost_eq(float(building["output_fraction"]), 0.0, 0.000001)


# Issue #51 review: the tick that uses the last of the reserved input is not a starved tick, even though the
# end-of-tick diagnostics already say there is no input.
func test_a_mill_that_uses_its_last_wheat_in_a_tick_is_not_counted_as_starved() -> void:
	_initial.buildings.append({"definition_id": &"mill", "cell": [1, 1]})
	_initial.stocks[&"wheat"] = 10
	var sim: Simulation = _sim()
	for index: int in range(60):
		sim.tick()
		assert_eq(sim.snapshot()["production"]["input_starved"].get(&"mill", 0), 0, "tick %d" % (index + 1))
	assert_eq(_reason(sim, &"mill"), &"no_input", "the diagnostics already say so at the end of tick 60")
	sim.tick()
	assert_eq(sim.snapshot()["production"]["input_starved"].get(&"mill", 0), 1, "tick 61 has nothing to grind")


# --- Stopped, and why --------------------------------------------------------------------------

func test_without_barley_the_malthouse_stops_and_says_so() -> void:
	_add(&"malthouse")
	var sim: Simulation = _sim()
	var state: Dictionary = _ticks(sim, 120)
	assert_eq(state["stocks"][&"malt"], 0)
	assert_eq(_reason(sim, &"malthouse"), &"no_barley")


func test_without_malt_the_brewery_stops_and_says_so() -> void:
	_add(&"brewery")
	var sim: Simulation = _sim()
	var state: Dictionary = _ticks(sim, 120)
	assert_eq(state["stocks"][&"beer"], 0)
	assert_eq(_reason(sim, &"brewery"), &"no_malt")


func test_without_workers_nothing_is_made_and_the_reason_is_no_workers() -> void:
	_add(&"malthouse")
	_add(&"brewery", [2, 1])
	_initial.population = 0
	_initial.stocks.assign({&"barley": 20, &"malt": 20, &"beer": 0})
	var sim: Simulation = _sim()
	var state: Dictionary = _ticks(sim, 120)
	assert_eq(state["stocks"][&"barley"], 20)
	assert_eq(state["stocks"][&"malt"], 20)
	assert_eq(state["stocks"][&"beer"], 0)
	assert_eq(_reason(sim, &"malthouse"), &"no_workers")
	assert_eq(_reason(sim, &"brewery"), &"no_workers")


func test_a_working_malthouse_reports_ok() -> void:
	_add(&"malthouse")
	_initial.stocks[&"barley"] = 10
	var sim: Simulation = _sim()
	_ticks(sim, 10)
	assert_eq(_reason(sim, &"malthouse"), &"ok")


# --- Warehouse caps ----------------------------------------------------------------------------

func test_malthouse_stops_at_the_cap_without_wasting_barley_and_resumes_when_there_is_room() -> void:
	_add(&"malthouse")
	_initial.stocks[&"barley"] = 100
	_initial.stocks[&"malt"] = 38
	var cap: int = int(_params.get_value(&"market.malt.storage_capacity"))
	var sim: Simulation = _sim()
	var state: Dictionary = _ticks(sim, 600)
	assert_eq(state["stocks"][&"malt"], cap)
	# 2 malt of room took exactly 2 barley: nothing is thrown away and nothing is taken for nothing.
	assert_eq(state["stocks"][&"barley"], 98)
	assert_eq(_reason(sim, &"malthouse"), &"storage_full")
	sim.apply_command(StockCommand.new(&"malt", cap - 4))
	state = _ticks(sim, 60)
	assert_eq(state["stocks"][&"malt"], cap)
	assert_eq(state["stocks"][&"barley"], 94)


func test_brewery_stops_at_the_cap_and_reports_a_full_warehouse() -> void:
	_add(&"brewery")
	_initial.stocks[&"malt"] = 100
	_initial.stocks[&"beer"] = 56
	var cap: int = int(_params.get_value(&"market.beer.storage_capacity"))
	var sim: Simulation = _sim()
	var state: Dictionary = _ticks(sim, 600)
	assert_eq(state["stocks"][&"beer"], cap)
	assert_eq(state["stocks"][&"malt"], 98, "4 beers of room took 2 malt")
	assert_eq(_reason(sim, &"brewery"), &"storage_full")


func test_a_full_warehouse_is_the_reason_even_when_the_input_is_gone() -> void:
	_add(&"brewery")
	_initial.stocks[&"beer"] = int(_params.get_value(&"market.beer.storage_capacity"))
	var sim: Simulation = _sim()
	_ticks(sim, 10)
	assert_eq(_reason(sim, &"brewery"), &"storage_full")


func test_capped_outputs_are_derived_from_the_goods_that_define_a_storage_capacity() -> void:
	var capped: Array[StringName] = ProductionSystem.capped_outputs(_params, _context)
	assert_eq(capped.size(), 2)
	assert_true(&"malt" in capped)
	assert_true(&"beer" in capped)
	# Wheat has a cap too, but no converter makes it; flour and bread have none.
	assert_true(ProductionSystem.has_storage_cap(_params, &"wheat"))
	assert_false(ProductionSystem.has_storage_cap(_params, &"flour"))
	assert_false(ProductionSystem.has_storage_cap(_params, &"bread"))


# Issue #51 review: two producers of the same capped good share one free space.
func test_two_breweries_cannot_both_use_the_last_unit_of_room() -> void:
	_add(&"brewery")
	_add(&"brewery", [2, 1])
	var cap: int = int(_params.get_value(&"market.beer.storage_capacity"))
	_initial.stocks[&"malt"] = 100
	_initial.stocks[&"beer"] = cap - 1
	var sim: Simulation = _sim()
	var state: Dictionary = _ticks(sim, 600)
	assert_eq(state["stocks"][&"beer"], cap)
	# One beer of room is half a malt. A malt taken from the stock stays reserved in its brewery until used,
	# so the malt in store plus the reserved one must add up to exactly 100 minus that half.
	var pending: float = 0.0
	var reserved: float = 0.0
	for building: Dictionary in state["buildings"]:
		pending += float(building["output_fraction"])
		reserved += float(building["reserved_input"])
	assert_almost_eq(pending, 0.0, 0.000001, "no hidden output beyond the cap")
	assert_almost_eq(float(state["stocks"][&"malt"]) + reserved, 99.5, 0.000001)


# --- Spoilage ----------------------------------------------------------------------------------

func test_beer_spoils_and_malt_does_not() -> void:
	_params = _isolated(true)
	_initial.stocks[&"beer"] = 50
	_initial.stocks[&"malt"] = 40
	var state: Dictionary = _ticks(_sim(), 600)
	assert_lt(state["stocks"][&"beer"], 50)
	# 50 * 0.98^10 = 40.8 after ten minutes.
	assert_between(state["stocks"][&"beer"], 40, 42)
	assert_eq(state["stocks"][&"malt"], 40)


# --- State -------------------------------------------------------------------------------------

func test_spoilage_fractions_survive_to_dict_and_old_saves_load_without_them() -> void:
	var state: EconomyState = EconomyState.new()
	state.stocks.assign({&"malt": 3, &"beer": 5})
	state.malt_decay_fraction = 0.25
	state.beer_decay_fraction = 0.5
	var copy: EconomyState = EconomyState.from_dict(state.to_dict())
	assert_eq(copy.malt_decay_fraction, 0.25)
	assert_eq(copy.beer_decay_fraction, 0.5)
	var old: Dictionary = state.to_dict()
	old.erase("malt_decay_fraction")
	old.erase("beer_decay_fraction")
	var loaded: EconomyState = EconomyState.from_dict(old)
	assert_eq(loaded.malt_decay_fraction, 0.0)
	assert_eq(loaded.beer_decay_fraction, 0.0)


func test_snapshot_shows_stock_and_cap_of_malt_and_beer() -> void:
	_initial.stocks[&"malt"] = 7
	_initial.stocks[&"beer"] = 9
	var market: Dictionary = _sim().snapshot()["market"]
	assert_eq(market["malt"], {"stock": 7, "capacity": 40})
	assert_eq(market["beer"], {"stock": 9, "capacity": 60})


# --- Worker order (D-021) ----------------------------------------------------------------------

func _all_five() -> void:
	_add(&"wharf", [0, 7])
	_add(&"mill", [2, 1])
	_add(&"bakery", [3, 1])
	_add(&"malthouse", [4, 1])
	_add(&"brewery", [5, 1])


func _workers(population: int) -> Array[int]:
	var state: EconomyState = EconomyState.from_dict(_initial.to_dict())
	state.population = population
	WorkersSystem.new().tick(state, _params)
	var result: Array[int] = []
	for building: Dictionary in state.buildings:
		result.append(int(building["workers"]))
	return result


func test_the_first_round_gives_one_worker_to_each_building_in_chain_order() -> void:
	_all_five()
	assert_eq(_workers(4), [1, 1, 1, 1, 0] as Array[int])
	assert_eq(_workers(5), [1, 1, 1, 1, 1] as Array[int])


func test_extras_fill_the_bread_chain_before_malt_and_beer() -> void:
	_all_five()
	# Bread first (bakery, mill, wharf), then the malthouse, then the brewery.
	assert_eq(_workers(6), [1, 1, 2, 1, 1] as Array[int])
	assert_eq(_workers(12), [4, 3, 3, 1, 1] as Array[int])
	assert_eq(_workers(13), [4, 3, 3, 2, 1] as Array[int])
	assert_eq(_workers(14), [4, 3, 3, 3, 1] as Array[int])
	assert_eq(_workers(16), [4, 3, 3, 3, 3] as Array[int])


func test_emigration_reverses_both_rounds_with_beer_leaving_first() -> void:
	_all_five()
	_initial.population = 16
	var fully_assigned: EconomyState = EconomyState.from_dict(_initial.to_dict())
	WorkersSystem.new().tick(fully_assigned, _params)
	for population: int in range(15, -1, -1):
		fully_assigned.population = population
		WorkersSystem.trim_to_population(fully_assigned)
		var expected: Array[int] = _workers(population)
		for index: int in range(expected.size()):
			assert_eq(int(fully_assigned.buildings[index]["workers"]), expected[index],
				"building %d at population %d" % [index, population])


func test_with_too_few_hands_the_beer_chain_is_the_last_to_be_staffed() -> void:
	_all_five()
	# The bread chain is complete (wharf, mill and bakery at their jobs) before the beer chain gets more
	# than its first worker.
	var staffed: Array[int] = _workers(12)
	assert_eq(staffed[0], int(_params.get_value(&"building.wharf.jobs")))
	assert_eq(staffed[1], int(_params.get_value(&"building.mill.jobs")))
	assert_eq(staffed[2], int(_params.get_value(&"building.bakery.jobs")))
	assert_eq(staffed[3] + staffed[4], 2)


# --- Data and ranges ---------------------------------------------------------------------------

func _documents() -> Dictionary[String, Dictionary]:
	var documents: Dictionary[String, Dictionary] = {}
	for folder: String in ["economy", "roles", "maps"]:
		for file_name: String in DirAccess.open("res://data/" + folder).get_files():
			if file_name.ends_with(".json"):
				var path: String = folder.path_join(file_name)
				documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))
	return documents


func test_the_agreed_starting_values_are_in_data() -> void:
	assert_eq(_params.get_value(&"building.malthouse.cost"), 200)
	assert_eq(_params.get_value(&"building.malthouse.jobs"), 3)
	assert_eq(_catalog.base_values[&"building.malthouse.upkeep_per_minute"], 3)
	assert_eq(_catalog.base_values[&"building.malthouse.wage_per_worker_per_minute"], 2)
	assert_eq(_catalog.base_values[&"building.malthouse.recipe.inputs.barley"], 4.0)
	assert_eq(_catalog.base_values[&"building.malthouse.recipe.outputs.malt"], 4.0)
	assert_eq(_catalog.base_values[&"building.malthouse.recipe.seconds"], 60)
	assert_eq(_catalog.base_values[&"building.brewery.cost"], 160)
	assert_eq(_catalog.base_values[&"building.brewery.jobs"], 3)
	assert_eq(_catalog.base_values[&"building.brewery.upkeep_per_minute"], 2)
	assert_eq(_catalog.base_values[&"building.brewery.wage_per_worker_per_minute"], 2)
	assert_eq(_catalog.base_values[&"building.brewery.recipe.inputs.malt"], 4.0)
	assert_eq(_catalog.base_values[&"building.brewery.recipe.outputs.beer"], 8.0)
	assert_eq(_catalog.base_values[&"building.brewery.recipe.seconds"], 60)
	assert_eq(_catalog.base_values[&"market.malt.storage_capacity"], 40)
	assert_eq(_catalog.base_values[&"market.malt.decay_fraction_per_minute"], 0.0)
	assert_eq(_catalog.base_values[&"market.beer.storage_capacity"], 60)
	assert_eq(_catalog.base_values[&"market.beer.decay_fraction_per_minute"], 0.02)


func test_loader_rejects_out_of_range_malt_and_beer_values() -> void:
	var cases: Array[Array] = [
		["malt", "storage_capacity", -1], ["malt", "storage_capacity", 10001], ["malt", "storage_capacity", 12.5],
		["beer", "storage_capacity", -1], ["beer", "storage_capacity", 10001], ["beer", "storage_capacity", 0.5],
		["malt", "decay_fraction_per_minute", 1.0], ["malt", "decay_fraction_per_minute", -0.1],
		["beer", "decay_fraction_per_minute", 1.0], ["beer", "decay_fraction_per_minute", 2],
	]
	for case: Array in cases:
		var documents: Dictionary[String, Dictionary] = _documents()
		documents["economy/market.json"][case[0]][case[1]] = case[2]
		var loaded: DataLoadResult = DataLoader.new().load_documents(documents)
		assert_false(loaded.is_ok(), "market.%s.%s = %s must be rejected" % [case[0], case[1], str(case[2])])


func test_the_loader_accepts_the_range_boundaries() -> void:
	var documents: Dictionary[String, Dictionary] = _documents()
	documents["economy/market.json"]["malt"]["storage_capacity"] = 0
	documents["economy/market.json"]["beer"]["storage_capacity"] = 10000
	documents["economy/market.json"]["beer"]["decay_fraction_per_minute"] = 0.99
	var loaded: DataLoadResult = DataLoader.new().load_documents(documents)
	assert_true(loaded.is_ok(), str(loaded.errors))


func test_role_modifiers_that_leave_the_range_are_rejected() -> void:
	var cases: Array[Array] = [
		[&"market.malt.storage_capacity", -1.0], [&"market.beer.storage_capacity", 10001.0],
		[&"market.beer.storage_capacity", 1.5], [&"market.malt.decay_fraction_per_minute", 1.0],
		[&"market.beer.decay_fraction_per_minute", -0.01],
	]
	for case: Array in cases:
		var role: RoleDef = RoleDef.new()
		role.modifiers.append(Modifier.new(case[0], &"set", case[1]))
		assert_null(Params.new(_catalog, role).get_value(case[0]), str(case[0]))
		assert_push_error("Params: invalid range for '%s'" % case[0])


func test_malthouse_and_brewery_are_buildable_on_land_but_not_on_the_river() -> void:
	for id: StringName in [&"malthouse", &"brewery"]:
		assert_eq(_context.building_unavailable_reason(id), &"")
		assert_eq(_context.terrain_placement_reason(id, Vector2i(2, 2)), &"")
		assert_eq(_context.terrain_placement_reason(id, Vector2i(2, 7)), &"requires_land")
