extends GutTest

# Issue #184 (D-086, task 1 of #183): a building covers footprint w x h cells from its cell, the north-west corner.
# Placing, occupying, demolishing and street access (D-079) go by the whole footprint; a 1x1 building plays as it
# always did. The bakery is made 2x2 here because every building in the data is still 1x1.

const BIG: StringName = &"bakery"
const SIZE: Vector2i = Vector2i(2, 2)
const MAP_SIZE: Vector2i = Vector2i(8, 6)
# The big bakery stands here in most tests: it covers (2,1), (3,1), (2,2) and (3,2).
const ORIGIN: Vector2i = Vector2i(2, 1)
const STREET_ROW: int = 3
const STRIP: StringName = &"riverside_strip"

var _catalog: DataCatalog
var _initial: EconomyState


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_catalog.buildings[BIG].footprint = SIZE
	_initial = EconomyState.new()
	_initial.money = 100000
	_initial.stocks.assign({&"wheat": 0, &"flour": 0, &"bread": 0})


# Land on rows 0 to 4, the river on row 5 and the given historic streets.
func _context(roads: Array[Vector2i]) -> EconomyContext:
	return RoadTestMap.custom(_catalog, MAP_SIZE, roads)


func _street_row() -> Array[Vector2i]:
	var roads: Array[Vector2i] = []
	for x: int in range(MAP_SIZE.x):
		roads.append(Vector2i(x, STREET_ROW))
	return roads


func _sim(context: EconomyContext) -> Simulation:
	return Simulation.new(SimTestParams.isolated_params(_catalog), _initial, 7, context)


func _run(sim: Simulation, command: SimulationCommand) -> SimulationCommand:
	sim.apply_command(command)
	sim.tick()
	return command


func _build(sim: Simulation, context: EconomyContext, id: StringName, cell: Vector2i) -> BuildCommand:
	return _run(sim, BuildCommand.new(context, id, cell)) as BuildCommand


func _buildings(sim: Simulation) -> Array:
	return sim.snapshot()["economy"]["buildings"]


func test_footprints_cannot_overlap() -> void:
	var context: EconomyContext = _context(_street_row())
	var sim: Simulation = _sim(context)
	assert_true(_build(sim, context, BIG, ORIGIN).accepted)
	for cell: Vector2i in [Vector2i(2, 1), Vector2i(3, 1), Vector2i(2, 2), Vector2i(3, 2)]:
		assert_eq(_build(sim, context, &"mill", cell).reason, &"occupied_cell", "mill on %s" % cell)
	# A second 2x2 whose corner falls on the first one's corner overlaps it too.
	assert_eq(_build(sim, context, BIG, Vector2i(1, 0)).reason, &"occupied_cell")
	assert_eq(_build(sim, context, BIG, Vector2i(3, 2)).reason, &"occupied_cell")
	assert_true(_build(sim, context, BIG, Vector2i(4, 1)).accepted, "side by side is not overlapping")
	assert_eq(_buildings(sim).size(), 2)


func test_footprint_must_fit_the_map() -> void:
	var context: EconomyContext = _context(_street_row())
	var sim: Simulation = _sim(context)
	assert_eq(_build(sim, context, BIG, Vector2i(MAP_SIZE.x - 1, 0)).reason, &"outside_map")
	assert_true(_build(sim, context, BIG, Vector2i(MAP_SIZE.x - 2, 0)).accepted)


func test_every_cell_of_a_footprint_checks_terrain() -> void:
	var context: EconomyContext = _context(_street_row())
	var sim: Simulation = _sim(context)
	# Row 4 is land, row 5 the river.
	assert_eq(_build(sim, context, BIG, Vector2i(0, 4)).reason, &"requires_land")
	assert_true(_buildings(sim).is_empty())


func test_footprint_cannot_cover_a_street() -> void:
	var context: EconomyContext = _context(_street_row())
	var sim: Simulation = _sim(context)
	assert_eq(_build(sim, context, BIG, Vector2i(5, STREET_ROW - 1)).reason, &"road_cell")


func test_road_cannot_go_inside_a_footprint() -> void:
	var context: EconomyContext = _context(_street_row())
	var sim: Simulation = _sim(context)
	_build(sim, context, BIG, ORIGIN)
	var road: BuildRoadCommand = _run(sim, BuildRoadCommand.new(context, Vector2i(3, 2))) as BuildRoadCommand
	assert_eq(road.reason, &"occupied_cell")


func test_demolish_any_cell_of_a_footprint() -> void:
	var context: EconomyContext = _context(_street_row())
	var sim: Simulation = _sim(context)
	_build(sim, context, BIG, ORIGIN)
	var demolish: DemolishCommand = _run(sim, DemolishCommand.new(Vector2i(3, 2))) as DemolishCommand
	assert_true(demolish.accepted)
	assert_true(_buildings(sim).is_empty())


