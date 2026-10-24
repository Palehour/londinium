extends GutTest

# Issue #202, task 2b (D-090): the Old Ford mission of the 1866 cholera. With the historic events on it starts by
# itself duration_min before the outbreak (events.cholera.trigger_min), cuts the district's fountains, and at its
# close a district with water_d under mission.min_water_d fails: pop x cholera.fail_mortality x (1 - prep) die, no
# immigration for cholera.vacancy_min, then immigration x cholera.recovery_mult for cholera.recovery_min. It is never a
# defeat. Until districts exist the whole map is the one district `default`.

const OLDFORD: StringName = &"oldford"
const HOUSE: StringName = &"housing"
const FOUNTAIN: StringName = &"public_fountain"
const LEA_BRIDGE: StringName = &"lea_bridge_fountain"
const WELL: StringName = &"well"
const MAP: StringName = &"whitechapel_1850s"
# Houses 2x2 side by side along the top row. A well at WELL_CELL reaches the first one (40 m) and no other.
const WELL_CELL: Vector2i = Vector2i(2, 0)
const HOUSE_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0), Vector2i(4, 0), Vector2i(6, 0), Vector2i(8, 0)]
const SEED: int = 7

var _catalog: DataCatalog
var _context: EconomyContext


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog
	_context = EconomyContext.new(_catalog, _catalog.maps[MAP])


# Events on, defeats off, and nothing else that moves people or money, so each test sees only the mission. The tests
# about defeats switch them back on.
func _params(modifiers: Array[Modifier] = []) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"events.enabled", &"set", 1.0))
	role.modifiers.append(Modifier.new(&"defeat.enabled", &"set", 0.0))
	role.modifiers.append_array(modifiers)
	return SimTestParams.isolated_params(_catalog, role)


func _defeats_on() -> Params:
	return _params([Modifier.new(&"defeat.enabled", &"set", 1.0), Modifier.new(&"defeat.grace_seconds", &"set", 0.0)])


func _value(params: Params, key: String) -> float:
	return float(params.get_value(StringName(key)))


func _ticks_of(params: Params, key: String) -> int:
	return SimTime.minutes_to_ticks(_value(params, key))


func _at(id: StringName, cell: Vector2i) -> Dictionary:
	return {"definition_id": id, "cell": [cell.x, cell.y]}


func _city(population: int, water: Array[Dictionary] = [], houses: int = HOUSE_CELLS.size()) -> EconomyState:
	var state: EconomyState = EconomyState.new()
	state.money = 100000
	state.population = population
	for index: int in range(houses):
		state.buildings.append(_at(HOUSE, HOUSE_CELLS[index]))
	state.buildings.append_array(water)
	return state


func _sim(params: Params, state: EconomyState) -> Simulation:
	return Simulation.new(params, state, SEED, _context)


func _start(sim: Simulation) -> void:
	var command: MissionCommand = MissionCommand.new(&"start", OLDFORD)
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted, str(command.reason))


static func _ticks(sim: Simulation, count: int) -> void:
	for index: int in range(count):
		sim.tick()


func _economy(sim: Simulation) -> Dictionary:
	return sim.snapshot()["economy"]


func _status(sim: Simulation) -> StringName:
	return StringName(_economy(sim)["missions"][OLDFORD]["status"])


func _water(sim: Simulation, params: Params) -> float:
	return WaterSystem.district_water(EconomyState.from_dict(sim.to_save()["economy"]), params, _context)[
		WaterSystem.DEFAULT_DISTRICT]


# Ticks from the start (its own tick included) to the close.
func _run_to_close(sim: Simulation, params: Params) -> void:
	_ticks(sim, _ticks_of(params, "mission.oldford.duration_min") - 1)


func test_with_events_on_it_starts_by_itself_so_it_closes_when_the_outbreak_arrives() -> void:
	var params: Params = _params()
	var outbreak: int = _ticks_of(params, "events.cholera.trigger_min")
	var duration: int = _ticks_of(params, "mission.oldford.duration_min")
	var sim: Simulation = _sim(params, _city(0))
	_ticks(sim, outbreak - duration - 1)
	assert_false(_economy(sim).has("missions"), "Not before the warning")
	sim.tick()
	assert_eq(_status(sim), &"active", "The warning of Bromley starts it")
	_ticks(sim, duration - 1)
	assert_eq(_status(sim), &"active")
	sim.tick()
	assert_ne(_status(sim), &"active", "It closes on the tick of the outbreak")
	assert_eq(sim.snapshot()["tick_count"], outbreak)


func test_with_events_off_it_never_starts() -> void:
	var params: Params = SimTestParams.isolated_params(_catalog)
	var sim: Simulation = _sim(params, _city(0))
	_ticks(sim, _ticks_of(params, "events.cholera.trigger_min") + 60)
	assert_false(_economy(sim).has("missions"))


