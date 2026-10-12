class_name ConsumptionSystem
extends RefCounted


func tick(state: EconomyState, params: Params) -> void:
	state.bread_demand = state.population * float(params.get_value(
		&"population.bread_per_person_per_minute")) / 60.0
	state.bread_demand_tick = state.bread_demand
	var available: float = float(state.stocks.get(&"bread", 0)) + state.bread_fraction
	state.bread_consumed = minf(available, state.bread_demand)
	state.bread_consumed_tick = state.bread_consumed
	state.bread_coverage = coverage(state, params)
	var decay: float = float(params.get_value(&"population.bread_decay_fraction_per_minute"))
	var remaining: float = maxf(0.0, available - state.bread_consumed) * pow(1.0 - decay, 1.0 / 60.0)
	var whole: int = ProductionSystem.whole_units(remaining)
	if state.stocks.has(&"bread") or whole > 0:
		state.stocks[&"bread"] = whole
	state.bread_fraction = maxf(0.0, remaining - whole)
	_consume_tea(state, params)


# Tea is optional: a city without any simply gets no bonus. It does not spoil, and the part of a unit
# already eaten waits in tea_fraction like the bread's.
func _consume_tea(state: EconomyState, params: Params) -> void:
	state.tea_demand = ImportSystem.tea_demand_per_second(state, params)
	var available: float = float(state.stocks.get(&"tea", 0)) + state.tea_fraction
	state.tea_consumed = minf(available, state.tea_demand)
	state.tea_coverage = tea_coverage(state, params)
	var remaining: float = maxf(0.0, available - state.tea_consumed)
	var whole: int = ProductionSystem.whole_units(remaining)
	if state.stocks.has(&"tea") or whole > 0:
		state.stocks[&"tea"] = whole
	state.tea_fraction = maxf(0.0, remaining - whole)


# Share of the tea demand the store covers, without consuming anything.
func tea_coverage(state: EconomyState, params: Params) -> float:
	var demand: float = ImportSystem.tea_demand_per_second(state, params)
	var available: float = float(state.stocks.get(&"tea", 0)) + state.tea_fraction
	if demand <= 0.0:
		return 1.0 if available > 0.0 else 0.0
	return clampf(available / demand, 0.0, 1.0)


# Preview supply against demand without consuming, decaying, or advancing the state.
func coverage(state: EconomyState, params: Params) -> float:
	var demand: float = state.population * float(params.get_value(
		&"population.bread_per_person_per_minute")) / 60.0
	var available: float = float(state.stocks.get(&"bread", 0)) + state.bread_fraction
	return clampf(available / demand, 0.0, 1.0) if demand > 0.0 else _empty_city_coverage(available, params)


func _empty_city_coverage(available: float, params: Params) -> float:
	var immigrants: float = float(params.get_value(&"population.growth.immigration_per_minute"))
	var per_person: float = float(params.get_value(&"population.bread_per_person_per_minute"))
	var lookahead: float = float(params.get_value(&"population.empty_city_bread_lookahead_seconds"))
	return 1.0 if available >= immigrants * per_person * lookahead / 60.0 else 0.0
