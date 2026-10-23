extends GutTest

# Issue #67 (D-070, D-080): the player builds orthogonal streets for roads.cost; demolishing one refunds like a
# building without jobs (D-029); the historic streets of the map cannot be demolished.
# Since issue #186 (D-086) a street is a piece of 2x2 cells for roads.cost, refunded by the piece, and the map is in
# blocks of 2x2 (RoadTestMap.blocks).

const LAND: Vector2i = Vector2i(3, RoadTestMap.LAND_ROW) * RoadTestMap.BLOCK

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
	sim.apply_command(BuildCommand.new(_context, &"mill", RoadTestMap.cell(Vector2i(5, RoadTestMap.LAND_ROW))))
	assert_eq(_build_road(sim, RoadTestMap.cell(Vector2i(5, RoadTestMap.LAND_ROW))).reason, &"occupied_cell")
	assert_eq(_build_road(sim, RoadTestMap.cell(Vector2i(2, RoadTestMap.ROAD_ROW))).reason, &"road_cell")
	assert_eq(_build_road(sim, RoadTestMap.cell(Vector2i(2, RoadTestMap.RIVER_ROW))).reason, &"requires_land")
	assert_eq(_build_road(sim, RoadTestMap.cell(Vector2i(8, 0))).reason, &"outside_map")
	assert_true(_build_road(sim, LAND).accepted)
	assert_eq(_build_road(sim, LAND).reason, &"road_cell")


# The standing buildings of the map block new building (D-075): streets too.
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
	var command: DemolishCommand = _demolish(sim, RoadTestMap.cell(Vector2i(2, RoadTestMap.ROAD_ROW)))
	assert_false(command.accepted)
	assert_eq(command.reason, &"historic_road")
	assert_eq(_money(sim), _initial.money)


# D-063: streets are neither buildings that make the city's administration dearer nor copies that escalate.
func test_streets_do_not_count_as_buildings() -> void:
	var sim: Simulation = _sim()
	_build_road(sim, LAND)
	assert_eq(sim.snapshot()["economy"]["buildings"], [])
	assert_eq(sim.tick_flows()["buildings"], {})


# Issue #186 (D-086): a street is one piece of roads.json footprint, 2x2. It costs roads.cost once, takes the four cells
# (no other street, building or water on any of them) and any of its cells demolishes it with one refund.
func test_a_street_is_a_two_by_two_piece_for_one_cost() -> void:
	assert_eq(_context.road_footprint, Vector2i(2, 2))
	var sim: Simulation = _sim()
	assert_true(_build_road(sim, LAND).accepted)
	assert_eq(_money(sim), _initial.money - _cost, "One piece, one roads.cost")
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(1, 1), Vector2i(-1, 0), Vector2i(-1, 1)]:
		assert_eq(_build_road(sim, LAND + offset).reason, &"road_cell", "A piece over %s" % (LAND + offset))
	assert_eq(_build_road(sim, LAND + Vector2i(2, 1)).reason, &"road_cell", "Its lower half reaches the street")
	assert_true(_build_road(sim, LAND + Vector2i(2, 0)).accepted, "Side by side is not overlapping")
	assert_eq(sim.snapshot()["distance"]["player_roads"], [[LAND.x, LAND.y], [LAND.x + 2, LAND.y]])


func test_any_cell_of_a_piece_demolishes_it_for_one_refund() -> void:
	var sim: Simulation = _sim()
	_build_road(sim, LAND)
	assert_true(_demolish(sim, LAND + Vector2i(1, 1)).accepted)
	assert_eq(_money(sim), _initial.money, "The whole piece back within the correction window")
	assert_eq(sim.snapshot()["distance"]["player_roads"], [])


func test_a_piece_needs_all_of_its_cells_free() -> void:
	var sim: Simulation = _sim()
	sim.apply_command(BuildCommand.new(_context, &"mill", LAND + Vector2i(2, 0)))
	assert_eq(_build_road(sim, LAND + Vector2i(1, 0)).reason, &"occupied_cell")
	assert_eq(_build_road(sim, Vector2i(_context.map.width - 1, RoadTestMap.LAND_ROW)).reason, &"outside_map")
	assert_eq(_money(sim), _initial.money - BuildingCosts.construction_cost(_params, EconomyState.new(),
		_context.buildings[&"mill"]))


# D-094: the Thames stairs are fixed ground like the river. No street goes over any cell of the piece, nothing is
# charged and the stairs stay; free land beside them still takes a street.
func test_no_street_on_the_stairs() -> void:
	var stairs: Vector2i = LAND + Vector2i(1, 1)
	_context.map.stairs_cells.append(stairs)
	var sim: Simulation = _sim()
	assert_eq(_build_road(sim, LAND).reason, &"requires_land")
	assert_eq(_money(sim), _initial.money)
	assert_eq(sim.snapshot()["distance"]["player_roads"], [])
	assert_true(stairs in _context.map.stairs_cells)
	assert_true(_build_road(sim, LAND + Vector2i(2, 0)).accepted)
	assert_eq(_money(sim), _initial.money - _cost)
