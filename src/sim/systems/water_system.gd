class_name WaterSystem
extends RefCounted

# Public fountains (issue #63, task 0, D-089): water_d, the share of a district's houses within fountain.radius_m of a
# fountain, times what the water's source leaves safe. Nothing in tick() asks for it yet: the historic events of #63
# will, so with them off the game plays as before.

const WATER_TAG: String = "water"
const HOUSING_TAG: String = "housing"


# min(1, covered houses / houses) x (1 - events.source_risk.<source>); 0 for a district without houses.
static func coverage(params: Params, context: EconomyContext, houses: Array[Dictionary],
		fountains: Array[Dictionary], source: StringName) -> float:
	if houses.is_empty():
		return 0.0
	var covered: int = houses.filter(func(house: Dictionary) -> bool:
		return is_covered(params, context, house, fountains)).size()
	var risk: float = float(params.get_value(StringName("events.source_risk.%s" % source)))
	return minf(1.0, float(covered) / float(houses.size())) * (1.0 - risk)


# Until districts exist (#60) the city is the one district: every house and every fountain of the state.
static func city_coverage(state: EconomyState, params: Params, context: EconomyContext, source: StringName) -> float:
	return coverage(params, context, _tagged(state, context, HOUSING_TAG), _tagged(state, context, WATER_TAG), source)


# Covered when the centre of some fountain is at most fountain.radius_m from the house's.
static func is_covered(params: Params, context: EconomyContext, house: Dictionary,
		fountains: Array[Dictionary]) -> bool:
	var radius: float = float(params.get_value(&"fountain.radius_m"))
	return fountains.any(func(fountain: Dictionary) -> bool:
		return distance_m(params, context, house, fountain) <= radius)


# Euclidean, centre to centre of the footprints, in metres (D-086): cells times map.cell_size_m, never rounded.
static func distance_m(params: Params, context: EconomyContext, a: Dictionary, b: Dictionary) -> float:
	return _centre(context, a).distance_to(_centre(context, b)) * float(params.get_value(&"map.cell_size_m"))


# A water building waits for the historic events: with events.enabled off it cannot be built (D-089).
static func unavailable_reason(params: Params, definition: BuildingDef) -> StringName:
	if WATER_TAG in definition.tags and not bool(params.get_value(&"events.enabled")):
		return &"events_disabled"
	return &""


static func _centre(context: EconomyContext, building: Dictionary) -> Vector2:
	var area: Rect2i = context.area_of(building)
	return Vector2(area.position) + Vector2(area.size) / 2.0


static func _tagged(state: EconomyState, context: EconomyContext, tag: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for building: Dictionary in state.buildings:
		var definition: BuildingDef = context.buildings.get(StringName(building["definition_id"]))
		if definition != null and tag in definition.tags:
			found.append(building)
	return found
