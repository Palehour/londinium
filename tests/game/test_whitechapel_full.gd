extends GutTest

# The full map of Whitechapel and its scenario (issue #204, task 3 of #61; D-086, D-093, D-094). The map is only data,
# drawn from Chronicler's sources (#201) in the format of #198; these tests hold it to them.

const MAP_ID: StringName = &"whitechapel_full"
const SCENARIO_ID: StringName = &"whitechapel_full"
const SOURCES: String = "res://data/maps/sources/whitechapel_full_sources.csv"
const DISTRICTS: Array[StringName] = [&"whitechapel", &"st_george_in_the_east", &"wapping"]
# 20 game minutes at one tick a second.
const GAME_TICKS: int = 20 * 60
const HALF_GAME_TICKS: int = 10 * 60
# The tax of the strip scripts (tests/scenarios/strip/), so the bread chain pays for itself.
const TAX_RATE: float = 0.6
# The game below. Wapping has no street (a liberty of the map), so the player lays one from Ratcliff Highway down
# between St Katharine and the Hermitage Basin to the river, and plays the bread chain there. One house stands beside
# a historic street in Whitechapel (High Street) and one in St George (Cable Street).
const WAPPING_ROADS: Array[Vector2i] = [Vector2i(28, 48), Vector2i(28, 50), Vector2i(28, 52), Vector2i(28, 54),
	Vector2i(28, 56), Vector2i(28, 58), Vector2i(26, 58), Vector2i(26, 60), Vector2i(24, 60), Vector2i(24, 62),
	Vector2i(23, 64)]
const CHAIN: Dictionary[Vector2i, StringName] = {Vector2i(24, 66): &"wharf", Vector2i(22, 62): &"mill",
	Vector2i(22, 60): &"bakery", Vector2i(26, 52): &"housing", Vector2i(26, 54): &"housing"}
const WHITECHAPEL_HOUSE: Vector2i = Vector2i(12, 22)
const ST_GEORGE_HOUSE: Vector2i = Vector2i(24, 40)
const WAPPING_HOUSE: Vector2i = Vector2i(26, 52)
# The coast of issue #307 (D-162, D-163): a band of riverbank two cells deep, with straight stretches where the player
# may build a wharf (D-155). The stretches, x from and to, follow Chronicler's wharves of Wapping [DEBATED, ±2]; they
# are only the reference of this test, not data of the game.
const BAND_DEPTH: int = 2
const STRAIGHT_STRETCHES: Array[Vector2i] = [Vector2i(1, 3), Vector2i(4, 5), Vector2i(6, 8), Vector2i(9, 12),
	Vector2i(19, 20), Vector2i(24, 26), Vector2i(28, 29), Vector2i(30, 31), Vector2i(32, 33), Vector2i(34, 36),
	Vector2i(37, 39), Vector2i(40, 43), Vector2i(45, 47)]
const WHARF_MONEY: int = 100000

var _catalog: DataCatalog
var _map: MapDef


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_map = _catalog.maps.get(MAP_ID)


func _params() -> Params:
	return Params.new(_catalog, _catalog.roles[&"neutral_administrator"])


func _session() -> GameSession:
	return GameSession.new(_catalog, _params(), SCENARIO_ID)


func _is_free_land(cell: Vector2i) -> bool:
	return cell not in _map.river_cells and cell not in _map.dock_cells and cell not in _map.road_cells \
		and cell not in _map.existing_cells and cell not in _map.stairs_cells


func _money(session: GameSession) -> int:
	return int(session.get_snapshot()["economy"]["money"])


# Each street row of the sources, as its id and the cells of its centre line.
func _source_streets() -> Dictionary[String, Array]:
	var streets: Dictionary[String, Array] = {}
	var file: FileAccess = FileAccess.open(SOURCES, FileAccess.READ)
	var header: PackedStringArray = file.get_csv_line()
	while not file.eof_reached():
		var line: PackedStringArray = file.get_csv_line()
		if line.size() != header.size() or line[header.find("type")] != "street":
			continue
		var cells: Array[Vector2i] = []
		for point: String in line[header.find("points")].split(" "):
			cells.append(Vector2i(int(point.get_slice(":", 0)), int(point.get_slice(":", 1))))
		streets[line[header.find("id")]] = cells
	return streets


