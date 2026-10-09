class_name BreadDiagnostics
extends RefCounted

# Same chain order as worker assignment (D-021), so causes read from the root outwards.
const CHAIN: Array[StringName] = [&"wharf", &"mill", &"bakery"]


static func build(state: EconomyState, params: Params, context: EconomyContext) -> Dictionary:
	var buildings: Array[Dictionary] = []
	for building: Dictionary in state.buildings:
		var id: StringName = StringName(building["definition_id"])
		var jobs: int = WorkersSystem.job_capacity(params, id)
		if jobs <= 0:
			continue
		buildings.append({
			"definition_id": id, "cell": building["cell"].duplicate(),
			"workers": int(building.get("workers", 0)), "jobs": jobs,
			"reason": building_reason(state, context, building),
		})
	var bread_short: bool = state.bread_coverage < 1.0
	var causes: Array[Dictionary] = _chain_causes(buildings)
	if bread_short and causes.is_empty():
		causes = _throughput_causes(buildings)
	return {
		"bread_short": bread_short,
		"bread_causes": causes,
		"buildings": buildings,
	}


static func building_reason(state: EconomyState, context: EconomyContext, building: Dictionary) -> StringName:
	var id: StringName = StringName(building["definition_id"])
	# The wharf is the only buyer; MarketSystem stops before staffing when purchases are off.
	if id == &"wharf" and not state.wheat_purchases_enabled:
		return &"wheat_purchases_disabled"
	if int(building.get("workers", 0)) <= 0:
		return &"no_workers"
	if id == &"wharf" and MarketSystem.affordable_wheat(state, 1) == 0:
		return &"no_money_for_wheat"
	var recipe: RecipeDef = context.buildings[id].recipe if context != null and context.buildings.has(id) else null
	if recipe == null or recipe.inputs.is_empty():
		return &"ok"
	var waiting_input: bool = int(state.stocks.get(recipe.inputs[0], 0)) <= 0 \
		and float(building.get("reserved_input", 0.0)) <= 0.0
	return &"no_input" if waiting_input else &"ok"


# One cause per chain stage: a stage blocks bread only when none of its buildings work.
static func _chain_causes(buildings: Array[Dictionary]) -> Array[Dictionary]:
	var causes: Array[Dictionary] = []
	for id: StringName in CHAIN:
		var reason: StringName = &"missing_building"
		for building: Dictionary in buildings:
			if building["definition_id"] != id:
				continue
			reason = building["reason"]
			if reason == &"ok":
				break
		if reason != &"ok":
			causes.append({"definition_id": id, "reason": reason})
	return causes


# Every stage works but bread still runs short: name the stages missing hands, or else the
# whole chain is simply too small for the population.
static func _throughput_causes(buildings: Array[Dictionary]) -> Array[Dictionary]:
	var causes: Array[Dictionary] = []
	for id: StringName in CHAIN:
		for building: Dictionary in buildings:
			if building["definition_id"] == id and building["workers"] < building["jobs"]:
				causes.append({"definition_id": id, "reason": &"understaffed"})
				break
	if causes.is_empty():
		causes.append({"definition_id": &"", "reason": &"insufficient_capacity"})
	return causes
