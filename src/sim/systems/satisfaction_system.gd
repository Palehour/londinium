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
	state.housing_capacity = 0
	for building: Dictionary in state.buildings:
		var id: StringName = building["definition_id"]
		if "housing" in context.buildings[id].tags:
			state.housing_capacity += maxi(0, int(params.get_value(StringName("building.%s.capacity" % id))))
	state.overcrowding = float(maxi(0, state.population - state.housing_capacity)) \
		/ state.population if state.population > 0 else 0.0
	state.satisfaction_breakdown.assign({
		"bread": state.hunger_smoothed_coverage * float(params.get_value(&"population.satisfaction.bread_weight")),
		"tea": 0.0,
		"tax": state.tax_rate * float(params.get_value(&"population.satisfaction.tax_weight")),
		"overcrowding": state.overcrowding * float(params.get_value(&"population.satisfaction.overcrowding_weight")),
	})
	state.satisfaction_target = clampf(state.satisfaction_breakdown["bread"] \
		- state.satisfaction_breakdown["tax"] - state.satisfaction_breakdown["overcrowding"], 0.0, 100.0)
	state.satisfaction_breakdown["target"] = state.satisfaction_target
	state.satisfaction_breakdown["smoothed"] = state.satisfaction