func test_the_full_map_loads_with_the_size_of_d093() -> void:
	assert_not_null(_map, "data/maps/whitechapel_full.json must pass the validation of #198")
	if _map == null:
		return
	assert_eq(Vector2i(_map.width, _map.height), Vector2i(48, 80))
	assert_true(_map.roads_enabled)
	assert_false(_map.stairs_cells.is_empty())


func test_every_source_street_is_on_the_map() -> void:
	var streets: Dictionary[String, Array] = _source_streets()
	assert_eq(streets.size(), 9, "the nine streets of task 1")
	for id: String in streets:
		for cell: Vector2i in streets[id]:
			assert_true(cell in _map.road_cells, "%s passes %s" % [id, cell])


func test_the_streets_form_one_network() -> void:
	var streets: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in _map.road_cells:
		streets[cell] = true
	var reached: Dictionary[Vector2i, bool] = {_map.road_cells[0]: true}
	var pending: Array[Vector2i] = [_map.road_cells[0]]
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		for side: Vector2i in RoadNetwork.SIDES:
			if streets.has(cell + side) and not reached.has(cell + side):
				reached[cell + side] = true
				pending.append(cell + side)
	assert_eq(reached.size(), streets.size(), "every street joins the others side to side")


func test_every_district_has_buildable_land_and_drinks_old_ford() -> void:
	assert_eq_deep(_map.district_names.keys(), DISTRICTS)
	var land: Dictionary[StringName, int] = {}
	for cell: Vector2i in _map.district_by_cell:
		if _is_free_land(cell):
			land[_map.district_by_cell[cell]] = land.get(_map.district_by_cell[cell], 0) + 1
	for id: StringName in DISTRICTS:
		assert_gt(land.get(id, 0), 0, id)
		assert_eq(_map.district_water_sources[id], &"old_ford", id)


# Only a side on the river counts (issue #61): docks and stairs are not the river.
func test_enough_buildable_land_beside_the_river() -> void:
	var riverside: int = 0
	for y: int in range(_map.height):
		for x: int in range(_map.width):
			var cell: Vector2i = Vector2i(x, y)
			if _is_free_land(cell) and RoadNetwork.SIDES.any(func(side: Vector2i) -> bool:
					return cell + side in _map.river_cells):
				riverside += 1
	assert_gte(riverside, int(_params().get_value(&"map.min_riverside_buildable")))


# D-094 on this map: every stairs refuses a street over it and nothing is charged.
func test_no_street_on_the_stairs_of_this_map() -> void:
	var session: GameSession = _session()
	var money: int = _money(session)
	for stairs: Vector2i in _map.stairs_cells:
		var command: BuildRoadCommand = BuildRoadCommand.new(session.context,
			RoadNetwork.piece_origin(stairs, session.context.road_footprint))
		session.submit_command(command)
		session.simulation.tick()
		assert_eq(command.reason, &"requires_land", str(stairs))
	assert_eq(_money(session), money)
	assert_eq(session.get_snapshot()["distance"]["player_roads"], [])


# Sends the commands, then ticks as the game does.
func _play(session: GameSession, commands: Array[SimulationCommand], ticks: int) -> void:
	for command: SimulationCommand in commands:
		session.submit_command(command)
	for tick: int in range(ticks):
		session.simulation.tick()
		session.publish_tick()


