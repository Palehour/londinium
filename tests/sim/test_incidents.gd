extends GutTest

# Issue #87, task 2 (D-119, D-121, D-122): each district gathers a pressure by attribute from (100 - attribute) x
# pressure_rate and the causes of the data, and every tick draws pressure x k for a small incident. A covered house's
# service pays for it; an uncovered one loses satisfaction. An outbreak makes the house sick (D-109). The map is the
# street of RoadTestMap, one district: every building on the land row touches it.

const WIDTH: int = 12
const HOUSE: StringName = &"housing"
const FIRE: StringName = &"fire_station"
const HEALTH_POST: StringName = &"health_post"
const POLICE: StringName = &"police_station"
const TAVERN: StringName = &"brewery"
const DISTRICT: StringName = WaterSystem.DEFAULT_DISTRICT
const SAFETY: StringName = ServiceSystem.SAFETY
const HEALTH: StringName = ServiceSystem.HEALTH
const ORDER: StringName = ServiceSystem.ORDER
const SEED: int = 7

var _catalog: DataCatalog
var _context: EconomyContext
var _initial: EconomyState


func before_all() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog


func before_each() -> void:
	_context = RoadTestMap.street(_catalog, WIDTH)
	_initial = EconomyState.new()
	_initial.money = 100000
	_initial.stocks.assign({&"wheat": 0, &"flour": 0, &"bread": 0})
	_initial.incidents_enabled = true


# Defeats off: an empty test city would lose within minutes and stop ticking.
func _params(modifiers: Array[Modifier] = []) -> Params:
	var role: RoleDef = RoleDef.new()
	role.modifiers.assign(modifiers)
	role.modifiers.append(Modifier.new(&"defeat.enabled", &"set", 0.0))
	return SimTestParams.isolated_params(_catalog, role)


func _key(attribute: StringName, field: String) -> StringName:
	return StringName("incident.%s.%s" % [attribute, field])


func _value(attribute: StringName, field: String) -> float:
	return float(_params().get_value(_key(attribute, field)))


# No incident ever: only the pressure moves.
func _calm() -> Array[Modifier]:
	var modifiers: Array[Modifier] = []
	for attribute: StringName in ServiceSystem.ATTRIBUTES:
		modifiers.append(Modifier.new(_key(attribute, "k"), &"set", 0))
	return modifiers


# Only `attribute` can strike, and at its top pressure it does on the first tick (top x k = 1).
func _certain(attribute: StringName) -> Array[Modifier]:
	var modifiers: Array[Modifier] = []
	for other: StringName in ServiceSystem.ATTRIBUTES:
		if other != attribute:
			modifiers.append(Modifier.new(_key(other, "k"), &"set", 0))
	modifiers.append(Modifier.new(_key(attribute, "k"), &"set", 1.0 / _value(attribute, "pressure_max")))
	_initial.incident_pressure[DISTRICT] = {attribute: _value(attribute, "pressure_max")}
	return modifiers


func _place(id: StringName, steps: int) -> void:
	var cell: Vector2i = RoadTestMap.land(steps)
	_initial.buildings.append({"definition_id": id, "cell": [cell.x, cell.y]})


func _sim(modifiers: Array[Modifier] = [], seed_value: int = SEED) -> Simulation:
	return Simulation.new(_params(modifiers), _initial, seed_value, _context)


func _ticks(sim: Simulation, count: int) -> void:
	for i: int in range(count):
		sim.tick()


func _entry(sim: Simulation, attribute: StringName) -> Dictionary:
	return sim.snapshot()["incidents"]["districts"][DISTRICT][attribute]


func _pressure(sim: Simulation, attribute: StringName) -> float:
	return float(_entry(sim, attribute)["pressure"])


func _incidents(sim: Simulation) -> int:
	var district: Dictionary = sim.snapshot()["incidents"]["districts"][DISTRICT]
	var total: int = 0
	for attribute: StringName in ServiceSystem.ATTRIBUTES:
		total += int(district[attribute]["resolved"]) + int(district[attribute]["unresolved"])
	return total


func _availability(sim: Simulation, steps: int) -> float:
	for service: Dictionary in sim.snapshot()["services"]["buildings"]:
		if service["cell"] == RoadTestMap.at(Vector2i(steps - 1, RoadTestMap.LAND_ROW)):
			return float(service["availability"])
	return -1.0


func _sick(sim: Simulation, steps: int) -> bool:
	for building: Dictionary in sim.snapshot()["economy"]["buildings"]:
		if building["cell"] == RoadTestMap.at(Vector2i(steps - 1, RoadTestMap.LAND_ROW)):
			return building.get(CrisisSystem.SICK, false)
	return false


