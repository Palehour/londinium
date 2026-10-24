extends GutTest

# Issue #209, task 4 of #61 (D-088, D-089, D-090): each house drinks from the water_source of its own district, read
# through district_by_cell and the map's districts. The fixture is the 16x16 harness map split in two parishes: West
# (x < 8) drinks from Old Ford, East from the neutral water. A house and a public fountain stand in each one, too far
# apart for a fountain to reach the other district's house.

const OLDFORD: StringName = &"oldford"
const HOUSE: StringName = &"housing"
const FOUNTAIN: StringName = &"public_fountain"
const WEST: StringName = &"west"
const EAST: StringName = &"east"
const PLAIN: StringName = &"plain"
const SPLIT_X: int = 8
const WEST_HOUSE: Vector2i = Vector2i(0, 0)
const EAST_HOUSE: Vector2i = Vector2i(10, 0)
const WEST_FOUNTAIN: Vector2i = Vector2i(0, 2)
const EAST_FOUNTAIN: Vector2i = Vector2i(10, 2)
const SEED: int = 7

var _catalog: DataCatalog
var _context: EconomyContext


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog


func before_each() -> void:
	_context = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	var map: MapDef = _context.map
	for x: int in range(map.width):
		for y: int in range(map.height):
			map.district_by_cell[Vector2i(x, y)] = WEST if x < SPLIT_X else EAST
	map.district_names[WEST] = "West"
	map.district_names[EAST] = "East"
	map.district_water_sources[WEST] = &"old_ford"
	map.district_water_sources[EAST] = &"neutral"


func _params(modifiers: Array[Modifier] = []) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"events.enabled", &"set", 1.0))
	role.modifiers.append(Modifier.new(&"defeat.enabled", &"set", 0.0))
	role.modifiers.append_array(modifiers)
	return SimTestParams.isolated_params(_catalog, role)


func _value(params: Params, key: String) -> float:
	return float(params.get_value(StringName(key)))


func _at(id: StringName, cell: Vector2i) -> Dictionary:
	return {"definition_id": id, "cell": [cell.x, cell.y]}


func _city(population: int) -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.money = 100000
	state.population = population
	for cell: Vector2i in [WEST_HOUSE, EAST_HOUSE]:
		state.buildings.append(_at(HOUSE, cell))
	for cell: Vector2i in [WEST_FOUNTAIN, EAST_FOUNTAIN]:
		state.buildings.append(_at(FOUNTAIN, cell))
	return state


func _water(state: EconomyState, params: Params) -> Dictionary[StringName, float]:
	return WaterSystem.district_water(state, params, _context)


func _sim_water(sim: Simulation, params: Params) -> Dictionary[StringName, float]:
	return _water(EconomyState.from_dict(sim.to_save()["economy"]), params)


func _start(sim: Simulation) -> void:
	var command: MissionCommand = MissionCommand.new(&"start", OLDFORD)
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted, str(command.reason))


static func _ticks(sim: Simulation, count: int) -> void:
	for index: int in range(count):
		sim.tick()


func test_the_fixture_fountains_reach_only_their_own_district() -> void:
	var params: Params = _params()
	var state: EconomyState = _city(0)
	var reach: float = _value(params, "fountain.radius_m")
	assert_lte(WaterSystem.distance_m(params, _context, state.buildings[0], state.buildings[2]), reach)
	assert_gt(WaterSystem.distance_m(params, _context, state.buildings[0], state.buildings[3]), reach)
	assert_gt(WaterSystem.distance_m(params, _context, state.buildings[1], state.buildings[2]), reach)


func test_a_house_in_each_district_takes_the_risk_of_its_own_source() -> void:
	var params: Params = _params()
	var water: Dictionary[StringName, float] = _water(_city(0), params)
	assert_eq(water[WEST], 1.0 - _value(params, "events.source_risk.old_ford"), "West drinks from Old Ford")
	assert_eq(water[EAST], 1.0 - _value(params, "events.source_risk.neutral"), "East drinks the neutral water")
	assert_ne(water[WEST], water[EAST], "With the default data the two sources differ")


func test_a_lea_bridge_district_takes_the_lea_bridge_risk() -> void:
	var params: Params = _params([Modifier.new(&"lea_bridge.source_risk", &"set", 0.3)])
	_context.map.district_water_sources[EAST] = &"lea_bridge"
	var water: Dictionary[StringName, float] = _water(_city(0), params)
	assert_almost_eq(water[EAST], 0.7, 0.0001)
	assert_eq(water[WEST], 1.0 - _value(params, "events.source_risk.old_ford"))


func test_a_district_without_water_source_is_neutral() -> void:
	var params: Params = _params([Modifier.new(&"events.source_risk.neutral", &"set", 0.4)])
	_context.map.district_water_sources.erase(EAST)
	assert_almost_eq(_water(_city(0), params)[EAST], 0.6, 0.0001)


func test_every_district_of_the_map_has_its_water_even_without_houses() -> void:
	_context.map.district_names[PLAIN] = "Plain"
	var water: Dictionary[StringName, float] = _water(_city(0), _params())
	assert_eq(water.keys(), [WEST, EAST, PLAIN])
	assert_eq(water[PLAIN], 0.0, "D-089: a district without houses has no water")


# The cut of Old Ford (D-090) falls on the districts that drink from it; the others keep their water.
func test_the_cut_and_its_repair_touch_only_the_old_ford_districts() -> void:
	var params: Params = _params()
	var sim: Simulation = Simulation.new(params, _city(0), SEED, _context)
	_start(sim)
	assert_eq(_sim_water(sim, params), {WEST: 0.0, EAST: 1.0} as Dictionary[StringName, float])
	_ticks(sim, SimTime.minutes_to_ticks(_value(params, "mission.oldford.duration_min")) - 1)
	var state: EconomyState = EconomyState.from_dict(sim.to_save()["economy"])
	assert_eq(StringName(state.missions[OLDFORD].status), MissionSystem.FAILED, "West stays without water")
	assert_eq(WaterSystem.district_risk(state, params, WEST), 1.0)
	assert_false(state.district_source_risk.has(EAST), "The neutral district keeps its own source")


# Only the failing district loses people: its share of the houses of the population x fail_mortality x (1 - prep).
func test_cholera_kills_only_in_the_failing_district() -> void:
	var params: Params = _params()
	var population: int = 80
	var sim: Simulation = Simulation.new(params, _city(population), SEED, _context)
	_start(sim)
	_ticks(sim, SimTime.minutes_to_ticks(_value(params, "mission.oldford.duration_min")) - 1)
	var economy: Dictionary = sim.snapshot()["economy"]
	assert_eq(StringName(economy["missions"][OLDFORD]["status"]), MissionSystem.FAILED)
	var deaths: int = roundi(population / 2.0 * _value(params, "cholera.fail_mortality"))
	assert_eq(deaths, 10, "Half of 80 lives in West, and a quarter of them die with the default data")
	assert_eq(economy["missions"][OLDFORD]["deaths"], deaths)
	assert_eq(economy["population"], population - deaths)


func test_a_map_without_districts_is_still_the_one_neutral_district() -> void:
	var context: EconomyContext = EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"])
	var params: Params = _params()
	var water: Dictionary[StringName, float] = WaterSystem.district_water(_city(0), params, context)
	assert_eq(water, {WaterSystem.DEFAULT_DISTRICT: 1.0 - _value(params, "events.source_risk.neutral")}
		as Dictionary[StringName, float])
