class_name IncidentSystem
extends RefCounted

# Small incidents (issue #87, D-119, after D-118): each district gathers a pressure for each attribute, from 0 to
# pressure_max. It gains (100 - attribute) x pressure_rate a minute, plus each cause of the data times its units in the
# district. Every tick draws p = pressure x k with the simulation's seeded generator: a fire, an outbreak or a riot
# strikes one of the district's houses, takes pressure_drop off the pressure and spends consume_amount of the service
# that covers that house. Without one the incident goes unresolved and the house loses unresolved_penalty of
# satisfaction for unresolved_min. An outbreak makes the house sick (D-109). The district warns from warning_threshold.
# Only with the incidents switched on (D-122): off, the pressure stays at 0 and nothing is drawn.
# Each resolved incident is a lesson for its district and attribute (D-120, task 3). The day of the cholera the health
# lessons and the health attribute set each district's severity, which multiplies the deaths in its houses; with the
# incidents off it is 1. The lessons are the resolved incidents of this game, so they last the chapter.

# What raises the pressure, by the id the data gives it: the share of the district's residents without room (0 to 1),
# its taverns, and its sick houses (D-109).
const OVERCROWDING: StringName = &"overcrowding"
const TAVERNS: StringName = &"taverns"
const SICK_HOUSES: StringName = &"sick_houses"
const CAUSES: Array[StringName] = [OVERCROWDING, TAVERNS, SICK_HOUSES]
const TAVERN_TAG: String = "tavern"
const RESOLVED: String = "resolved"
const UNRESOLVED: String = "unresolved"
# Fields of a house's dictionary: the seconds left of the satisfaction an unresolved incident took from it, and the
# attribute of that incident, whose data says how much it takes. A new one starts the term again.
const PENALTY: String = "incident_penalty_ticks"
const PENALTY_ATTRIBUTE: String = "incident_penalty_attribute"


# Districts and attributes in the map's order and the order of ATTRIBUTES, so the same state draws the same numbers.
static func tick(state: EconomyState, params: Params, context: EconomyContext, rng: RandomNumberGenerator) -> void:
	if not state.incidents_enabled:
		return
	_count_down(state)
	var districts: Dictionary[StringName, Dictionary] = ServiceSystem.district_values(state, params, context)
	for district: StringName in districts:
		var houses: Array[Dictionary] = []
		for entry: Dictionary in districts[district]["houses"]:
			houses.append(entry["house"])
		# A district without houses has no one to strike: its pressure waits as it is.
		if houses.is_empty():
			continue
		for attribute: StringName in ServiceSystem.ATTRIBUTES:
			var raised: float = _raise(state, params, context, district, attribute, houses,
				float(districts[district]["attributes"][attribute]))
			# No draw at all without pressure, so a calm district leaves the generator where it was.
			var chance: float = minf(1.0, raised * float(params.get_value(_key(attribute, "k"))))
			if chance > 0.0 and rng.randf() < chance:
				_strike(state, params, context, district, attribute, houses[rng.randi_range(0, houses.size() - 1)])


static func pressure(state: EconomyState, district: StringName, attribute: StringName) -> float:
	return float(state.incident_pressure.get(district, {}).get(attribute, 0.0))


static func lessons(state: EconomyState, district: StringName, attribute: StringName) -> int:
	return int(state.incident_counts.get(district, {}).get(attribute, {}).get(RESOLVED, 0))


# severity_base x (1 - health / 100) x (1 - min(lessons x lesson_value, lesson_cap)) of D-120; 1 with the incidents
# off, so the crisis kills as it did before them (D-122).
static func severity(state: EconomyState, params: Params, district: StringName, health: float) -> float:
	if not state.incidents_enabled:
		return 1.0
	var learned: float = minf(lessons(state, district, ServiceSystem.HEALTH)
		* float(params.get_value(&"incident.lessons.lesson_value")), float(params.get_value(&"incident.lessons.lesson_cap")))
	return float(params.get_value(&"incident.lessons.severity_base")) * (1.0 - clampf(health, 0.0, 100.0) / 100.0) \
		* (1.0 - learned)


# The pressure each cause adds a minute in the district, with the data's rate per unit.
static func cause_rate(state: EconomyState, params: Params, context: EconomyContext, attribute: StringName,
		houses: Array[Dictionary]) -> float:
	var rate: float = 0.0
	for cause: StringName in CAUSES:
		var key: StringName = StringName("incident.%s.cause.%s" % [attribute, cause])
		if params.has_value(key):
			rate += float(params.get_value(key)) * _units(state, context, cause, houses)
	return rate


# The satisfaction an unresolved incident takes from a class: the penalty times the share of its houses that carry it.
static func class_penalty(state: EconomyState, params: Params, context: EconomyContext, def: ClassDef) -> float:
	if not state.incidents_enabled:
		return 0.0
	var houses: int = 0
	var penalty: float = 0.0
	for building: Dictionary in state.buildings:
		if not _belongs_to(context, building, def):
			continue
		houses += 1
		if int(building.get(PENALTY, 0)) > 0:
			penalty += float(params.get_value(_key(StringName(building[PENALTY_ATTRIBUTE]), "unresolved_penalty")))
	return penalty / houses if houses > 0 else 0.0