func test_the_cut_leaves_the_district_fountains_without_water_but_not_wells_or_lea_bridge() -> void:
	var params: Params = _params()
	var fountains: Array[Dictionary] = [_at(FOUNTAIN, Vector2i(4, 2))]
	var sim: Simulation = _sim(params, _city(0, fountains))
	assert_eq(_water(sim, params), 1.0, "Before the warning the neutral source is safe")
	_start(sim)
	assert_eq(_water(sim, params), 0.0, "Old Ford cut: the fountains give nothing")
	var alternatives: Array[Dictionary] = [_at(LEA_BRIDGE, Vector2i(4, 2)), _at(WELL, Vector2i(0, 2))]
	var everything: Array[Dictionary] = []
	everything.append_array(fountains)
	everything.append_array(alternatives)
	var other: Simulation = _sim(params, _city(0, everything))
	_start(other)
	assert_gt(_water(other, params), 0.0)


# Three of five houses reach a Lea Bridge fountain: water_d is exactly the threshold, and the mission is met.
func test_water_exactly_at_the_threshold_completes() -> void:
	# 100 m reaches the three houses nearest to the fountain (71, 50 and 71 m) and not the other two (112 and 158 m).
	var params: Params = _params([Modifier.new(&"fountain.radius_m", &"set", 100.0)])
	var lea: Array[Dictionary] = [_at(LEA_BRIDGE, Vector2i(2, 2))]
	var state: EconomyState = _city(40, lea)
	var houses: Array[Dictionary] = []
	houses.assign(state.buildings.slice(0, HOUSE_CELLS.size()))
	assert_eq(WaterSystem.coverage(params, _context, houses, lea, WaterSystem.DEFAULT_SOURCE),
		_value(params, "mission.min_water_d"), "3 of 5 houses")
	var sim: Simulation = _sim(params, state)
	_start(sim)
	_run_to_close(sim, params)
	assert_eq(_status(sim), &"completed")
	assert_eq(_economy(sim)["population"], 40, "Nobody dies")


# A well whose risk leaves exactly the threshold completes; a hundredth of risk more fails.
func test_water_at_0_6_completes_and_at_0_59_fails() -> void:
	var threshold: float = _value(_params(), "mission.min_water_d")
	var cases: Array[Array] = [[1.0 - threshold, &"completed"], [1.0 - threshold + 0.01, &"failed"]]
	for case: Array in cases:
		var params: Params = _params([Modifier.new(&"well.source_risk", &"set", case[0])])
		var sim: Simulation = _sim(params, _city(40, [_at(WELL, WELL_CELL)], 1))
		_start(sim)
		_run_to_close(sim, params)
		assert_eq(_status(sim), case[1], str(case[0]))


func test_a_failed_district_with_zero_prep_loses_exactly_a_quarter() -> void:
	var params: Params = _params()
	var population: int = 80
	var sim: Simulation = _sim(params, _city(population))
	_start(sim)
	_run_to_close(sim, params)
	assert_eq(_status(sim), &"failed")
	var deaths: float = population * _value(params, "cholera.fail_mortality")
	assert_eq(deaths, 20.0, "With the default data a quarter of 80")
	assert_eq(_economy(sim)["population"], population - int(deaths))
	assert_eq(_economy(sim)["missions"][OLDFORD]["deaths"], int(deaths))


# prep = w_water x water_d (no sewer nor health yet): half the water spares half of w_water of the deaths.
func test_preparation_lowers_the_deaths() -> void:
	var risk: float = 0.5
	var params: Params = _params([Modifier.new(&"well.source_risk", &"set", risk)])
	var population: int = 80
	var sim: Simulation = _sim(params, _city(population, [_at(WELL, WELL_CELL)], 1))
	_start(sim)
	_run_to_close(sim, params)
	var prep: float = _value(params, "events.prep.w_water") * (1.0 - risk)
	var deaths: int = roundi(population * _value(params, "cholera.fail_mortality") * (1.0 - prep))
	assert_eq(_economy(sim)["population"], population - deaths)


func test_an_empty_district_that_fails_has_no_deaths() -> void:
	var params: Params = _params()
	var sim: Simulation = _sim(params, _city(0))
	_start(sim)
	_run_to_close(sim, params)
	assert_eq(_status(sim), &"failed")
	assert_eq(_economy(sim)["population"], 0)


func test_no_immigration_during_the_vacancy_then_faster_during_the_recovery() -> void:
	var params: Params = _params()
	var sim: Simulation = _sim(params, _city(80))
	_start(sim)
	_run_to_close(sim, params)
	var state: EconomyState = EconomyState.from_dict(sim.to_save()["economy"])
	var vacancy: int = _ticks_of(params, "cholera.vacancy_min")
	var recovery: int = _ticks_of(params, "cholera.recovery_min")
	var seen: Array[float] = []
	for index: int in range(vacancy + recovery + 1):
		seen.append(MissionSystem.immigration_multiplier(state, params))
		state = _after_tick(sim)
	assert_eq(seen.slice(0, vacancy), _repeat(0.0, vacancy))
	assert_eq(seen.slice(vacancy, vacancy + recovery), _repeat(_value(params, "cholera.recovery_mult"), recovery))
	assert_eq(seen[vacancy + recovery], 1.0)


