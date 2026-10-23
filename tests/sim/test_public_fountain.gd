extends GutTest

# Issue #63, task 0 (D-089, Cristian via Chief): the public fountain covers the houses within fountain.radius_m,
# centre to centre and in metres (D-086), and water_d = min(1, covered houses / houses) x (1 - source_risk).
# Districts arrive with #60: until then the city is the one district.

const FOUNTAIN: StringName = &"public_fountain"
const HOUSE: StringName = &"housing"
const NEUTRAL: StringName = &"neutral"
const OLD_FORD: StringName = &"old_ford"
const RADIUS_KEY: StringName = &"fountain.radius_m"
# Far from the fountain at (0, 0) on any radius of the range: more than 400 m away.
const FAR_CELLS: Array[Vector2i] = [Vector2i(14, 14), Vector2i(14, 12)]
const NEAR_CELLS: Array[Vector2i] = [Vector2i(2, 0), Vector2i(0, 2)]

var _catalog: DataCatalog
var _context: EconomyContext


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])


func _params(modifiers: Array[Modifier] = []) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign(modifiers)
	return Params.new(_catalog, role)


func _at(id: StringName, cell: Vector2i) -> Dictionary:
	return {"definition_id": id, "cell": [cell.x, cell.y]}


func _houses(cells: Array[Vector2i]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for cell: Vector2i in cells:
		found.append(_at(HOUSE, cell))
	return found


func _fountain_at_origin() -> Array[Dictionary]:
	var found: Array[Dictionary] = [_at(FOUNTAIN, Vector2i.ZERO)]
	return found


# The cells east of the fountain at which a house's centre is exactly fountain.radius_m away.
func _cells_at_radius(params: Params) -> int:
	var radius: float = float(params.get_value(RADIUS_KEY))
	var cell_size: float = float(params.get_value(&"map.cell_size_m"))
	assert_eq(fmod(radius, cell_size), 0.0, "The radius of the data falls on a whole cell")
	return int(radius / cell_size)


func test_the_fountain_data_has_no_jobs_and_no_recipe() -> void:
	var params: Params = _params()
	var fountain: BuildingDef = _catalog.buildings[FOUNTAIN]
	assert_eq(fountain.footprint, Vector2i(2, 2))
	assert_true(WaterSystem.WATER_TAG in fountain.tags)
	assert_null(fountain.recipe)
	assert_eq(params.get_value(&"building.public_fountain.jobs"), 0)
	assert_eq(params.get_value(&"building.public_fountain.cost"), 400)
	assert_eq(params.get_value(&"building.public_fountain.upkeep_per_minute"), 1)
	assert_eq(params.get_value(RADIUS_KEY), 150.0)


func test_a_radius_outside_its_range_is_rejected() -> void:
	for radius: float in [49.0, 401.0]:
		var role: RoleDef = RoleDef.new()
		role.modifiers.append(Modifier.new(RADIUS_KEY, &"set", radius))
		assert_null(Params.new(_catalog, role).get_value(RADIUS_KEY), str(radius))
		assert_push_error("Params: invalid range for '%s'" % RADIUS_KEY)


func test_a_house_at_exactly_the_radius_is_covered_and_a_hundredth_beyond_is_not() -> void:
	var params: Params = _params()
	var houses: Array[Dictionary] = _houses([Vector2i(_cells_at_radius(params), 0)])
	assert_eq(WaterSystem.coverage(params, _context, houses, _fountain_at_origin(), NEUTRAL), 1.0)
	var radius: float = float(params.get_value(RADIUS_KEY))
	var shorter: Params = _params([Modifier.new(RADIUS_KEY, &"set", radius - 0.01)])
	assert_eq(WaterSystem.coverage(shorter, _context, houses, _fountain_at_origin(), NEUTRAL), 0.0)


func test_none_half_or_all_houses_in_the_radius_give_zero_half_or_one() -> void:
	var params: Params = _params()
	var cases: Array[Array] = [[FAR_CELLS, 0.0], [NEAR_CELLS + FAR_CELLS, 0.5], [NEAR_CELLS, 1.0]]
	for case: Array in cases:
		var cells: Array[Vector2i] = []
		cells.assign(case[0])
		assert_eq(WaterSystem.coverage(params, _context, _houses(cells), _fountain_at_origin(), NEUTRAL), case[1],
			str(cells))


func test_a_district_without_houses_has_no_water() -> void:
	assert_eq(WaterSystem.coverage(_params(), _context, [], _fountain_at_origin(), NEUTRAL), 0.0)


func test_with_old_ford_the_fountains_do_not_protect() -> void:
	var params: Params = _params()
	assert_eq(params.get_value(&"events.source_risk.old_ford"), 1.0)
	assert_eq(WaterSystem.coverage(params, _context, _houses(NEAR_CELLS), _fountain_at_origin(), OLD_FORD), 0.0)


func test_without_fountains_no_house_is_covered() -> void:
	assert_eq(WaterSystem.coverage(_params(), _context, _houses(NEAR_CELLS), [], NEUTRAL), 0.0)


# Every house of the city counts, whatever housing it is, and only the state's fountains cover them.
func test_the_city_is_one_district_of_every_house() -> void:
	var state: EconomyState = EconomyState.new()
	state.buildings.append(_at(FOUNTAIN, Vector2i.ZERO))
	state.buildings.append(_at(HOUSE, NEAR_CELLS[0]))
	state.buildings.append(_at(&"dense_housing", FAR_CELLS[0]))
	state.buildings.append(_at(&"mill", NEAR_CELLS[1]))
	assert_eq(WaterSystem.city_coverage(state, _params(), _context, NEUTRAL), 0.5)


func test_with_events_off_the_fountain_cannot_be_built() -> void:
	var params: Params = _params()
	assert_false(params.get_value(&"events.enabled"))
	var state: EconomyState = EconomyState.new()
	state.money = int(params.get_value(&"building.public_fountain.cost"))
	var command: BuildCommand = BuildCommand.new(_context, FOUNTAIN, _free_cell())
	command.execute(state, params, RandomNumberGenerator.new())
	assert_false(command.accepted)
	assert_eq(command.reason, &"events_disabled")
	assert_true(state.buildings.is_empty())
	var sim: Simulation = Simulation.new(params, EconomyState.new(), 1, _context)
	assert_eq(sim.get_building_unavailable_reason(FOUNTAIN), &"events_disabled")
	assert_eq(sim.get_building_unavailable_reason(HOUSE), &"")


func test_with_events_on_the_fountain_is_built() -> void:
	var params: Params = _params([Modifier.new(&"events.enabled", &"set", 1.0)])
	var state: EconomyState = EconomyState.new()
	state.money = int(params.get_value(&"building.public_fountain.cost"))
	var command: BuildCommand = BuildCommand.new(_context, FOUNTAIN, _free_cell())
	command.execute(state, params, RandomNumberGenerator.new())
	assert_true(command.accepted, str(command.reason))
	var sim: Simulation = Simulation.new(params, EconomyState.new(), 1, _context)
	assert_eq(sim.get_building_unavailable_reason(FOUNTAIN), &"")


func _free_cell() -> Vector2i:
	for x: int in range(_context.map.width):
		for y: int in range(_context.map.height):
			if _context.placement_reason(FOUNTAIN, Vector2i(x, y)) == &"":
				return Vector2i(x, y)
	fail_test("No cell of the map takes a fountain")
	return Vector2i.ZERO
