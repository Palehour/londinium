class_name SatisfactionSystem
extends RefCounted


func tick(state: EconomyState, params: Params, context: EconomyContext) -> void:
	update_target(state, params, context)
	var smoothing: float = float(params.get_value(&"population.satisfaction.smoothing_per_second"))
	state.satisfaction += (state.satisfaction_target - state.satisfaction) * smoothing
	var epsilon: float = float(params.get_value(&"population.satisfaction.snap_epsilon"))
	if absf(state.satisfaction_target - state.satisfaction) < epsilon:
		state.satisfaction = state.satisfaction_target
	state.satisfaction_breakdown["smoothed"] = state.satisfaction


func update_target(state: EconomyState, params: Params, context: EconomyContext) -> void:
	NeedsSystem.evaluate(state, params, context)
	state.housing_capacity = NeedsSystem.housing_capacity(state, params, context)
	state.overcrowding = float(maxi(0, state.population - state.housing_capacity)) \
		/ state.population if state.population > 0 else 0.0
	var breakdown: Dictionary[String, float] = {}
	# Terms follow the order the data declares the needs in, so the sum is the same on every run.
	var needs_total: float = 0.0
	for definition: ClassDef in context.classes.values():
		for need: NeedDef in definition.needs:
			var term: float = NeedsSystem.coverage(state, need.good) * float(params.get_value(need.satisfaction_key))
			breakdown[String(need.good)] = breakdown.get(String(need.good), 0.0) + term
			needs_total += term
	breakdown["tax"] = state.tax_rate * float(params.get_value(&"population.satisfaction.tax_weight"))
	breakdown["overcrowding"] = state.overcrowding * float(params.get_value(&"population.satisfaction.overcrowding_weight"))
	state.satisfaction_breakdown.assign(breakdown)
	state.satisfaction_target = clampf(needs_total - state.satisfaction_breakdown["tax"] \
		- state.satisfaction_breakdown["overcrowding"], 0.0, 100.0)
	state.satisfaction_breakdown["target"] = state.satisfaction_target
	state.satisfaction_breakdown["smoothed"] = state.satisfaction
