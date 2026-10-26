extends GutTest

# Issue #87, task 3 (D-120, D-122): each resolved incident of a district is a lesson for its attribute. The day of the
# cholera (the crisis of D-120, the only one that kills) each district works out
# severity = severity_base x (1 - health/100) x (1 - min(lessons x lesson_value, lesson_cap)) from its health
# attribute and its health lessons, and the severity multiplies cholera.fail_mortality in its houses only. The lessons
# last the chapter: a new game starts without them. With the incidents off there are none and the multiplier is 1.
# The map is the street of RoadTestMap split in two districts: West up to WEST_END street pieces, East after it.

const WIDTH: int = 24
const WEST_END: int = 12
const WEST: StringName = &"west"
const EAST: StringName = &"east"
const OLDFORD: StringName = &"oldford"
const HOUSE: StringName = &"housing"
const HEALTH_POST: StringName = &"health_post"
const HEALTH: StringName = ServiceSystem.HEALTH
const SAFETY: StringName = ServiceSystem.SAFETY
const POPULATION: int = 160
# Street pieces: a post at 1 reaches the houses at 2 and 3 but not the one at 11, nor anything in East.
const WEST_POST: int = 1
const WEST_HOUSES: Array[int] = [2, 3]
const WEST_FAR_HOUSE: int = 11
const EAST_HOUSES: Array[int] = [20, 21]
const SEED: int = 7
# A chance of an outbreak per tick and point of pressure, within its range, high enough for a few in minutes.
const OFTEN_K: float = 0.002

var _catalog: DataCatalog
var _context: EconomyContext
var _initial: EconomyState


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog


func before_each() -> void:
	_context = RoadTestMap.street(_catalog, WIDTH)
	var map: MapDef = _context.map
	for x: int in range(map.width):
		for y: int in range(map.height):
			map.district_by_cell[Vector2i(x, y)] = WEST if x < RoadTestMap.land(WEST_END + 1).x else EAST
	map.district_names[WEST] = "West"
	map.district_names[EAST] = "East"
	_initial = EconomyState.new()
	_initial.money = 100000
	_initial.population = POPULATION
	_initial.incidents_enabled = true


# Events on so the mission can run, defeats off; with `calm` no incident is ever drawn, so only the lessons a test
# gives the state count.
func _params(modifiers: Array[Modifier] = [], calm: bool = true) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.append(Modifier.new(&"events.enabled", &"set", 1.0))
	role.modifiers.append(Modifier.new(&"defeat.enabled", &"set", 0.0))
	if calm:
		for attribute: StringName in ServiceSystem.ATTRIBUTES:
			role.modifiers.append(Modifier.new(StringName("incident.%s.k" % attribute), &"set", 0))
	role.modifiers.append_array(modifiers)
	return SimTestParams.isolated_params(_catalog, role)


func _value(key: String) -> float:
	return float(_params().get_value(StringName(key)))


func _place(id: StringName, steps: int) -> void:
	var cell: Vector2i = RoadTestMap.land(steps)
	_initial.buildings.append({"definition_id": id, "cell": [cell.x, cell.y]})


func _houses(steps: Array[int]) -> void:
	for step: int in steps:
		_place(HOUSE, step)


func _lessons_given(district: StringName, count: int, attribute: StringName = HEALTH) -> void:
	_initial.incident_counts.get_or_add(district, {})[attribute] = {IncidentSystem.RESOLVED: count}


func _sim(params: Params = _params(), seed_value: int = SEED) -> Simulation:
	return Simulation.new(params, _initial, seed_value, _context)


static func _ticks(sim: Simulation, count: int) -> void:
	for index: int in range(count):
		sim.tick()


func _start(sim: Simulation) -> void:
	var command: MissionCommand = MissionCommand.new(&"start", OLDFORD)
	sim.apply_command(command)
	sim.tick()
	assert_true(command.accepted, str(command.reason))


# Starts the mission and runs it to its close, the day of the crisis.
func _crisis(sim: Simulation) -> void:
	_start(sim)
	_ticks(sim, SimTime.minutes_to_ticks(_value("mission.oldford.duration_min")) - 1)
	assert_eq(StringName(sim.snapshot()["economy"]["missions"][OLDFORD]["status"]), MissionSystem.FAILED)


func _district(sim: Simulation, district: StringName) -> Dictionary:
	return sim.snapshot()["incidents"]["districts"][district]


func _lessons(sim: Simulation, district: StringName, attribute: StringName = HEALTH) -> int:
	return int(_district(sim, district)[attribute]["lessons"])


func _severity(sim: Simulation, district: StringName) -> float:
	return float(_district(sim, district)["crisis"]["severity"])


