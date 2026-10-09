class_name SatisfactionSystem
extends RefCounted


func tick(state: EconomyState, params: Params) -> void:
	state.housing_capacity = 0
	for building: Dictionary in state.buildings:
		if building["definition_id"] == &"housing":
			state.housing_capacity += maxi(0, int(params.get_value(&"building.housing.capacity")))
	state.overcrowding = float(maxi(0, state.population - state.housing_capacity)) \
		/ state.population if state.population > 0 else 0.0
	state.satisfaction_breakdown.assign({
		"bread": state.bread_coverage * float(params.get_value(&"population.satisfaction.bread_weight")),
		"tea": 0.0,
		"tax": state.tax_rate * float(params.get_value(&"population.satisfaction.tax_weight")),
		"overcrowding": state.overcrowding * float(params.get_value(&"population.satisfaction.overcrowding_weight")),
	})
	state.satisfaction = clampf(state.satisfaction_breakdown["bread"] \
		- state.satisfaction_breakdown["tax"] - state.satisfaction_breakdown["overcrowding"], 0.0, 100.0)
