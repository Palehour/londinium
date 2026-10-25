class_name CrisisSystem
extends RefCounted

# Houses in a crisis (issue #222, D-104 to D-108). Only health exists (D-105): a crisis is active while a house has
# sick people. A sick house is never demolished during the crisis (D-106); within the health post's radius it can be
# disinfected for crisis.health.response_cost, which frees it once done (D-104). The houses exposed to it wait out a
# preventive quarantine, shorter within the radius, once per crisis: a new case does not restart it (D-107). When the
# crisis ends every lock goes and an unfinished disinfection is paid back.
# The outbreaks of #87 (IncidentSystem, D-119) make a house sick through mark_sick(); cure() is for the tests (D-109).
# The state lives on the house's own dictionary, so it is saved with it and goes when the house does.

const HEALTH: StringName = &"health"
const TYPES: Array[StringName] = [HEALTH]
const POST_TAG: String = "health"
# Why a house cannot be demolished, or disinfected.
const HOUSE_SICK: StringName = &"house_sick"
const HOUSE_QUARANTINE: StringName = &"house_quarantine"
const NOT_SICK: StringName = &"house_not_sick"
const OUTSIDE_POST: StringName = &"outside_health_post"
const DISINFECTION_RUNNING: StringName = &"disinfection_running"
# Fields of the house's dictionary. A quarantine of 0 has been served: the house is free for the rest of the crisis.
const SICK: String = "sick"
const QUARANTINE: String = "quarantine_ticks"
const DISINFECTION: String = "disinfection_ticks"
const DISINFECTION_PAID: String = "disinfection_paid"


# The one check before a house is demolished (or moved, once it can be): &"" when it is free.
static func lock_reason(building: Dictionary) -> StringName:
	if building.get(SICK, false):
		return HOUSE_SICK
	if int(building.get(QUARANTINE, 0)) > 0:
		return HOUSE_QUARANTINE
	return &""


static func active(state: EconomyState) -> bool:
	return state.buildings.any(func(building: Dictionary) -> bool: return building.get(SICK, false))


# The house falls sick: its quarantine, if any, gives way to D-106, and every neighbour that has not had one yet starts
# its own. False for a building that is not a house or a house already sick.
static func mark_sick(state: EconomyState, params: Params, context: EconomyContext, house: Dictionary) -> bool:
	if not _is_house(context, house) or house.get(SICK, false):
		return false
	house[SICK] = true
	if house.has(QUARANTINE):
		house[QUARANTINE] = 0
	for other: Dictionary in state.buildings:
		if is_same(other, house) or not _is_house(context, other) or other.get(SICK, false) or other.has(QUARANTINE):
			continue
		if exposed(params, context, house, other):
			var key: StringName = &"crisis.health.quarantine_post_min" if in_post_radius(state, context, other) \
				else &"crisis.health.quarantine_min"
			other[QUARANTINE] = SimTime.minutes_to_ticks(float(params.get_value(key)))
	return true


# The house has no sick people left: a disinfection still running is paid back, and with the last one the crisis ends.
static func cure(state: EconomyState, house: Dictionary) -> bool:
	if not house.get(SICK, false):
		return false
	house.erase(SICK)
	if house.has(DISINFECTION):
		var paid: int = int(house[DISINFECTION_PAID])
		state.money += paid
		state.construction_spent_tick -= paid
		state.refunds_tick += paid
		_clear_disinfection(house)
	_end_if_over(state)
	return true


# Quarantines and disinfections count down one second; a finished disinfection leaves the house clean.
static func tick(state: EconomyState) -> void:
	for building: Dictionary in state.buildings:
		if int(building.get(QUARANTINE, 0)) > 0:
			building[QUARANTINE] = int(building[QUARANTINE]) - 1
		if building.has(DISINFECTION):
			building[DISINFECTION] = int(building[DISINFECTION]) - 1
			if int(building[DISINFECTION]) <= 0:
				_clear_disinfection(building)
				building.erase(SICK)
	_end_if_over(state)