func _deaths(sim: Simulation, district: StringName) -> int:
	return int(_district(sim, district)["crisis"]["deaths"])


func _health(sim: Simulation, district: StringName) -> float:
	return float(sim.snapshot()["services"]["districts"][district][HEALTH])


# Today's deaths of a failing district with no water (prep 0): its share of the people times fail_mortality.
func _plain_deaths(share: float, severity: float = 1.0) -> int:
	return roundi(POPULATION * share * _value("cholera.fail_mortality") * severity)


func _expected(health: float, lessons: int) -> float:
	return _value("incident.lessons.severity_base") * (1.0 - health / 100.0) \
		* (1.0 - minf(lessons * _value("incident.lessons.lesson_value"), _value("incident.lessons.lesson_cap")))


# Criterion 1.
func test_with_health_at_100_the_severity_is_0_and_nobody_dies_there() -> void:
	_place(HEALTH_POST, WEST_POST)
	_houses(WEST_HOUSES)
	_houses(EAST_HOUSES)
	var sim: Simulation = _sim()
	_crisis(sim)
	assert_eq(_health(sim, WEST), 100.0, "The post reaches both West houses")
	assert_eq(_severity(sim, WEST), 0.0)
	assert_eq(_deaths(sim, WEST), 0)
	assert_eq(_deaths(sim, EAST), _plain_deaths(0.5, _value("incident.lessons.severity_base")))


func test_with_health_at_0_and_no_lessons_the_severity_is_the_base() -> void:
	_houses(WEST_HOUSES)
	_houses(EAST_HOUSES)
	var sim: Simulation = _sim()
	_crisis(sim)
	assert_eq(_health(sim, WEST), 0.0)
	assert_eq(_severity(sim, WEST), _value("incident.lessons.severity_base"))
	assert_eq(_deaths(sim, WEST), _plain_deaths(0.5, _value("incident.lessons.severity_base")))


func test_the_health_attribute_and_the_lessons_multiply() -> void:
	_place(HEALTH_POST, WEST_POST)
	_houses(WEST_HOUSES)
	_place(HOUSE, WEST_FAR_HOUSE)
	_place(HOUSE, WEST_FAR_HOUSE - 1)
	_houses(EAST_HOUSES)
	_lessons_given(WEST, 2)
	var sim: Simulation = _sim()
	_crisis(sim)
	assert_eq(_health(sim, WEST), 50.0, "The post reaches two of the four West houses")
	assert_almost_eq(_severity(sim, WEST), _expected(50.0, 2), 0.0001)
	assert_eq(_deaths(sim, WEST), _plain_deaths(4.0 / 6.0, _expected(50.0, 2)))


# Criterion 2: a resolved incident is a lesson for its district and its attribute; an unresolved one is not.
func test_a_resolved_incident_is_a_lesson_and_an_unresolved_one_is_not() -> void:
	_place(HEALTH_POST, WEST_POST)
	_houses(WEST_HOUSES)
	_houses(EAST_HOUSES)
	var top: float = _value("incident.health.pressure_max")
	for district: StringName in [WEST, EAST]:
		_initial.incident_pressure[district] = {HEALTH: top}
	var sim: Simulation = _sim(_params([Modifier.new(&"incident.health.k", &"set", 1.0 / top)]))
	sim.tick()
	var west: Dictionary = _district(sim, WEST)[HEALTH]
	var east: Dictionary = _district(sim, EAST)[HEALTH]
	assert_eq(int(west[IncidentSystem.RESOLVED]), 1)
	assert_eq(int(west["lessons"]), 1)
	assert_eq(int(east[IncidentSystem.UNRESOLVED]), 1)
	assert_eq(int(east["lessons"]), 0)
	assert_eq(_lessons(sim, WEST, SAFETY), 0, "A health incident teaches nothing about safety")


func test_only_the_health_lessons_lower_the_cholera() -> void:
	_houses(WEST_HOUSES)
	_houses(EAST_HOUSES)
	_lessons_given(WEST, 3, SAFETY)
	var sim: Simulation = _sim()
	_crisis(sim)
	assert_eq(_lessons(sim, WEST, SAFETY), 3)
	assert_eq(_severity(sim, WEST), _value("incident.lessons.severity_base"))


# Criterion 3.
func test_the_lessons_never_take_off_more_than_the_cap() -> void:
	_houses(WEST_HOUSES)
	_houses(EAST_HOUSES)
	var many: int = ceili(_value("incident.lessons.lesson_cap") / _value("incident.lessons.lesson_value")) + 5
	_lessons_given(WEST, many)
	var sim: Simulation = _sim()
	_crisis(sim)
	assert_gt(many * _value("incident.lessons.lesson_value"), _value("incident.lessons.lesson_cap"))
	assert_almost_eq(_severity(sim, WEST),
		_value("incident.lessons.severity_base") * (1.0 - _value("incident.lessons.lesson_cap")), 0.0001)


