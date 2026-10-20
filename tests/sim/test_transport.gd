extends GutTest

# Issue #67 (D-070, D-080): every building pays, for each of its inputs, the units it takes times the street steps
# to its nearest supplier times k, added to the upkeep in whole pence with the fraction carried over.
# Since issue #186 (D-086) k is per metre and a step is a street piece of 50 m: k of a step is k x 50 m.

const WIDTH: int = 24
const WHEAT: int = 200

var _catalog: DataCatalog
var _context: EconomyContext
var _initial: EconomyState
var _params: Params


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = RoadTestMap.street(_catalog, WIDTH)
	# Stored wheat that spoils would leave the store without travelling: off, so what leaves is what the mill takes.
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"market.wheat.decay_fraction_per_minute", &"set", 0))
	_params = SimTestParams.isolated_params(_catalog, role)
	_initial = EconomyState.new()
	_initial.money = 100000
	_initial.population = 12
	# Nothing is bought, so the only money that moves is the transport.
	_initial.wheat_purchases_enabled = false
	_initial.stocks.assign({&"wheat": WHEAT, &"flour": 0, &"bread": 0, &"barley": 0})


func _sim(buildings: Array[Array]) -> Simulation:
	var sim: Simulation = Simulation.new(_params, _initial, 7, _context)
	for entry: Array in buildings:
		sim.apply_command(BuildCommand.new(_context, entry[0], entry[1]))
	sim.tick()
	return sim


func _ticks(sim: Simulation, count: int) -> void:
	for index: int in count:
		sim.tick()


# Per unit and step: per metre times the metres of one street piece.
func _k() -> float:
	return float(_params.get_value(&"transport.cost_per_unit_per_m")) * RoadSystem.metres(_params, _context, 1)


func _wheat_taken(sim: Simulation) -> int:
	return WHEAT - int(sim.snapshot()["economy"]["stocks"][&"wheat"])


func _spent(sim: Simulation) -> int:
	return _initial.money - int(sim.snapshot()["economy"]["money"]) - _construction(sim)


func _construction(sim: Simulation) -> int:
	var paid: int = 0
	for building: Dictionary in sim.snapshot()["economy"]["buildings"]:
		paid += int(building["paid"])
	return paid


func test_mill_pays_leg_from_nearest_wharf() -> void:
	var sim: Simulation = _sim([[&"wharf", RoadTestMap.river(1)], [&"wharf", RoadTestMap.river(6)],
		[&"mill", RoadTestMap.land(8)]] as Array[Array])
	var leg: Dictionary = RoadTestMap.entry(sim.snapshot(), "legs", RoadTestMap.land(8), &"wheat")
	assert_eq(leg["supplier_cell"], RoadTestMap.at(Vector2i(5, RoadTestMap.RIVER_ROW)), "the nearer wharf supplies the mill")
	assert_eq(leg["steps"], 3)
	_ticks(sim, 120)
	assert_gt(_wheat_taken(sim), 0)
	assert_eq(_spent(sim), ProductionSystem.whole_units(_wheat_taken(sim) * 3 * _k()))


# Field to mill (D-080): no map in data/ has cultivable cells (D-010), so this test map gets one.
func test_mill_pays_leg_from_the_wheat_field() -> void:
	_context.map.cultivable_cells.append_array(EconomyContext.cells_of(Rect2i(RoadTestMap.land(2), _context.buildings[&"wheat_field"].footprint)))
	var sim: Simulation = _sim([[&"wheat_field", RoadTestMap.land(2)], [&"wharf", RoadTestMap.river(12)],
		[&"mill", RoadTestMap.land(6)]] as Array[Array])
	var leg: Dictionary = RoadTestMap.entry(sim.snapshot(), "legs", RoadTestMap.land(6), &"wheat")
	assert_eq(leg["supplier_cell"], RoadTestMap.at(Vector2i(1, RoadTestMap.LAND_ROW)), "the field is nearer than the wharf")
	assert_eq(leg["supplier_id"], &"wheat_field")
	assert_eq(leg["steps"], 5)
	_ticks(sim, 120)
	assert_gt(_wheat_taken(sim), 0)
	assert_eq(_spent(sim), ProductionSystem.whole_units(_wheat_taken(sim) * 5 * _k()))