static func disinfect_reason(state: EconomyState, params: Params, context: EconomyContext,
		house: Dictionary) -> StringName:
	if not house.get(SICK, false):
		return NOT_SICK
	if house.has(DISINFECTION):
		return DISINFECTION_RUNNING
	if not in_post_radius(state, context, house):
		return OUTSIDE_POST
	if state.money < int(params.get_value(&"crisis.health.response_cost")):
		return &"insufficient_money"
	return &""


# Paid now, in full; disinfect_reason() said it may start.
static func start_disinfection(state: EconomyState, params: Params, house: Dictionary) -> void:
	var cost: int = int(params.get_value(&"crisis.health.response_cost"))
	state.money -= cost
	state.construction_spent_tick += cost
	house[DISINFECTION] = SimTime.minutes_to_ticks(float(params.get_value(&"crisis.health.response_min")))
	house[DISINFECTION_PAID] = cost


# Within exposure_tiles of the sick house, counted between the nearest cells of both footprints: a square counts the
# diagonals (8 neighbours at 1 tile), a diamond does not (4).
static func exposed(params: Params, context: EconomyContext, sick: Dictionary, other: Dictionary) -> bool:
	var a: Rect2i = context.area_of(sick)
	var b: Rect2i = context.area_of(other)
	var dx: int = maxi(0, maxi(b.position.x - a.end.x + 1, a.position.x - b.end.x + 1))
	var dy: int = maxi(0, maxi(b.position.y - a.end.y + 1, a.position.y - b.end.y + 1))
	var tiles: int = dx + dy if params.get_value(&"crisis.health.exposure_diamond") else maxi(dx, dy)
	return tiles <= int(params.get_value(&"crisis.health.exposure_tiles"))


# The post has one radius (D-121): its service_radius_m along the streets, the coverage it has as the health service
# (D-118), worked out by RoadSystem. A house without a street, or on a map without streets, is outside it.
static func in_post_radius(state: EconomyState, context: EconomyContext, house: Dictionary) -> bool:
	var covering: Array = state.service_cover.get(RoadNetwork.cell_of(house), {}).get(ServiceSystem.HEALTH, [])
	return state.buildings.any(func(building: Dictionary) -> bool:
		var definition: BuildingDef = context.buildings.get(StringName(building["definition_id"]))
		return definition != null and POST_TAG in definition.tags and building.has("cell") \
			and RoadNetwork.cell_of(building) in covering)


# For the map (D-108): the price and length of a disinfection, and every locked house with why, whether it can be
# disinfected now (&"" when it can) and the seconds left of its quarantine or disinfection.
static func snapshot(state: EconomyState, params: Params, context: EconomyContext) -> Dictionary:
	var houses: Array[Dictionary] = []
	if context != null:
		for building: Dictionary in state.buildings:
			var lock: StringName = lock_reason(building)
			if lock == &"":
				continue
			houses.append({"definition_id": building["definition_id"], "cell": building["cell"].duplicate(),
				"lock": lock,
				"disinfect": disinfect_reason(state, params, context, building),
				"seconds_left": int(building.get(DISINFECTION, building.get(QUARANTINE, 0)))})
	return {"active": active(state), "houses": houses,
		"cost": int(params.get_value(&"crisis.health.response_cost")),
		"duration_seconds": SimTime.minutes_to_ticks(float(params.get_value(&"crisis.health.response_min")))}


static func _end_if_over(state: EconomyState) -> void:
	if active(state):
		return
	for building: Dictionary in state.buildings:
		building.erase(QUARANTINE)


static func _clear_disinfection(house: Dictionary) -> void:
	house.erase(DISINFECTION)
	house.erase(DISINFECTION_PAID)


static func _is_house(context: EconomyContext, building: Dictionary) -> bool:
	var definition: BuildingDef = context.buildings.get(StringName(building["definition_id"]))
	return definition != null and WaterSystem.HOUSING_TAG in definition.tags