func test_switched_off_there_is_no_pressure_and_no_draw() -> void:
	_initial.incidents_enabled = false
	_place(HOUSE, 2)
	var sim: Simulation = _sim()
	_ticks(sim, SimTime.TICKS_PER_MINUTE * 10)
	assert_false(sim.snapshot()["incidents"]["enabled"])
	assert_false(sim.snapshot()["economy"].has("incident_pressure"), "The pressure stays at 0")
	assert_false(sim.to_save().has("incident_rng_state"), "Nothing was drawn, and the save is as before")
	assert_false(_sick(sim, 2))


func test_with_every_attribute_at_100_and_no_cause_the_pressure_stays_at_0() -> void:
	_place(FIRE, 1)
	_place(HEALTH_POST, 2)
	_place(POLICE, 3)
	_place(HOUSE, 4)
	var sim: Simulation = _sim()
	_ticks(sim, SimTime.TICKS_PER_MINUTE * 10)
	for attribute: StringName in ServiceSystem.ATTRIBUTES:
		assert_eq(_pressure(sim, attribute), 0.0, attribute)
	assert_eq(_incidents(sim), 0)


func test_the_pressure_gains_the_missing_attribute_times_pressure_rate_a_minute() -> void:
	_place(HOUSE, 2)
	var sim: Simulation = _sim(_calm())
	_ticks(sim, SimTime.TICKS_PER_MINUTE)
	for attribute: StringName in ServiceSystem.ATTRIBUTES:
		assert_almost_eq(_pressure(sim, attribute), 100.0 * _value(attribute, "pressure_rate"), 0.0001, attribute)


func test_the_pressure_stops_at_its_top() -> void:
	_place(HOUSE, 2)
	var modifiers: Array[Modifier] = _calm()
	modifiers.append(Modifier.new(_key(SAFETY, "pressure_rate"), &"set", 10))
	var sim: Simulation = _sim(modifiers)
	_ticks(sim, SimTime.TICKS_PER_MINUTE)
	assert_eq(_pressure(sim, SAFETY), _value(SAFETY, "pressure_max"))


func test_each_tavern_of_the_district_raises_the_order_pressure_by_its_rate() -> void:
	_place(POLICE, 1)
	_place(HOUSE, 2)
	_place(TAVERN, 3)
	_place(TAVERN, 4)
	var sim: Simulation = _sim(_calm())
	_ticks(sim, SimTime.TICKS_PER_MINUTE)
	assert_almost_eq(_pressure(sim, ORDER), 2.0 * _value(ORDER, "cause.taverns"), 0.0001)


func test_each_sick_house_of_the_district_raises_the_health_pressure_by_its_rate() -> void:
	_place(HEALTH_POST, 1)
	_place(HOUSE, 2)
	_place(HOUSE, 3)
	var sim: Simulation = _sim(_calm())
	sim.mark_house_sick(RoadTestMap.land(2))
	sim.mark_house_sick(RoadTestMap.land(3))
	_ticks(sim, SimTime.TICKS_PER_MINUTE)
	assert_almost_eq(_pressure(sim, HEALTH), 2.0 * _value(HEALTH, "cause.sick_houses"), 0.0001)


func test_overcrowding_raises_the_pressure_by_its_rate_times_the_share_without_room() -> void:
	_place(FIRE, 1)
	_place(HOUSE, 2)
	# Twice the room of the house: half the people have none.
	_initial.population = 2 * int(_params().get_value(&"building.housing.capacity"))
	var sim: Simulation = _sim(_calm())
	_ticks(sim, SimTime.TICKS_PER_MINUTE)
	var share: float = float(sim.snapshot()["economy"]["overcrowding"])
	assert_almost_eq(share, 0.5, 0.0001)
	assert_almost_eq(_pressure(sim, SAFETY), share * _value(SAFETY, "cause.overcrowding"), 0.0001)


func test_the_same_seed_and_state_give_the_same_incidents_on_the_same_ticks() -> void:
	_place(HOUSE, 2)
	_place(HOUSE, 3)
	var first: Simulation = _sim()
	var second: Simulation = _sim()
	var seen: Array[int] = []
	for tick: int in range(SimTime.TICKS_PER_MINUTE * 30):
		first.tick()
		second.tick()
		var count: int = _incidents(first)
		assert_eq(_incidents(second), count, "tick %d" % tick)
		if seen.size() < count:
			seen.append(tick)
	assert_gt(seen.size(), 0, "30 minutes without any service bring some incidents")
	assert_eq(second.snapshot()["economy"], first.snapshot()["economy"])


func test_a_saved_game_draws_the_same_incidents_as_one_that_went_on() -> void:
	_place(HOUSE, 2)
	_place(HOUSE, 3)
	var sim: Simulation = _sim()
	_ticks(sim, SimTime.TICKS_PER_MINUTE * 10)
	var loaded: Simulation = Simulation.from_save(_params(), _context, [], sim.to_save())
	_ticks(sim, SimTime.TICKS_PER_MINUTE * 20)
	_ticks(loaded, SimTime.TICKS_PER_MINUTE * 20)
	assert_gt(_incidents(sim), 0)
	assert_eq(loaded.snapshot()["incidents"], sim.snapshot()["incidents"])


