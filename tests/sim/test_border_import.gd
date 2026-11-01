extends GutTest

# Issue #306 (D-164). A map with no river imports tea and flour from the scenario's entry cells and pays
# D-080 transport from the nearest one. A map with a river ignores those cells and keeps the wharf path.


const BAKERY: Vector2i = Vector2i(2, 2)
const HOUSE: Vector2i = Vector2i(14, 2)
const CUT_OFF: Vector2i = Vector2i(0, 4)
const NEAR_STEPS: int = 1
const FAR_STEPS: int = 7
const TEA_STOCK: int = 20

var _catalog: DataCatalog
var _params: Params
var _scenario: Dictionary


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_params = SimTestParams.isolated_params(_catalog)
	_scenario = _catalog.scenarios[&"border_import"]


func _border_context() -> EconomyContext:
	var context: EconomyContext = EconomyContext.new(_catalog, _catalog.maps[&"border_import"])
	context.apply_border(_scenario)
	return context


func _state() -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.money = 100000
	state.population = 12
	state.wheat_purchases_enabled = false
	state.stocks[&"bread"] = 100
	return state


func _sim(context: EconomyContext, state: EconomyState, buildings: Array[Array]) -> Simulation:
	var sim: Simulation = Simulation.new(_params, state, 7, context)
	for entry: Array in buildings:
		sim.apply_command(BuildCommand.new(context, entry[0], entry[1]))
	sim.tick()
	return sim


func _ticks(sim: Simulation, count: int) -> void:
	for index: int in count:
		sim.tick()


func _k(context: EconomyContext) -> float:
	return float(_params.get_value(&"transport.cost_per_unit_per_m")) * RoadSystem.metres(_params, context, 1)


func _construction(sim: Simulation) -> int:
	var paid: int = 0
	for building: Dictionary in sim.snapshot()["economy"]["buildings"]:
		paid += int(building["paid"])
	return paid


func _leg(sim: Simulation, cell: Vector2i, good: StringName) -> Dictionary:
	return RoadTestMap.entry(sim.snapshot(), "legs", cell, good)


func _house(sim: Simulation, cell: Vector2i) -> Dictionary:
	for house: Dictionary in sim.snapshot()["distance"]["houses"]:
		if house["cell"] == [cell.x, cell.y]:
			return house
	return {}


func _near_entry() -> Vector2i:
	var entries: Array = _scenario["import_entries"]
	return entries[1]


func test_entry_cells_come_from_scenario_data() -> void:
	var file: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/border_import.json"))
	assert_eq(_scenario["import_entries"], [Vector2i(0, 0), Vector2i(2, 0)])
	assert_eq(file["import_entries"], [[0.0, 0.0], [2.0, 0.0]])
	assert_eq(_scenario["import_goods"], [&"tea", &"flour"])
	assert_true(_catalog.maps[&"border_import"].river_cells.is_empty())
	var state: EconomyState = _state()
	state.flour_imports_enabled = true
	var sim: Simulation = _sim(_border_context(), state, [[&"bakery", BAKERY]] as Array[Array])
	var leg: Dictionary = _leg(sim, BAKERY, &"flour")
	assert_eq(leg["supplier_cell"], [_near_entry().x, _near_entry().y])
	assert_eq(leg["supplier_id"], EconomyContext.BORDER_SUPPLIER)
	assert_eq(leg["steps"], NEAR_STEPS)
	var stripped: Dictionary = _scenario.duplicate(true)
	stripped["import_entries"] = []
	var bare: EconomyContext = EconomyContext.new(_catalog, _catalog.maps[&"border_import"])
	bare.apply_border(stripped)
	var without: Simulation = _sim(bare, state, [[&"bakery", BAKERY]] as Array[Array])
	assert_eq(_leg(without, BAKERY, &"flour"), {})
	assert_eq(int(without.snapshot()["economy"]["stocks"].get(&"flour", 0)), 0)


func test_border_flour_pays_d080_and_leaves_no_debt() -> void:
	var state: EconomyState = _state()
	state.flour_imports_enabled = true
	var context: EconomyContext = _border_context()
	var sim: Simulation = _sim(context, state, [[&"bakery", BAKERY]] as Array[Array])
	_ticks(sim, 120)
	var economy: Dictionary = sim.snapshot()["economy"]
	var price: int = int(_params.get_value(&"market.imported_flour.price_per_lot"))
	assert_eq(float(economy["flour_unloading_debt"]), 0.0)
	var spent: int = state.money - int(economy["money"]) - _construction(sim)
	assert_gte(spent, price, "at least one lot of D-026 was paid, with no unloading debt")
	assert_eq(sim.snapshot()["imports"]["flour"]["reason"], &"ok")


