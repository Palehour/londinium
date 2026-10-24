class_name WaterSystem
extends RefCounted

# Water buildings (issue #63, D-089; issue #202, D-090): water_d, how safely a district's houses drink. The public
# fountain draws from the source of the house's district (issue #209), the Lea Bridge fountain and the well from their
# own. Only the Old Ford mission (issue #202) reads it, and only with the historic events on, so with them off the game plays as before.

const WATER_TAG: String = "water"
const HOUSING_TAG: String = "housing"
# A map without districts is this one district, and a house outside every district belongs to it (issue #209). A
# district drinks from the water_source the map gives it, the neutral one (D-088) if none, unless a mission set its
# risk (EconomyState.district_source_risk).
const DEFAULT_DISTRICT: StringName = &"default"
const DEFAULT_SOURCE: StringName = MapDef.DEFAULT_WATER_SOURCE


# Each house drinks the safest water that reaches it (issue #202, D-090): the best 1 - risk among the water buildings
# whose radius covers it, 0 without any. water_d is their sum over the houses, capped at 1; with one source this is
# D-089's min(1, covered houses / houses) x (1 - events.source_risk.<source>). 0 for a district without houses.
# `district_risk`, when not negative, replaces the risk of the district's source (the Old Ford cut, issue #202).
static func coverage(params: Params, context: EconomyContext, houses: Array[Dictionary],
		water: Array[Dictionary], source: StringName, district_risk: float = -1.0) -> float:
	if houses.is_empty():
		return 0.0
	var total: float = 0.0
	for house: Dictionary in houses:
		var best: float = 0.0
		for building: Dictionary in water:
			if distance_m(params, context, house, building) <= radius_m(params, context, building):
				best = maxf(best, 1.0 - risk(params, context, building, source, district_risk))
		total += best
	return minf(1.0, total / float(houses.size()))


# The whole city as one district of the source: every house and every water building of the state.
static func city_coverage(state: EconomyState, params: Params, context: EconomyContext, source: StringName) -> float:
	return coverage(params, context, _tagged(state, context, HOUSING_TAG), _tagged(state, context, WATER_TAG), source)


# water_d of each district of the map (D-090), each house with the source of its own district (issue #209) and the
# risk a mission left on it. Every water building counts for every house it reaches, whatever its district.
static func district_water(state: EconomyState, params: Params,
		context: EconomyContext) -> Dictionary[StringName, float]:
	var water: Array[Dictionary] = _tagged(state, context, WATER_TAG)
	var houses: Dictionary[StringName, Array] = district_houses(state, context)
	var result: Dictionary[StringName, float] = {}
	for district: StringName in houses:
		var in_district: Array[Dictionary] = []
		in_district.assign(houses[district])
		result[district] = coverage(params, context, in_district, water, source_of(context, district),
			state.district_source_risk.get(district, -1.0))
	return result


# The houses of each district, every district of the map listed even without houses. A house belongs to the district
# of the cell it is placed at (its top-left one).
static func district_houses(state: EconomyState, context: EconomyContext) -> Dictionary[StringName, Array]:
	var result: Dictionary[StringName, Array] = {}
	for district: StringName in districts(context):
		result[district] = []
	for house: Dictionary in _tagged(state, context, HOUSING_TAG):
		var cell: Vector2i = Vector2i(int(house["cell"][0]), int(house["cell"][1]))
		var district: StringName = context.map.district_by_cell.get(cell, DEFAULT_DISTRICT)
		if not result.has(district):
			result[district] = []
		result[district].append(house)
	return result


static func districts(context: EconomyContext) -> Array[StringName]:
	var found: Array[StringName] = []
	found.assign(context.map.district_names.keys())
	if found.is_empty():
		found.append(DEFAULT_DISTRICT)
	return found


# The districts a source runs to: those the map gives it. A map without districts is the one district, and the cut of
# Old Ford falls on it as it did before districts (issue #202).
static func districts_drinking(context: EconomyContext, source: StringName) -> Array[StringName]:
	if context.map.district_names.is_empty():
		return [DEFAULT_DISTRICT]
	return districts(context).filter(func(district: StringName) -> bool:
		return source_of(context, district) == source)


static func source_of(context: EconomyContext, district: StringName) -> StringName:
	return context.map.district_water_sources.get(district, DEFAULT_SOURCE)


# The risk of the district's own source: what a mission set, or the data's for its source.
static func district_risk(state: EconomyState, params: Params, district: StringName = DEFAULT_DISTRICT,
		source: StringName = DEFAULT_SOURCE) -> float:
	if state.district_source_risk.has(district):
		return state.district_source_risk[district]
	return source_risk(params, source)


# A source of the events data (events.source_risk.<source>: neutral, Old Ford) or one with a section of its own
# (<source>.source_risk: Lea Bridge, the well).
static func source_risk(params: Params, source: StringName) -> float:
	var key: StringName = StringName("events.source_risk.%s" % source)
	if not params.has_value(key):
		key = StringName("%s.source_risk" % source)
	return float(params.get_value(key))


# `<coverage>.radius_m` of the building's data: the fountain's for both fountains, the well's own for the well.
static func radius_m(params: Params, context: EconomyContext, building: Dictionary) -> float:
	var definition: BuildingDef = context.buildings[StringName(building["definition_id"])]
	return float(params.get_value(StringName("%s.radius_m" % definition.coverage)))


# A building with a source of its own (the well, Lea Bridge) carries its `source_risk`; any other drinks from the
# district's source.
static func risk(params: Params, context: EconomyContext, building: Dictionary, source: StringName,
		district_risk: float = -1.0) -> float:
	var definition: BuildingDef = context.buildings[StringName(building["definition_id"])]
	if definition.water_source != &"":
		return float(params.get_value(StringName("%s.source_risk" % definition.water_source)))
	if district_risk >= 0.0:
		return district_risk
	return source_risk(params, source)


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