func test_a_resolved_incident_lowers_the_pressure_and_spends_the_service() -> void:
	_place(FIRE, 1)
	_place(HOUSE, 2)
	var sim: Simulation = _sim(_certain(SAFETY))
	sim.tick()
	assert_eq(int(_entry(sim, SAFETY)["resolved"]), 1)
	assert_almost_eq(_pressure(sim, SAFETY), _value(SAFETY, "pressure_max") - _value(SAFETY, "pressure_drop"), 0.0001)
	assert_almost_eq(_availability(sim, 1), float(_params().get_value(&"service.fire_station.availability_max"))
		- _value(SAFETY, "consume_amount"), 0.0001)
	assert_false(sim.snapshot()["economy"]["satisfaction_breakdown"].has("incidents"))


func test_an_unresolved_incident_takes_satisfaction_from_its_house_for_unresolved_min() -> void:
	_place(HOUSE, 2)
	_place(HOUSE, 3)
	var sim: Simulation = _sim(_certain(SAFETY))
	sim.tick()
	assert_eq(int(_entry(sim, SAFETY)["unresolved"]), 1)
	# One of the class's two houses carries it.
	var breakdown: Dictionary = sim.snapshot()["economy"]["satisfaction_breakdown"]
	assert_almost_eq(float(breakdown["incidents"]), _value(SAFETY, "unresolved_penalty") / 2.0, 0.0001)
	# The pressure is still high, so the next ones may strike: take k away to watch the first one run out.
	var calm: Simulation = Simulation.from_save(_params(_calm()), _context, [], sim.to_save())
	_ticks(calm, SimTime.minutes_to_ticks(_value(SAFETY, "unresolved_min")) - 1)
	assert_true(calm.snapshot()["economy"]["satisfaction_breakdown"].has("incidents"))
	calm.tick()
	assert_false(calm.snapshot()["economy"]["satisfaction_breakdown"].has("incidents"))


func test_an_outbreak_makes_the_house_sick_and_the_post_inspects_it_within_its_street_radius() -> void:
	_place(HEALTH_POST, 1)
	_place(HOUSE, 2)
	var sim: Simulation = _sim(_certain(HEALTH))
	sim.tick()
	assert_eq(int(_entry(sim, HEALTH)["resolved"]), 1)
	assert_true(_sick(sim, 2))
	var crisis: Dictionary = sim.snapshot()["crisis"]
	assert_true(crisis["active"], "D-109: the crisis is on while a house is sick")
	assert_eq(StringName(crisis["houses"][0]["lock"]), CrisisSystem.HOUSE_SICK)
	assert_eq(StringName(crisis["houses"][0]["disinfect"]), &"", "Within service_radius_m along the street (D-121)")


func test_an_outbreak_beyond_the_post_street_radius_cannot_be_disinfected() -> void:
	var steps: int = int(_params().get_value(&"building.health_post.service_radius_m")) \
		/ RoadSystem.metres(_params(), _context, 1) + 1
	_place(HEALTH_POST, 1)
	_place(HOUSE, steps)
	var sim: Simulation = _sim(_certain(HEALTH))
	sim.tick()
	assert_eq(int(_entry(sim, HEALTH)["unresolved"]), 1)
	assert_true(_sick(sim, steps))
	assert_eq(StringName(sim.snapshot()["crisis"]["houses"][0]["disinfect"]), CrisisSystem.OUTSIDE_POST)


func test_the_warning_shows_from_the_threshold_and_goes_when_the_pressure_drops() -> void:
	_place(HOUSE, 2)
	var sim: Simulation = _sim(_calm())
	var threshold: float = _value(SAFETY, "warning_threshold")
	var shown: bool = false
	for tick: int in range(SimTime.TICKS_PER_MINUTE * 15):
		sim.tick()
		var entry: Dictionary = _entry(sim, SAFETY)
		assert_eq(bool(entry["warning"]), float(entry["pressure"]) >= threshold, "tick %d" % tick)
		shown = shown or bool(entry["warning"])
	assert_true(shown)
	# An incident takes it below the threshold again.
	_initial.incident_pressure[DISTRICT] = {}
	var modifiers: Array[Modifier] = _certain(SAFETY)
	modifiers.append(Modifier.new(_key(SAFETY, "pressure_drop"), &"set", _value(SAFETY, "pressure_max") - threshold + 1))
	var striking: Simulation = _sim(modifiers)
	assert_true(bool(_entry(striking, SAFETY)["warning"]))
	striking.tick()
	assert_false(bool(_entry(striking, SAFETY)["warning"]))