# The bread chain of Wapping first, at the tax of the strip scripts; the houses of the other two districts once the
# chain has paid for them, halfway through.
func test_twenty_minutes_on_the_new_scenario() -> void:
	var session: GameSession = _session()
	assert_eq(session.context.map.id, MAP_ID)
	var commands: Array[SimulationCommand] = [SetTaxCommand.new(TAX_RATE)]
	for cell: Vector2i in WAPPING_ROADS:
		commands.append(BuildRoadCommand.new(session.context, cell))
	for cell: Vector2i in CHAIN:
		commands.append(BuildCommand.new(session.context, CHAIN[cell], cell))
	var later: Array[SimulationCommand] = []
	for cell: Vector2i in [WHITECHAPEL_HOUSE, ST_GEORGE_HOUSE]:
		later.append(BuildCommand.new(session.context, &"housing", cell))
	_play(session, commands, HALF_GAME_TICKS)
	_play(session, later, GAME_TICKS - HALF_GAME_TICKS)
	for command: SimulationCommand in commands + later:
		assert_true(command.accepted, "%s: %s" % [command, command.reason])
	var districts: Array[StringName] = []
	for cell: Vector2i in [WHITECHAPEL_HOUSE, ST_GEORGE_HOUSE, WAPPING_HOUSE]:
		districts.append(_map.district_by_cell[cell])
	assert_eq(districts, DISTRICTS)
	assert_eq(session.get_snapshot()["defeat"]["causes"], [], "the city lives the 20 minutes")
	assert_gt(int(session.get_snapshot()["economy"]["population"]), 0)


# The first river cell of a column: the coast never moves (#307), so every column meets the river.
func _coast_row(x: int) -> int:
	for y: int in range(_map.height):
		if Vector2i(x, y) in _map.river_cells:
			return y
	return _map.height


func _touches_dock(cell: Vector2i) -> bool:
	return RoadNetwork.SIDES.any(func(side: Vector2i) -> bool: return cell + side in _map.dock_cells)


# D-162: two cells of riverbank (or the stairs that cross it) above the river in every column. Only beside the St
# Katharine lock, whose row 59 stays as it is, may a column have less.
func test_the_riverbank_is_a_band_of_two_cells() -> void:
	for x: int in range(_map.width):
		var depth: int = 0
		var cell: Vector2i = Vector2i(x, _coast_row(x) - 1)
		while depth < BAND_DEPTH and (_map.terrain.get(cell) == &"riverbank" or cell in _map.stairs_cells):
			depth += 1
			cell.y -= 1
		var bank: Vector2i = Vector2i(x, _coast_row(x) - 1)
		if bank in _map.dock_cells or _touches_dock(bank):
			continue
		assert_eq(depth, BAND_DEPTH, "column %d" % x)


# No river cell left in a notch of the shore, with land on three of its sides.
func test_no_river_cell_is_left_alone_on_the_shore() -> void:
	var bounds: Rect2i = Rect2i(0, 0, _map.width, _map.height)
	for cell: Vector2i in _map.river_cells:
		var land: int = RoadNetwork.SIDES.filter(func(side: Vector2i) -> bool:
			return bounds.has_point(cell + side) and cell + side not in _map.river_cells \
				and cell + side not in _map.dock_cells).size()
		assert_lt(land, 3, str(cell))


# D-155 and D-163: on every straight stretch the player can build a wharf, its north row on the riverbank and its
# south row on the river, from each column but the last.
func test_a_wharf_fits_on_every_straight_stretch() -> void:
	var context: EconomyContext = EconomyContext.new(_catalog, _map)
	var width: int = _catalog.buildings[&"wharf"].footprint.x
	for stretch: Vector2i in STRAIGHT_STRETCHES:
		for x: int in range(stretch.x, stretch.y - width + 2):
			var initial: EconomyState = EconomyState.new()
			initial.money = WHARF_MONEY
			var sim: Simulation = Simulation.new(_params(), initial, 7, context)
			var command: BuildCommand = BuildCommand.new(context, &"wharf", Vector2i(x, _coast_row(x) - 1))
			sim.apply_command(command)
			sim.tick()
			assert_true(command.accepted, "wharf at x %d of %s: %s" % [x, stretch, command.reason])
