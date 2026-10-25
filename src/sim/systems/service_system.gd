class_name ServiceSystem
extends RefCounted

# Service buildings (issue #87, D-054, D-118): one for each district attribute, safety (fires), health (outbreaks) and
# order (riots). A house is covered by a service when the service radius of D-086 reaches it along the streets: the
# coverage of RoadSystem, worked out with the rest of the layout (RoadSystem.evaluate). A covered house is worth the
# availability of the best service of its kind that reaches it, 0 when none does, and a district's attribute is the
# mean of its houses. A service's availability, 0 to availability_max, is spent by consume() and comes back at
# recovery_per_min. The incidents of D-119 (IncidentSystem) spend it, and so do the tests. It lives on the building's
# own dictionary, so it is saved with it and goes when the building does; a building without it stands at its maximum.

const SERVICE_TAG: String = "service"
const SAFETY: StringName = &"safety"
const HEALTH: StringName = &"health"
const ORDER: StringName = &"order"
const ATTRIBUTES: Array[StringName] = [SAFETY, HEALTH, ORDER]
const AVAILABILITY: String = "availability"


static func is_service(context: EconomyContext, building: Dictionary) -> bool:
	var definition: BuildingDef = context.buildings.get(StringName(building["definition_id"]))
	return definition != null and SERVICE_TAG in definition.tags


static func attribute_of(context: EconomyContext, service: Dictionary) -> StringName:
	return context.buildings[StringName(service["definition_id"])].service_attribute


# Called by RoadSystem.evaluate with its network and its connected buildings: each connected house to the cells of the
# services of each attribute that cover it. A house or a service without a street covers and is covered by nothing.
static func evaluate(state: EconomyState, params: Params, context: EconomyContext, network: RoadNetwork,
		connected: Array[Dictionary]) -> void:
	var services: Array[Dictionary] = []
	for building: Dictionary in connected:
		if is_service(context, building):
			services.append(building)
	for house: Dictionary in connected:
		if not _is_house(context, house):
			continue
		var covering: Dictionary = {}
		for service: Dictionary in services:
			if RoadSystem.within_radius(params, context, network, service, house):
				covering.get_or_add(attribute_of(context, service), []).append(RoadNetwork.cell_of(service))
		state.service_cover[RoadNetwork.cell_of(house)] = covering


# One tick: every service spent below its maximum gets back recovery_per_min / 60, up to the maximum.
static func tick(state: EconomyState, params: Params, context: EconomyContext) -> void:
	for building: Dictionary in state.buildings:
		if not building.has(AVAILABILITY) or not is_service(context, building):
			continue
		var top: float = availability_max(params, building)
		var recovered: float = float(building[AVAILABILITY]) \
			+ float(params.get_value(_key(building, "recovery_per_min"))) / SimTime.TICKS_PER_MINUTE
		if recovered >= top:
			building.erase(AVAILABILITY)
		else:
			building[AVAILABILITY] = recovered


# Spends `amount` of the service's availability, never below 0. False for a building that is not a service or an
# amount below 0, which would refill it.
static func consume(params: Params, context: EconomyContext, service: Dictionary, amount: float) -> bool:
	if not is_service(context, service) or amount < 0.0:
		return false
	service[AVAILABILITY] = maxf(0.0, availability(params, service) - amount)
	return true


static func availability(params: Params, service: Dictionary) -> float:
	return minf(float(service.get(AVAILABILITY, INF)), availability_max(params, service))


static func availability_max(params: Params, service: Dictionary) -> float:
	return float(params.get_value(_key(service, "availability_max")))


# For the views and the tests: every service with its availability, every house with its district and what it is
# worth for each attribute, and each district's attributes (every district of the map, 0 without houses).
static func snapshot(state: EconomyState, params: Params, context: EconomyContext) -> Dictionary:
	var result: Dictionary = {"buildings": [], "houses": [], "districts": {}}
	if context == null:
		return result
	for service: Dictionary in _services_by_cell(state, context).values():
		result["buildings"].append({"cell": service["cell"].duplicate(),
			"definition_id": service["definition_id"], "attribute": attribute_of(context, service),
			"availability": availability(params, service), "availability_max": availability_max(params, service)})
	var districts: Dictionary[StringName, Dictionary] = district_values(state, params, context)
	for district: StringName in districts:
		for entry: Dictionary in districts[district]["houses"]:
			var house: Dictionary = entry["house"]
			result["houses"].append({"cell": house["cell"].duplicate(), "definition_id": house["definition_id"],
				"district": district, "values": entry["values"]})
		result["districts"][district] = districts[district]["attributes"]
	return result


