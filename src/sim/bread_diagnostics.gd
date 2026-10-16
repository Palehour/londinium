class_name BreadDiagnostics
extends RefCounted

# Same chain order as worker assignment (D-021), so causes read from the root outwards.
const CHAIN: Array[StringName] = [&"wharf", &"mill", &"bakery"]
# The beer chain says which input is missing; the bread chain keeps the generic "no_input".
const MISSING_INPUT_REASONS: Dictionary[StringName, StringName] = {&"barley": &"no_barley", &"malt": &"no_malt"}


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
			"reason": building_reason(state, context, building, params),
		})
	var bread_short: bool = state.bread_coverage < 1.0
	# Imported flour skips the wharf's wheat and the mill, so only the bakery is left in the chain; the
	# wharf is blamed only when it cannot pay for the flour.
	var stages: Array[StringName] = CHAIN
	if ImportSystem.flour_import_active(state):
		stages = [&"bakery"]
	var causes: Array[Dictionary] = _chain_causes(buildings, stages)
	if ImportSystem.flour_import_active(state) and ImportSystem.flour_reason(state, params) == &"no_money_for_imports":
		causes.push_front({"definition_id": &"wharf", "reason": &"no_money_for_imports"})
	if bread_short and causes.is_empty():
		causes = _throughput_causes(buildings, stages)
	return {
		"bread_short": bread_short,
		"bread_causes": causes,
		"buildings": buildings,
		"unloading_split": unloading_split(state, params),
	}


# The mill gets less wheat than it grinds because the wharf gives part of its unloading to the barley
# (issue #106). It only explains the tension D-031 wants; both conditions have to hold at once.
static func unloading_split(state: EconomyState, params: Params) -> Dictionary:
	var received: float = MarketSystem.wheat_unloading_per_minute(state, params)
	var needed: float = MarketSystem.mill_consumption_per_second(state, params) * MarketSystem.SECONDS_PER_MINUTE
	var short: bool = received < needed - ProductionSystem.ROUNDING_EPSILON
	return {
		"active": short and MarketSystem.barley_percent(state) > 0,
		"received_per_minute": received,
		"needed_per_minute": needed,
	}


static func building_reason(state: EconomyState, context: EconomyContext, building: Dictionary,
		params: Params) -> StringName:
	var id: StringName = StringName(building["definition_id"])
	# A staffed wharf that brings in the flour is working, whatever the wheat purchases do, unless it
	# cannot pay for the flour. An unstaffed one falls through to the usual reasons.
	if id == &"wharf" and ImportSystem.flour_import_active(state) and int(building.get("workers", 0)) > 0:
		var flour: StringName = ImportSystem.flour_reason(state, params)
		return flour if flour == &"no_money_for_imports" else &"ok"
	# The wharf is the only buyer; MarketSystem stops before staffing when purchases are off.
	if id == &"wharf" and not state.wheat_purchases_enabled:
		return &"wheat_purchases_disabled"
	if int(building.get("workers", 0)) <= 0:
		return &"no_workers"
	# With stock the mills keep working, so only an empty warehouse makes the price the reason; and
	# under the safety reserve the wharf buys anyway, so then the price is not stopping it.
	if id == &"wharf" and MarketSystem.is_halted_by_price(state, params) and int(state.stocks.get(&"wheat", 0)) <= 0:
		return &"wheat_price_above_max"
	if id == &"wharf" and MarketSystem.affordable_wheat(state, 1) == 0:
		return &"no_money_for_wheat"
	var recipe: RecipeDef = context.buildings[id].recipe if context != null and context.buildings.has(id) else null
	if recipe == null or recipe.inputs.is_empty():
		return &"ok"
	# A full warehouse stops a producer whatever it has to work with (issue #51).
	if ProductionSystem.storage_full(state, params, recipe.outputs[0]):
		return &"storage_full"
	var waiting_input: bool = int(state.stocks.get(recipe.inputs[0], 0)) <= 0 \
		and float(building.get("reserved_input", 0.0)) <= 0.0
	if not waiting_input:
		return &"ok"
	return MISSING_INPUT_REASONS.get(recipe.inputs[0], &"no_input")


# One cause per chain stage: a stage blocks bread only when none of its buildings work.
static func _chain_causes(buildings: Array[Dictionary], stages: Array[StringName]) -> Array[Dictionary]:
	var causes: Array[Dictionary] = []
	for id: StringName in stages:
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
static func _throughput_causes(buildings: Array[Dictionary], stages: Array[StringName]) -> Array[Dictionary]:
	var causes: Array[Dictionary] = []
	for id: StringName in stages:
		for building: Dictionary in buildings:
			if building["definition_id"] == id and building["workers"] < building["jobs"]:
				causes.append({"definition_id": id, "reason": &"understaffed"})
				break
	if causes.is_empty():
		causes.append({"definition_id": &"", "reason": &"insufficient_capacity"})
	return causes
