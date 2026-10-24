class_name WaterSystem
extends RefCounted

# Water buildings (issue #63, D-089; issue #202, D-090): water_d, how safely a district's houses drink. The public
# fountain draws from the district's source, the Lea Bridge fountain and the well from their own. Nothing in tick() asks for it yet: the historic events of #63
# will, so with them off the game plays as before.

const WATER_TAG: String = "water"
const HOUSING_TAG: String = "housing"


# Each house drinks the safest water that reaches it (issue #202, D-090): the best 1 - risk among the water buildings
# whose radius covers it, 0 without any. water_d is their sum over the houses, capped at 1; with one source this is
# D-089's min(1, covered houses / houses) x (1 - events.source_risk.<source>). 0 for a district without houses.
static func coverage(params: Params, context: EconomyContext, houses: Array[Dictionary],
		water: Array[Dictionary], source: StringName) -> float:
	if houses.is_empty():
		return 0.0
	var total: float = 0.0
	for house: Dictionary in houses:
		var best: float = 0.0
		for building: Dictionary in water:
			if distance_m(params, context, house, building) <= radius_m(params, context, building):
				best = maxf(best, 1.0 - risk(params, context, building, source))
		total += best
	return minf(1.0, total / float(houses.size()))


# Until districts exist (#60) the city is the one district: every house and every water building of the state.
static func city_coverage(state: EconomyState, params: Params, context: EconomyContext, source: StringName) -> float:
	return coverage(params, context, _tagged(state, context, HOUSING_TAG), _tagged(state, context, WATER_TAG), source)


# `<coverage>.radius_m` of the building's data: the fountain's for both fountains, the well's own for the well.
static func radius_m(params: Params, context: EconomyContext, building: Dictionary) -> float:
	var definition: BuildingDef = context.buildings[StringName(building["definition_id"])]
	return float(params.get_value(StringName("%s.radius_m" % definition.coverage)))


# A building with a source of its own (the well, Lea Bridge) carries its `source_risk`; any other drinks from the
# district's source.
static func risk(params: Params, context: EconomyContext, building: Dictionary, source: StringName) -> float:
	var definition: BuildingDef = context.buildings[StringName(building["definition_id"])]
	if definition.water_source != &"":
		return float(params.get_value(StringName("%s.source_risk" % definition.water_source)))
	return float(params.get_value(StringName("events.source_risk.%s" % source)))


# Euclidean, centre to centre of the footprints, in metres (D-086): cells times map.cell_size_m, never rounded.
static func distance_m(params: Params, context: EconomyContext, a: Dictionary, b: Dictionary) -> float:
	return _centre(context, a).distance_to(_centre(context, b)) * float(params.get_value(&"map.cell_size_m"))


# A water building waits for the historic events: with events.enabled off it cannot be built (D-089). A source with
# a cap (`<water_source>.max_fountains`, Lea Bridge, issue #202) takes no more buildings once it has that many.
static func unavailable_reason(params: Params, state: EconomyState, context: EconomyContext,
		definition: BuildingDef) -> StringName:
	if WATER_TAG not in definition.tags:
		return &""
	if not bool(params.get_value(&"events.enabled")):
		return &"events_disabled"
	var cap_key: StringName = StringName("%s.max_fountains" % definition.water_source)
	if definition.water_source != &"" and params.has_value(cap_key) 			and _drawing_from(state, context, definition.water_source) >= int(params.get_value(cap_key)):
		return &"water_source_cap"
	return &""


static func _drawing_from(state: EconomyState, context: EconomyContext, water_source: StringName) -> int:
	return _tagged(state, context, WATER_TAG).filter(func(building: Dictionary) -> bool:
		return context.buildings[StringName(building["definition_id"])].water_source == water_source).size()


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