# Every district of the map with its houses, each {house, values}, and its attributes: the mean of its houses, 0
# without any. The incidents of D-119 read the same figures the views do.
static func district_values(state: EconomyState, params: Params,
		context: EconomyContext) -> Dictionary[StringName, Dictionary]:
	var by_cell: Dictionary[Vector2i, Dictionary] = _services_by_cell(state, context)
	var houses: Dictionary[StringName, Array] = {}
	for district: StringName in WaterSystem.districts(context):
		houses[district] = []
	for building: Dictionary in state.buildings:
		# A state saved before the map (M1) has buildings without a cell: they stand nowhere, so nothing covers them.
		if building.has("cell") and _is_house(context, building):
			var cell: Vector2i = RoadNetwork.cell_of(building)
			houses.get_or_add(context.map.district_by_cell.get(cell, WaterSystem.DEFAULT_DISTRICT), []).append(building)
	var result: Dictionary[StringName, Dictionary] = {}
	for district: StringName in houses:
		var totals: Dictionary = _zeros()
		var entries: Array[Dictionary] = []
		for house: Dictionary in houses[district]:
			var values: Dictionary = _house_values(state, params, by_cell, house)
			for attribute: StringName in ATTRIBUTES:
				totals[attribute] += values[attribute]
			entries.append({"house": house, "values": values})
		for attribute: StringName in ATTRIBUTES:
			if not entries.is_empty():
				totals[attribute] /= float(entries.size())
		result[district] = {"houses": entries, "attributes": totals}
	return result


# The service of the attribute with the most availability among those that cover the house, {} when none does.
static func best_service(state: EconomyState, params: Params, context: EconomyContext, house: Dictionary,
		attribute: StringName) -> Dictionary:
	var by_cell: Dictionary[Vector2i, Dictionary] = _services_by_cell(state, context)
	var best: Dictionary = {}
	for cell: Vector2i in state.service_cover.get(RoadNetwork.cell_of(house), {}).get(attribute, []):
		if by_cell.has(cell) and (best.is_empty() or availability(params, by_cell[cell]) > availability(params, best)):
			best = by_cell[cell]
	return best


static func _services_by_cell(state: EconomyState, context: EconomyContext) -> Dictionary[Vector2i, Dictionary]:
	var by_cell: Dictionary[Vector2i, Dictionary] = {}
	for building: Dictionary in state.buildings:
		if building.has("cell") and is_service(context, building):
			by_cell[RoadNetwork.cell_of(building)] = building
	return by_cell


# Covered times the availability of the best service that covers it, for each attribute.
static func _house_values(state: EconomyState, params: Params, by_cell: Dictionary[Vector2i, Dictionary],
		house: Dictionary) -> Dictionary:
	var values: Dictionary = _zeros()
	var covering: Dictionary = state.service_cover.get(RoadNetwork.cell_of(house), {})
	for attribute: StringName in covering:
		for cell: Vector2i in covering[attribute]:
			if by_cell.has(cell):
				values[attribute] = maxf(values[attribute], availability(params, by_cell[cell]))
	return values


static func _is_house(context: EconomyContext, building: Dictionary) -> bool:
	var definition: BuildingDef = context.buildings.get(StringName(building["definition_id"]))
	return definition != null and WaterSystem.HOUSING_TAG in definition.tags


static func _zeros() -> Dictionary:
	var values: Dictionary = {}
	for attribute: StringName in ATTRIBUTES:
		values[attribute] = 0.0
	return values


static func _key(service: Dictionary, field: String) -> StringName:
	return StringName("service.%s.%s" % [service["definition_id"], field])