# An anchor is known by the cell where it stands, its north-west corner; touching any other cell of it keeps it too.
func test_anchor_with_footprint_is_kept_from_any_cell() -> void:
	var context: EconomyContext = _context(_street_row())
	context.map.anchors[ORIGIN] = BIG
	_initial.buildings.append({"definition_id": BIG, "cell": [ORIGIN.x, ORIGIN.y]})
	var sim: Simulation = _sim(context)
	var demolish: DemolishCommand = _run(sim, DemolishCommand.new(Vector2i(3, 2))) as DemolishCommand
	assert_false(demolish.accepted)
	assert_eq(demolish.reason, &"historic_anchor")
	assert_eq(_buildings(sim).size(), 1)


# D-079 with footprints: a street beside any edge cell gives access, not only one beside the corner it stands on.
func test_street_beside_any_edge_cell_gives_access() -> void:
	for street: Vector2i in [Vector2i(4, 2), Vector2i(3, 3), Vector2i(1, 2), Vector2i(3, 0), Vector2i(2, 0)]:
		var context: EconomyContext = _context([street] as Array[Vector2i])
		var sim: Simulation = _sim(context)
		assert_true(_build(sim, context, BIG, ORIGIN).accepted, "street %s" % street)
		assert_eq(RoadTestMap.entry(sim.snapshot(), "blocked", ORIGIN), {}, "street %s" % street)


func test_street_on_the_corner_of_a_footprint_is_not_access() -> void:
	var context: EconomyContext = _context([Vector2i(4, 3)] as Array[Vector2i])
	var sim: Simulation = _sim(context)
	_build(sim, context, BIG, ORIGIN)
	assert_eq(RoadTestMap.entry(sim.snapshot(), "blocked", ORIGIN)["reason"], RoadSystem.NO_ROAD_ACCESS)


# The flour walks from the mill's street, (6,3), to the nearest street beside the bakery, (3,3): 6, 5, 4 and 3.
func test_steps_start_at_the_nearest_edge() -> void:
	var context: EconomyContext = _context(_street_row())
	var sim: Simulation = _sim(context)
	_build(sim, context, &"mill", Vector2i(6, 2))
	_build(sim, context, BIG, ORIGIN)
	var leg: Dictionary = RoadTestMap.entry(sim.snapshot(), "legs", ORIGIN, &"flour")
	assert_eq(leg.get("steps"), 4)
	assert_eq(leg.get("supplier_cell"), [6, 2])


# Exact parity of the 1x1 (D-086): on the real strip every building, as the data has it, is placed by the rules of a
# single cell (taken, terrain, street) and reaches the streets only from its four sides.
func test_one_by_one_matches_single_cell_rules() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	var catalog: DataCatalog = loaded.catalog
	var strip: EconomyContext = EconomyContext.new(catalog, catalog.maps[STRIP])
	var params: Params = SimTestParams.isolated_params(catalog)
	var state: EconomyState = EconomyState.new()
	state.money = 100000
	state.population = int(params.get_value(&"startup.population"))
	var start: Dictionary = Simulation.create_new(params, state, 42, strip).snapshot()["economy"]
	var taken: Array = start["buildings"].map(func(building: Dictionary) -> Array: return building["cell"])
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var mismatches: Array[String] = []
	for id: StringName in strip.buildings:
		if not strip.buildings[id].buildable:
			continue
		for y: int in range(strip.map.height):
			for x: int in range(strip.map.width):
				var cell: Vector2i = Vector2i(x, y)
				var expected: StringName = &"occupied_cell" if [x, y] in taken \
					else strip.terrain_placement_reason(id, cell)
				if expected == &"" and cell in strip.map.road_cells:
					expected = &"road_cell"
				var command: BuildCommand = BuildCommand.new(strip, id, cell)
				command.execute(EconomyState.from_dict(start), params, rng)
				if command.reason != expected:
					mismatches.append("%s at %s: %s, not %s" % [id, cell, command.reason, expected])
	for y: int in range(strip.map.height):
		for x: int in range(strip.map.width):
			var cell: Vector2i = Vector2i(x, y)
			var lone: EconomyState = EconomyState.from_dict(start)
			lone.buildings.assign([{"definition_id": &"mill", "cell": [x, y]}])
			RoadSystem.evaluate(lone, params, strip)
			var blocked: bool = lone.road_blocked.get(cell, &"") == RoadSystem.NO_ROAD_ACCESS
			if blocked == strip.map.beside_road(cell):
				mismatches.append("mill at %s: access %s" % [cell, not blocked])
	assert_eq(mismatches, [] as Array[String])