# For the views and the tests: each district's pressure, whether it warns, its incidents and its lessons, by
# attribute, and once the cholera has come the severity and deaths it had there under "crisis".
static func snapshot(state: EconomyState, params: Params, context: EconomyContext) -> Dictionary:
	var districts: Dictionary = {}
	if context == null or not state.incidents_enabled:
		return {"enabled": false, "districts": districts}
	for district: StringName in WaterSystem.districts(context):
		var entry: Dictionary = {}
		for attribute: StringName in ServiceSystem.ATTRIBUTES:
			var value: float = pressure(state, district, attribute)
			var counts: Dictionary = state.incident_counts.get(district, {}).get(attribute, {})
			entry[attribute] = {"pressure": value,
				"warning": value >= float(params.get_value(_key(attribute, "warning_threshold"))),
				RESOLVED: int(counts.get(RESOLVED, 0)), UNRESOLVED: int(counts.get(UNRESOLVED, 0)),
				"lessons": lessons(state, district, attribute)}
		for mission: MissionState in state.missions.values():
			if mission.districts.has(district):
				entry["crisis"] = mission.districts[district].duplicate()
		districts[district] = entry
	return {"enabled": true, "districts": districts}


static func _raise(state: EconomyState, params: Params, context: EconomyContext, district: StringName,
		attribute: StringName, houses: Array[Dictionary], value: float) -> float:
	var per_minute: float = (100.0 - value) * float(params.get_value(_key(attribute, "pressure_rate"))) \
		+ cause_rate(state, params, context, attribute, houses)
	var raised: float = clampf(pressure(state, district, attribute) + per_minute / SimTime.TICKS_PER_MINUTE, 0.0,
		float(params.get_value(_key(attribute, "pressure_max"))))
	_set_pressure(state, district, attribute, raised)
	return raised


static func _strike(state: EconomyState, params: Params, context: EconomyContext, district: StringName,
		attribute: StringName, house: Dictionary) -> void:
	_set_pressure(state, district, attribute,
		maxf(0.0, pressure(state, district, attribute) - float(params.get_value(_key(attribute, "pressure_drop")))))
	var service: Dictionary = ServiceSystem.best_service(state, params, context, house, attribute)
	var outcome: String = RESOLVED
	if service.is_empty():
		outcome = UNRESOLVED
		house[PENALTY] = SimTime.minutes_to_ticks(float(params.get_value(_key(attribute, "unresolved_min"))))
		house[PENALTY_ATTRIBUTE] = String(attribute)
	else:
		ServiceSystem.consume(params, context, service, float(params.get_value(_key(attribute, "consume_amount"))))
	var counts: Dictionary = state.incident_counts.get_or_add(district, {}).get_or_add(attribute, {})
	counts[outcome] = int(counts.get(outcome, 0)) + 1
	if attribute == ServiceSystem.HEALTH:
		CrisisSystem.mark_sick(state, params, context, house)


static func _units(state: EconomyState, context: EconomyContext, cause: StringName, houses: Array[Dictionary]) -> float:
	match cause:
		OVERCROWDING:
			var total: float = 0.0
			for house: Dictionary in houses:
				total += _overcrowding(state, context, house)
			return total / houses.size()
		TAVERNS:
			var district: StringName = _district_of(context, houses[0])
			return float(state.buildings.filter(func(building: Dictionary) -> bool:
				var definition: BuildingDef = context.buildings.get(StringName(building["definition_id"]))
				return definition != null and TAVERN_TAG in definition.tags and building.has("cell") \
					and _district_of(context, building) == district).size())
		SICK_HOUSES:
			return float(houses.filter(func(house: Dictionary) -> bool: return house.get(CrisisSystem.SICK, false)).size())
	return 0.0


# The share of the residents of the house's class without room, the overcrowding of SatisfactionSystem.
static func _overcrowding(state: EconomyState, context: EconomyContext, house: Dictionary) -> float:
	for def: ClassDef in ClassStates.defs(context):
		if not _belongs_to(context, house, def):
			continue
		if def.base:
			return state.overcrowding
		return state.class_states[def.id].overcrowding if state.class_states.has(def.id) else 0.0
	return 0.0


# A house of the class: its own housing, and for the base class any housing no class claims (RoadSystem does the same).
static func _belongs_to(context: EconomyContext, building: Dictionary, def: ClassDef) -> bool:
	var definition: BuildingDef = context.buildings.get(StringName(building["definition_id"]))
	if definition == null or WaterSystem.HOUSING_TAG not in definition.tags:
		return false
	var owner: StringName = context.class_of_housing(definition.id)
	return owner == def.id or (def.base and owner == &"")


static func _district_of(context: EconomyContext, building: Dictionary) -> StringName:
	return context.map.district_by_cell.get(RoadNetwork.cell_of(building), WaterSystem.DEFAULT_DISTRICT)


# The penalties of unresolved incidents run out one second at a time.
static func _count_down(state: EconomyState) -> void:
	for building: Dictionary in state.buildings:
		if not building.has(PENALTY):
			continue
		building[PENALTY] = int(building[PENALTY]) - 1
		if int(building[PENALTY]) <= 0:
			building.erase(PENALTY)
			building.erase(PENALTY_ATTRIBUTE)


static func _set_pressure(state: EconomyState, district: StringName, attribute: StringName, value: float) -> void:
	state.incident_pressure.get_or_add(district, {})[attribute] = value


static func _key(attribute: StringName, field: String) -> StringName:
	return StringName("incident.%s.%s" % [attribute, field])