func test_malthouse_pays_leg_from_wharf() -> void:
	var sim: Simulation = _sim([[&"wharf", RoadTestMap.river(1)], [&"malthouse", RoadTestMap.land(4)]] as Array[Array])
	var leg: Dictionary = RoadTestMap.entry(sim.snapshot(), "legs", RoadTestMap.land(4), &"barley")
	assert_eq(leg["supplier_cell"], RoadTestMap.at(Vector2i(0, RoadTestMap.RIVER_ROW)))
	assert_eq(leg["steps"], 4)


func test_bakery_pays_leg_from_wharf_with_imported_flour() -> void:
	_initial.flour_imports_enabled = true
	var sim: Simulation = _sim([[&"wharf", RoadTestMap.river(1)], [&"bakery", RoadTestMap.land(5)]] as Array[Array])
	var leg: Dictionary = RoadTestMap.entry(sim.snapshot(), "legs", RoadTestMap.land(5), &"flour")
	assert_eq(leg["supplier_cell"], RoadTestMap.at(Vector2i(0, RoadTestMap.RIVER_ROW)))
	assert_eq(leg["steps"], 5)


# Without imported flour the wharf brings no flour, so a bakery with no mill has no leg yet (and no "no route").
func test_wharf_supplies_flour_only_while_it_is_imported() -> void:
	var sim: Simulation = _sim([[&"wharf", RoadTestMap.river(1)], [&"bakery", RoadTestMap.land(5)]] as Array[Array])
	assert_eq(RoadTestMap.entry(sim.snapshot(), "legs", RoadTestMap.land(5), &"flour"), {})
	assert_eq(RoadTestMap.entry(sim.snapshot(), "blocked", RoadTestMap.land(5)), {})


func test_transport_cost_accumulates_fraction() -> void:
	var sim: Simulation = _sim([[&"wharf", RoadTestMap.river(1)], [&"mill", RoadTestMap.land(1)]] as Array[Array])
	assert_lt(_wheat_taken(sim) * _k(), 1.0, "one step of one unit costs less than a penny")
	assert_eq(_spent(sim), 0)
	_ticks(sim, 65)
	assert_gt(_wheat_taken(sim) * _k(), 1.0)
	assert_eq(_spent(sim), ProductionSystem.whole_units(_wheat_taken(sim) * _k()))


func test_leg_shows_its_cost_per_minute() -> void:
	var sim: Simulation = _sim([[&"wharf", RoadTestMap.river(1)], [&"mill", RoadTestMap.land(4)]] as Array[Array])
	var per_minute: float = float(_params.get_value(&"building.mill.recipe.inputs.wheat")) * 4 * _k()
	var leg: Dictionary = RoadTestMap.entry(sim.snapshot(), "legs", RoadTestMap.land(4), &"wheat")
	assert_almost_eq(float(leg["cost_per_minute"]), per_minute, 1e-9)


func test_nine_steps_no_warning_ten_steps_warns() -> void:
	var threshold: int = int(_params.get_value(&"transport.expensive_m")) / RoadSystem.metres(_params, _context, 1)
	var short: Simulation = _sim([[&"wharf", RoadTestMap.river(1)], [&"mill", RoadTestMap.land(threshold - 1)]] as Array[Array])
	var long: Simulation = _sim([[&"wharf", RoadTestMap.river(1)], [&"mill", RoadTestMap.land(threshold)]] as Array[Array])
	assert_false(RoadTestMap.entry(short.snapshot(), "legs", RoadTestMap.land(threshold - 1), &"wheat")["expensive"])
	assert_true(RoadTestMap.entry(long.snapshot(), "legs", RoadTestMap.land(threshold), &"wheat")["expensive"])
