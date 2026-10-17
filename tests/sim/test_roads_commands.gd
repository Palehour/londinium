extends GutTest

# Issue #67 (D-070, D-080): the player builds orthogonal streets for roads.cost; demolishing one refunds like a
# building without jobs (D-029); the historic streets of the map cannot be demolished.

const LAND: Vector2i = Vector2i(3, RoadTestMap.LAND_ROW)

var _catalog: DataCatalog
var _context: EconomyContext
var _initial: EconomyState
var _params: Params
var _cost: int


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = RoadTestMap.street(_catalog, 8)
	_params = SimTestParams.isolated_params(_catalog)
	_cost = int(_params.get_value(&"roads.cost"))
	_initial = EconomyState.new()
	_initial.money = 1000
	_initial.stocks.assign({&"wheat": 0, &"flour": 0, &"bread": 0})


func _sim() -> Simulation:
	return Simulation.new(_params, _initial, 7, _context)


func _ticks(sim: Simulation, count: int) -> void:
	for index: int in count:
		sim.tick()


func _money(sim: Simulation) -> int:
	return int(sim.snapshot()["economy"]["money"])


func _build_road(sim: Simulation, cell: Vector2i) -> BuildRoadCommand:
	var command: BuildRoadCommand = BuildRoadCommand.new(_context, cell)
	sim.apply_command(command)
	sim.tick()
	return command


func _demolish(sim: Simulation, cell: Vector2i) -> DemolishCommand:
	var command: DemolishCommand = DemolishCommand.new(cell)
	sim.apply_command(command)
	sim.tick()
	return command


func test_build_road_costs_roads_cost() -> void:
	var sim: Simulation = _sim()
	assert_true(_build_road(sim, LAND).accepted)
	assert_eq(_money(sim), _initial.money - _cost)
	assert_eq(sim.snapshot()["distance"]["player_roads"], [[LAND.x, LAND.y]])


func test_streets_go_only_on_free_land() -> void:
	var sim: Simulation = _sim()
	sim.apply_command(BuildCommand.new(_context, &"mill", Vector2i(5, RoadTestMap.LAND_ROW)))
	assert_eq(_build_road(sim, Vector2i(5, RoadTestMap.LAND_ROW)).reason, &"occupied_cell")
	assert_eq(_build_road(sim, Vector2i(2, RoadTestMap.ROAD_ROW)).reason, &"road_cell")
	assert_eq(_build_road(sim, Vector2i(2, RoadTestMap.RIVER_ROW)).reason, &"requires_land")
	assert_eq(_build_road(sim, Vector2i(9, 0)).reason, &"outside_map")
	assert_true(_build_road(sim, LAND).accepted)
	assert_eq(_build_road(sim, LAND).reason, &"road_cell")


# The standing buildings of the map block new building until the tracing of #152 (D-075): streets too.
func test_no_street_on_a_standing_building() -> void:
	_context.map.existing_cells.append(LAND)
	var sim: Simulation = _sim()
	assert_eq(_build_road(sim, LAND).reason, &"existing_building")
	assert_eq(_money(sim), _initial.money)


func test_build_road_needs_the_money() -> void:
	_initial.money = _cost - 1
	assert_eq(_build_road(_sim(), LAND).reason, &"insufficient_money")


func test_demolish_road_in_grace_refunds_full() -> void:
	var sim: Simulation = _sim()
	_build_road(sim, LAND)
	_ticks(sim, int(_params.get_value(&"demolish.refund_grace_seconds")) - 1)
	assert_true(_demolish(sim, LAND).accepted)
	assert_eq(_money(sim), _initial.money)
	assert_eq(sim.snapshot()["distance"]["player_roads"], [])


func test_after_grace_refunds_half() -> void:
	var sim: Simulation = _sim()
	_build_road(sim, LAND)
	_ticks(sim, int(_params.get_value(&"demolish.refund_grace_seconds")) + 1)
	assert_true(_demolish(sim, LAND).accepted)
	var refund: int = roundi(_cost * float(_params.get_value(&"demolish.no_jobs_refund_ratio")))
	assert_eq(_money(sim), _initial.money - _cost + refund)


func test_historic_road_cannot_be_demolished() -> void:
	var sim: Simulation = _sim()
	var command: DemolishCommand = _demolish(sim, Vector2i(2, RoadTestMap.ROAD_ROW))
	assert_false(command.accepted)
	assert_eq(command.reason, &"historic_road")
	assert_eq(_money(sim), _initial.money)


# D-063: streets are neither buildings that make the city's administration dearer nor copies that escalate.
func test_streets_do_not_count_as_buildings() -> void:
	var sim: Simulation = _sim()
	_build_road(sim, LAND)
	assert_eq(sim.snapshot()["economy"]["buildings"], [])
	assert_eq(sim.tick_flows()["buildings"], {})