# Criterion 4: the same attribute and different lessons give different severities, and a district left alone keeps
# its own severity beside a good one.
func test_two_districts_with_the_same_attribute_and_different_lessons_differ() -> void:
	_houses(WEST_HOUSES)
	_houses(EAST_HOUSES)
	_lessons_given(WEST, 3)
	var sim: Simulation = _sim()
	_crisis(sim)
	assert_eq(_health(sim, WEST), _health(sim, EAST))
	assert_almost_eq(_severity(sim, WEST), _expected(0.0, 3), 0.0001)
	assert_eq(_severity(sim, EAST), _value("incident.lessons.severity_base"))
	assert_lt(_deaths(sim, WEST), _deaths(sim, EAST))


func test_an_abandoned_district_is_not_covered_by_a_good_one() -> void:
	_place(HEALTH_POST, WEST_POST)
	_houses(WEST_HOUSES)
	_houses(EAST_HOUSES)
	_lessons_given(WEST, 5)
	var sim: Simulation = _sim()
	_crisis(sim)
	assert_eq(_deaths(sim, WEST), 0)
	assert_eq(_severity(sim, EAST), _value("incident.lessons.severity_base"))
	assert_eq(_deaths(sim, EAST), _plain_deaths(0.5, _value("incident.lessons.severity_base")))
	assert_eq(int(sim.snapshot()["economy"]["missions"][OLDFORD]["deaths"]), _deaths(sim, EAST))


# Criterion 5: the lessons last the chapter. A chapter starts as a new game, so whatever state it is given, it starts
# without lessons.
func test_a_new_chapter_starts_without_lessons() -> void:
	_houses(WEST_HOUSES)
	_lessons_given(WEST, 4)
	_lessons_given(EAST, 2, SAFETY)
	var played: Simulation = _sim()
	assert_eq(_lessons(played, WEST), 4)
	var next: EconomyState = EconomyState.from_dict(played.to_save()["economy"])
	var chapter: Simulation = Simulation.create_new(_params(), next, SEED, _context)
	for district: StringName in [WEST, EAST]:
		for attribute: StringName in ServiceSystem.ATTRIBUTES:
			assert_eq(_lessons(chapter, district, attribute), 0, "%s %s" % [district, attribute])


# Criterion 6: a save keeps the lessons, and the crisis then gives the same severity as a game that went on.
func test_a_saved_game_keeps_the_lessons_and_the_same_severity() -> void:
	_place(HEALTH_POST, WEST_POST)
	_houses(WEST_HOUSES)
	_place(HOUSE, WEST_FAR_HOUSE)
	_houses(EAST_HOUSES)
	# Only outbreaks, often enough that ten minutes bring a few.
	var params: Params = _params([Modifier.new(&"incident.health.k", &"set", OFTEN_K)])
	var sim: Simulation = _sim(params)
	_ticks(sim, SimTime.minutes_to_ticks(10.0))
	assert_gt(_lessons(sim, WEST), 0, "Ten minutes bring some resolved outbreaks in West")
	var loaded: Simulation = Simulation.from_save(params, _context, [], sim.to_save())
	assert_eq(_lessons(loaded, WEST), _lessons(sim, WEST))
	_crisis(sim)
	_crisis(loaded)
	assert_eq(_lessons(loaded, WEST), _lessons(sim, WEST))
	for district: StringName in [WEST, EAST]:
		assert_eq(_severity(loaded, district), _severity(sim, district), str(district))
		assert_eq(_deaths(loaded, district), _deaths(sim, district), str(district))
	var reloaded: Simulation = Simulation.from_save(params, _context, [], sim.to_save())
	assert_eq(_district(reloaded, WEST)["crisis"], _district(sim, WEST)["crisis"], "The severity it had is saved")


# D-122: with the incidents off there are no lessons and the multiplier is 1, so the cholera kills as before.
func test_with_the_incidents_off_the_cholera_kills_as_before() -> void:
	_initial.incidents_enabled = false
	_place(HEALTH_POST, WEST_POST)
	_houses(WEST_HOUSES)
	_houses(EAST_HOUSES)
	var sim: Simulation = _sim(_params([], false))
	_crisis(sim)
	var economy: Dictionary = sim.snapshot()["economy"]
	assert_eq(int(economy["missions"][OLDFORD]["deaths"]), 2 * _plain_deaths(0.5))
	assert_false(economy["missions"][OLDFORD].has("districts"), "Nothing new is saved")
	assert_eq(IncidentSystem.severity(EconomyState.from_dict(economy), _params(), WEST, 100.0), 1.0)
