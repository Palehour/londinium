extends GutTest

# Issue #67 (D-034, D-058, D-080): a building works only beside a street of the network, which starts at the
# historic streets; the player's streets join it orthogonally and diagonals exist only as edges the map lists.

var _catalog: DataCatalog
var _initial: EconomyState


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_initial = EconomyState.new()
	_initial.money = 100000
	_initial.population = 12
	_initial.stocks.assign({&"wheat": 50, &"flour": 0, &"bread": 0, &"malt": 50})


func _sim(context: EconomyContext) -> Simulation:
	return Simulation.new(SimTestParams.isolated_params(_catalog), _initial, 7, context)


func _build(sim: Simulation, context: EconomyContext, id: StringName, cell: Vector2i) -> BuildCommand:
	var command: BuildCommand = BuildCommand.new(context, id, cell)
	sim.apply_command(command)
	return command


func _diagnostic(sim: Simulation, cell: Vector2i) -> Dictionary:
	for building: Dictionary in sim.snapshot()["diagnostics"]["buildings"]:
		if building["cell"] == [cell.x, cell.y]:
			return building
	return {}


func test_building_next_to_road_is_connected() -> void:
	var context: EconomyContext = RoadTestMap.street(_catalog, 6)
	var sim: Simulation = _sim(context)
	_build(sim, context, &"mill", RoadTestMap.land(2))
	sim.tick()
	assert_gt(_diagnostic(sim, RoadTestMap.land(2))["workers"], 0)
	assert_eq(_diagnostic(sim, RoadTestMap.land(2))["reason"], &"ok")


func test_isolated_building_has_no_road_access() -> void:
	var roads: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1)]
	var context: EconomyContext = RoadTestMap.custom(_catalog, Vector2i(6, 5), roads)
	var sim: Simulation = _sim(context)
	_build(sim, context, &"mill", Vector2i(4, 2))
	sim.tick()
	var mill: Dictionary = _diagnostic(sim, Vector2i(4, 2))
	assert_eq(mill["workers"], 0, "a building without a street gets no workers")
	assert_eq(mill["reason"], &"no_road_access")
	assert_eq(RoadTestMap.entry(sim.snapshot(), "blocked", Vector2i(4, 2))["reason"], &"no_road_access")


# Diagonal neighbours of a street are not access: only the four sides count.
func test_a_street_on_the_corner_is_not_access() -> void:
	var roads: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1)]
	var context: EconomyContext = RoadTestMap.custom(_catalog, Vector2i(6, 5), roads)
	var sim: Simulation = _sim(context)
	_build(sim, context, &"mill", Vector2i(2, 2))
	sim.tick()
	assert_eq(_diagnostic(sim, Vector2i(2, 2))["reason"], &"no_road_access")


func test_wharf_needs_river_and_road() -> void:
	var roads: Array[Vector2i] = [Vector2i(0, 3), Vector2i(1, 3)]
	var context: EconomyContext = RoadTestMap.custom(_catalog, Vector2i(6, 5), roads)
	var sim: Simulation = _sim(context)
	_build(sim, context, &"wharf", Vector2i(1, 4))
	_build(sim, context, &"wharf", Vector2i(4, 4))
	sim.tick()
	assert_eq(_diagnostic(sim, Vector2i(1, 4))["reason"], &"ok")
	assert_gt(_diagnostic(sim, Vector2i(1, 4))["workers"], 0)
	assert_eq(_diagnostic(sim, Vector2i(4, 4))["reason"], &"no_road_access")


# The network starts at the historic streets (#60): a player street that touches none of them connects nothing.
func test_player_street_away_from_the_network_does_not_connect() -> void:
	var roads: Array[Vector2i] = [Vector2i(0, 1)]
	var context: EconomyContext = RoadTestMap.custom(_catalog, Vector2i(6, 5), roads)
	var sim: Simulation = _sim(context)
	sim.apply_command(BuildRoadCommand.new(context, Vector2i(4, 1)))
	_build(sim, context, &"mill", Vector2i(4, 0))
	sim.tick()
	assert_eq(_diagnostic(sim, Vector2i(4, 0))["reason"], &"no_road_access")
	for x: int in [1, 2, 3]:
		sim.apply_command(BuildRoadCommand.new(context, Vector2i(x, 1)))
	sim.tick()
	assert_eq(_diagnostic(sim, Vector2i(4, 0))["reason"], &"ok")