func test_border_flour_transport_matches_the_entry_steps() -> void:
	var state: EconomyState = _state()
	state.flour_imports_enabled = true
	state.stocks[&"flour"] = 200
	var context: EconomyContext = _border_context()
	var sim: Simulation = _sim(context, state, [[&"bakery", BAKERY]] as Array[Array])
	_ticks(sim, 180)
	var economy: Dictionary = sim.snapshot()["economy"]
	var taken: int = 200 - int(economy["stocks"][&"flour"])
	assert_gt(taken, 0)
	assert_eq(state.money - int(economy["money"]) - _construction(sim),
		ProductionSystem.whole_units(float(taken) * NEAR_STEPS * _k(context)))
	assert_eq(float(economy["flour_unloading_debt"]), 0.0)


func test_border_tea_reaches_a_far_house_and_pays_from_the_entry() -> void:
	var state: EconomyState = _state()
	state.stocks[&"tea"] = TEA_STOCK
	var context: EconomyContext = _border_context()
	var sim: Simulation = _sim(context, state, [[&"housing", HOUSE], [&"housing", CUT_OFF]] as Array[Array])
	var leg: Dictionary = _leg(sim, HOUSE, &"tea")
	assert_eq(leg["supplier_cell"], [_near_entry().x, _near_entry().y])
	assert_eq(leg["steps"], FAR_STEPS)
	assert_gt(int(leg["metres"]), int(_params.get_value(&"building.wharf.service_radius_m")))
	var served: Dictionary = _house(sim, HOUSE)
	assert_true(served["served"][&"tea"])
	var cut: Dictionary = _house(sim, CUT_OFF)
	assert_false(cut["connected"])
	assert_false(cut["served"][&"tea"])
	assert_eq(_leg(sim, CUT_OFF, &"tea"), {})
	_ticks(sim, 180)
	var economy: Dictionary = sim.snapshot()["economy"]
	var left: float = float(economy["stocks"][&"tea"]) + float(economy["tea_fraction"])
	var consumed: float = float(TEA_STOCK) - left
	assert_gt(consumed, 1.0)
	assert_eq(state.money - int(economy["money"]) - _construction(sim),
		ProductionSystem.whole_units(consumed * FAR_STEPS * _k(context)))


func test_a_river_map_ignores_entry_cells() -> void:
	var context: EconomyContext = RoadTestMap.street(_catalog, 24)
	context.apply_border(_scenario)
	assert_false(context.border_import_active())
	var state: EconomyState = _state()
	state.flour_imports_enabled = true
	var sim: Simulation = _sim(context, state, [[&"wharf", RoadTestMap.river(1)],
		[&"bakery", RoadTestMap.land(5)]] as Array[Array])
	var leg: Dictionary = _leg(sim, RoadTestMap.land(5), &"flour")
	assert_eq(leg["supplier_id"], &"wharf")
	assert_ne(leg["supplier_id"], EconomyContext.BORDER_SUPPLIER)
	_ticks(sim, 120)
	assert_gt(float(sim.snapshot()["economy"]["flour_unloading_debt"]), 0.0)


func test_save_load_keeps_border_import_and_old_saves_load() -> void:
	var state: EconomyState = _state()
	state.flour_imports_enabled = true
	var context: EconomyContext = _border_context()
	var sim: Simulation = _sim(context, state, [[&"bakery", BAKERY]] as Array[Array])
	_ticks(sim, 40)
	var saved: Dictionary = sim.to_save()
	assert_false(saved["economy"].has("import_entries"))
	var loaded: Simulation = Simulation.from_save(_params, _border_context(), [], saved)
	_ticks(sim, 40)
	_ticks(loaded, 40)
	assert_eq(loaded.snapshot()["economy"]["money"], sim.snapshot()["economy"]["money"])
	assert_eq(loaded.snapshot()["economy"]["stocks"], sim.snapshot()["economy"]["stocks"])
	assert_eq(float(loaded.snapshot()["economy"]["flour_unloading_debt"]), 0.0)
	var old: Dictionary = EconomyState.new().to_dict()
	old.erase("flour_unloading_debt")
	var restored: EconomyState = EconomyState.from_dict(old)
	assert_eq(restored.flour_unloading_debt, 0.0)
	var river: Simulation = Simulation.from_save(_params, RoadTestMap.street(_catalog, 8), [],
		Simulation.new(_params, EconomyState.new(), 3, RoadTestMap.street(_catalog, 8)).to_save())
	river.tick()
	assert_eq(float(river.snapshot()["economy"]["flour_unloading_debt"]), 0.0)
