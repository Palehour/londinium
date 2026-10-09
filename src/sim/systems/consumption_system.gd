class_name ConsumptionSystem
extends RefCounted


func tick(state: EconomyState, params: Params) -> void:
	state.bread_demand = state.population * float(params.get_value(
		&"population.bread_per_person_per_minute")) / 60.0
	var available: float = float(state.stocks.get(&"bread", 0)) + state.bread_fraction
	state.bread_consumed = minf(available, state.bread_demand)
	state.bread_coverage = clampf(state.bread_consumed / state.bread_demand, 0.0, 1.0) \
		if state.bread_demand > 0.0 else 1.0
	var decay: float = float(params.get_value(&"population.bread_decay_fraction_per_minute"))
	var remaining: float = maxf(0.0, available - state.bread_consumed) * pow(1.0 - decay, 1.0 / 60.0)
	var whole: int = ProductionSystem.whole_units(remaining)
	if state.stocks.has(&"bread") or whole > 0:
		state.stocks[&"bread"] = whole
	state.bread_fraction = maxf(0.0, remaining - whole)