func test_no_route_stops_building() -> void:
	var roads: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(5, 1), Vector2i(6, 1)]
	var context: EconomyContext = RoadTestMap.custom(_catalog, Vector2i(8, 4), roads)
	var sim: Simulation = _sim(context)
	_build(sim, context, &"malthouse", Vector2i(1, 0))
	_build(sim, context, &"brewery", Vector2i(6, 0))
	sim.tick()
	var brewery: Dictionary = _diagnostic(sim, Vector2i(6, 0))
	assert_eq(brewery["reason"], &"no_route")
	assert_eq(brewery["workers"], 0)
	for index: int in 60:
		sim.tick()
	assert_eq(int(sim.snapshot()["economy"]["stocks"].get(&"beer", 0)), 0, "a brewery without a route brews nothing")
	for x: int in [3, 4]:
		sim.apply_command(BuildRoadCommand.new(context, Vector2i(x, 1)))
	sim.tick()
	assert_eq(_diagnostic(sim, Vector2i(6, 0))["reason"], &"ok")
	sim.apply_command(DemolishCommand.new(Vector2i(3, 1)))
	sim.tick()
	assert_eq(_diagnostic(sim, Vector2i(6, 0))["reason"], &"no_route", "cutting the street breaks the chain")


func test_empty_diagonals_do_not_connect() -> void:
	var sim: Simulation = _diagonal_sim([] as Array[Vector4i])
	assert_eq(_diagnostic(sim, Vector2i(3, 3))["reason"], &"no_route")


func test_loaded_diagonal_edge_connects() -> void:
	var sim: Simulation = _diagonal_sim([Vector4i(1, 1, 2, 2)] as Array[Vector4i])
	assert_eq(_diagnostic(sim, Vector2i(3, 3))["reason"], &"ok")
	var leg: Dictionary = RoadTestMap.entry(sim.snapshot(), "legs", Vector2i(3, 3), &"malt")
	assert_eq(leg["steps"], 4, "(0,1) → (1,1) → (2,2) → (3,2)")


# Two historic streets that only meet corner to corner: the malthouse on one, the brewery on the other.
func _diagonal_sim(diagonals: Array[Vector4i]) -> Simulation:
	var roads: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 2)]
	var context: EconomyContext = RoadTestMap.custom(_catalog, Vector2i(6, 5), roads, diagonals)
	var sim: Simulation = _sim(context)
	_build(sim, context, &"malthouse", Vector2i(0, 0))
	_build(sim, context, &"brewery", Vector2i(3, 3))
	sim.tick()
	return sim


func test_buildings_are_not_built_on_a_street() -> void:
	var context: EconomyContext = RoadTestMap.street(_catalog, 6)
	var sim: Simulation = _sim(context)
	var command: BuildCommand = _build(sim, context, &"mill", Vector2i(2, RoadTestMap.ROAD_ROW))
	sim.tick()
	assert_false(command.accepted)
	assert_eq(command.reason, &"road_cell")


# D-070: on a map without streets (the 8x8 of the harness) nothing changes: every building works where it stands.
func test_disabled_roads_change_nothing() -> void:
	var context: EconomyContext = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	assert_false(context.map.roads_enabled)
	var sim: Simulation = _sim(context)
	_build(sim, context, &"mill", Vector2i(3, 3))
	sim.tick()
	assert_eq(_diagnostic(sim, Vector2i(3, 3))["reason"], &"ok")
	assert_false(sim.snapshot()["distance"]["enabled"])
	assert_eq(sim.snapshot()["distance"]["legs"], [])
	var road: BuildRoadCommand = BuildRoadCommand.new(context, Vector2i(2, 2))
	sim.apply_command(road)
	sim.tick()
	assert_eq(road.reason, &"roads_disabled")
