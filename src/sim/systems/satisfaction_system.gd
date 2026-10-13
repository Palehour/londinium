class_name SatisfactionSystem
extends RefCounted


func tick(state: EconomyState, params: Params, context: EconomyContext) -> void:
	update_target(state, params, context)
	for def: ClassDef in ClassStates.defs(context):
		var entry: ClassState = ClassStates.checkout(state, def)
		var smoothing: float = float(params.get_value(def.smoothing_key))
		entry.satisfaction += (entry.satisfaction_target - entry.satisfaction) * smoothing
		var epsilon: float = float(params.get_value(def.snap_epsilon_key))
		if absf(entry.satisfaction_target - entry.satisfaction) < epsilon:
			entry.satisfaction = entry.satisfaction_target
		entry.satisfaction_breakdown["smoothed"] = entry.satisfaction
		ClassStates.commit(state, def, entry)


# A new game starts every class at its target instead of walking up to it.
func snap_to_target(state: EconomyState, context: EconomyContext) -> void:
	for def: ClassDef in ClassStates.defs(context):
		var entry: ClassState = ClassStates.checkout(state, def)
		entry.satisfaction = entry.satisfaction_target
		entry.satisfaction_breakdown["smoothed"] = entry.satisfaction
		ClassStates.commit(state, def, entry)


func update_target(state: EconomyState, params: Params, context: EconomyContext) -> void:
	NeedsSystem.evaluate(state, params, context)
	var total_capacity: int = 0
	for def: ClassDef in ClassStates.defs(context):
		var entry: ClassState = ClassStates.checkout(state, def)
		entry.housing_capacity = NeedsSystem.class_housing_capacity(state, params, context, def)
		total_capacity += entry.housing_capacity
		_update_class_target(state, params, def, entry)
		ClassStates.commit(state, def, entry)
	state.housing_capacity = total_capacity


# A class that did not exist when the state was built (saved before it, or never lived in) starts at its
# target instead of walking up to it from zero. Run after NeedsSystem.evaluate().
func prime_class(state: EconomyState, params: Params, context: EconomyContext, def: ClassDef) -> void:
	var entry: ClassState = ClassStates.checkout(state, def)
	var capacity: int = NeedsSystem.class_housing_capacity(state, params, context, def)
	_update_class_target(state, params, def, entry, capacity)
	entry.satisfaction = entry.satisfaction_target
	entry.satisfaction_breakdown["smoothed"] = entry.satisfaction
	ClassStates.commit(state, def, entry)


func _update_class_target(state: EconomyState, params: Params, def: ClassDef, entry: ClassState,
		capacity: int = -1) -> void:
	var residents: int = ClassStates.population_of(state, def)
	var room: int = entry.housing_capacity if capacity < 0 else capacity
	entry.overcrowding = float(maxi(0, residents - room)) / residents if residents > 0 else 0.0
	var breakdown: Dictionary[String, float] = {}
	# Terms follow the order the data declares the needs in, so the sum is the same on every run.
	var needs_total: float = 0.0
	for need: NeedDef in def.needs:
		var term: float = NeedsSystem.coverage(state, need.good) * float(params.get_value(need.satisfaction_key))
		breakdown[String(need.good)] = breakdown.get(String(need.good), 0.0) + term
		needs_total += term
	breakdown["tax"] = state.tax_rate * float(params.get_value(def.tax_weight_key))
	breakdown["overcrowding"] = entry.overcrowding * float(params.get_value(def.overcrowding_weight_key))
	entry.satisfaction_breakdown.assign(breakdown)
	entry.satisfaction_target = clampf(needs_total - entry.satisfaction_breakdown["tax"] 		- entry.satisfaction_breakdown["overcrowding"], 0.0, 100.0)
	entry.satisfaction_breakdown["target"] = entry.satisfaction_target
	entry.satisfaction_breakdown["smoothed"] = entry.satisfaction
