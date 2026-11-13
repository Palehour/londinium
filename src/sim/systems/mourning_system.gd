class_name MourningSystem
extends RefCounted

# Luto (issue #370, D-194, D-195): a satisfaction term fed by cholera deaths. Each death is assigned to the nearest
# cemetery with free space in its district; the rest stay unburied. Buried and unburied memories decay with
# satisfaction.mourning.deaths_memory_seconds. The atrio of St Mary Matfelon is a historic anchor (D-193) and a
# cemetery; player cemeteries are buildable only while mourning is enabled and cannot be demolished while occupied.

const CEMETERY_TAG: String = "cemetery"
const BURIED: String = "buried"
const UNBURIED: String = "unburied"


# Called from MissionSystem._cholera in the tick the deaths happen. `deaths_by_district` maps a district id to the
# number of deaths there. The rule that computes the deaths is not changed; this only decides where each one is buried.
static func assign_deaths(state: EconomyState, params: Params, context: EconomyContext,
		deaths_by_district: Dictionary[StringName, int]) -> void:
	if not state.mourning_enabled:
		return
	var cemeteries: Array[Dictionary] = _cemeteries(state, context)
	for district: StringName in deaths_by_district:
		var remaining: int = deaths_by_district[district]
		if remaining <= 0:
			continue
		var centroid: Vector2 = _district_centroid(context, district)
		var candidates: Array[Dictionary] = _candidates(state, params, context, cemeteries, district, centroid)
		var buried: int = 0
		for candidate: Dictionary in candidates:
			if remaining <= 0:
				break
			var free: int = candidate.capacity - int(candidate.building.get(BURIED, 0))
			if free <= 0:
				continue
			var taken: int = mini(remaining, free)
			candidate.building[BURIED] = int(candidate.building.get(BURIED, 0)) + taken
			buried += taken
			remaining -= taken
		state.mourning_buried[district] = state.mourning_buried.get(district, 0.0) + float(buried)
		state.mourning_unburied[district] = state.mourning_unburied.get(district, 0.0) + float(remaining)


# One tick of memory decay. Memories are floats so partial deaths fade smoothly.
static func tick(state: EconomyState, params: Params) -> void:
	if not state.mourning_enabled:
		return
	var seconds: float = float(params.get_value(&"satisfaction.mourning.deaths_memory_seconds"))
	if seconds <= 0.0:
		return
	var factor: float = 1.0 - 1.0 / seconds
	_decay(state.mourning_unburied, factor)
	_decay(state.mourning_buried, factor)


# Satisfaction penalty of a class: the mean district mourning of its houses times the class weight.
static func class_penalty(state: EconomyState, params: Params, context: EconomyContext, def: ClassDef) -> float:
	if not state.mourning_enabled or def.mourning_weight_key == &"":
		return 0.0
	var mourning_by_district: Dictionary[StringName, float] = district_mourning(state, params, context)
	var total: float = 0.0
	var houses: int = 0
	for building: Dictionary in state.buildings:
		if not _is_house_of(context, building, def):
			continue
		houses += 1
		total += mourning_by_district.get(_district_of(context, building), 0.0)
	var average: float = total / float(houses) if houses > 0 else 0.0
	return average * float(params.get_value(def.mourning_weight_key))


# `luto_d` for every district that exists on the map.
static func district_mourning(state: EconomyState, params: Params, context: EconomyContext) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	var buried_factor: float = float(params.get_value(&"satisfaction.mourning.buried_factor"))
	var populations: Dictionary[StringName, float] = _district_populations(state, context)
	for district: StringName in WaterSystem.districts(context):
		var unburied: float = state.mourning_unburied.get(district, 0.0)
		var buried: float = state.mourning_buried.get(district, 0.0)
		var pop: float = populations.get(district, 0.0)
		result[district] = clampf((unburied + buried * buried_factor) / maxf(1.0, pop), 0.0, 1.0)
	return result


static func _cemeteries(state: EconomyState, context: EconomyContext) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for building: Dictionary in state.buildings:
		var definition: BuildingDef = context.buildings.get(StringName(building["definition_id"]))
		if definition != null and CEMETERY_TAG in definition.tags:
			found.append(building)
	return found


static func _candidates(state: EconomyState, params: Params, context: EconomyContext,
		cemeteries: Array[Dictionary], district: StringName, centroid: Vector2) -> Array[Dictionary]:
	var cell_size: float = float(params.get_value(&"map.cell_size_m"))
	var found: Array[Dictionary] = []
	for building: Dictionary in cemeteries:
		var prefix: String = _cemetery_prefix(context, building)
		var radius: float = float(params.get_value(StringName("%s.radius_m" % prefix)))
		var capacity: int = int(params.get_value(StringName("%s.capacity" % prefix)))
		var center: Vector2 = WaterSystem._centre(context, building)
		var distance: float = centroid.distance_to(center) * cell_size
		if distance > radius:
			continue
		var cell: Vector2i = RoadNetwork.cell_of(building)
		found.append({"distance": distance, "cell": cell, "building": building, "capacity": capacity})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.distance != b.distance:
			return a.distance < b.distance
		if a.cell.y != b.cell.y:
			return a.cell.y < b.cell.y
		return a.cell.x < b.cell.x)
	return found


static func _cemetery_prefix(context: EconomyContext, building: Dictionary) -> String:
	# The preplaced atrio is the only building that uses the preplaced cemetery parameters (D-195).
	if building["definition_id"] == &"st_mary_atrium":
		return "cemetery.preplaced"
	return "cemetery.player"


static func _district_centroid(context: EconomyContext, district: StringName) -> Vector2:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in context.map.district_by_cell:
		if context.map.district_by_cell[cell] == district:
			cells.append(cell)
	if cells.is_empty():
		return Vector2(float(context.map.width) / 2.0, float(context.map.height) / 2.0)
	var total: Vector2 = Vector2.ZERO
	for cell: Vector2i in cells:
		total += Vector2(cell)
	return total / float(cells.size())


static func _district_populations(state: EconomyState, context: EconomyContext) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for def: ClassDef in ClassStates.defs(context):
		var people: int = ClassStates.population_of(state, def)
		var total_houses: int = 0
		var by_district: Dictionary[StringName, int] = {}
		for building: Dictionary in state.buildings:
			if not _is_house_of(context, building, def):
				continue
			total_houses += 1
			var district: StringName = _district_of(context, building)
			by_district[district] = by_district.get(district, 0) + 1
		for district: StringName in by_district:
			result[district] = result.get(district, 0.0) + float(people) * float(by_district[district]) \
				/ float(maxi(1, total_houses))
	return result


static func _is_house_of(context: EconomyContext, building: Dictionary, def: ClassDef) -> bool:
	var definition: BuildingDef = context.buildings.get(StringName(building["definition_id"]))
	if definition == null or WaterSystem.HOUSING_TAG not in definition.tags:
		return false
	var owner: StringName = context.class_of_housing(definition.id)
	return owner == def.id or (def.base and owner == &"")


static func _district_of(context: EconomyContext, building: Dictionary) -> StringName:
	return context.map.district_by_cell.get(RoadNetwork.cell_of(building), WaterSystem.DEFAULT_DISTRICT)


static func _decay(memories: Dictionary[StringName, float], factor: float) -> void:
	for district: StringName in memories:
		memories[district] = maxf(0.0, memories[district] * factor)