func _after_tick(sim: Simulation) -> EconomyState:
	sim.tick()
	return EconomyState.from_dict(sim.to_save()["economy"])


static func _repeat(value: float, count: int) -> Array[float]:
	var values: Array[float] = []
	for index: int in range(count):
		values.append(value)
	return values


# The growth step reads that multiplier: with the room free and the class ready to grow, nobody arrives while the
# houses stand empty, and arrivals come recovery_mult times as fast afterwards.
func test_growth_follows_the_vacancy_and_the_recovery() -> void:
	var params: Params = _params()
	var state: EconomyState = _city(80)
	var entry: MissionState = MissionState.new()
	entry.status = MissionSystem.FAILED
	entry.vacancy_ticks = 1
	state.missions[OLDFORD] = entry
	assert_eq(MissionSystem.immigration_multiplier(state, params), 0.0)
	entry.vacancy_ticks = 0
	entry.recovery_ticks = 1
	assert_eq(MissionSystem.immigration_multiplier(state, params), _value(params, "cholera.recovery_mult"))
	entry.recovery_ticks = 0
	assert_eq(MissionSystem.immigration_multiplier(state, params), 1.0)


func test_even_failed_it_is_never_a_defeat_and_the_depopulation_waits() -> void:
	var params: Params = _defeats_on()
	var sim: Simulation = _sim(params, _city(80))
	_start(sim)
	_run_to_close(sim, params)
	assert_eq(_status(sim), &"failed")
	var aftermath: int = _ticks_of(params, "cholera.vacancy_min") + _ticks_of(params, "cholera.recovery_min")
	for index: int in range(aftermath):
		sim.tick()
		assert_eq(_economy(sim)["depopulation"]["elapsed_seconds"], 0, "Paused until the recovery ends")
	assert_eq(_economy(sim)["defeat_causes"], [])


func test_only_bankruptcy_still_defeats_during_the_mission() -> void:
	var params: Params = _defeats_on()
	var state: EconomyState = _city(80)
	state.money = int(params.get_value(&"defeat.bankruptcy.threshold")) - 1
	var sim: Simulation = _sim(params, state)
	_start(sim)
	_ticks(sim, _ticks_of(params, "mission.oldford.duration_min") + int(params.get_value(
		&"defeat.bankruptcy.duration_seconds")))
	assert_eq(_economy(sim)["defeat_causes"], [&"bankruptcy"])


func test_completing_leaves_old_ford_safe_and_abandoning_brings_it_back() -> void:
	var fountains: Array[Dictionary] = [_at(FOUNTAIN, Vector2i(4, 2))]
	var params: Params = _params()
	var both: Array[Dictionary] = [_at(FOUNTAIN, Vector2i(4, 2)), _at(LEA_BRIDGE, Vector2i(4, 2))]
	var safe: Simulation = _sim(params, _city(40, both))
	_start(safe)
	_run_to_close(safe, params)
	assert_eq(_status(safe), &"completed")
	assert_eq(WaterSystem.district_risk(EconomyState.from_dict(safe.to_save()["economy"]), params), 0.0)
	var left: Simulation = _sim(params, _city(40, fountains))
	_start(left)
	left.apply_command(MissionCommand.new(&"abandon", OLDFORD))
	left.tick()
	assert_eq(_status(left), &"abandoned")
	assert_eq(WaterSystem.district_risk(EconomyState.from_dict(left.to_save()["economy"]), params), 1.0)
	assert_eq(_water(left, params), 0.0, "Old Ford is back, with its full risk")
	assert_eq(_economy(left)["population"], 40, "Abandoning kills nobody")


func test_failing_leaves_old_ford_risky() -> void:
	var params: Params = _params()
	var sim: Simulation = _sim(params, _city(40, [_at(FOUNTAIN, Vector2i(4, 2))]))
	_start(sim)
	_run_to_close(sim, params)
	assert_eq(_status(sim), &"failed")
	assert_eq(WaterSystem.district_risk(EconomyState.from_dict(sim.to_save()["economy"]), params), 1.0)


# The same seed gives the same game, saved and loaded halfway through the mission or through the vacancy or not.
func test_same_seed_same_result_with_a_save_halfway() -> void:
	var params: Params = _params([Modifier.new(&"population.growth.immigration_per_minute", &"set", 6.0)])
	var duration: int = _ticks_of(params, "mission.oldford.duration_min")
	var total: int = _ticks_of(params, "events.cholera.trigger_min") + _ticks_of(params, "cholera.vacancy_min") \
		+ _ticks_of(params, "cholera.recovery_min") + 60
	var straight: Simulation = _sim(params, _city(80))
	_ticks(straight, total)
	for cut: int in [total - duration - 400, total - 300 - duration / 2, total - 200]:
		var first: Simulation = _sim(params, _city(80))
		_ticks(first, cut)
		var loaded: Simulation = Simulation.from_save(params, _context, [], first.to_save())
		_ticks(loaded, total - cut)
		assert_eq(loaded.to_save()["economy"], straight.to_save()["economy"], "Saved at tick %d" % cut)
	assert_has(_economy(straight)["missions"], OLDFORD)
