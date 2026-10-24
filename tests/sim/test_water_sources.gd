extends GutTest

# Issue #202, task 2a (D-090): besides the public fountain (D-089) a house can drink from a well (1x1, its own radius
# and risk) or from a fountain connected to Lea Bridge (the public fountain's keys, risk 0, at most
# lea_bridge.max_fountains of them). Each house takes the safest water that covers it.

const FOUNTAIN: StringName = &"public_fountain"
const LEA_BRIDGE: StringName = &"lea_bridge_fountain"
const WELL: StringName = &"well"
const HOUSE: StringName = &"housing"
const NEUTRAL: StringName = &"neutral"
const OLD_FORD: StringName = &"old_ford"
const WELL_RADIUS_KEY: StringName = &"well.radius_m"
const WELL_RISK_KEY: StringName = &"well.source_risk"
const LEA_BRIDGE_RISK_KEY: StringName = &"lea_bridge.source_risk"
const CAP_KEY: StringName = &"lea_bridge.max_fountains"
const PRICE_FIELDS: Array[String] = ["cost", "upkeep_per_minute", "wage_per_worker_per_minute", "jobs"]

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


func _events_on() -> Params:
	return _params([Modifier.new(&"events.enabled", &"set", 1.0)])


func _at(id: StringName, cell: Vector2i) -> Dictionary:
	return {"definition_id": id, "cell": [cell.x, cell.y]}


func _one(building: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = [building]
	return found


func test_the_well_is_one_cell_and_reads_its_own_keys() -> void:
	var params: Params = _params()
	var well: BuildingDef = _catalog.buildings[WELL]
	assert_eq(well.footprint, Vector2i.ONE)
	assert_true(WaterSystem.WATER_TAG in well.tags)
	assert_null(well.recipe)
	assert_eq(params.get_value(&"building.well.cost"), 150)
	assert_eq(params.get_value(&"building.well.upkeep_per_minute"), 0)
	assert_eq(params.get_value(&"building.well.jobs"), 0)
	assert_eq(params.get_value(WELL_RADIUS_KEY), 50.0)
	assert_eq(params.get_value(WELL_RISK_KEY), 0.3)
	assert_eq(params.get_value(CAP_KEY), 3)
	assert_eq(params.get_value(LEA_BRIDGE_RISK_KEY), 0.0)


# "Con el costo y el radio leídos de las claves de public_fountain, sin copiar los números" (Cristian, #202).
func test_the_lea_bridge_fountain_reads_the_public_fountain_keys() -> void:
	assert_eq(_catalog.buildings[LEA_BRIDGE].footprint, _catalog.buildings[FOUNTAIN].footprint)
	for field: String in PRICE_FIELDS:
		assert_false(_catalog.base_values.has(StringName("building.lea_bridge_fountain.%s" % field)), field)
	var cost: int = int(_params().get_value(&"building.public_fountain.cost"))
	var dearer: Params = _params([Modifier.new(&"building.public_fountain.cost", &"set", float(cost + 100))])
	assert_eq(dearer.get_value(&"building.lea_bridge_fountain.cost"), cost + 100)
	for field: String in PRICE_FIELDS:
		assert_eq(_params().get_value(StringName("building.lea_bridge_fountain.%s" % field)),
			_params().get_value(StringName("building.public_fountain.%s" % field)), field)
	var house: Array[Dictionary] = _one(_at(HOUSE, Vector2i(6, 0)))
	var lea: Array[Dictionary] = _one(_at(LEA_BRIDGE, Vector2i.ZERO))
	var shorter: Params = _params([Modifier.new(&"fountain.radius_m", &"set",
		WaterSystem.distance_m(_params(), _context, house[0], lea[0]) - 0.01)])
	assert_eq(WaterSystem.coverage(_params(), _context, house, lea, OLD_FORD), 1.0)
	assert_eq(WaterSystem.coverage(shorter, _context, house, lea, OLD_FORD), 0.0)


# The well's radius is its own: a house exactly at well.radius_m drinks from it, a hundredth beyond does not, whatever
# the fountain's radius says. What it gives is 1 - well.source_risk.
func test_a_well_covers_its_own_radius_with_its_own_risk() -> void:
	var house: Array[Dictionary] = _one(_at(HOUSE, Vector2i(2, 0)))
	var well: Array[Dictionary] = _one(_at(WELL, Vector2i.ZERO))
	var distance: float = WaterSystem.distance_m(_params(), _context, house[0], well[0])
	var exact: Params = _params([Modifier.new(WELL_RADIUS_KEY, &"set", distance)])
	var safe: float = 1.0 - float(exact.get_value(WELL_RISK_KEY))
	assert_almost_eq(WaterSystem.coverage(exact, _context, house, well, NEUTRAL), safe, 1e-9)
	var short: Params = _params([Modifier.new(WELL_RADIUS_KEY, &"set", distance - 0.01),
		Modifier.new(&"fountain.radius_m", &"set", 400.0)])
	assert_eq(WaterSystem.coverage(short, _context, house, well, NEUTRAL), 0.0)


# Each house takes the safest water that reaches it; the district's water is their sum over its houses.
func test_each_house_takes_the_safest_water_that_covers_it() -> void:
	var params: Params = _params()
	var houses: Array[Dictionary] = [_at(HOUSE, Vector2i(1, 0)), _at(HOUSE, Vector2i(40, 0)),
		_at(HOUSE, Vector2i(20, 40)), _at(HOUSE, Vector2i(40, 70))]
	var water: Array[Dictionary] = [_at(WELL, Vector2i(0, 0)), _at(LEA_BRIDGE, Vector2i(42, 0)),
		_at(WELL, Vector2i(22, 40)), _at(FOUNTAIN, Vector2i(20, 42))]
	var well_safe: float = 1.0 - float(params.get_value(WELL_RISK_KEY))
	var lea_safe: float = 1.0 - float(params.get_value(LEA_BRIDGE_RISK_KEY))
	# Under Old Ford the public fountain protects nobody, so the third house keeps its well; the fourth has nothing.
	assert_almost_eq(WaterSystem.coverage(params, _context, houses, water, OLD_FORD),
		(well_safe + lea_safe + well_safe) / 4.0, 1e-9)
	# With a neutral source the fountain beats the well.
	assert_almost_eq(WaterSystem.coverage(params, _context, houses, water, NEUTRAL),
		(well_safe + lea_safe + 1.0) / 4.0, 1e-9)


func test_the_city_counts_wells_and_lea_bridge_fountains() -> void:
	var state: EconomyState = EconomyState.new()
	state.buildings.append(_at(WELL, Vector2i.ZERO))
	state.buildings.append(_at(HOUSE, Vector2i(1, 0)))
	state.buildings.append(_at(HOUSE, Vector2i(40, 70)))
	var params: Params = _params()
	assert_almost_eq(WaterSystem.city_coverage(state, params, _context, OLD_FORD),
		(1.0 - float(params.get_value(WELL_RISK_KEY))) / 2.0, 1e-9)


func test_with_events_off_neither_can_be_built() -> void:
	var params: Params = _params()
	for id: StringName in [WELL, LEA_BRIDGE]:
		var state: EconomyState = _rich_state()
		var command: BuildCommand = BuildCommand.new(_context, id, _free_cell(state, id))
		command.execute(state, params, RandomNumberGenerator.new())
		assert_eq(command.reason, &"events_disabled", str(id))
		assert_true(state.buildings.is_empty())


# The test reads the cap from the data (Cristian, #202): with the default, the fourth is refused, and costs nothing.
func test_a_lea_bridge_fountain_past_the_cap_is_refused_without_charge() -> void:
	var params: Params = _events_on()
	var cap: int = int(params.get_value(CAP_KEY))
	var state: EconomyState = _rich_state()
	for index: int in range(cap):
		assert_true(_build(state, params, LEA_BRIDGE).accepted, "fountain %d" % index)
	var money: int = state.money
	var command: BuildCommand = _build(state, params, LEA_BRIDGE)
	assert_false(command.accepted)
	assert_eq(command.reason, &"water_source_cap")
	assert_eq(state.money, money)
	assert_eq(BuildingCosts.count_of(state, LEA_BRIDGE), cap)
	var sim: Simulation = Simulation.new(params, state, 1, _context)
	assert_eq(sim.get_building_unavailable_reason(LEA_BRIDGE), &"water_source_cap")
	assert_eq(sim.get_building_unavailable_reason(WELL), &"")


func test_wells_have_no_cap() -> void:
	var params: Params = _events_on()
	var state: EconomyState = _rich_state()
	for index: int in range(int(params.get_value(CAP_KEY)) * 2 + 1):
		var command: BuildCommand = _build(state, params, WELL)
		assert_true(command.accepted, "well %d: %s" % [index, command.reason])


func _rich_state() -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.money = 1000000
	return state


func _build(state: EconomyState, params: Params, id: StringName) -> BuildCommand:
	var command: BuildCommand = BuildCommand.new(_context, id, _free_cell(state, id))
	command.execute(state, params, RandomNumberGenerator.new())
	return command


func _free_cell(state: EconomyState, id: StringName) -> Vector2i:
	var size: Vector2i = _catalog.buildings[id].footprint
	for x: int in range(_context.map.width):
		for y: int in range(_context.map.height):
			var area: Rect2i = Rect2i(Vector2i(x, y), size)
			var taken: bool = state.buildings.any(func(building: Dictionary) -> bool:
				return _context.area_of(building).intersects(area))
			if not taken and _context.placement_reason(id, Vector2i(x, y)) == &"":
				return Vector2i(x, y)
	fail_test("No free cell of the map takes %s" % id)
	return Vector2i.ZERO
